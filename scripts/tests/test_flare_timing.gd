extends RefCounted

## 无头智能放焰测试（2026-06-14）
## 验证 AircraftFlares.player_flare_should_trigger：玩家方只对"会命中且即将到达"的导弹放焰，
## 对慢速/追不上的导弹不放（不浪费）。
## 运行：godot --headless --path . -- --bench=flare
##
## 几何约定：ac 在原点、heading=0（机头朝北 -y、前向=(0,-1)）。
## 1 像素 = 2 米（PIXELS_PER_METER=0.5）。导弹放在 +y（机尾后方）做尾追，heading=0 表示也朝 -y 追。

const PPM := 0.5

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ 智能放焰(TTI)测试 ════════")
	print("阈值：TTI≤%.1fs 放 / 距离≤%.0fm 兜底放 / 闭合<%.0fm·s⁻¹ 不放" % [
		AircraftFlares.FLARE_TTI_THRESHOLD, AircraftFlares.FLARE_MIN_DIST_M,
		AircraftFlares.FLARE_MIN_CLOSING_MS])

	# (ac_spd, m_dist_px, m_spd, m_hdg, 期望放焰?, 说明)
	# ac 始终 heading=0 speed=300m/s；导弹位置 (0, +dist_px) 在机尾后方
	_case("慢速追不上(浪费案例)", 300.0, 400.0, 250.0, 0.0, false,
			"导弹 250<本机 300，间距在拉大 → 不放")
	_case("快弹远距(3km)",        300.0, 1500.0, 1100.0, 0.0, false,
			"闭合 800，但 TTI=3.75s 还早 → 等")
	_case("快弹逼近(1km)",        300.0, 500.0, 1100.0, 0.0, true,
			"闭合 800，TTI=1.25s≤1.5 → 放")
	_case("慢弹但逼近·贴脸300m",  300.0, 150.0, 350.0, 0.0, true,
			"闭合 50，TTI=6s 但距离=300m 触兜底 → 放")
	_case("慢弹逼近·仍远800m",    300.0, 400.0, 350.0, 0.0, false,
			"闭合 50，TTI=16s 且 800m>300m → 等（进 300m 才放）")

	print("── 规避(加速散开)威胁门：只对逼近且即将到达的导弹散开 ──")
	print("阈值：TTI≤%.1fs 且 闭合≥%.0fm·s⁻¹ 才散开" % [
		MissileEvasion.EVADE_TTI_THRESHOLD, MissileEvasion.EVADE_MIN_CLOSING_MS])
	# ac heading=0 speed=250m/s（巡航）；导弹在机尾后方 +y 追击
	_evade_case("慢弹追不上",     250.0, 400.0, 280.0, false, "闭合 30<60 → 不散开(留阵型,flare 兜底)")
	_evade_case("快弹远(TTI5.9s)", 250.0, 2500.0, 1100.0, false, "闭合 850 但 TTI 5.9s 还早 → 不散开")
	_evade_case("快弹中距(TTI4s)", 250.0, 1700.0, 1100.0, false, "TTI 4.0s>3.5 → 再等等")
	_evade_case("快弹临近(TTI1.9s)",250.0, 800.0, 1100.0, true,  "闭合 850,TTI 1.9s≤3.5 → 散开")

	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("════════════════════════════════\n")


func _evade_case(name: String, ac_spd: float, m_dist_px: float, m_spd: float,
		expect: bool, note: String) -> void:
	var ac = load("res://scripts/aircraft.gd").new()
	ac.global_position = Vector2.ZERO
	ac.heading = 0.0
	ac.speed = ac_spd
	ac.team = 0
	var m := Missile.new()
	m.global_position = Vector2(0.0, m_dist_px)
	m.heading = 0.0
	m.speed = m_spd
	var got: bool = MissileEvasion._is_evasion_threat(ac, m)
	var ok := got == expect
	if ok: _pass += 1
	else: _fail += 1
	print("  %s %-18s 距离=%.0fm 期望=%s 实际=%s — %s" % [
		"✓" if ok else "✗", name, m_dist_px / PPM,
		"散开" if expect else "不散开", "散开" if got else "不散开", note])
	m.free(); ac.free()


func _case(name: String, ac_spd: float, m_dist_px: float, m_spd: float,
		m_hdg_deg: float, expect: bool, note: String) -> void:
	var ac = load("res://scripts/aircraft.gd").new()
	ac.global_position = Vector2.ZERO
	ac.heading = 0.0
	ac.speed = ac_spd
	var m := Missile.new()
	m.global_position = Vector2(0.0, m_dist_px)   # 机尾后方 +y
	m.heading = deg_to_rad(m_hdg_deg)
	m.speed = m_spd
	var got: bool = AircraftFlares.player_flare_should_trigger(ac, m)
	var dist_m := m_dist_px / PPM
	var ok := got == expect
	if ok: _pass += 1
	else: _fail += 1
	print("  %s %-22s 距离=%.0fm 期望=%s 实际=%s — %s" % [
		"✓" if ok else "✗", name, dist_m,
		"放" if expect else "不放", "放" if got else "不放", note])
	m.free(); ac.free()
