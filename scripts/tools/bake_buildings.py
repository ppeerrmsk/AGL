#!/usr/bin/env python3
"""
OSM GeoJSON → yokohama_buildings.json 独立烘焙脚本（隔离于 bake_tokyo_bay.py）

用法:
    python scripts/tools/bake_buildings.py [INPUT_GEOJSON] [OUTPUT_JSON]

默认输入: C:/Users/noelu/Downloads/buildings.geojson
默认输出: resources/maps/yokohama_buildings.json

重要：
- 与 bake_tokyo_bay.py 使用同一坐标系（FIXED_LAT_C/LON_C, ±7500 px, 1 px = 2 m）
- 框外建筑直接丢
- 仅保留真实高度 ≥ HEIGHT_MIN 的建筑
- 输出独立 JSON，不污染 tokyo_bay.json
- 撤回：删本脚本 + 删输出 JSON 即可

Overpass turbo 查询（重导 GeoJSON 时用这段，覆盖 ±7500px = 约 ±0.135° 范围）：

    [out:json][timeout:120];
    (
      way["building"](35.305,139.625,35.575,139.895);
      relation["building"](35.305,139.625,35.575,139.895);
    );
    out geom;

导出为 GeoJSON 后运行本脚本。
"""
import json
import math
import os
import sys

# ---- 与 bake_tokyo_bay.py 严格一致的投影参数（不要改）----
FIXED_LAT_C = 35.44
FIXED_LON_C = 139.76
FIXED_PX_PER_M = 0.5
WORLD_HALF_PX = 7500.0

# ---- 建筑筛选阈值（独立可调）----
HEIGHT_NORMAL_MIN = 80.0      # 普通高楼最低真实高度（米）— 单独绘制
HEIGHT_LANDMARK_MIN = 150.0   # 地标最低真实高度（米）— 显眼绘制
HEIGHT_DISTRICT_MIN = 10.0    # 街区合并最低高度（米）— 3 层以上都纳入
LEVEL_TO_METERS = 3.2         # building:levels 缺 height 时的换算
FOOTPRINT_SIMPLIFY_EPS_PX = 2.0   # 单栋建筑简化
MIN_FOOTPRINT_AREA_PX = 50.0      # 太小的单栋建筑丢

# ---- 街区合并参数（shapely 的 buffer-union-buffer 流水线）----
# 1 px = 2 m。横滨街道宽度通常 12-20m → buffer 4-5px(8-10m) 不会跨街道连
DISTRICT_BUFFER_OUT_PX = 5.0   # 外扩半径（每栋楼膨胀 10m 再 union）
DISTRICT_BUFFER_IN_PX = 2.0    # 内缩半径（让街区轮廓比楼群外沿大 6m）
# 后处理：simplify 去掉合并产生的小凹凸，再 buffer±2 平滑
DISTRICT_POST_SIMPLIFY_PX = 10.0
DISTRICT_POST_SMOOTH_PX = 2.0
DISTRICT_MIN_AREA_PX = 800.0   # 太小的街区丢（独栋大楼会形成微小 polygon）

DEFAULT_IN = r"C:\Users\noelu\Downloads\buildings.geojson"
DEFAULT_OUT = r"C:\Users\noelu\Documents\AGL\resources\maps\yokohama_buildings.json"


def log(msg):
    try:
        print(msg, flush=True)
    except UnicodeEncodeError:
        print(msg.encode("ascii", "replace").decode("ascii"), flush=True)


# ==========================================
# 投影 —— 与 tokyo_bay_bg.json 完全一致（保证建筑贴合 basemap PNG）
# basemap 用 m_per_lat=111000 常量 + m_per_lon=111000*cos(lat0)
# 这里不用 bake_tokyo_bay.py 的椭球体公式（差 ~0.3% 会和 basemap 错开 ~38m）
# ==========================================
def make_projector():
    lat0_rad = math.radians(FIXED_LAT_C)
    m_per_deg_lat = 111000.0
    m_per_deg_lon = 111000.0 * math.cos(lat0_rad)

    def proj(lon, lat):
        x_m = (lon - FIXED_LON_C) * m_per_deg_lon
        y_m = (lat - FIXED_LAT_C) * m_per_deg_lat
        x_px = x_m * FIXED_PX_PER_M
        y_px = -y_m * FIXED_PX_PER_M  # Godot Y 朝下
        return (x_px, y_px)

    return proj


def inside_world(pts):
    return all(abs(x) <= WORLD_HALF_PX and abs(y) <= WORLD_HALF_PX for x, y in pts)


# ==========================================
# Douglas-Peucker（精简版）
# ==========================================
def perp_sq(p, a, b):
    ax, ay = a; bx, by = b; px, py = p
    dx, dy = bx - ax, by - ay
    if dx == 0 and dy == 0:
        return (px - ax) ** 2 + (py - ay) ** 2
    t = ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)
    t = max(0.0, min(1.0, t))
    cx, cy = ax + t * dx, ay + t * dy
    return (px - cx) ** 2 + (py - cy) ** 2


def rdp(pts, eps_sq):
    if len(pts) < 3:
        return pts
    keep = [False] * len(pts)
    keep[0] = keep[-1] = True
    stack = [(0, len(pts) - 1)]
    while stack:
        i, j = stack.pop()
        max_d, max_k = 0.0, -1
        for k in range(i + 1, j):
            d = perp_sq(pts[k], pts[i], pts[j])
            if d > max_d:
                max_d, max_k = d, k
        if max_d > eps_sq and max_k != -1:
            keep[max_k] = True
            stack.append((i, max_k))
            stack.append((max_k, j))
    return [p for p, k in zip(pts, keep) if k]


def poly_area(pts):
    if len(pts) < 3:
        return 0.0
    s = 0.0
    for i in range(len(pts)):
        x1, y1 = pts[i]
        x2, y2 = pts[(i + 1) % len(pts)]
        s += x1 * y2 - x2 * y1
    return abs(s) * 0.5


# ==========================================
# 高度解析
# ==========================================
def parse_height(props):
    """从 OSM tags 解析真实高度（米）。返回 None 表示无法确定。"""
    h = props.get("height")
    if h is not None:
        try:
            return float(str(h).split()[0].replace("m", "").strip())
        except (ValueError, IndexError):
            pass
    lv = props.get("building:levels")
    if lv is not None:
        try:
            return float(str(lv).split()[0]) * LEVEL_TO_METERS
        except (ValueError, IndexError):
            pass
    return None


# ==========================================
# 街区合并（buffer-union-buffer）
# ==========================================
def merge_districts(footprints, building_meta):
    """把所有 footprint 外扩 → union → 内缩 → simplify → 平滑，得到城市街区多边形

    building_meta: [(footprint_pts, real_h)] 用于给每个街区算 max_real_h
    返回: [{footprint, max_real_h}]
    """
    try:
        from shapely.geometry import Polygon, Point
        from shapely.ops import unary_union
    except ImportError:
        log("[district] shapely not installed; skipping district merge")
        return []

    log(f"[district] input footprints: {len(footprints)}")
    expanded = []
    for fp in footprints:
        if len(fp) < 3:
            continue
        try:
            p = Polygon(fp).buffer(DISTRICT_BUFFER_OUT_PX, join_style=1)
            if not p.is_empty:
                expanded.append(p)
        except Exception:
            pass

    log(f"[district] valid expanded shapes: {len(expanded)}")
    merged = unary_union(expanded)
    if merged.is_empty:
        return []
    shrunk = merged.buffer(-DISTRICT_BUFFER_IN_PX, join_style=1)
    if shrunk.is_empty:
        return []

    # 后处理：每个街区独立 simplify + 微 buffer±N 平滑边缘小凹凸
    polys = []
    if shrunk.geom_type == "Polygon":
        polys.append(shrunk)
    elif shrunk.geom_type == "MultiPolygon":
        polys.extend(shrunk.geoms)

    # 后处理：每个街区先 simplify+平滑，再套 convex_hull 去除凹陷
    # convex_hull 保留大致轮廓（圆形商业区还是圆形），但拒绝任何凹角和扭曲
    # 视觉效果：街区是干净的凸多边形（4-12 顶点），不再有诡异的 L/U 形
    smoothed = []
    for poly in polys:
        try:
            s = poly.simplify(DISTRICT_POST_SIMPLIFY_PX, preserve_topology=True)
            s = s.buffer(DISTRICT_POST_SMOOTH_PX, join_style=1).buffer(-DISTRICT_POST_SMOOTH_PX, join_style=1)
            if s.is_empty:
                continue
            base_polys = []
            if s.geom_type == "Polygon":
                base_polys.append(s)
            elif s.geom_type == "MultiPolygon":
                base_polys.extend(s.geoms)
            for bp in base_polys:
                hull = bp.convex_hull
                # hull "充得过满" 拒收：面积膨胀 >50% 说明楼群是稀疏链条
                # （如沿街道一长串楼），hull 后会变成大三角/大梯形 — 反而失真
                if not hull.is_empty and hull.geom_type == "Polygon":
                    if bp.area > 0 and (hull.area / bp.area) <= 1.5:
                        smoothed.append(hull)
                    else:
                        smoothed.append(bp)
                else:
                    smoothed.append(bp)
        except Exception:
            smoothed.append(poly)

    # 给每个街区找出包含的建筑，取 max real_h
    out = []
    for poly in smoothed:
        coords = list(poly.exterior.coords)
        if len(coords) >= 2 and coords[0] == coords[-1]:
            coords = coords[:-1]
        if len(coords) < 3:
            continue
        if poly_area(coords) < DISTRICT_MIN_AREA_PX:
            continue

        max_h = HEIGHT_DISTRICT_MIN
        for fp, real_h in building_meta:
            cx = sum(p[0] for p in fp) / len(fp)
            cy = sum(p[1] for p in fp) / len(fp)
            if poly.contains(Point(cx, cy)):
                if real_h > max_h:
                    max_h = real_h

        out.append({
            "footprint": [[round(x, 1), round(y, 1)] for x, y in coords],
            "max_real_h": round(max_h, 1),
        })

    log(f"[district] merged → {len(out)} polygons "
        f"(total verts: {sum(len(d['footprint']) for d in out)})")
    if out:
        log(f"[district] max_real_h range: {min(d['max_real_h'] for d in out):.0f}-{max(d['max_real_h'] for d in out):.0f}m")
    return out


# ==========================================
# 主流程
# ==========================================
def main():
    in_path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_IN
    out_path = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_OUT

    if not os.path.exists(in_path):
        log(f"[err] input not found: {in_path}")
        log(f"[hint] 先用脚本头部的 Overpass 查询重导 GeoJSON")
        sys.exit(1)

    log(f"[load] {in_path}")
    with open(in_path, "r", encoding="utf-8") as f:
        data = json.load(f)
    feats = data.get("features", [])
    log(f"[load] features: {len(feats)}")

    proj = make_projector()
    eps_sq = FOOTPRINT_SIMPLIFY_EPS_PX * FOOTPRINT_SIMPLIFY_EPS_PX

    # 统计
    stat_no_building = 0
    stat_no_height = 0
    stat_below_thresh = 0
    stat_outside = 0
    stat_too_small = 0
    stat_bad_geom = 0

    normal = []
    landmark = []
    district_input = []  # 喂给 shapely 的所有 ≥DISTRICT_MIN 的 footprint
    district_meta = []   # 平行列表：(footprint, real_h)，用于给每个街区算 max_real_h
    stat_district_input = 0

    for feat in feats:
        props = feat.get("properties") or {}
        if not props.get("building"):
            stat_no_building += 1
            continue

        h = parse_height(props)
        if h is None:
            stat_no_height += 1
            continue
        if h < HEIGHT_DISTRICT_MIN:
            stat_below_thresh += 1
            continue

        geom = feat.get("geometry") or {}
        gtype = geom.get("type")
        coords = geom.get("coordinates")
        if not coords:
            stat_bad_geom += 1
            continue

        # 取外环
        if gtype == "Polygon":
            ring = coords[0]
        elif gtype == "MultiPolygon":
            ring = coords[0][0]  # 第一个 polygon 的外环
        else:
            stat_bad_geom += 1
            continue

        pts = [proj(lon, lat) for lon, lat in ring]
        # 去掉闭合重复点
        if len(pts) >= 2 and pts[0] == pts[-1]:
            pts = pts[:-1]
        if len(pts) < 3:
            stat_bad_geom += 1
            continue

        if not inside_world(pts):
            stat_outside += 1
            continue

        pts = rdp(pts, eps_sq)
        if len(pts) < 3 or poly_area(pts) < MIN_FOOTPRINT_AREA_PX:
            stat_too_small += 1
            continue

        # ≥DISTRICT_MIN 的全部喂给街区合并
        district_input.append(pts)
        district_meta.append((pts, h))
        stat_district_input += 1

        # ≥NORMAL_MIN 的另外作为单栋建筑保存
        if h < HEIGHT_NORMAL_MIN:
            continue
        is_landmark = h >= HEIGHT_LANDMARK_MIN
        entry = {
            "footprint": [[round(x, 1), round(y, 1)] for x, y in pts],
            "real_h": round(h, 1),
            "name": props.get("name") or props.get("name:en") or "",
        }
        (landmark if is_landmark else normal).append(entry)

    log(f"[stat] skipped: no_building={stat_no_building} "
        f"no_height={stat_no_height} below_dist_thresh={stat_below_thresh} "
        f"outside={stat_outside} too_small={stat_too_small} bad_geom={stat_bad_geom}")
    log(f"[result] district input (>= {HEIGHT_DISTRICT_MIN}m): {stat_district_input}")
    log(f"[result] normal     (>= {HEIGHT_NORMAL_MIN}m): {len(normal)}")
    log(f"[result] landmark   (>= {HEIGHT_LANDMARK_MIN}m): {len(landmark)}")

    districts = merge_districts(district_input, district_meta)

    pack = {
        "meta": {
            "world_half_px": WORLD_HALF_PX,
            "px_per_m": FIXED_PX_PER_M,
            "lat_c": FIXED_LAT_C,
            "lon_c": FIXED_LON_C,
            "height_district_min": HEIGHT_DISTRICT_MIN,
            "height_normal_min": HEIGHT_NORMAL_MIN,
            "height_landmark_min": HEIGHT_LANDMARK_MIN,
        },
        "normal": normal,
        "landmark": landmark,
        "districts": districts,
    }

    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(pack, f, ensure_ascii=False, separators=(",", ":"))
    log(f"[write] {out_path}")

    if landmark:
        log("[landmark sample]")
        for e in landmark[:10]:
            cx = sum(p[0] for p in e["footprint"]) / len(e["footprint"])
            cy = sum(p[1] for p in e["footprint"]) / len(e["footprint"])
            log(f"  {e['real_h']:>5.0f}m @ ({cx:>7.0f},{cy:>7.0f})  {e['name']}")


if __name__ == "__main__":
    main()
