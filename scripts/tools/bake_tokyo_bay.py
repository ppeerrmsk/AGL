#!/usr/bin/env python3
"""
OSM GeoJSON → map_geography_data.gd 烘焙脚本

用法:
    python scripts/tools/bake_tokyo_bay.py [INPUT_GEOJSON] [OUTPUT_GD]

默认输入: C:/Users/noelu/Downloads/export.geojson
默认输出: scripts/survivor/map_geography_data.gd

流程:
1. 解析 GeoJSON 特征
2. 按 tag 分类（海岸线 / landuse / 各级道路 / 机场）
3. 投影 lat/lon → 世界坐标（墨卡托近似 + 自适应缩放到 ±7300 px）
4. 海岸线端点匹配拼接，过短丢弃，开放链沿 bbox 闭合成陆地多边形
5. Douglas-Peucker 简化（epsilon ≈ 15 px 激进）+ 小多边形过滤
6. 输出可直接被 Godot 预载的 .gd 文件

运行后请检查日志的 land/urban/roads 统计。
"""
import json
import math
import sys
import os
from pathlib import Path

DEFAULT_IN = r"C:\Users\noelu\Downloads\export.geojson"
DEFAULT_OUT = r"C:\Users\noelu\Documents\AGL\scripts\survivor\map_geography_data.gd"
DEFAULT_OUT_JSON = r"C:\Users\noelu\Documents\AGL\resources\maps\tokyo_bay.json"

# ---- 坐标系 ----
# 对齐手画的 map_geography.gd：中心 (35.44°N, 139.76°E)，世界 ±7500 px，1 px = 2 m
FIXED_LAT_C = 35.44
FIXED_LON_C = 139.76
FIXED_PX_PER_M = 0.5
WORLD_HALF_PX = 15000.0  # 2026-07-05 扩图 30km→60km（spec map-expansion），与 MapBoundary.WORLD_HALF_PX 保持一致
WORLD_MARGIN_PX = 500.0  # 超出 ±8000 的 feature 直接丢

MAP_USABLE_HALF_PX = 7300.0  # (旧自适应缩放用；现在改成固定投影)
SIMPLIFY_EPS_PX = 6.0             # 陆地 — 保留海岸细节（以前 15 太猛）
URBAN_SIMPLIFY_EPS_PX = 22.0
ROAD_SIMPLIFY_EPS_PX = 10.0
MIN_LAND_AREA_PX = 10000.0       # <100x100 px 丢弃
MIN_URBAN_AREA_PX = 8000.0
COASTLINE_MERGE_TOL = 1e-7
# 道路分段长度过滤（像素），丢掉太短的支路
ROAD_MIN_LEN_BY_TIER = {
    "motorway":  120.0,
    "trunk":     100.0,
    "primary":   150.0,
    "secondary": 200.0,
}
# tertiary 完全不烘焙（数量太大，游戏中用不上）


def log(msg):
    print(msg, flush=True)


# ==========================================
# 1. 加载
# ==========================================
def load_geojson(path):
    log(f"[load] {path}")
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    log(f"[load] features: {len(data['features'])}")
    return data


# ==========================================
# 2. 分类
# ==========================================
def categorize(data):
    out = {
        "coastline": [],
        "urban": [],
        "motorway": [],
        "trunk": [],
        "primary": [],
        "secondary": [],
        "tertiary": [],
        "aerodrome": [],
    }
    for feat in data["features"]:
        props = (feat.get("properties") or {})
        geom = (feat.get("geometry") or {})
        gtype = geom.get("type")
        coords = geom.get("coordinates")
        if not coords:
            continue
        nat = props.get("natural")
        aw = props.get("aeroway")
        hw = props.get("highway")
        lu = props.get("landuse")

        if nat == "coastline" and gtype == "LineString":
            out["coastline"].append([tuple(c) for c in coords])
            continue
        if aw == "aerodrome" and gtype == "Polygon":
            out["aerodrome"].append([tuple(c) for c in coords[0]])
            continue
        if lu in ("residential", "commercial", "industrial", "retail") and gtype == "Polygon":
            out["urban"].append([tuple(c) for c in coords[0]])
            continue
        if hw and gtype == "LineString":
            tier = hw if hw in out else None
            if tier:
                out[tier].append([tuple(c) for c in coords])
    for k, v in out.items():
        log(f"[cat] {k}: {len(v)}")
    return out


# ==========================================
# 3. 投影
# ==========================================
def compute_projection(cat):
    """使用固定投影：对齐手画 map_geography.gd 的坐标系
    center=(FIXED_LAT_C, FIXED_LON_C), scale=FIXED_PX_PER_M
    """
    M_PER_DEG_LAT = 111000.0
    M_PER_DEG_LON = 111000.0 * math.cos(math.radians(FIXED_LAT_C))

    # 统计 bbox 只为日志
    all_pts = []
    for w in cat["coastline"]:
        all_pts.extend(w)
    for p in cat["urban"]:
        all_pts.extend(p)
    for a in cat["aerodrome"]:
        all_pts.extend(a)
    for tier in ("motorway", "trunk", "primary", "secondary", "tertiary"):
        for r in cat[tier]:
            all_pts.extend(r)
    if all_pts:
        lons = [p[0] for p in all_pts]
        lats = [p[1] for p in all_pts]
        lon_min, lon_max = min(lons), max(lons)
        lat_min, lat_max = min(lats), max(lats)
    else:
        lon_min = lon_max = FIXED_LON_C
        lat_min = lat_max = FIXED_LAT_C

    log(f"[proj] input bbox: ({lat_min:.4f}..{lat_max:.4f}, {lon_min:.4f}..{lon_max:.4f})")
    log(f"[proj] FIXED center: ({FIXED_LAT_C}, {FIXED_LON_C})")
    log(f"[proj] FIXED scale:  1m = {FIXED_PX_PER_M} px (= {FIXED_PX_PER_M*1000} px/km)")
    log(f"[proj] world rect:   ±{WORLD_HALF_PX} px (margin {WORLD_MARGIN_PX})")

    def proj(lon, lat):
        x = (lon - FIXED_LON_C) * M_PER_DEG_LON * FIXED_PX_PER_M
        y = -(lat - FIXED_LAT_C) * M_PER_DEG_LAT * FIXED_PX_PER_M
        return (x, y)

    bbox_ll = (lon_min, lon_max, lat_min, lat_max)
    return proj, FIXED_PX_PER_M, bbox_ll


def inside_world(pts, margin=WORLD_MARGIN_PX):
    """至少一个顶点在 (世界 + margin) 内 → 保留"""
    lim = WORLD_HALF_PX + margin
    for x, y in pts:
        if -lim <= x <= lim and -lim <= y <= lim:
            return True
    return False


def clip_segment_to_world(pts, margin=WORLD_MARGIN_PX):
    """保留完全在世界矩形内的段。简化：只保留两端都在矩形内的线段。
    对长线段来说会丢掉一些穿过边界的片段，但对城区/道路够用。
    """
    lim = WORLD_HALF_PX + margin
    out_segments = []
    cur = []
    for x, y in pts:
        if -lim <= x <= lim and -lim <= y <= lim:
            cur.append((x, y))
        else:
            if len(cur) >= 2:
                out_segments.append(cur)
            cur = []
    if len(cur) >= 2:
        out_segments.append(cur)
    return out_segments


# ==========================================
# 4. 海岸线拼接
# ==========================================
def stitch_coastlines(ways):
    """OSM 海岸线在 LineString 边界处切断，端点匹配拼接回长链。"""
    def key(pt):
        return (round(pt[0] / COASTLINE_MERGE_TOL), round(pt[1] / COASTLINE_MERGE_TOL))

    ways = [list(w) for w in ways if w]
    prev_n = -1
    iter_n = 0
    while len(ways) != prev_n and iter_n < 30:
        prev_n = len(ways)
        iter_n += 1
        by_start = {}
        for i, w in enumerate(ways):
            by_start.setdefault(key(w[0]), []).append(i)
        used = [False] * len(ways)
        new_ways = []
        for i, w in enumerate(ways):
            if used[i]:
                continue
            cur = list(w)
            used[i] = True
            while True:
                k = key(cur[-1])
                found = -1
                for j in by_start.get(k, []):
                    if not used[j] and j != i:
                        found = j
                        break
                if found < 0:
                    break
                cur.extend(ways[found][1:])
                used[found] = True
            new_ways.append(cur)
        ways = new_ways
    ways.sort(key=len, reverse=True)
    log(f"[coast] stitched into {len(ways)} chains (iter={iter_n})")
    for i, w in enumerate(ways[:6]):
        closed = math.hypot(w[0][0] - w[-1][0], w[0][1] - w[-1][1]) < 1e-5
        log(f"[coast]   chain[{i}]: {len(w):5d} nodes, closed={closed}")
    return ways


def close_chain_via_bbox(chain, bbox_ll):
    """把开放链沿 bbox 边界闭合成多边形。陆地在海岸方向的右侧。"""
    lon_min, lon_max, lat_min, lat_max = bbox_ll
    start = chain[0]
    end = chain[-1]

    def side_of(pt, tol=0.005):
        lon, lat = pt
        dW = abs(lon - lon_min); dE = abs(lon - lon_max)
        dS = abs(lat - lat_min); dN = abs(lat - lat_max)
        m = min(dW, dE, dS, dN)
        if m > tol:
            return None
        if m == dW: return "W"
        if m == dE: return "E"
        if m == dS: return "S"
        return "N"

    s_side = side_of(start)
    e_side = side_of(end)
    if s_side is None or e_side is None:
        return None

    NE = (lon_max, lat_max)
    SE = (lon_max, lat_min)
    SW = (lon_min, lat_min)
    NW = (lon_min, lat_max)
    # CW 顺序：N→E→S→W→N，land 在 coastline 方向右侧
    order = ["N", "E", "S", "W"]
    corner_after = {"N": NE, "E": SE, "S": SW, "W": NW}
    path = []
    cur = e_side
    for _ in range(4):
        if cur == s_side:
            break
        path.append(corner_after[cur])
        cur = order[(order.index(cur) + 1) % 4]
    return list(chain) + path


# ==========================================
# 5. Douglas-Peucker
# ==========================================
def perp_sq(p, a, b):
    dx = b[0] - a[0]
    dy = b[1] - a[1]
    if dx == 0 and dy == 0:
        return (p[0] - a[0]) ** 2 + (p[1] - a[1]) ** 2
    t = ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / (dx * dx + dy * dy)
    t = max(0.0, min(1.0, t))
    px = a[0] + t * dx
    py = a[1] + t * dy
    return (p[0] - px) ** 2 + (p[1] - py) ** 2


def rdp(pts, eps_sq):
    if len(pts) < 3:
        return list(pts)
    keep = [False] * len(pts)
    keep[0] = keep[-1] = True
    stk = [(0, len(pts) - 1)]
    while stk:
        lo, hi = stk.pop()
        if hi - lo < 2:
            continue
        md = 0.0; idx = lo
        a = pts[lo]; b = pts[hi]
        for i in range(lo + 1, hi):
            d = perp_sq(pts[i], a, b)
            if d > md:
                md = d; idx = i
        if md > eps_sq:
            keep[idx] = True
            stk.append((lo, idx))
            stk.append((idx, hi))
    return [pts[i] for i in range(len(pts)) if keep[i]]


# ==========================================
# 6. 多边形工具
# ==========================================
def poly_area(pts):
    if len(pts) < 3:
        return 0.0
    s = 0.0
    n = len(pts)
    for i in range(n):
        x1, y1 = pts[i]
        x2, y2 = pts[(i + 1) % n]
        s += x1 * y2 - x2 * y1
    return abs(s) * 0.5


# ==========================================
# 7. 主处理
# ==========================================
def process(cat, proj, bbox_ll):
    # --- 海岸线（改成输出 LineString，用于细节描边；不再封闭成大陆多边形） ---
    chains = stitch_coastlines(cat["coastline"])
    coastline_px = []
    total_raw = 0
    total_final = 0
    for c in chains:
        if len(c) < 10:
            continue
        pts = [proj(lon, lat) for (lon, lat) in c]
        total_raw += len(pts)
        pts = rdp(pts, SIMPLIFY_EPS_PX * SIMPLIFY_EPS_PX)
        # 按世界矩形裁剪
        for seg in clip_segment_to_world(pts):
            if len(seg) >= 4:
                coastline_px.append(seg)
                total_final += len(seg)
    log(f"[coast] final segments: {len(coastline_px)} ({total_raw} raw verts -> {total_final})")

    # --- 城区 ---（裁剪到世界矩形）
    urban_px = []
    for ring in cat["urban"]:
        pts = [proj(lon, lat) for (lon, lat) in ring]
        pts = rdp(pts, URBAN_SIMPLIFY_EPS_PX * URBAN_SIMPLIFY_EPS_PX)
        if not inside_world(pts):
            continue
        if poly_area(pts) >= MIN_URBAN_AREA_PX:
            urban_px.append(pts)
    log(f"[urban] final polygons: {len(urban_px)}")

    # --- 机场 ---
    aero_px = []
    for ring in cat["aerodrome"]:
        pts = [proj(lon, lat) for (lon, lat) in ring]
        pts = rdp(pts, SIMPLIFY_EPS_PX * SIMPLIFY_EPS_PX)
        if not inside_world(pts):
            continue
        if poly_area(pts) >= MIN_LAND_AREA_PX:
            aero_px.append(pts)
    log(f"[aero] final polygons: {len(aero_px)}")

    # --- 道路 ---
    def polyline_length(pts):
        s = 0.0
        for i in range(len(pts) - 1):
            s += math.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1])
        return s

    def process_roads(tier, eps, min_len):
        out = []
        dropped_short = 0
        dropped_outside = 0
        for r in cat[tier]:
            pts = [proj(lon, lat) for (lon, lat) in r]
            pts = rdp(pts, eps * eps)
            # 裁剪到世界矩形：整条完全在外就丢，部分在外拆成段
            for seg in clip_segment_to_world(pts):
                if len(seg) < 2:
                    continue
                if polyline_length(seg) < min_len:
                    dropped_short += 1
                    continue
                out.append(seg)
            if not inside_world(pts):
                dropped_outside += 1
        log(f"[road] {tier} kept={len(out)} dropped_short={dropped_short} all_outside={dropped_outside}")
        return out

    roads = {
        "motorway":  process_roads("motorway",  ROAD_SIMPLIFY_EPS_PX,       ROAD_MIN_LEN_BY_TIER["motorway"]),
        "trunk":     process_roads("trunk",     ROAD_SIMPLIFY_EPS_PX,       ROAD_MIN_LEN_BY_TIER["trunk"]),
        "primary":   process_roads("primary",   ROAD_SIMPLIFY_EPS_PX,       ROAD_MIN_LEN_BY_TIER["primary"]),
        "secondary": process_roads("secondary", ROAD_SIMPLIFY_EPS_PX * 1.3, ROAD_MIN_LEN_BY_TIER["secondary"]),
        "tertiary":  [],  # 跳过 — 16k 条太多
    }
    for k, v in roads.items():
        total_pts = sum(len(r) for r in v)
        log(f"[road] {k}: {len(v)} ways, {total_pts} pts")

    # ---- 陆地 mask（城区 + 道路外扩并集，offline 合并大幅减少多边形数量） ----
    land_mask = _build_land_mask(urban_px, roads)

    return {
        "coastline": coastline_px,
        "urban": urban_px,
        "aero": aero_px,
        "roads": roads,
        "land_mask": land_mask,
    }


def _build_land_mask(urban_polys, roads_by_tier):
    """用 shapely 把所有 OSM 城区 + 道路外扩的并集合成少量大多边形
    目的：降低游戏运行时 GPU overdraw"""
    try:
        from shapely.geometry import Polygon, LineString
        from shapely.ops import unary_union
    except ImportError:
        log("[land_mask] shapely not installed; skipping merge — game will get 1000+ polygons")
        return []

    URBAN_EXPAND = 320.0
    ROAD_EXPAND = 160.0

    log(f"[land_mask] starting union: {len(urban_polys)} urban + ?road polylines ...")
    t0 = time.time() if 'time' in globals() else 0
    import time as _time

    shapes = []
    for pts in urban_polys:
        if len(pts) < 3:
            continue
        try:
            p = Polygon(pts).buffer(URBAN_EXPAND, join_style=1)  # 1=round
            if not p.is_empty:
                shapes.append(p)
        except Exception:
            pass
    for tier, roads in roads_by_tier.items():
        for pts in roads:
            if len(pts) < 2:
                continue
            try:
                ln = LineString(pts).buffer(ROAD_EXPAND, cap_style=1, join_style=1)
                if not ln.is_empty:
                    shapes.append(ln)
            except Exception:
                pass

    log(f"[land_mask] {len(shapes)} shapes to union ...")
    t1 = _time.time()
    merged = unary_union(shapes)
    t2 = _time.time()

    result = []
    def _poly_to_px_list(poly):
        coords = list(poly.exterior.coords)
        return [(x, y) for (x, y) in coords]

    if merged.geom_type == "Polygon":
        result.append(_poly_to_px_list(merged))
    elif merged.geom_type == "MultiPolygon":
        for poly in merged.geoms:
            result.append(_poly_to_px_list(poly))

    total_verts = sum(len(r) for r in result)
    log(f"[land_mask] unioned {len(shapes)} shapes -> {len(result)} polygons, {total_verts} verts ({(t2-t1)*1000:.0f}ms)")

    # 简化每个结果多边形（shapely 输出顶点可能偏多）
    SIMPLIFY_EPS = 8.0
    simplified = []
    for poly_pts in result:
        s = rdp(poly_pts, SIMPLIFY_EPS * SIMPLIFY_EPS)
        if len(s) >= 4:
            simplified.append(s)
    log(f"[land_mask] after simplify (eps={SIMPLIFY_EPS}): {sum(len(r) for r in simplified)} verts")
    return simplified


# ==========================================
# 8. 输出 GDScript
# ==========================================
def fmt_polyline(pts, indent):
    ind = "\t" * indent
    parts = [f"{ind}Vector2({x:.1f}, {y:.1f})," for (x, y) in pts]
    return "\n".join(parts)


def emit(pack, out_path, src_path):
    lines = []
    lines.append("class_name MapGeographyData")
    lines.append("extends RefCounted")
    lines.append("")
    lines.append("## 自动生成 - 请勿手动编辑")
    lines.append(f"## 源文件: {os.path.basename(src_path)}")
    lines.append(f"## 脚本: scripts/tools/bake_tokyo_bay.py")
    lines.append("")

    # Coastline lines (open polylines — 不封闭成大陆多边形，用作细节描边)
    lines.append("static var COASTLINE_LINES: Array = [")
    for poly in pack["coastline"]:
        lines.append("\tPackedVector2Array([")
        lines.append(fmt_polyline(poly, 2))
        lines.append("\t]),")
    lines.append("]")
    lines.append("")

    # Urban
    lines.append("static var URBAN_POLYGONS: Array = [")
    for poly in pack["urban"]:
        lines.append("\tPackedVector2Array([")
        lines.append(fmt_polyline(poly, 2))
        lines.append("\t]),")
    lines.append("]")
    lines.append("")

    # Aerodrome
    lines.append("static var AERODROME_POLYGONS: Array = [")
    for poly in pack["aero"]:
        lines.append("\tPackedVector2Array([")
        lines.append(fmt_polyline(poly, 2))
        lines.append("\t]),")
    lines.append("]")
    lines.append("")

    # Roads
    for tier in ("motorway", "trunk", "primary", "secondary", "tertiary"):
        lines.append(f"static var ROADS_{tier.upper()}: Array = [")
        for poly in pack["roads"][tier]:
            lines.append("\tPackedVector2Array([")
            lines.append(fmt_polyline(poly, 2))
            lines.append("\t]),")
        lines.append("]")
        lines.append("")

    # Land mask (unioned)
    lines.append("static var LAND_MASK_POLYGONS: Array = [")
    for poly in pack.get("land_mask", []):
        lines.append("\tPackedVector2Array([")
        lines.append(fmt_polyline(poly, 2))
        lines.append("\t]),")
    lines.append("]")
    lines.append("")

    content = "\n".join(lines) + "\n"
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(content)
    log(f"[emit] wrote {out_path} ({len(content)/1024:.1f} KB)")


def emit_json(pack, out_path):
    """输出 JSON 格式 —— Godot 用 JSON.parse_string() 读取
    每个多边形/折线存成扁平 [x1, y1, x2, y2, ...] 便于解析。"""
    def flatten(pts):
        out = []
        for (x, y) in pts:
            out.append(round(x, 1))
            out.append(round(y, 1))
        return out

    def flatten_list(polys):
        return [flatten(p) for p in polys]

    data = {
        "coastline": flatten_list(pack["coastline"]),
        "urban": flatten_list(pack["urban"]),
        "aero": flatten_list(pack["aero"]),
        "roads_motorway": flatten_list(pack["roads"]["motorway"]),
        "roads_trunk": flatten_list(pack["roads"]["trunk"]),
        "roads_primary": flatten_list(pack["roads"]["primary"]),
        "roads_secondary": flatten_list(pack["roads"]["secondary"]),
        "land_mask": flatten_list(pack.get("land_mask", [])),
    }
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, separators=(',', ':'))
    size_kb = os.path.getsize(out_path) / 1024
    log(f"[emit-json] wrote {out_path} ({size_kb:.1f} KB)")


# ==========================================
# main
# ==========================================
def main():
    in_path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_IN
    out_path = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_OUT
    data = load_geojson(in_path)
    cat = categorize(data)
    proj, scale, bbox_ll = compute_projection(cat)
    pack = process(cat, proj, bbox_ll)
    # 旧路径：把所有数据写成 8000+ 行 GDScript 静态数组。在 Godot 编辑器 @tool
    # 上下文里 static var 懒初始化不触发，class_name 引用拿到的是空。已改走 JSON
    # emit(pack, out_path, in_path)
    emit_json(pack, DEFAULT_OUT_JSON)
    log("[done]")


if __name__ == "__main__":
    main()
