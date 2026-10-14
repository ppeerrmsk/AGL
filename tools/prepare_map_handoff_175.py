"""核验175号历史输入，生成指向当前检出目录的新请求；不启动引擎。"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import json
from pathlib import Path


def prepare(root: Path, output: Path) -> Path:
    root = root.resolve()
    output = output.resolve()
    output.relative_to(root / "tmp")
    source = root / "tmp/tokyo-complete-production-02/joint-boundary-175/request.json"
    original = source.read_bytes()
    expected = "9e2d5e5635cb9b07b29a8a7469ad0bb625d2bf9a66268fb8dcea57f978027158"
    if hashlib.sha256(original).hexdigest() != expected:
        raise ValueError("175号原始请求摘要不匹配，拒绝使用未知输入")
    request = json.loads(original)
    for field in ("native_control", "native_candidate"):
        for channel in ("vertices", "indices", "mask"):
            entry = request[field][channel]
            filename = entry["path"].replace("\\", "/").rsplit("/", 1)[-1]
            path = source.parent / filename
            raw = path.read_bytes()
            if hashlib.sha256(raw).hexdigest() != entry["sha256"]:
                raise ValueError(f"输入摘要不匹配: {filename}")
            if len(gzip.decompress(raw)) != entry["decoded_bytes"]:
                raise ValueError(f"解压长度不匹配: {filename}")
            entry["path"] = str(path)
    output.mkdir(parents=True, exist_ok=False)
    request["output"] = str(output / "engine")
    target = output / "request.json"
    target.write_text(json.dumps(request, ensure_ascii=False, indent=2), encoding="utf-8")
    return target


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", default="tmp/map-handoff-175-replay")
    args = parser.parse_args()
    target = prepare(args.root, args.root / args.output)
    print(f"request={target}")
    print(f"sha256={hashlib.sha256(target.read_bytes()).hexdigest()}")
    print("仅生成请求。使用既有bench入口运行，不覆盖历史证据。")


if __name__ == "__main__":
    main()
