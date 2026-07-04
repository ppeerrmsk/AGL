extends RefCounted

## 武器使用准则竞选器测试（spec weapon-employment-doctrine §5 验收，阶段 1）
## 运行：godot --headless --path . -- --bench=weapon_doctrine（或 --bench=all）

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ 武器竞选器（weapon-employment-doctrine §2.2） ════════")
	_test_pure_select()
	_test_dynamic_candidates()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════════════\n")


func _test_pure_select() -> void:
	print("── 竞选规则（纯函数）──")
	var cands := [
		{"kind": "railgun", "band_min": 2500.0, "band_max": 8000.0, "ready": true},
		{"kind": "missile", "band_min": 500.0, "band_max": 6000.0, "ready": true},
		{"kind": "gun", "band_min": 60.0, "band_max": 1000.0, "ready": true},
	]
	# 1. 远距重叠区（railgun+missile 都在带内）→ 命中率优先选电磁炮
	var r := WeaponSelector.select(cands, 5000.0)
	_check("重叠区命中率优先=电磁炮", r.kind == "railgun", "5000m：railgun(100)>missile(70)")
	# 2. 电磁炮冷却中 → 导弹接手
	cands[0]["ready"] = false
	r = WeaponSelector.select(cands, 5000.0)
	_check("电磁炮 CD → 导弹", r.kind == "missile", "")
	cands[0]["ready"] = true
	# 3. 近距（电磁炮最近射程外）→ 固定机炮（涌现，无特判）
	r = WeaponSelector.select(cands, 300.0)
	_check("近距固定机炮", r.kind == "gun", "300m < railgun band_min 且 < missile min")
	# 4. 全失格 → 维持追击 + 导弹纪律等待
	var all_cd := [
		{"kind": "missile", "band_min": 500.0, "band_max": 6000.0, "ready": false},
		{"kind": "gun", "band_min": 60.0, "band_max": 1000.0, "ready": false},
	]
	r = WeaponSelector.select(all_cd, 800.0)
	_check("全 CD → 空手 + 导弹纪律等待", r.kind == "" and r.wait_doctrine == "missile",
			"不再机炮硬兜底，crank 保锁等 CD")
	# 5. 滞回：上任 missile 仍合格且保持 <1.5s → 不切 railgun
	r = WeaponSelector.select(cands, 5000.0, "missile", 0.5)
	_check("滞回期内不换武器", r.kind == "missile", "hold 0.5s < 1.5s")
	r = WeaponSelector.select(cands, 5000.0, "missile", 1.6)
	_check("滞回期满切到更优武器", r.kind == "railgun", "hold 1.6s ≥ 1.5s")
	# 6. 上任已失格（出带）→ 滞回不锁死，立即重选
	r = WeaponSelector.select(cands, 300.0, "railgun", 0.2)
	_check("上任出带立即重选", r.kind == "gun", "滞回只对'仍合格'的上任生效")


func _test_dynamic_candidates() -> void:
	print("── 动态距离带（live params，升级即时生效）──")
	var ac: Aircraft = load("res://scripts/aircraft.gd").new()
	var p = AircraftParams.new()
	var g = GunParams.new(); g.max_range = 1000.0
	p.gun = g
	var m = MissileParams.new(); m.min_range = 500.0; m.max_range_rear = 6000.0
	p.missile = m
	ac.params = p
	ac.ammo = 100
	ac.missiles_remaining = 4

	var cands := WeaponSelector.build_candidates(ac)
	_check("候选表含 gun+missile", cands.size() == 2, "")
	var r := WeaponSelector.select(cands, 7000.0)
	_check("7000m 超出导弹带 → 空手", r.kind == "", "升级前打不到")

	# 模拟"导弹锁定距离升级"：改 live params → 下次竞选立即反映（用户定稿 1a/1b）
	m.max_range_rear = 9000.0
	cands = WeaponSelector.build_candidates(ac)
	r = WeaponSelector.select(cands, 7000.0)
	_check("升级射程后同距离立即可用", r.kind == "missile",
			"距离带动态：改 params 下一次竞选即生效，无烘焙")

	# 弹药就绪门
	ac.missiles_remaining = 0
	cands = WeaponSelector.build_candidates(ac)
	r = WeaponSelector.select(cands, 7000.0)
	_check("弹尽失格", r.kind == "", "")

	ac.free()


func _check(name: String, got: bool, note: String) -> void:
	if got: _pass += 1
	else: _fail += 1
	print("  %s %-28s — %s" % ["✓" if got else "✗", name, note])
