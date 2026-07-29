extends RefCounted

## 无头验收：战区海上任务的舰队**不得开上陆地**
##
## 事故：CSG（BOSS 舰队）2026-07-28 已有摆位地形校验，但战区海上任务（zone_mission
## `_spawn_naval_*`）**一次都没查过水**：旗舰沿 `center.x ± radius×0.7~0.85` 走东西直线，
## 僚舰刚体跟随、偏移最大 2600 px，掉头时整队还转过所有朝向 —— 舰队扫过的圆盘半径
## 3331 / 3897 / 4725 px（1★/2★/3★），而战区 E（浦贺水道）能容下的最大全水圆只有
## ~2750 px 半径。实测采样点 9.7% / 15.7% / 16.0% 落在陆地上。
##
## 现在：编队缩到装得进水域 + 旗舰恒定盘旋（不掉头）+ NavalPlacement 打分挑圆心。
## 本测试用**比实现更密的取样**（轨道步长 40 px vs 实现 150 px）独立复核最终摆位，
## 不吃"自己给自己打分"的自证。
##
## 运行：godot --headless --path . -- --bench=naval_zone_water（或 --bench=all）

const VERIFY_STEP_PX := 40.0   ## 复核用轨道采样步长（实现里 150 px，这里加密 ~4 倍）

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ 战区海上舰队水域校验 ════════")
	for z in ZoneData.ZONES:
		if not _zone_can_be_naval(z):
			continue
		_check_zone(z)
	_check_csg()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════════════\n")


func _zone_can_be_naval(z: Dictionary) -> bool:
	if String(z.get("mission_type", "")) == "naval":
		return true
	var restricted: Array = z.get("restricted_mission_types", [])
	return restricted.has("naval")


func _check_zone(z: Dictionary) -> void:
	var center: Vector2 = z["center"]
	var radius: float = float(z["radius"])
	print("── 战区 %s：center=%s radius=%.0f ──" % [String(z["label"]), str(center), radius])
	var budget: Dictionary = _water_budget(center, radius)
	var budget_r: float = float(budget["radius"])
	print("   可用水域：以 %s 为心最大全水半径 %.0f px（舰队占地必须塞进这个圆）" % [
		str((budget["center"] as Vector2).round()), budget_r])

	var nudges: Array = NavalPlacement.ring_nudges(ZoneMission.NAVAL_PLACEMENT_NUDGE_RADII)
	for star in [1, 2, 3]:
		var offsets: Array = ZoneMission.NAVAL_ESCORT_OFFSETS[star]
		var head: float = deg_to_rad(ZoneMission.NAVAL_LEADER_HEADING_DEG)
		var placement: Dictionary = NavalPlacement.pick_placement(
				center, nudges, ZoneMission.NAVAL_RING_CANDIDATES, offsets, head)
		var c: Vector2 = placement["center"]
		var ring_used: float = float(placement["ring"])
		var reach: float = NavalPlacement.fleet_reach(ring_used, offsets)
		var land: int = _verify_land_hits(c, ring_used, offsets, head)
		print("   %d★：盘旋半径 %.0f、占地半径 %.0f px；摆位圆心 %s（离战区中心 %.0f px）；加密复核落地 %d 点" % [
			star, ring_used, reach, str(c.round()), c.distance_to(center), land])
		_check("战区 %s %d★ 舰队占地 %.0f ≤ 可用水域 %.0f" % [String(z["label"]), star, reach, budget_r],
			reach <= budget_r)
		_check("战区 %s %d★ 舰队全程不上岸（40px 步长复核）" % [String(z["label"]), star], land == 0)
		# 水域优先于"圈内"：窄水域（浦贺水道）里挪不出既贴中心又全水的位置时，
		# 允许舰队外圈溢出战区环 —— 但溢出必须有界，否则任务目标会跑到玩家找不到的地方
		_check("战区 %s %d★ 舰队溢出战区环有界（圆心 %.0f + 占地 %.0f ≤ 半径 + 2000）" % [
				String(z["label"]), star, c.distance_to(center), reach],
			c.distance_to(center) + reach <= radius + 2000.0)


## CSG（BOSS 舰队）：南/北两个 BOSS 锚点吸附水面后，11 舰盘旋一圈同样不许上岸
func _check_csg() -> void:
	print("── CSG BOSS 舰队（南/北锚点）──")
	var zd := ZoneData.new()
	var offsets: Array = CarrierStrikeGroup.ESCORT_OFFSETS
	var nudges: Array = NavalPlacement.ring_nudges(CarrierStrikeGroup.PLACEMENT_NUDGE_RADII)
	for entry in [["北", ZoneData.BOSS_NORTH_CENTER], ["南", ZoneData.BOSS_SOUTH_CENTER]]:
		var label: String = entry[0]
		var raw: Vector2 = entry[1]
		var anchor: Vector2 = zd._snap_to_water(raw, ZoneData.BOSS_RADIUS)
		var budget: Dictionary = _water_budget(anchor, 4000.0)
		print("   %s 锚点可用水域：以 %s 为心最大全水半径 %.0f px" % [
			label, str((budget["center"] as Vector2).round()), budget["radius"]])
		# CSG 出场朝向：南锚点朝北(0°)、北锚点朝西南(225°)，与 ZoneData 的 BOSS_*_HEADING_DEG 一致
		var head: float = deg_to_rad(
				ZoneData.BOSS_SOUTH_HEADING_DEG if label == "南" else ZoneData.BOSS_NORTH_HEADING_DEG)
		var picked: Dictionary = NavalPlacement.pick_placement(
				anchor, nudges, CarrierStrikeGroup.PLACEMENT_RING_CANDIDATES, offsets, head)
		var c: Vector2 = picked["center"]
		var ring_used: float = float(picked["ring"])
		var reach: float = NavalPlacement.fleet_reach(ring_used, offsets)
		var land: int = _verify_land_hits(c, ring_used, offsets, head)
		print("   %s 锚点 %s → 摆位圆心 %s（挪了 %.0f px）；盘旋半径 %.0f、占地半径 %.0f；加密复核落地 %d 点" % [
			label, str(anchor.round()), str(c.round()), c.distance_to(anchor), ring_used, reach, land])
		_check("CSG %s 锚点舰队全程不上岸（40px 步长复核）" % label, land == 0)


## 加密复核：沿每艘船的轨道圆用**比实现更细的步长**扫一遍（实现 150 px，这里 40 px）
func _verify_land_hits(center: Vector2, ring: float, offsets: Array, base_heading_rad: float = 0.0) -> int:
	var land := 0
	if ring <= 1.0:
		# 原地驻泊：舰队完全不动，只有出生那一组位置
		for p in NavalPlacement.fleet_positions(center, 0.0, offsets, base_heading_rad):
			if MapGeography.is_on_land(p):
				land += 1
		return land
	for r in NavalPlacement.ship_orbit_radii(ring, offsets):
		var n: int = clampi(ceili(TAU * r / VERIFY_STEP_PX), 8, 1024)
		for k in range(n):
			var a: float = TAU * float(k) / float(n)
			if MapGeography.is_on_land(center + Vector2(cos(a), sin(a)) * r):
				land += 1
	return land


## 战区内可用水域预算：搜一个"全水圆"最大的圆心 → { center, radius }
## 舰队占地半径必须塞进这个圆，否则怎么挪都会有船上岸（只能缩编队）
func _water_budget(center: Vector2, zone_radius: float) -> Dictionary:
	var best := {"center": center, "radius": 0.0}
	var step: float = zone_radius / 5.0
	var g: int = 5
	for ix in range(-g, g + 1):
		for iy in range(-g, g + 1):
			var c: Vector2 = center + Vector2(float(ix) * step, float(iy) * step)
			if c.distance_to(center) > zone_radius:
				continue
			if MapGeography.is_on_land(c):
				continue
			var r: float = 0.0
			var probe: float = 250.0
			while probe <= 5000.0:
				var clear := true
				for k in range(16):
					var a: float = TAU * float(k) / 16.0
					if MapGeography.is_on_land(c + Vector2(cos(a), sin(a)) * probe):
						clear = false
						break
				if not clear:
					break
				r = probe
				probe += 250.0
			if r > float(best["radius"]):
				best = {"center": c, "radius": r}
	return best


func _check(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("   ✓ %s" % label)
	else:
		_fail += 1
		printerr("   ✗ %s" % label)
