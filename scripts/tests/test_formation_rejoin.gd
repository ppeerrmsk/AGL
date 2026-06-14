extends RefCounted

## 无头编队归队速度测试（2026-06-13）
## 量化"僚机飞回长机身边"的归队耗时 + 超调，验证 _update_speed 提速修复。
## 运行：godot --headless --path . -- --bench=rejoin
##
## 隔离被测函数 AircraftFormation._update_speed：裸构造 leader/wingman + 手填 ctx，
## 1D 闭合仿真（slot 以长机速度前进，僚机以自身速度追），统计归队到 ≤50px 的耗时。

const DT := 0.05   ## 20Hz，匹配编队速度更新分频（update_follow 每 3 帧 ×3）
const PPM := 0.5   ## PIXELS_PER_METER
const CLOSE := 50.0
const MAX_T := 30.0


func run() -> void:
	print("\n════════ 编队归队速度测试 ════════")
	var params: Resource = load("res://resources/playable_f14_wingman.tres")
	if params == null:
		params = load("res://resources/default_fighter.tres")
	var ldr_kmh := 850.0
	print("长机匀速直飞=%.0fkmh  机型=%s max_speed=%.0fkmh" % [
		ldr_kmh, str(params.display_name), params.max_speed])
	print("── 纯尾后归队（slot 在正前方）──")
	_sim_trailing(params, ldr_kmh, 600.0)
	_sim_trailing(params, ldr_kmh, 400.0)
	_sim_trailing(params, ldr_kmh, 200.0)
	print("── FAR 归队放开 bank 到满 G（compute_target_bank 直测）──")
	_bank_cap_check()
	print("── 航向对齐门（同一 slot_d=600px，槽位在不同方位时的目标速度）──")
	print("    期望：对准(0°)→满速冲刺；侧/后(≥90°)→角点速度先转向")
	_alignment_speed(params, ldr_kmh, 600.0, 0.0)
	_alignment_speed(params, ldr_kmh, 600.0, 90.0)
	_alignment_speed(params, ldr_kmh, 600.0, 180.0)
	print("── 掉头归队（机头背对槽位，需 ~180° 转弯 + 闭合）2D ──")
	print("    长机匀速 %.0fkmh（接战中疾飞，worst case）：" % ldr_kmh)
	_sim_turnback(params, ldr_kmh, 2000.0)
	_sim_turnback(params, ldr_kmh, 1000.0)
	print("    长机 250kmh（玩家未操作/不接战，realistic）：")
	_sim_turnback(params, 250.0, 2000.0)
	_sim_turnback(params, 250.0, 1000.0)
	print("════════════════════════════════\n")


## 2D 掉头归队：僚机起始在槽位后方 gap0、机头【背对】槽位（需先掉头 ~180° 再闭合）。
## 复现"max 速度归队转不回来原地绕大圈、slot_d 越飞越远"的回归。
## 转向用 ω=min(maxG·g/v, FORMATION_MAX_TURN_RATE)（捕捉 ω∝1/v 的转弯半径耦合），速度走真实 _update_speed。
func _sim_turnback(params: Resource, ldr_kmh: float, gap0: float) -> void:
	var ldr = load("res://scripts/aircraft.gd").new()
	ldr.params = params; ldr.heading = 0.0; ldr.altitude = 6000.0
	ldr.speed = ldr_kmh / 3.6
	ldr.global_position = Vector2.ZERO
	var ac = _make_ac(params, ldr_kmh)
	var offset := Vector2(0.0, 300.0)            # 槽位 = 长机正后方 300px（尾随槽）
	ac.global_position = ldr.global_position + offset + Vector2(0.0, gap0)  # 再靠后 gap0
	ac.heading = deg_to_rad(180.0)               # 机头朝南：背对北边的长机/槽位 → 需掉头
	var maxg: float = params.max_g if "max_g" in params and params.max_g > 0.0 else 8.0
	var t := 0.0
	var rejoin_t := -1.0
	var max_slot_d := 0.0
	while t < 30.0:
		ldr.global_position += Vector2(sin(ldr.heading), -cos(ldr.heading)) * ldr.speed * PPM * DT
		var slot_pos: Vector2 = ldr.global_position + offset
		var to_slot: Vector2 = slot_pos - ac.global_position
		var slot_d_px: float = to_slot.length()
		max_slot_d = maxf(max_slot_d, slot_d_px)
		if rejoin_t < 0.0 and slot_d_px <= CLOSE:
			rejoin_t = t
			break
		var slot_local: Vector2 = to_slot.rotated(-ldr.heading)
		var ctx := {
			"ldr": ldr, "b": 1.0, "slot_pos": slot_pos,
			"slot_dist": slot_d_px, "fwd_offset": -slot_local.y,
			"jitter_t": 0.0, "jitter_phase": 0.0,
		}
		AircraftFormation._update_speed(ac, ctx, DT)
		var slot_hdg := atan2(to_slot.x, -to_slot.y)
		var herr: float = atan2(sin(slot_hdg - ac.heading), cos(slot_hdg - ac.heading))
		var omega: float = minf(maxg * 9.81 / maxf(ac.speed, 50.0), AircraftFormation.FORMATION_MAX_TURN_RATE)
		var step: float = clampf(herr, -omega * DT, omega * DT)
		ac.heading = atan2(sin(ac.heading + step), cos(ac.heading + step))
		ac.global_position += Vector2(sin(ac.heading), -cos(ac.heading)) * ac.speed * PPM * DT
		t += DT
	var rt := ("%.1fs" % rejoin_t) if rejoin_t > 0.0 else ">30s 未归队"
	print("  起始后方 %4.0fpx 背对 → 归队 %-12s 峰值 slot_d=%.0fpx" % [gap0, rt, max_slot_d])
	ldr.free(); ac.free()


func _make_ac(params: Resource, ldr_kmh: float):
	var ac = load("res://scripts/aircraft.gd").new()
	ac.params = params
	ac.altitude = 6000.0
	ac.speed = ldr_kmh / 3.6
	ac.cloud_state = 0
	ac.in_building = false
	return ac


## 1D 尾后归队：slot 在正前方 gap0 px，统计归队耗时 + 超调
func _sim_trailing(params: Resource, ldr_kmh: float, gap0: float) -> void:
	var ldr = load("res://scripts/aircraft.gd").new()
	ldr.params = params
	ldr.speed = ldr_kmh / 3.6
	var ac = _make_ac(params, ldr_kmh)
	var gap := gap0
	var t := 0.0
	var min_gap := gap0
	var rejoin_t := -1.0
	while t < MAX_T:
		var ctx := {
			"ldr": ldr, "b": 1.0,
			"slot_pos": Vector2(0.0, -gap),          # 槽位正前方（机头 heading=0 = 北 -y）→ 对齐
			"fwd_offset": gap, "slot_dist": absf(gap),
			"jitter_t": 0.0, "jitter_phase": 0.0,
		}
		AircraftFormation._update_speed(ac, ctx, DT)
		gap -= (ac.speed - ldr.speed) * PPM * DT   # slot 前进 vs 僚机前进 → 闭合
		min_gap = minf(min_gap, gap)
		t += DT
		if rejoin_t < 0.0 and gap <= CLOSE:
			rejoin_t = t
		if rejoin_t > 0.0 and t > rejoin_t + 3.0:
			break   # 归队后再跑 3s 看超调/稳定
	var overshoot := maxf(0.0, -min_gap)   # 冲过 slot 中心多少 px
	var rt_str := ("%.1fs" % rejoin_t) if rejoin_t > 0.0 else (">%.0fs 未归队" % MAX_T)
	print("  起始 %4.0fpx → 归队(≤50px) %-12s 末速=%.0fkmh 超调=%.0fpx" % [
		gap0, rt_str, ac.speed * 3.6, overshoot])
	ldr.free(); ac.free()


## FAR 归队 bank 上限直测：大航向误差下，formation 柔和 cap(0.9×) vs FAR 满 bank 的 G 对比。
## 修复前编队恒走 0.9×max_bank → ~4.4G；修复后 FAR(_formation_full_bank) 走满 bank → ~12.5G（追平玩家）。
func _bank_cap_check() -> void:
	var max_g_struct := 12.5
	var max_bank: float = acos(1.0 / max_g_struct)   # 结构极限坡度（=12.5G）
	var speed := 194.0                                # m/s，角点速度量级
	var e := 1.5                                      # rad，大航向误差（FAR 归队典型）
	# formation_mode 参数：false = FAR 满 bank 路径；true = 旧编队柔和 0.9 cap
	var b_full: float = AircraftPhysics.compute_target_bank(
			e, 0.0, 0.0, speed, max_bank, false, false, 0, 0, false, 1.0, 0.02, 5.0, 1.0)
	var b_form: float = AircraftPhysics.compute_target_bank(
			e, 0.0, 0.0, speed, max_bank, false, false, 0, 0, true, 1.0, 0.02, 5.0, 1.0)
	var g_full: float = 1.0 / cos(absf(b_full))
	var g_form: float = 1.0 / cos(absf(b_form))
	var ok := g_full > g_form + 3.0
	print("  %s FAR 满bank: bank=%.0f° G=%.1f   旧编队cap: bank=%.0f° G=%.1f" % [
		"✓" if ok else "✗", rad_to_deg(b_full), g_full, rad_to_deg(b_form), g_form])


## 航向对齐门：槽位放在机头 angle_deg 方位（0=正前/对准, 90=正侧, 180=正后），看目标速度。
## 对准 → 全速冲刺；未对准（≥90°）→ 角点速度先转向（max 速度转不回来 → 原地绕圈的根因修复）。
func _alignment_speed(params: Resource, ldr_kmh: float, slot_d: float, angle_deg: float) -> void:
	var ldr = load("res://scripts/aircraft.gd").new()
	ldr.params = params
	ldr.speed = ldr_kmh / 3.6
	var ac = _make_ac(params, ldr_kmh)
	ac.global_position = Vector2.ZERO
	ac.heading = 0.0   # 机头朝北 -y
	# 槽位在机头 angle_deg 方位、距离 slot_d px
	var a: float = deg_to_rad(angle_deg)
	var slot_pos: Vector2 = Vector2(sin(a), -cos(a)) * slot_d
	var slot_local: Vector2 = slot_pos.rotated(-ldr.heading)
	var ctx := {
		"ldr": ldr, "b": 1.0, "slot_pos": slot_pos,
		"fwd_offset": -slot_local.y, "slot_dist": slot_d,
		"jitter_t": 0.0, "jitter_phase": 0.0,
	}
	AircraftFormation._update_speed(ac, ctx, DT)
	var chase_kmh: float = ac._dbg_chase_target_kmh
	var corner_kmh: float = AircraftPhysics.effective_corner_speed_kmh(ac)
	print("  槽位方位 %3.0f° → chase_target=%.0fkmh (角点≈%.0f, max=%.0f)" % [
		angle_deg, chase_kmh, corner_kmh, params.max_speed])
	ldr.free(); ac.free()
