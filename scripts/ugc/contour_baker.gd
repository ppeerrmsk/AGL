class_name ContourBaker
extends RefCounted

## 格子位图 → 平滑矢量多边形 的烘焙流水线（map-editor spec §3.1）
##   涂格 bitmap → 边界追踪提取闭合轮廓（含孔洞）→ Douglas-Peucker 抽稀 → Chaikin 平滑
## 纯静态函数、无状态、可无头单测。逆向（多边形 → 格子）见 rasterize_polygons，
## 供官方地图转换器反推 editor_cells（spec §3.4）。
##
## 坐标约定：格子 (cx, cy) 的世界范围 = origin + [cx, cx+1]×[cy, cy+1] × cell_size；
## 轮廓顶点落在格点上，再经抽稀/平滑变成任意点。

## 抽稀阈值 = 该系数 × 格边长（spec §3.1：0.4）
const SIMPLIFY_EPS_FACTOR := 0.4
## Chaikin 迭代次数（与 MapGeography 手画地块同参数）
const SMOOTH_ITERATIONS := 2


## 主入口：把一层涂格位图烘焙成多边形数组。
## cells: PackedByteArray，长度 grid_w×grid_h，非 0 = 已涂；行主序（idx = cy*grid_w + cx）
## 返回 Array[PackedVector2Array]，每个是闭合多边形（外环与孔洞均为独立环，偶奇判定由调用方负责）
static func bake_layer(cells: PackedByteArray, grid_w: int, grid_h: int,
		cell_size: float, origin: Vector2) -> Array[PackedVector2Array]:
	var loops := _trace_boundary_loops(cells, grid_w, grid_h)
	var result: Array[PackedVector2Array] = []
	var eps := SIMPLIFY_EPS_FACTOR * cell_size
	for lp in loops:
		var world := PackedVector2Array()
		for p in lp:
			world.append(origin + p * cell_size)
		var simplified := simplify_closed(world, eps)
		if simplified.size() < 3:
			continue
		result.append(chaikin_closed(simplified, SMOOTH_ITERATIONS))
	return result


## 逆向：多边形组 → 涂格位图（格心偶奇判定：被奇数个多边形包含 = 已涂）。
## 官方图转换用；一次性调用，150×150 × 多边形数量级。
static func rasterize_polygons(polys: Array, grid_w: int, grid_h: int,
		cell_size: float, origin: Vector2) -> PackedByteArray:
	var cells := PackedByteArray()
	cells.resize(grid_w * grid_h)
	for cy in range(grid_h):
		for cx in range(grid_w):
			var center := origin + Vector2(cx + 0.5, cy + 0.5) * cell_size
			var hits := 0
			for poly in polys:
				if Geometry2D.is_point_in_polygon(center, poly):
					hits += 1
			if hits % 2 == 1:
				cells[cy * grid_w + cx] = 1
	return cells


# ══════════════════════════════════════════════
#  ① 边界追踪：涂格区域 → 格点闭合环（直角折线）
# ══════════════════════════════════════════════

## 提取所有边界环。返回 Array[PackedVector2Array]，顶点为格点坐标（未乘 cell_size）。
## 原理：每个"已涂格子贴空邻居"的边生成一条有向边（内部恒在行进方向右侧），
## 再把有向边链成闭合环。对角相触的鞍点按"优先右转"选路，保证不同区域不粘连。
static func _trace_boundary_loops(cells: PackedByteArray, grid_w: int, grid_h: int) -> Array[PackedVector2Array]:
	# 有向边表：start 格点 id → Array[end 格点 id]（格点 id = y*(grid_w+1)+x）
	var vw := grid_w + 1
	var edges_out: Dictionary = {}
	var edge_used: Dictionary = {}  # "start:end" → false
	var _filled := func(cx: int, cy: int) -> bool:
		if cx < 0 or cy < 0 or cx >= grid_w or cy >= grid_h:
			return false
		return cells[cy * grid_w + cx] != 0
	var _add_edge := func(sx: int, sy: int, ex: int, ey: int) -> void:
		var s := sy * vw + sx
		var e := ey * vw + ex
		if not edges_out.has(s):
			edges_out[s] = []
		edges_out[s].append(e)
		edge_used["%d:%d" % [s, e]] = false

	for cy in range(grid_h):
		for cx in range(grid_w):
			if not _filled.call(cx, cy):
				continue
			if not _filled.call(cx, cy - 1):  # 上边：→ 向右
				_add_edge.call(cx, cy, cx + 1, cy)
			if not _filled.call(cx + 1, cy):  # 右边：→ 向下
				_add_edge.call(cx + 1, cy, cx + 1, cy + 1)
			if not _filled.call(cx, cy + 1):  # 下边：→ 向左
				_add_edge.call(cx + 1, cy + 1, cx, cy + 1)
			if not _filled.call(cx - 1, cy):  # 左边：→ 向上
				_add_edge.call(cx, cy + 1, cx, cy)

	var loops: Array[PackedVector2Array] = []
	for start_v in edges_out:
		for first_e in edges_out[start_v]:
			var key := "%d:%d" % [start_v, first_e]
			if edge_used[key]:
				continue
			var lp := _walk_loop(start_v, first_e, edges_out, edge_used, vw)
			if lp.size() >= 4:
				loops.append(_collapse_collinear(lp))
	return loops


## 从一条有向边出发沿边界走到回起点，返回格点坐标环
@warning_ignore("integer_division")
static func _walk_loop(start_v: int, first_e: int, edges_out: Dictionary,
		edge_used: Dictionary, vw: int) -> PackedVector2Array:
	var lp := PackedVector2Array()
	var cur := start_v
	var nxt := first_e
	var guard := 0
	while guard < 1000000:
		guard += 1
		edge_used["%d:%d" % [cur, nxt]] = true
		lp.append(Vector2(cur % vw, cur / vw))
		var dir_in := Vector2((nxt % vw) - (cur % vw), (nxt / vw) - (cur / vw))
		cur = nxt
		if cur == start_v:
			break
		# 鞍点消歧：多条出边时按 右转 > 直行 > 左转 优先（内部在右侧 → 右转贴紧本区域）
		var candidates: Array = edges_out.get(cur, [])
		var best := -1
		var best_rank := 4
		for e in candidates:
			if edge_used.get("%d:%d" % [cur, e], true):
				continue
			var dir_out := Vector2((e % vw) - (cur % vw), (e / vw) - (cur / vw))
			var rank := _turn_rank(dir_in, dir_out)
			if rank < best_rank:
				best_rank = rank
				best = e
		if best == -1:
			break  # 断链（理论不可达）：放弃本环
		nxt = best
	return lp


## 转向优先级：0=右转 1=直行 2=左转 3=掉头（y 向下坐标系，cross>0 = 右转）
static func _turn_rank(dir_in: Vector2, dir_out: Vector2) -> int:
	var cross := dir_in.x * dir_out.y - dir_in.y * dir_out.x
	if cross > 0.0:
		return 0
	if cross == 0.0:
		return 1 if dir_in.dot(dir_out) > 0.0 else 3
	return 2


## 合并共线顶点（直角折线上的中间点）
static func _collapse_collinear(lp: PackedVector2Array) -> PackedVector2Array:
	var n := lp.size()
	var out := PackedVector2Array()
	for i in range(n):
		var prev := lp[(i - 1 + n) % n]
		var next := lp[(i + 1) % n]
		var d1 := lp[i] - prev
		var d2 := next - lp[i]
		if d1.x * d2.y - d1.y * d2.x != 0.0:  # 非共线才保留
			out.append(lp[i])
	return out


# ══════════════════════════════════════════════
#  ② Douglas-Peucker 抽稀（闭合多边形版）
# ══════════════════════════════════════════════

## 闭合多边形抽稀：以顶点 0 与其最远点为锚，拆成两条开链分别 DP
static func simplify_closed(poly: PackedVector2Array, eps: float) -> PackedVector2Array:
	var n := poly.size()
	if n < 5:
		return poly
	var far := 0
	var far_d := -1.0
	for i in range(1, n):
		var d := poly[0].distance_squared_to(poly[i])
		if d > far_d:
			far_d = d
			far = i
	var keep := PackedByteArray()
	keep.resize(n)
	keep[0] = 1
	keep[far] = 1
	_dp_mark(poly, 0, far, eps, keep)
	_dp_mark_wrapped(poly, far, n, eps, keep)
	var out := PackedVector2Array()
	for i in range(n):
		if keep[i] != 0:
			out.append(poly[i])
	return out


## 标准 DP：标记 [first, last] 开链中需保留的点
static func _dp_mark(poly: PackedVector2Array, first: int, last: int, eps: float, keep: PackedByteArray) -> void:
	if last - first < 2:
		return
	var far := -1
	var far_d := eps
	for i in range(first + 1, last):
		var d := _point_seg_dist(poly[i], poly[first], poly[last])
		if d > far_d:
			far_d = d
			far = i
	if far == -1:
		return
	keep[far] = 1
	_dp_mark(poly, first, far, eps, keep)
	_dp_mark(poly, far, last, eps, keep)


## 环绕段 DP：处理 far → (0 经 wrap) 的后半段（把索引平移展开为开链）
static func _dp_mark_wrapped(poly: PackedVector2Array, far: int, n: int, eps: float, keep: PackedByteArray) -> void:
	var chain := PackedVector2Array()
	var idx_map: Array[int] = []
	for i in range(far, n):
		chain.append(poly[i])
		idx_map.append(i)
	chain.append(poly[0])
	idx_map.append(0)
	var sub_keep := PackedByteArray()
	sub_keep.resize(chain.size())
	_dp_mark(chain, 0, chain.size() - 1, eps, sub_keep)
	for i in range(chain.size()):
		if sub_keep[i] != 0:
			keep[idx_map[i]] = 1


static func _point_seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq == 0.0:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)


# ══════════════════════════════════════════════
#  ③ Chaikin 平滑（与 MapGeography._chaikin_closed 同数学，测试对拍保证一致）
# ══════════════════════════════════════════════

static func chaikin_closed(poly: PackedVector2Array, iterations: int) -> PackedVector2Array:
	var cur := poly
	for _iter in range(iterations):
		var out := PackedVector2Array()
		var n := cur.size()
		for i in range(n):
			var a: Vector2 = cur[i]
			var b: Vector2 = cur[(i + 1) % n]
			out.append(a * 0.75 + b * 0.25)
			out.append(a * 0.25 + b * 0.75)
		cur = out
	return cur
