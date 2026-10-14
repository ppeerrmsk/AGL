"""R51 相机无关父包共同分区，来源排序与生产身份一致。"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
from build_tokyo_shared_roofs import build, GRID


def canonicalize(data):
    if not data.get("camera_independent") or len(data.get("parents", [])) != 16:
        raise ValueError("requires complete sixteen-parent native export")
    if sorted(p["parent_id"] for p in data["parents"]) != list(range(16)):
        raise ValueError("duplicate or missing parent")
    layers = {(m["parent_id"], m["kind"]) for m in data["meshes"]}
    if len(data["meshes"]) != 32 or layers != {(parent, kind) for parent in range(16) for kind in (0, 1)}:
        raise ValueError("requires both native mesh layers for every parent")
    result = copy.deepcopy(data)
    result["parents"].sort(key=lambda parent: parent["parent_id"])
    identity = lambda mesh: (mesh["path"], mesh["kind"], mesh["precision_guarded"])
    ordered = sorted(result["meshes"], key=identity)
    if len({identity(mesh) for mesh in ordered}) != len(ordered):
        raise ValueError("duplicate native mesh identity")
    mapping = {mesh["id"]: index for index, mesh in enumerate(ordered)}
    if len(mapping) != len(ordered):
        raise ValueError("duplicate native mesh id")
    for index, mesh in enumerate(ordered):
        mesh["id"] = index
    result["meshes"] = ordered
    for source in result["native"]:
        source["mesh"] = mapping[source["mesh"]]
    result["native"].sort(key=lambda source: (source["mesh"], source["surface"], source["triangle"]))
    keys = [(s["mesh"], s["surface"], s["triangle"]) for s in result["native"]]
    if len(set(keys)) != len(keys):
        raise ValueError("duplicate native source triangle")
    result["expected"].sort(key=lambda source: source["source_id"])
    return result


def generate(data):
    source = canonicalize(data)
    plan = build(source, grid=source.get("shared_grid", GRID))
    plan["configuration"] = source["configuration"]
    plan["parents"] = sorted(source["parents"], key=lambda parent: parent["parent_id"])
    plan["camera_independent"] = True
    plan["game_source_sha256"] = source["game_source_sha256"]
    # 与源JSON的文件哈希分开，保证来源数组换序不会改变几何归属。
    plan["canonical_source_sha256"] = digest(source)
    return plan


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.mkdir(exist_ok=False)
    manifest = json.loads((args.source / "manifest.json").read_bytes())
    rows = []
    expected_signature = None
    collision_signature = None
    for entry in manifest["configurations"]:
        raw = (args.source / entry["file"]).read_bytes()
        if hashlib.sha256(raw).hexdigest() != entry["sha256"]:
            raise ValueError("export manifest hash mismatch")
        data = json.loads(raw)
        current = digest(sorted(data["expected"], key=lambda s: s["source_id"]))
        if expected_signature is not None and (current != expected_signature or data["collision_sha256"] != collision_signature):
            raise ValueError("gameplay sources differ between LOD configurations")
        expected_signature, collision_signature = current, data["collision_sha256"]
        plan = generate(data)
        plan["source_sha256"] = entry["sha256"]
        name = data["configuration"]["name"]
        # 每个真实输入也反向排列验证；不能只依赖合成反例。
        reversed_input = copy.deepcopy(data)
        reversed_input["meshes"].reverse()
        reversed_input["native"].reverse()
        reversed_input["expected"].reverse()
        reversed_input["parents"].reverse()
        repeated = generate(reversed_input)
        repeat_match = digest({k: v for k, v in plan.items() if k != "source_sha256"}) == digest(repeated)
        plan["source_order_independent"] = repeat_match
        plan["passed"] = plan["passed"] and repeat_match
        destination = args.output / (name + ".json")
        with destination.open("x", encoding="utf-8") as file:
            json.dump(plan, file, ensure_ascii=False, separators=(",", ":"), allow_nan=False)
        row = dict(name=name, file=destination.name, sha256=hashlib.sha256(destination.read_bytes()).hexdigest(),
            passed=plan["passed"], native=len(data["native"]), triangles=len(plan["triangles"]),
            failures=len(plan["failures"]), source_order_independent=repeat_match)
        rows.append(row)
        print(json.dumps(row), flush=True)
    with (args.output / "manifest.json").open("x", encoding="utf-8") as file:
        json.dump(dict(configurations=rows, expected_sha256=expected_signature, collision_sha256=collision_signature,
            passed=all(row["passed"] for row in rows), production_enabled=False), file)
    return 0 if all(row["passed"] for row in rows) else 1


if __name__ == "__main__":
    raise SystemExit(main())
