"""安装/核验冻结的M20性能问题实物包；仅Python标准库，不生成地图、不启动引擎。"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import zipfile

MANIFEST = "tokyo-m20-runtime-20261014-manifest.json"
HEX = re.compile(r"[0-9a-f]{64}\Z")
ARCHIVE = re.compile(r"tokyo-m20-runtime-20261014-part[0-9]{2}\.zip\Z")
PACKAGE = "resources/maps/tokyo_playable/m20/package.json"
GATE = "resources/maps/tokyo_volume_preview/downtown_lod.res"


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def safe_path(root: Path, relative: str) -> Path:
    path = PurePosixPath(relative)
    if "\\" in relative or ":" in relative or path.is_absolute() or ".." in path.parts:
        raise ValueError(f"不安全路径: {relative}")
    if not relative.startswith("resources/maps/"):
        raise ValueError(f"超出地图目录: {relative}")
    target = root.joinpath(*path.parts)
    if not target.resolve().is_relative_to(root.resolve()):
        raise ValueError(f"链接逃出项目: {relative}")
    current = target
    while current != root:
        if current.is_symlink() or (hasattr(current, "is_junction") and current.is_junction()):
            raise ValueError(f"拒绝链接路径: {relative}")
        current = current.parent
    return target


def load_manifest(bundle: Path, expected: str) -> dict:
    raw = (bundle / MANIFEST).read_bytes()
    if not HEX.fullmatch(expected) or hashlib.sha256(raw).hexdigest() != expected:
        raise ValueError("manifest SHA256不匹配，停止")
    data = json.loads(raw)
    if data.get("schema") != 1 or data.get("package") != PACKAGE:
        raise ValueError("未知地图包格式")
    names = set()
    for archive in data["archives"]:
        if not ARCHIVE.fullmatch(archive["name"]) or archive["name"] in names:
            raise ValueError("不安全或重复的分包名")
        names.add(archive["name"])
        if not HEX.fullmatch(archive["sha256"]):
            raise ValueError("无效分包摘要")
    paths = set()
    for row in data["files"]:
        if row["path"].lower() in paths or not HEX.fullmatch(row["sha256"]) or row["bytes"] < 0:
            raise ValueError("重复路径或无效文件条目")
        paths.add(row["path"].lower())
        if row["delivery"] == "release":
            if not (row["path"].startswith("resources/maps/tokyo_playable/m20/") or row["path"] == GATE):
                raise ValueError("分包不能写入M20及必要入口归档以外的位置")
            if row["archive"] not in names:
                raise ValueError("文件引用未知分包")
        elif row["delivery"] != "git":
            raise ValueError("未知文件交付方式")
    data["manifest_sha256"] = expected
    return data


def inspect_existing(root: Path, row: dict) -> tuple[dict, bool]:
    target = safe_path(root, row["path"])
    if not target.exists():
        if row["delivery"] == "git":
            raise ValueError(f"缺少源码分支中的依赖: {row['path']}")
        return row, False
    if not target.is_file():
        raise ValueError(f"目标不是普通文件: {row['path']}")
    if target.stat().st_size == row["bytes"] and digest(target) == row["sha256"]:
        return row, True
    # Git文本在Windows可能转成CRLF；仅Git前置文件可接受已记录的LF等价摘要。
    if row["delivery"] == "git" and row.get("lf_sha256"):
        if hashlib.sha256(target.read_bytes().replace(b"\r\n", b"\n")).hexdigest() == row["lf_sha256"]:
            return row, True
    raise ValueError(f"已有文件与冻结包不同，拒绝覆盖: {row['path']}")


def verify_archive(bundle: Path, archive: dict, payloads: dict) -> int:
    path = bundle / archive["name"]
    if path.stat().st_size != archive["bytes"] or digest(path) != archive["sha256"]:
        raise ValueError(f"分包摘要或长度错误: {path.name}")
    wanted = {"blobs/" + sha: size for sha, size in payloads.items()}
    with zipfile.ZipFile(path) as zipped:
        infos = zipped.infolist()
        if len(infos) != len(wanted) or {x.filename for x in infos} != set(wanted):
            raise ValueError(f"分包内容清单不一致: {path.name}")
        for item in infos:
            if item.file_size != wanted[item.filename] or item.is_dir():
                raise ValueError("错误载荷长度")
            with zipped.open(item) as stream:
                sha = hashlib.file_digest(stream, "sha256").hexdigest()
            if sha != item.filename.removeprefix("blobs/"):
                raise ValueError(f"载荷摘要错误: {item.filename}")
    print(f"Verified {path.name}: {len(wanted)} payloads", flush=True)
    return len(wanted)


def install(root: Path, bundle: Path, data: dict, missing: list[dict]) -> None:
    folders = [root / "resources/maps/tokyo_playable/m20", root / "resources/maps/tokyo_volume_preview"]
    # 最后一个文件写完后也可能中断；再次安装仍须清除本包留下的隔离标记。
    if not missing and not any((folder / ".gdignore").exists() for folder in folders):
        return
    needed = sum(row["bytes"] for row in missing)
    if shutil.disk_usage(root).free < needed + 1024**3:
        raise ValueError("空间不足：需要缺失资源大小加1GiB安全余量")
    if os.name == "nt":
        probe = subprocess.run(
            ["powershell", "-NoProfile", "-Command",
             "Get-Process -ErrorAction Stop | Where-Object ProcessName -Like 'godot*' | Select-Object -ExpandProperty Id"],
            capture_output=True, text=True, timeout=20, creationflags=subprocess.CREATE_NO_WINDOW)
        if probe.returncode != 0 or probe.stdout.strip():
            raise ValueError("请关闭Godot后安装；无法确认引擎空闲时也拒绝写资源")
    lock = root / "tmp/godot-bench.lock"
    lock.parent.mkdir(parents=True, exist_ok=True)
    lock.mkdir()  # 不夺取、不回收其他task的锁。
    owner = lock / "owner.pid"
    owner.write_text(str(os.getpid()), encoding="ascii")
    guards = []
    try:
        marker = ("map handoff installation " + data["manifest_sha256"] + "\n").encode("ascii")
        for folder in folders:
            folder.mkdir(parents=True, exist_ok=True)
            guard = folder / ".gdignore"
            if guard.exists() and guard.read_bytes() != marker:
                raise ValueError(f"已有不同用途的.gdignore，保留不改动: {guard}")
            if not guard.exists():
                with guard.open("xb") as stream:
                    stream.write(marker)
            guards.append(guard)  # 同一manifest的中断安装可安全续传并清理自己的标记。
        for archive in data["archives"]:
            jobs = [row for row in missing if row["archive"] == archive["name"]]
            with zipfile.ZipFile(bundle / archive["name"]) as zipped:
                for row in jobs:
                    target = safe_path(root, row["path"])
                    target.parent.mkdir(parents=True, exist_ok=True)
                    with target.open("xb") as output:  # 永不覆盖已有文件。
                        try:
                            sha = hashlib.sha256()
                            with zipped.open("blobs/" + row["sha256"]) as source:
                                while chunk := source.read(1024 * 1024):
                                    output.write(chunk)
                                    sha.update(chunk)
                            if sha.hexdigest() != row["sha256"]:
                                raise ValueError(f"写入摘要错误: {row['path']}")
                        except BaseException:
                            output.close()
                            target.unlink()  # 只删除本次独占创建、未完成的这个文件。
                            raise
                    if digest(target) != row["sha256"]:
                        raise ValueError(f"磁盘读回不一致，保留现场: {row['path']}")
            print(f"Installed {archive['name']}: {len(jobs)} files", flush=True)
        for guard in guards:
            guard.unlink()
    finally:
        if owner.exists() and owner.read_text() == str(os.getpid()):
            owner.unlink()
            lock.rmdir()  # 不递归删除；遇到外来内容保留并报错。


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--manifest-sha256", required=True)
    parser.add_argument("--verify-only", action="store_true", help="完整核验分包/载荷与现有文件，不写地图")
    args = parser.parse_args()
    root = args.root.resolve()
    bundle = args.bundle.resolve()
    if not (root / "project.godot").is_file():
        raise ValueError("目标不是AGL项目")
    data = load_manifest(bundle, args.manifest_sha256)
    with ThreadPoolExecutor(max_workers=8) as pool:
        states = list(pool.map(lambda row: inspect_existing(root, row), data["files"]))
    missing = [row for row, exists in states if not exists]
    groups = {row["name"]: {} for row in data["archives"]}
    for row in data["files"]:
        if row["delivery"] == "release":
            groups[row["archive"]][row["sha256"]] = row["bytes"]
    with ThreadPoolExecutor(max_workers=3) as pool:
        list(pool.map(lambda archive: verify_archive(bundle, archive, groups[archive["name"]]), data["archives"]))
    if not args.verify_only:
        install(root, bundle, data, missing)
    print(json.dumps({"verified_files": len(states), "missing_before_install": len(missing),
                      "installed": 0 if args.verify_only else len(missing), "verify_only": args.verify_only,
                      "package_sha256": data["package_sha256"], "engine_started": False}, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, zipfile.BadZipFile, subprocess.SubprocessError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)
