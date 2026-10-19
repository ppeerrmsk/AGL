"""R50 离线共同屋面分区；来源冲突失败关闭，不修改原生包或碰撞数据。"""
import argparse
import hashlib
import json
import math
import struct
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tmp/tokyo-r3-pydeps"))
from shapely import constrained_delaunay_triangles, make_valid, set_precision, union_all
from shapely.geometry import Polygon
from shapely.ops import polygonize
from shapely.strtree import STRtree

GRID = 1 / 2048
FULL_GRID = 1 / 1024
EPSILON = 0.001


def polygon_parts(geometry):
    if geometry.geom_type == "Polygon":
        yield geometry
    elif hasattr(geometry, "geoms"):
        for child in geometry.geoms:
            yield from polygon_parts(child)


def canonical_points(polygon):
    points = [list(p) for p in list(polygon.exterior.coords)[:-1]]
    # Godot XZ 正面顺序与二维 XY 的逆时针相反；这里只固定可重复序列，烘焙时校正法线。
    return min(points[i:] + points[:i] for i in range(len(points)))


def native_attributes(source):
    colors, normals = source["colors"], source["normals"]
    if len(colors) != 3 or len(normals) != 3:
        raise ValueError("missing triangle attributes")
    if any(c != colors[0] for c in colors) or any(n != normals[0] for n in normals):
        raise ValueError("non-flat native attributes require explicit interpolation")
    return (source["height"], tuple(colors[0]), tuple(normals[0]))


def build(data, *, grid=GRID):
    # 全图坐标超过8192后float32步长为1/1024；不改旧局部配方，也不放宽0.001位移门。
    if grid not in (GRID, FULL_GRID):
        raise ValueError("unsupported shared roof precision")
    groups = defaultdict(list)
    warnings, failures, output, audits = [], [], [], []
    for layer in ("native", "expected"):
        for index, source in enumerate(data[layer]):
            geometry = Polygon(source["points"])
            if not geometry.is_valid:
                if layer != "expected":
                    raise ValueError(f"invalid native triangle {index}")
                warnings.append(dict(source_id=source["source_id"], kind="self_touch_linework"))
                geometry = make_valid(geometry, method="linework")
            original = union_all(list(polygon_parts(geometry)))
            snapped = set_precision(original, grid)
            if original.difference(snapped.buffer(EPSILON)).area > 1e-9 or snapped.difference(original.buffer(EPSILON)).area > 1e-9:
                failures.append(dict(kind="input_displacement", layer=layer, source=index))
            if snapped.is_empty:
                warnings.append(dict(layer=layer, source=index, kind="collapsed_subgrid_source"))
            groups[math.floor(source["height"] * 1000 + 0.5)].append(
                dict(layer=layer, index=index, source=source, original=original, geometry=snapped))
    for height_key, sources in sorted(groups.items()):
        active = [s for s in sources if not s["geometry"].is_empty]
        if not active:
            continue
        tree = STRtree([s["geometry"] for s in active])
        lines = union_all([s["geometry"].boundary for s in active], grid_size=grid)
        cells = sorted(polygonize(list(lines.geoms) if hasattr(lines, "geoms") else [lines]), key=lambda p: (p.bounds, p.area))
        generated = {"native": [], "candidate": []}
        shared_target = []
        source_coverage = defaultdict(list)
        for cell in cells:
            center = cell.representative_point()
            owners = [active[int(i)] for i in tree.query(center, predicate="intersects")]
            natives = sorted((s for s in owners if s["layer"] == "native"), key=lambda s: s["index"])
            expected = sorted((s for s in owners if s["layer"] == "expected"), key=lambda s: s["index"])
            if not owners:
                continue
            shared_target.append(set_precision(cell, 0))
            if natives:
                attributes = [native_attributes(s["source"]) for s in natives]
                if len(set(attributes)) != 1:
                    failures.append(dict(kind="native_attribute_conflict", height_key=height_key,
                        sources=[s["index"] for s in natives], area=cell.area, bounds=cell.bounds))
                    continue
                height, color, normal = attributes[0]
                layer = "native"
                owner = natives[0]["index"]
            else:
                heights = {s["source"]["height"] for s in expected}
                if len(heights) != 1:
                    failures.append(dict(kind="expected_height_conflict", height_key=height_key))
                    continue
                height = next(iter(heights))
                color, normal, layer, owner = [176 / 255, 177 / 255, 169 / 255, 1], [0, 1, 0], "candidate", None
            for triangle in sorted(constrained_delaunay_triangles(cell).geoms, key=lambda p: (p.bounds, p.area)):
                points = canonical_points(triangle)
                if len(points) != 3 or any(struct.unpack("f", struct.pack("f", v))[0] != v for p in points for v in p):
                    raise ValueError("non-float32 shared vertex")
                generated[layer].append(Polygon(points))
                for source in natives:
                    source_coverage[source["index"]].append(Polygon(points))
                output.append(dict(layer=layer, owner=owner, native_sources=[s["index"] for s in natives],
                    game_sources=[s["source"]["source_id"] for s in expected], height=height,
                    points=points, color=list(color), normal=list(normal)))
        native, candidate = (union_all(generated[name]) for name in ("native", "candidate"))
        # 共同线网的 snap-rounding 会移动交点；不能再用独立面 union 的第二次舍入作目标。
        # 原轮廓仍独立通过双向 0.001 位移门，每个原生来源也单独检查，重叠门保持严格为零。
        target = union_all(shared_target)
        individually_snapped = union_all([set_precision(s["geometry"], 0) for s in active])
        original = union_all([s["original"] for s in active])
        coverage = union_all([native, candidate])
        row = dict(height_key=height_key, overlap=native.intersection(candidate).area,
            duplicate_area=sum(p.area for p in generated["native"] + generated["candidate"]) - coverage.area,
            missing=target.difference(coverage).area, outside=coverage.difference(target).area,
            independent_snap_difference=individually_snapped.symmetric_difference(coverage).area,
            missing_beyond_epsilon=original.difference(coverage.buffer(EPSILON)).area,
            outside_beyond_epsilon=coverage.difference(original.buffer(EPSILON)).area)
        row["pass"] = row["overlap"] == 0 and all(abs(row[k]) <= 1e-8 for k in (
            "duplicate_area", "missing", "outside", "missing_beyond_epsilon", "outside_beyond_epsilon"))
        audits.append(row)
        for source in active:
            if source["layer"] != "native":
                continue
            rebuilt = union_all(source_coverage[source["index"]])
            missing = source["original"].difference(rebuilt.buffer(EPSILON)).area
            outside = rebuilt.difference(source["original"].buffer(EPSILON)).area
            if missing > 1e-8 or outside > 1e-8:
                failures.append(dict(kind="native_source_displacement", source=source["index"], missing=missing, outside=outside))
    return dict(schema=1, pose=data.get("pose"), grid=grid, max_displacement=EPSILON,
        collision_sha256=data.get("collision_sha256"), meshes=data.get("meshes", []),
        expected=data["expected"], native_sources=data["native"], triangles=output, warnings=warnings, failures=failures,
        audits=audits, passed=not failures and all(r["pass"] for r in audits), production_enabled=False)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    raw = args.input.read_bytes()
    result = build(json.loads(raw))
    result["source_sha256"] = hashlib.sha256(raw).hexdigest()
    # x 模式保护既有证据，失败报告仍保留但不得作为可烘焙包消费。
    with args.output.open("x", encoding="utf-8") as file:
        json.dump(result, file, ensure_ascii=False, separators=(",", ":"), allow_nan=False)
    print(json.dumps(dict(pose=result["pose"], passed=result["passed"], triangles=len(result["triangles"]),
        conflicts=len(result["failures"]), failed_groups=sum(not r["pass"] for r in result["audits"]))))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
