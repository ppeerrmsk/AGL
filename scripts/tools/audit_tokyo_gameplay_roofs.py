"""独立审计原生导出的游戏街区补面；只读，不修改几何或图片。"""
import argparse
import json
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tmp/tokyo-r3-pydeps"))
from shapely.geometry import Polygon
from shapely.ops import unary_union
from shapely import make_valid, is_valid_reason


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    args = parser.parse_args()
    data = json.loads(args.input.read_text(encoding="utf-8"))
    layers = {}
    edge_layers = {}
    source_ring_warnings = []
    for name in ("expected", "native", "candidate"):
        buckets = defaultdict(list)
        for entry in data[name]:
            polygon = Polygon(entry["points"])
            if polygon.area == 0:
                continue
            if not polygon.is_valid:
                assert name == "expected", (name, entry["height"])
                source_ring_warnings.append(dict(height=entry["height"], reason=is_valid_reason(polygon)))
                # 仅在审计内按原边的奇偶填充解释旧自接触环；不写回、不简化碰撞来源。
                polygon = make_valid(polygon, method="linework")
            buckets[entry["height"]].append(polygon)
        layers[name] = {height: unary_union(polys) for height, polys in buckets.items()}
        if name == "native":
            edge_layers = {height: unary_union([poly.boundary for poly in polys]) for height, polys in buckets.items()}
    rows = []
    for height, expected in layers["expected"].items():
        native = layers["native"].get(height, Polygon())
        candidate = layers["candidate"].get(height, Polygon())
        coverage = unary_union([native, candidate])
        # 0.001 world px = 2 mm，仅吸收float32大坐标裁切舍入；不是屏幕误差放宽。
        epsilon = 0.001
        row = dict(height_key=height,
                   missing_area=expected.difference(coverage).area,
                   outside_area=candidate.difference(expected).area,
                   overlap_area=candidate.intersection(native).area,
                   missing_beyond_float32=expected.difference(coverage.buffer(epsilon)).area,
                   outside_beyond_float32=candidate.difference(expected.buffer(epsilon)).area,
                   overlap_beyond_float32=candidate.intersection(native.buffer(-epsilon)).area)
        row["pass"] = all(row[key] <= 1e-6 for key in ("missing_beyond_float32", "outside_beyond_float32", "overlap_beyond_float32"))
        # 补充定位浮点残留，保留上面的严格失败，不用这个诊断覆盖验收结果。
        edge_band = edge_layers.get(height, Polygon()).buffer(epsilon)
        row["overlap_outside_original_triangle_edge_band"] = candidate.intersection(native).difference(edge_band).area
        rows.append(row)
    result = dict(rows=rows, fail=sum(not row["pass"] for row in rows), source_ring_warnings=source_ring_warnings,
                  expected=len(data["expected"]), native=len(data["native"]), candidate=len(data["candidate"]))
    print(json.dumps(result, ensure_ascii=False))
    return int(result["fail"] != 0)


if __name__ == "__main__":
    raise SystemExit(main())
