class_name NavalPlacement
extends RefCounted

## 舰队摆位的共用水域校验（CSG BOSS 舰队 / 战区海上任务共用）
##
## 舰队模型：**旗舰在半径 ring_radius 的圆上恒定盘旋，僚舰刚体跟随**
## （偏移在旗舰本地系：+X 船头 / +Y 右舷；见 NavalUnit.patrol_center / formation_offset）。
##
## 为什么校验必须"对朝向取样"：整队会缓慢转过所有朝向（一圈十几到二十分钟），
## 只查出生那一刻的朝向 = 只保证"刚下水时不在陆地上"，转过去照样搁浅。
##
## 舰队占地半径 = ring_radius + max(|offset|) —— 这个圆必须整个落在水里，
## 装不下就只能缩编队，不能靠挪位置解决（浦贺水道那种窄水域尤其明显）。

## 转位取样数（越大越准，一次摆位的一次性开销）。12 = 每 30° 一采，
## 6 采曾漏掉"只在某个中间朝向蹭岸"的摆位（回归见 tests/test_naval_zone_water.gd 的 24 采复核）
const ROTATION_SAMPLES: int = 12

## 舰队占地半径（旗舰盘旋圆 + 最外圈僚舰）
static func fleet_reach(ring_radius: float, offsets: Array) -> float:
	var r_max: float = 0.0
	for off in offsets:
		r_max = maxf(r_max, (off as Vector2).length())
	return ring_radius + r_max

## 旗舰在某个转位下的世界坐标 —— 盘旋圆心在旗舰右舷（顺时针盘旋）
static func leader_pos(center: Vector2, ring_radius: float, heading_rad: float) -> Vector2:
	return center - Vector2(cos(heading_rad), sin(heading_rad)) * ring_radius

## 某个转位下的全部船位（旗舰 + 僚舰）
static func fleet_positions(center: Vector2, ring_radius: float, offsets: Array,
		heading_rad: float) -> Array:
	var fwd := Vector2(sin(heading_rad), -cos(heading_rad))
	var stb := Vector2(cos(heading_rad), sin(heading_rad))
	var lead: Vector2 = center - stb * ring_radius
	var out: Array = [lead]
	for off in offsets:
		var o: Vector2 = off
		out.append(lead + fwd * o.x + stb * o.y)
	return out

## 每艘船的**轨道半径**（到盘旋圆心的距离）——刚体整队绕圆心转，
## 每艘船到圆心的距离恒定，所以它一辈子走的就是这一个同心圆。
## 校验落地只要沿这几个圆采样即可，既精确又不用"猜转位"。
static func ship_orbit_radii(ring_radius: float, offsets: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for p in fleet_positions(Vector2.ZERO, ring_radius, offsets, 0.0):
		out.append((p as Vector2).length())
	return out

## 沿轨道圆的采样步长（px）——取值 ≈ 舰体半长，保证不会从两个采样点之间"跳过"一小块陆地
const ORBIT_SAMPLE_STEP_PX: float = 150.0

## 数一个盘旋圆心下有多少采样点撞岸（每艘船一个同心圆，按步长细采）
## ring_radius ≤ 1 = 原地驻泊（舰队完全不动）→ 只查出生那一组位置，不扫圆
static func score(center: Vector2, ring_radius: float, offsets: Array,
		base_heading_rad: float = 0.0) -> int:
	var land: int = 0
	if ring_radius <= 1.0:
		for p in fleet_positions(center, 0.0, offsets, base_heading_rad):
			if MapGeography.is_on_land(p):
				land += 1
		return land
	if MapGeography.is_on_land(center):
		land += 1
	for r in ship_orbit_radii(ring_radius, offsets):
		var n: int = clampi(ceili(TAU * r / ORBIT_SAMPLE_STEP_PX), 8, 256)
		for k in n:
			var a: float = TAU * float(k) / float(n)
			if MapGeography.is_on_land(center + Vector2(cos(a), sin(a)) * r):
				land += 1
	return land

## 在候选圆心里挑落地点最少的一个 → { center, land }
## nudges 按"由近及远"排列，找到全水面解立即返回（近的优先 = 尽量贴原位）
static func pick_center(base_center: Vector2, nudges: Array, ring_radius: float,
		offsets: Array, base_heading_rad: float = 0.0) -> Dictionary:
	var best := {
		"center": base_center,
		"land": score(base_center, ring_radius, offsets, base_heading_rad),
	}
	if int(best["land"]) == 0:
		return best
	for nudge in nudges:
		var c: Vector2 = base_center + (nudge as Vector2)
		var land: int = score(c, ring_radius, offsets, base_heading_rad)
		if land < int(best["land"]):
			best = {"center": c, "land": land}
			if land == 0:
				return best
	return best

## 逐级降级摆位：盘旋半径**由大到小**试（最后一档给 0 = 原地驻泊），
## 返回第一个全水面解 → { center, ring, land }。
## 为什么要降级：窄水域（湾北桥下只有 ~1750 px 的全水圆）装不下"编队 + 盘旋圆"，
## 与其让护卫舰开上岸，不如让舰队缩小巡航半径乃至就地抛锚。
static func pick_placement(base_center: Vector2, nudges: Array, ring_candidates: Array,
		offsets: Array, base_heading_rad: float = 0.0) -> Dictionary:
	var best := {"center": base_center, "ring": 0.0, "land": -1}
	for rc in ring_candidates:
		var ring: float = float(rc)
		var picked: Dictionary = pick_center(base_center, nudges, ring, offsets, base_heading_rad)
		var land: int = int(picked["land"])
		if land == 0:
			return {"center": picked["center"], "ring": ring, "land": 0}
		if int(best["land"]) < 0 or land < int(best["land"]):
			best = {"center": picked["center"], "ring": ring, "land": land}
	return best

## 生成"由近及远、八方向"的候选偏移环（配合 pick_center）
static func ring_nudges(radii: Array) -> Array:
	var out: Array = []
	for r in radii:
		var rad: float = float(r)
		for k in 8:
			var a: float = TAU * float(k) / 8.0
			out.append(Vector2(cos(a), sin(a)) * rad)
	return out
