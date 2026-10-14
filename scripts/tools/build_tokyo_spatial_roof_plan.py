"""R52 固定街区父块归属；只分配来源与整三角，不改R51几何。"""
import argparse
import hashlib
import json
import struct
from collections import defaultdict
from pathlib import Path
from build_tokyo_canonical_roofs import digest
from build_tokyo_shared_roofs import FULL_GRID, Polygon, make_valid, polygon_parts, union_all
from shapely.geometry import box


def geometry(points):
    value = Polygon(points)
    if not value.is_valid:
        value = make_valid(value, method="linework")
    return union_all(list(polygon_parts(value)))


def ownership(plan):
    if plan["configuration"]["name"] != "lod5_full" or not plan["passed"] or not plan["camera_independent"]:
        raise ValueError("ownership requires passing canonical LOD5")
    parents = {p["parent_id"]: box(p["bounds"][0], p["bounds"][1],
        p["bounds"][0] + p["bounds"][2], p["bounds"][1] + p["bounds"][3]) for p in plan["parents"]}
    if len(plan["parents"]) != 16 or set(parents) != set(range(16)):
        raise ValueError("requires exactly sixteen unique parents")
    meshes = {m["id"]: m for m in plan["meshes"]}
    # 整图按实际渲染高度精确相等；不改原始楼高、摘要或归属排序，也不加容差。
    rendered_height = plan.get("grid") == FULL_GRID or plan.get("interaction_scope", {}).get("schema") == 1
    height_key = (lambda value: struct.pack("<f", value)) if rendered_height else (lambda value: value)
    grouped = defaultdict(list)
    for native in sorted(plan["native_sources"], key=lambda s: (s["mesh"], s["surface"], s["triangle"])):
        grouped[(height_key(native["height"]), meshes[native["mesh"]]["parent_id"])].append(geometry(native["points"]))
    roofs = {key: union_all(value) for key, value in grouped.items()}
    rows = []
    seen = set()
    for source in sorted(plan["expected"], key=lambda value: value["source_id"]):
        if source["source_id"] in seen:
            raise ValueError("duplicate gameplay source")
        seen.add(source["source_id"])
        polygon = geometry(source["points"])
        if polygon.is_empty or polygon.area <= 0:
            raise ValueError("empty gameplay footprint")
        scores = []
        for parent, bounds in sorted(parents.items()):
            roof = roofs.get((height_key(source["height"]), parent))
            same_height = polygon.intersection(roof).area if roof is not None else 0.0
            overlap = polygon.intersection(bounds).area
            expanded = polygon.union(bounds).envelope.area - bounds.area
            scores.append(((-same_height, -overlap, expanded, bounds.area, parent), same_height))
        score, same_height = min(scores)
        rows.append(dict(source_id=source["source_id"], parent_id=score[-1], same_height_area=same_height,
            footprint_sha256=digest(source)))
    return rows


def partition(plan, owners):
    if not plan["passed"] or not plan["camera_independent"]:
        raise ValueError("requires passing camera independent plan")
    mapping = {r["source_id"]: r for r in owners}
    expected = {s["source_id"]: s for s in plan["expected"]}
    if len(mapping) != len(owners) or len(expected) != len(plan["expected"]) or set(mapping) != set(expected):
        raise ValueError("missing or duplicate gameplay identity")
    parts = [dict(parent_id=p, expected=[], triangles=[]) for p in range(16)]
    for identity, source in sorted(expected.items()):
        owner = mapping[identity]
        if owner["footprint_sha256"] != digest(source) or owner["parent_id"] not in range(16):
            raise ValueError("gameplay source drift or invalid owner")
        parts[owner["parent_id"]]["expected"].append(identity)
    for index, triangle in enumerate(plan["triangles"]):
        if triangle["layer"] != "candidate":
            continue
        sources = triangle["game_sources"]
        if not sources or any(s not in mapping for s in sources):
            raise ValueError("candidate without complete gameplay ownership")
        parent, _ = min((mapping[s]["parent_id"], s) for s in sources)
        parts[parent]["triangles"].append(index)
    return parts


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    manifest = json.loads((args.source / "manifest.json").read_bytes())
    if not manifest["passed"] or len(manifest["configurations"]) != 11:
        raise ValueError("requires eleven verified combinations")
    plans = {}
    for row in manifest["configurations"]:
        raw = (args.source / row["file"]).read_bytes()
        if hashlib.sha256(raw).hexdigest() != row["sha256"] or row["name"] in plans:
            raise ValueError("plan hash drift or duplicate configuration")
        plans[row["name"]] = json.loads(raw)
    owners = ownership(plans["lod5_full"])
    reversed_plan = dict(plans["lod5_full"])
    for key in ("parents", "meshes", "native_sources", "expected"):
        reversed_plan[key] = list(reversed(reversed_plan[key]))
    if owners != ownership(reversed_plan):
        raise ValueError("order dependent ownership")
    rows = []
    for row in manifest["configurations"]:
        plan = plans[row["name"]]
        if plan["collision_sha256"] != manifest["collision_sha256"] or plan["game_source_sha256"] != plans["lod5_full"]["game_source_sha256"]:
            raise ValueError("cross configuration gameplay source drift")
        rows.append(dict(name=row["name"], file=row["file"], plan_sha256=row["sha256"], parts=partition(plan, owners)))
    result = dict(schema_version=1, owners=owners, owners_sha256=digest(owners), configurations=rows,
        collision_sha256=manifest["collision_sha256"], game_source_sha256=plans["lod5_full"]["game_source_sha256"],
        source_order_independent=True, production_enabled=False, passed=True)
    with args.output.open("x", encoding="utf-8") as file:
        json.dump(result, file, ensure_ascii=False, separators=(",", ":"), allow_nan=False)
    print(json.dumps(dict(configurations=len(rows), owners=len(owners), parents=sorted({r["parent_id"] for r in owners}),
        same_height=sum(r["same_height_area"] > 0 for r in owners), passed=True)))


if __name__ == "__main__":
    main()
