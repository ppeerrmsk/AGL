"""磁盘原生顶点的独立几何门；不能只复用制作器的passed字段。"""
import argparse
import hashlib
import json
import struct
from collections import Counter, defaultdict
from pathlib import Path
from build_tokyo_shared_roofs import EPSILON, FULL_GRID, Polygon, make_valid, polygon_parts, union_all


def key(triangle, render_height=False):
    # 整图证据比较实际float32高度的精确值，不用epsilon吞掉可表示的高度变化。
    height = struct.unpack('f', struct.pack('f', triangle['height']))[0] if render_height else triangle['height']
    return (triangle["layer"], triangle["owner"], height,
            tuple(sorted(tuple(p) for p in triangle["points"])))


def audit(plan, saved):
    rows = []
    native, candidate, expected = defaultdict(list), defaultdict(list), defaultdict(list)
    render_height = plan.get('grid') == FULL_GRID or plan.get('interaction_scope', {}).get('schema') == 1
    identity = lambda triangle: key(triangle, render_height)
    matching = Counter(map(identity, plan["triangles"])) == Counter(map(identity, saved["triangles"]))
    for triangle in saved["triangles"]:
        group = native if triangle["layer"] == "native" else candidate
        group[round(triangle["height"] * 1000)].append(Polygon(triangle["points"]))
    for source in plan["expected"] + plan["native_sources"]:
        expected[round(source["height"] * 1000)].extend(polygon_parts(make_valid(Polygon(source["points"]), method="linework")))
    for height in sorted(expected):
        a, b, target = (union_all(group[height]) for group in (native, candidate, expected))
        coverage = union_all([a, b])
        row = dict(height=height, overlap=a.intersection(b).area,
            duplicates=sum(p.area for p in native[height] + candidate[height]) - coverage.area,
            missing=target.difference(coverage.buffer(EPSILON)).area,
            outside=coverage.difference(target.buffer(EPSILON)).area)
        row["pass"] = row["overlap"] == 0 and all(abs(row[k]) <= 1e-8 for k in ("duplicates", "missing", "outside"))
        rows.append(row)
    return dict(pose=plan["pose"], matching=matching, rows=rows, passed=matching and all(r["pass"] for r in rows))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("plan", type=Path)
    parser.add_argument("saved", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    raw = args.plan.read_bytes()
    plan = json.loads(raw)
    saved = json.loads(args.saved.read_bytes())
    result = audit(plan, saved)
    result["hash_match"] = saved["plan_sha256"] == hashlib.sha256(raw).hexdigest()
    result["passed"] = result["passed"] and result["hash_match"]
    with args.output.open("x", encoding="utf-8") as file:
        json.dump(result, file, ensure_ascii=False)
    print(json.dumps(dict(pose=result["pose"], passed=result["passed"], matching=result["matching"],
        overlap=sum(r["overlap"] for r in result["rows"]), failed_groups=sum(not r["pass"] for r in result["rows"]))))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
