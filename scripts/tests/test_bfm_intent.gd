class_name BfmIntentTest extends RefCounted

## TacticalPlanner / BfmIntent 单元测试
##
## 调用方式：
##   var ok: bool = BfmIntentTest.run_all()
##
## 测试通过原则：
## - 每个测试构造一个 Situation（手填字段，不依赖 Aircraft 实例）
## - 调用 TacticalPlanner.plan(s) 或单个 BfmIntent.xxx(s)
## - 断言关键字段（intent / weapon_mode / afterburner / pursuit_pos）
##
## 失败时打印每条 case 的预期 vs 实际 + 诊断 dict，便于定位

static var _failures: Array[String] = []
static var _passed: int = 0

# ══════════════════════════════════════════════
#  入口
# ══════════════════════════════════════════════

static func run_all() -> bool:
	_failures = []
	_passed = 0

	test_cruise_no_target()
	test_passive_auto_fire()
	test_passive_disabled_when_auto_off()
	test_waypoint_aligned()
	test_waypoint_big_turn()
	test_evade_overrides_combat()
	test_close_tail_far()
	test_tail_chase_in_range()
	test_lead_turn_unaligned()
	test_lead_pursuit_side()
	test_lag_pursuit_circling()
	test_merge_pass_head_on()
	test_wide_turn()
	test_weapon_lock_force_gun()
	test_charge_overrides_lock()
	test_tail_chase_with_missiles_uses_missile()
	test_close_tail_with_missiles_uses_missile()
	test_ground_strafe_charge_uses_max_speed()
	test_ground_strafe_default_speed()
	test_ground_strafe_setup_when_off_axis()
	test_ground_strafe_break_when_overshoot()
	test_naval_target_uses_strafe()
	test_missile_mode_uses_crank_geometry()
	test_hysteresis_holds_combat_intent()
	test_hysteresis_doesnt_lock_evade()
	test_overshoot_triggers_extend()
	test_extend_remaining_holds_intent()
	test_evade_overrides_extend()
	test_boom_zoom_triggers_on_stalemate()
	test_boom_zoom_skipped_if_aspect_improved()
	test_boom_zoom_skipped_for_gladiator()
	test_wingman_lateral_offset()
	test_wingman_no_offset_solo()
	test_waypoint_move_allows_passive_fire()
	test_wingman_complementary_lag_when_leader_tail_chase()
	test_wingman_complementary_lead_when_leader_tail_chase()
	test_wingman_follows_leader_extend()
	test_altitude_preference_low_in_cruise()
	test_altitude_preference_low_in_waypoint()
	test_crank_stays_in_radar_cone()
	test_lock_band_keeps_los()
	test_missile_unlocked_keeps_los()

	var total: int = _passed + _failures.size()
	print("════════════════════════════════════════════")
	print("BfmIntent 测试结果：%d / %d 通过" % [_passed, total])
	if _failures.size() > 0:
		print("失败列表：")
		for f in _failures:
			print("  ✗ ", f)
	else:
		print("全部通过 ✓")
	print("════════════════════════════════════════════")
	return _failures.is_empty()

# ══════════════════════════════════════════════
#  测试用例
# ══════════════════════════════════════════════

static func test_cruise_no_target() -> void:
	# 无目标 + 无 missile auto-fire 条件 → CRUISE。weapon = GUN（防止 salvo 路径残留发射）
	var s := Situation.new_for_test({"has_target": false, "missiles": 0})
	var p := TacticalPlanner.plan(s)
	_assert_eq("cruise_no_target.intent", TacticalPlan.Intent.CRUISE, p.intent)
	_assert_eq("cruise_no_target.weapon=GUN", TacticalPlan.WeaponMode.GUN, p.weapon_mode)
	_assert_eq("cruise_no_target.no_msl", false, p.allow_missile_fire)
	_assert_eq("cruise_no_target.ab", false, p.afterburner)

## 无 combat_target 但有雷达锁定 + 有导弹 + auto-fire 开 → PASSIVE_AUTO_FIRE
static func test_passive_auto_fire() -> void:
	var s := Situation.new_for_test({
		"has_target": false,
		"missiles": 4,
		"missile_auto_fire": true,
		"has_radar_lock": true,
	})
	var p := TacticalPlanner.plan(s)
	_assert_eq("passive.intent", TacticalPlan.Intent.PASSIVE_AUTO_FIRE, p.intent)
	_assert_eq("passive.weapon=MSL", TacticalPlan.WeaponMode.MISSILE, p.weapon_mode)
	_assert_eq("passive.fire_msl", true, p.allow_missile_fire)

## auto-fire 关 → 即使有锁定也不进 PASSIVE，回到 CRUISE
static func test_passive_disabled_when_auto_off() -> void:
	var s := Situation.new_for_test({
		"has_target": false,
		"missiles": 4,
		"missile_auto_fire": false,
		"has_radar_lock": true,
	})
	var p := TacticalPlanner.plan(s)
	_assert_eq("passive_off.intent", TacticalPlan.Intent.CRUISE, p.intent)

static func test_waypoint_aligned() -> void:
	var s := Situation.new_for_test({
		"has_target": false,
		"my_pos": Vector2.ZERO,
		"my_heading": 0.0,  # 朝北
	})
	# waypoint 在正北 1km 处，对准
	var wp := Vector2(0, -1000.0)
	var p := TacticalPlanner.plan(s, wp)
	_assert_eq("waypoint_aligned.intent", TacticalPlan.Intent.WAYPOINT_MOVE, p.intent)
	_assert_true("waypoint_aligned.spd>cruise", p.target_speed_kmh > s.cruise_speed_kmh)

static func test_waypoint_big_turn() -> void:
	# 2026-05-07 设计变更（bfm_intent.waypoint_move 注释）：AB 不再按"hdiff>60° 禁开"
	# 离散切换，改为"当前速度 < target 的 95% 就给"，跟随 smoothstep 的 target 平滑变化。
	# 旧断言 ab=false 属旧设计残留（F10 手测时代未被发现，2026-07-03 接入 bench 后修正）。
	var s := Situation.new_for_test({
		"has_target": false,
		"my_pos": Vector2.ZERO,
		"my_heading": 0.0,  # 朝北
	})
	# waypoint 在正东（90° 偏差）→ t=0 全 corner speed
	var wp := Vector2(1000.0, 0)
	var p := TacticalPlanner.plan(s, wp)
	_assert_eq("waypoint_big_turn.intent", TacticalPlan.Intent.WAYPOINT_MOVE, p.intent)
	_assert_eq("waypoint_big_turn.spd=corner", s.corner_speed_kmh, p.target_speed_kmh)
	# 慢速（my_speed=0）大转弯：低于 corner×0.95 → 开 AB 追目标速度
	_assert_eq("waypoint_big_turn.ab_slow=true", true, p.afterburner)
	# 已在角点速度巡航转弯：不浪费 AB
	var s2 := Situation.new_for_test({
		"has_target": false,
		"my_pos": Vector2.ZERO,
		"my_heading": 0.0,
		"my_speed_ms": s.corner_speed_kmh / 3.6,
	})
	var p2 := TacticalPlanner.plan(s2, wp)
	_assert_eq("waypoint_big_turn.ab_at_corner=false", false, p2.afterburner)

static func test_evade_overrides_combat() -> void:
	# 即使有目标 + 对头，规避也优先
	var s := Situation.new_for_test({
		"has_target": true,
		"evasion_intent": true,
		"my_pos": Vector2.ZERO, "tgt_pos": Vector2(0, -500.0),
		"my_heading": 0.0, "tgt_heading": PI,  # 对头
	})
	var p := TacticalPlanner.plan(s)
	_assert_eq("evade.intent", TacticalPlan.Intent.EVADE_MISSILE, p.intent)
	_assert_eq("evade.ab", true, p.afterburner)
	_assert_eq("evade.weapon", TacticalPlan.WeaponMode.NONE, p.weapon_mode)

static func test_close_tail_far() -> void:
	# 玩家在敌后 1500m，敌航向同向（同向追尾），敌速慢
	# F-16 gun_range = 1000m，超过 1.2× = 1200m → 应触发 CLOSE_TAIL
	var s := _build_tail_situation(1500.0)
	var p := TacticalPlanner.plan(s)
	_assert_eq("close_tail.intent", TacticalPlan.Intent.CLOSE_TAIL, p.intent)
	_assert_true("close_tail.ab", p.afterburner)
	_assert_eq("close_tail.weapon", TacticalPlan.WeaponMode.GUN, p.weapon_mode)
	_assert_eq("close_tail.no_fire", false, p.allow_gun_fire)

static func test_tail_chase_in_range() -> void:
	# 玩家在敌后 800m，gun_range 1000m，应该 TAIL_CHASE
	var s := _build_tail_situation(800.0)
	var p := TacticalPlanner.plan(s)
	_assert_eq("tail_chase.intent", TacticalPlan.Intent.TAIL_CHASE, p.intent)
	_assert_eq("tail_chase.weapon", TacticalPlan.WeaponMode.GUN, p.weapon_mode)
	# allow_gun_fire 取决于 lead_pos 角度，这里同向追尾 lead 偏移小，应该开火
	_assert_true("tail_chase.fire_allowed", p.allow_gun_fire)

static func test_lead_turn_unaligned() -> void:
	# 玩家在敌后但 heading 偏 60°（aim_align ≈ 0.5）
	var s := Situation.new_for_test({
		"has_target": true,
		"my_pos": Vector2.ZERO,
		"tgt_pos": Vector2(0, -800.0),  # 敌在正北 800m
		"my_heading": deg_to_rad(60.0),  # 我朝东北 60°
		"tgt_heading": 0.0,  # 敌朝北（同向）
		"my_speed_ms": 200.0, "tgt_speed_ms": 150.0,
		"missiles": 0,
	})
	var p := TacticalPlanner.plan(s)
	_assert_eq("lead_turn.intent", TacticalPlan.Intent.LEAD_TURN, p.intent)
	_assert_eq("lead_turn.spd=corner", s.corner_speed_kmh, p.target_speed_kmh)

static func test_lead_pursuit_side() -> void:
	# 敌在玩家右侧，飞向北，玩家朝北。aspect 90°，bank 0
	var s := Situation.new_for_test({
		"has_target": true,
		"my_pos": Vector2.ZERO,
		"tgt_pos": Vector2(800.0, 0),  # 正东 800m
		"my_heading": deg_to_rad(90.0),  # 我朝东
		"tgt_heading": 0.0,  # 敌朝北
		"tgt_bank_deg": 5.0,  # 几乎没在转弯
		"my_speed_ms": 200.0, "tgt_speed_ms": 150.0,
		"missiles": 0,
	})
	var p := TacticalPlanner.plan(s)
	_assert_eq("lead_pursuit.intent", TacticalPlan.Intent.LEAD_PURSUIT, p.intent)

static func test_lag_pursuit_circling() -> void:
	# 敌在玩家右侧绕圈（bank 75°），距离 1200m（清晰在 LAG 触发带 < gun_range × 3 = 3000m 内）
	var s := Situation.new_for_test({
		"has_target": true,
		"my_pos": Vector2.ZERO,
		"tgt_pos": Vector2(600.0, 0),  # dist_px=600 → dist_m=1200m
		"my_heading": deg_to_rad(90.0),
		"tgt_heading": 0.0,
		"tgt_bank_deg": 75.0,  # 急转
		"my_speed_ms": 200.0, "tgt_speed_ms": 180.0,
		"gun_range_m": 1000.0,
		"missiles": 0,
	})
	var p := TacticalPlanner.plan(s)
	_assert_eq("lag.intent", TacticalPlan.Intent.LAG_PURSUIT, p.intent)
	_assert_eq("lag.spd=corner", s.corner_speed_kmh, p.target_speed_kmh)
	# pursuit_pos 应该不是简单的 lead_pos，至少应当与 lead_pursuit 的输出不同
	var p_lead := BfmIntent.lead_pursuit(s)
	_assert_true("lag.pursuit_distinct", p.pursuit_pos.distance_to(p_lead.pursuit_pos) > 100.0)

static func test_merge_pass_head_on() -> void:
	# 头对头：玩家朝北，敌朝南，距离 1500m
	var s := Situation.new_for_test({
		"has_target": true,
		"my_pos": Vector2.ZERO,
		"tgt_pos": Vector2(0, -1500.0),  # 敌在我正北 1500m
		"my_heading": 0.0,  # 朝北
		"tgt_heading": PI,  # 朝南（朝我）
		"my_speed_ms": 250.0, "tgt_speed_ms": 250.0,
		"missiles": 0,  # 无导弹强制走机炮
	})
	var p := TacticalPlanner.plan(s)
	_assert_eq("merge.intent", TacticalPlan.Intent.MERGE_PASS, p.intent)

static func test_wide_turn() -> void:
	# 玩家与目标 heading 差 >90° — 目标在玩家身后
	var s := Situation.new_for_test({
		"has_target": true,
		"my_pos": Vector2.ZERO,
		"tgt_pos": Vector2(0, 800.0),  # 敌在正南（我身后）
		"my_heading": 0.0,  # 我朝北
		"tgt_heading": 0.0,
		"my_speed_ms": 200.0, "tgt_speed_ms": 100.0,
	})
	var p := TacticalPlanner.plan(s)
	_assert_eq("wide_turn.intent", TacticalPlan.Intent.WIDE_TURN, p.intent)

static func test_weapon_lock_force_gun() -> void:
	# 几何上应该用导弹（侧翼 + 远距），但玩家锁了机炮
	var s := Situation.new_for_test({
		"has_target": true,
		"my_pos": Vector2.ZERO,
		"tgt_pos": Vector2(3000.0, 0),
		"my_heading": deg_to_rad(90.0),
		"tgt_heading": 0.0,
		"tgt_bank_deg": 5.0,
		"my_speed_ms": 200.0, "tgt_speed_ms": 150.0,
		"missiles": 6,
		"missile_max_range_m": 8000.0, "missile_min_range_m": 500.0,
		"weapon_lock": Situation.WEAPON_LOCK_FORCE_GUN,
	})
	var p := TacticalPlanner.plan(s)
	_assert_eq("lock_gun.weapon", TacticalPlan.WeaponMode.GUN, p.weapon_mode)
	_assert_eq("lock_gun.no_msl", false, p.allow_missile_fire)

static func test_charge_overrides_lock() -> void:
	# 玩家原本 PREFER_MISSILE（weapon_lock=NONE），双击 charge → 强制机炮
	var s := Situation.new_for_test({
		"has_target": true,
		"my_pos": Vector2.ZERO,
		"tgt_pos": Vector2(3000.0, 0),
		"my_heading": deg_to_rad(90.0),
		"tgt_heading": 0.0,
		"tgt_bank_deg": 5.0,
		"my_speed_ms": 200.0, "tgt_speed_ms": 150.0,
		"missiles": 6,
		"missile_max_range_m": 8000.0, "missile_min_range_m": 500.0,
		"charge_intent": true,
	})
	var p := TacticalPlanner.plan(s)
	_assert_eq("charge.weapon", TacticalPlan.WeaponMode.GUN, p.weapon_mode)
	_assert_eq("charge.no_msl", false, p.allow_missile_fire)

# ══════════════════════════════════════════════
#  测试场景构造器
# ══════════════════════════════════════════════

## 玩家有导弹 + 在尾追射程内 + 也在导弹包络内 → 应优先用导弹（不 lock 机炮）
static func test_tail_chase_with_missiles_uses_missile() -> void:
	var dist_m: float = 800.0
	var dist_px: float = dist_m * CombatUnit.PIXELS_PER_METER
	var s := Situation.new_for_test({
		"has_target": true,
		"my_pos": Vector2.ZERO,
		"tgt_pos": Vector2(0, -dist_px),
		"my_heading": 0.0, "tgt_heading": 0.0,
		"my_speed_ms": 250.0, "tgt_speed_ms": 100.0,
		"gun_range_m": 1000.0, "missile_max_range_m": 8000.0, "missile_min_range_m": 500.0,
		"missiles": 6,  # 有导弹
		"weapon_lock": Situation.WEAPON_LOCK_NONE,
	})
	var p := TacticalPlanner.plan(s)
	_assert_eq("tail_msl.intent", TacticalPlan.Intent.TAIL_CHASE, p.intent)
	_assert_eq("tail_msl.weapon", TacticalPlan.WeaponMode.MISSILE, p.weapon_mode)
	_assert_eq("tail_msl.no_gun", false, p.allow_gun_fire)
	_assert_eq("tail_msl.fire_msl", true, p.allow_missile_fire)

## 玩家在尾后远距 + 有导弹 + 距离在导弹包络内 → 不需要冲到机炮射程，先打导弹
static func test_close_tail_with_missiles_uses_missile() -> void:
	var dist_m: float = 1500.0  # 超出 gun_range × 1.2 = 1200，触发 CLOSE_TAIL
	var dist_px: float = dist_m * CombatUnit.PIXELS_PER_METER
	var s := Situation.new_for_test({
		"has_target": true,
		"my_pos": Vector2.ZERO,
		"tgt_pos": Vector2(0, -dist_px),
		"my_heading": 0.0, "tgt_heading": 0.0,
		"my_speed_ms": 250.0, "tgt_speed_ms": 100.0,
		"gun_range_m": 1000.0, "missile_max_range_m": 8000.0, "missile_min_range_m": 500.0,
		"missiles": 6,
	})
	var p := TacticalPlanner.plan(s)
	_assert_eq("close_tail_msl.intent", TacticalPlan.Intent.CLOSE_TAIL, p.intent)
	_assert_eq("close_tail_msl.weapon", TacticalPlan.WeaponMode.MISSILE, p.weapon_mode)
	_assert_eq("close_tail_msl.fire_msl", true, p.allow_missile_fire)
	# 导弹模式应该不开 AB（不需要冲过包络）
	_assert_eq("close_tail_msl.no_ab", false, p.afterburner)

## 双击地面目标 + 机头对准 → 强制机炮 + RUN 速度 + AB（不能用 corner speed 龟速接近）
static func test_ground_strafe_charge_uses_max_speed() -> void:
	var s := Situation.new_for_test({
		"has_target": true, "tgt_is_surface": true,
		"my_pos": Vector2.ZERO,
		"tgt_pos": Vector2(0, -2000.0),  # 地面目标在前方 2000px (=4000m) 远，机头对准
		"my_heading": 0.0, "my_speed_ms": 250.0, "tgt_speed_ms": 0.0,
		"missiles": 0,  # 没导弹强制走机炮
		"charge_intent": true,
	})
	var p := TacticalPlanner.plan(s)
	_assert_eq("ground_charge.intent", TacticalPlan.Intent.GROUND_STRAFE, p.intent)
	_assert_eq("ground_charge.weapon", TacticalPlan.WeaponMode.GUN, p.weapon_mode)
	# RUN 状态：速度高于 corner 但被 max×0.75 cap
	_assert_true("ground_charge.spd>=corner+200", p.target_speed_kmh >= s.corner_speed_kmh + 200.0)
	_assert_true("ground_charge.spd<=max*0.76", p.target_speed_kmh <= s.max_speed_kmh * 0.76)
	_assert_true("ground_charge.ab", p.afterburner)

## 默认地面攻击（无 charge）有导弹时打 AGM
static func test_ground_strafe_default_speed() -> void:
	var s := Situation.new_for_test({
		"has_target": true, "tgt_is_surface": true,
		"my_pos": Vector2.ZERO,
		"tgt_pos": Vector2(0, -2000.0),
		"my_heading": 0.0, "my_speed_ms": 250.0, "tgt_speed_ms": 0.0,
		"missiles": 4, "missile_min_range_m": 500.0, "missile_max_range_m": 8000.0,
	})
	var p := TacticalPlanner.plan(s)
	_assert_eq("ground_def.intent", TacticalPlan.Intent.GROUND_STRAFE, p.intent)
	# 4000m 在导弹包络内 → 用导弹
	_assert_eq("ground_def.weapon=MSL", TacticalPlan.WeaponMode.MISSILE, p.weapon_mode)
	_assert_eq("ground_def.fire_msl", true, p.allow_missile_fire)

## 舰船（NavalUnit）也是 surface 目标 → 走 ground_strafe RUN
## 注意 Situation.from_aircraft 里靠 `tgt is NavalUnit` 检测，单元测试直接传 tgt_is_surface=true
static func test_naval_target_uses_strafe() -> void:
	var s := Situation.new_for_test({
		"has_target": true, "tgt_is_surface": true,
		"my_pos": Vector2.ZERO,
		"tgt_pos": Vector2(0, -3000.0),
		"my_heading": 0.0, "my_speed_ms": 250.0,
		"tgt_speed_ms": 12.0,  # ~24 节船速
		"missiles": 0,
	})
	var p := TacticalPlanner.plan(s)
	_assert_eq("naval.intent", TacticalPlan.Intent.GROUND_STRAFE, p.intent)
	# RUN 速度：高于 corner，cap 在 max×0.75
	_assert_true("naval.spd>corner", p.target_speed_kmh > s.corner_speed_kmh)
	_assert_true("naval.spd<=max*0.76", p.target_speed_kmh <= s.max_speed_kmh * 0.76)

## 对地 SETUP：机头未对准（off_axis>30°）→ corner speed 转弯重整，关 AB
static func test_ground_strafe_setup_when_off_axis() -> void:
	# 飞机朝北（heading=0），目标在东侧 90°
	var s := Situation.new_for_test({
		"has_target": true, "tgt_is_surface": true,
		"my_pos": Vector2.ZERO,
		"tgt_pos": Vector2(2000.0, 0.0),  # 正东 4000m
		"my_heading": 0.0, "my_speed_ms": 250.0, "tgt_speed_ms": 0.0,
		"missiles": 0,
	})
	var p := TacticalPlanner.plan(s)
	_assert_eq("setup.intent", TacticalPlan.Intent.GROUND_STRAFE, p.intent)
	_assert_eq("setup.spd=corner", s.corner_speed_kmh, p.target_speed_kmh)
	_assert_eq("setup.no_ab", false, p.afterburner)

## 对地 BREAK：极近距离 + 远离 → 直线脱离 3km，关 AB
static func test_ground_strafe_break_when_overshoot() -> void:
	# 飞机朝北，目标在身后 200m → closing 极负
	var s := Situation.new_for_test({
		"has_target": true, "tgt_is_surface": true,
		"my_pos": Vector2.ZERO,
		"tgt_pos": Vector2(0, 100.0),   # 身后 200m（heading 0=北=屏幕上方）
		"my_heading": 0.0, "my_speed_ms": 280.0, "tgt_speed_ms": 0.0,
		"missiles": 0,
		"gun_range_m": 1500.0,
	})
	var p := TacticalPlanner.plan(s)
	_assert_eq("break.intent", TacticalPlan.Intent.GROUND_STRAFE, p.intent)
	_assert_eq("break.no_ab", false, p.afterburner)
	# pursuit_pos 应在我前方而不是 tgt 处
	var to_pursuit: Vector2 = (p.pursuit_pos - s.my_pos).normalized()
	_assert_true("break.pursuit_in_front", to_pursuit.dot(s.my_fwd) > 0.9)

## 已锁定 + 在 crank 包络内 → pursuit_pos 必须用 crank 几何（远离 LOS）
## 未锁定时不 crank，避免目标飞出锥
static func test_missile_mode_uses_crank_geometry() -> void:
	# 玩家在敌后 800m + 已锁定 → 应 crank
	var dist_px: float = 800.0 * CombatUnit.PIXELS_PER_METER
	var s := Situation.new_for_test({
		"has_target": true,
		"my_pos": Vector2.ZERO,
		"tgt_pos": Vector2(0, -dist_px),
		"my_heading": 0.0, "tgt_heading": 0.0,
		"my_speed_ms": 250.0, "tgt_speed_ms": 100.0,
		"gun_range_m": 1000.0,
		"missile_min_range_m": 500.0, "missile_max_range_m": 8000.0,
		"missiles": 4,
		"target_locked": true,  # 已锁定才 crank
	})
	var p := TacticalPlanner.plan(s)
	_assert_eq("crank.weapon", TacticalPlan.WeaponMode.MISSILE, p.weapon_mode)
	_assert_true("crank.pursuit_offset", p.pursuit_pos.distance_to(s.tgt_pos) > 1000.0)

## 未锁定时 missile 模式应保持 LOS，不 crank（避免 lock 失败）
static func test_missile_unlocked_keeps_los() -> void:
	var dist_px: float = 800.0 * CombatUnit.PIXELS_PER_METER
	var s := Situation.new_for_test({
		"has_target": true,
		"my_pos": Vector2.ZERO,
		"tgt_pos": Vector2(0, -dist_px),
		"my_heading": 0.0, "tgt_heading": 0.0,
		"my_speed_ms": 250.0, "tgt_speed_ms": 100.0,
		"gun_range_m": 1000.0,
		"missile_min_range_m": 500.0, "missile_max_range_m": 8000.0,
		"missiles": 4,
		"target_locked": false,  # 未锁定
	})
	var p := TacticalPlanner.plan(s)
	_assert_eq("unlocked.weapon", TacticalPlan.WeaponMode.MISSILE, p.weapon_mode)
	_assert_true("unlocked.pursuit_eq_tgt", p.pursuit_pos.distance_to(s.tgt_pos) < 1.0)

## hysteresis：上帧 TAIL_CHASE，本帧几何边界几乎切到 LEAD_PURSUIT，但 prev_intent_held_for < 0.5s → 保持 TAIL_CHASE
static func test_hysteresis_holds_combat_intent() -> void:
	# 几何：理想情况会触发 LEAD_PURSUIT（侧翼 aspect=95°）
	var s := Situation.new_for_test({
		"has_target": true,
		"my_pos": Vector2.ZERO,
		"tgt_pos": Vector2(800.0, 0),
		"my_heading": deg_to_rad(90.0),
		"tgt_heading": 0.0,
		"my_speed_ms": 200.0, "tgt_speed_ms": 150.0,
		"missiles": 0,
		"prev_intent": TacticalPlan.Intent.TAIL_CHASE,
		"prev_intent_held_for": 0.2,  # < 0.5s 阈值
	})
	var p := TacticalPlanner.plan(s)
	# 应该保持 TAIL_CHASE 不切到 LEAD_PURSUIT
	_assert_eq("hysteresis.holds_tail", TacticalPlan.Intent.TAIL_CHASE, p.intent)

## hysteresis 不应该锁住 EVADE → 紧急规避必须立即响应
static func test_hysteresis_doesnt_lock_evade() -> void:
	var s := Situation.new_for_test({
		"has_target": true,
		"evasion_intent": true,  # 触发 EVADE
		"my_pos": Vector2.ZERO,
		"tgt_pos": Vector2(0, -500.0),
		"my_heading": 0.0, "tgt_heading": PI,
		"prev_intent": TacticalPlan.Intent.TAIL_CHASE,  # 上帧在追
		"prev_intent_held_for": 0.1,  # 远小于阈值
	})
	var p := TacticalPlanner.plan(s)
	_assert_eq("hyst_evade.intent", TacticalPlan.Intent.EVADE_MISSILE, p.intent)

## overshoot：dist 极近 + closing 负 → 触发 EXTEND（trigger_extend_seconds > 0）
## 几何：玩家朝北高速直飞，目标在玩家右后方近距 → 已"穿过"目标
## planner 顺序保证 overshoot 在 wide_turn 之前触发，即使 heading_diff > 90
static func test_overshoot_triggers_extend() -> void:
	var s := Situation.new_for_test({
		"has_target": true,
		"my_pos": Vector2.ZERO,
		"tgt_pos": Vector2(50.0, 100.0),  # 右后方 ~111px ≈ 223m，gun_range×0.4=400 内
		"my_heading": 0.0,
		"tgt_heading": 0.0, "tgt_speed_ms": 50.0,
		"my_speed_ms": 250.0,  # 高速远离
		"gun_range_m": 1000.0,
	})
	# closing_ms ≈ -179（远离），dist_m ≈ 223 < 400 → 触发
	var p := TacticalPlanner.plan(s)
	_assert_eq("overshoot.intent", TacticalPlan.Intent.EXTEND_RECOVER, p.intent)
	_assert_true("overshoot.trigger>0", p.trigger_extend_seconds > 0.0)

## extend_remaining > 0 → 强制返回 EXTEND_RECOVER（即使重新有目标）
static func test_extend_remaining_holds_intent() -> void:
	# 几何上是普通侧翼，但 extend_remaining > 0
	var s := Situation.new_for_test({
		"has_target": true,
		"my_pos": Vector2.ZERO,
		"tgt_pos": Vector2(800.0, 0),
		"my_heading": deg_to_rad(90.0),
		"tgt_heading": 0.0,
		"my_speed_ms": 250.0, "tgt_speed_ms": 100.0,
		"missiles": 0,
		"extend_remaining": 1.5,  # 还有 1.5s 在脱离
	})
	var p := TacticalPlanner.plan(s)
	_assert_eq("extend_hold.intent", TacticalPlan.Intent.EXTEND_RECOVER, p.intent)

## EVADE 优先级高于 EXTEND（紧急规避不能被 extend 锁住）
static func test_evade_overrides_extend() -> void:
	var s := Situation.new_for_test({
		"has_target": true,
		"evasion_intent": true,
		"extend_remaining": 1.5,  # 同时也在 extend 中
	})
	var p := TacticalPlanner.plan(s)
	_assert_eq("evade_over_ext.intent", TacticalPlan.Intent.EVADE_MISSILE, p.intent)

## 僚机协同：is_wingman + following_leader_target → 在 GUN 模式下 pursuit_pos 加横向偏移
static func test_wingman_lateral_offset() -> void:
	# 场景：僚机 #1 跟随长机锁定同目标，TAIL_CHASE GUN 模式
	var s := Situation.new_for_test({
		"has_target": true,
		"my_pos": Vector2.ZERO,
		"tgt_pos": Vector2(0, -800.0),  # 正北 1600m
		"my_heading": 0.0, "tgt_heading": 0.0,
		"my_speed_ms": 250.0, "tgt_speed_ms": 100.0,
		"missiles": 0,  # 走 GUN 模式
		"is_wingman": true, "squad_index": 1, "following_leader_target": true,
	})
	var p := TacticalPlanner.plan(s)
	# pursuit_pos 应当被横向偏移（与原 gun_lead 不同）
	# squad_index=1 → 左 250m，垂直 LOS=(0,-1) 的左侧法向 ≈ (-1, 0) → 偏移 (-125px, 0)
	_assert_true("wing_offset.x_negative", p.pursuit_pos.x < -50.0)

## 单机（非僚机）pursuit_pos 不应有 squad 偏移
static func test_wingman_no_offset_solo() -> void:
	var s := Situation.new_for_test({
		"has_target": true,
		"my_pos": Vector2.ZERO,
		"tgt_pos": Vector2(0, -800.0),
		"my_heading": 0.0, "tgt_heading": 0.0,
		"my_speed_ms": 250.0, "tgt_speed_ms": 100.0,
		"missiles": 0,
		# is_wingman 默认 false
	})
	var p := TacticalPlanner.plan(s)
	# 单机：pursuit_pos 应靠近 LOS 中线（gun_lead 偏移很小）
	_assert_true("solo.x_near_zero", absf(p.pursuit_pos.x) < 20.0)

## 玩家"低空优先"：CRUISE 状态下 plan 设 target_altitude_tier = LOW
static func test_altitude_preference_low_in_cruise() -> void:
	var s := Situation.new_for_test({
		"has_target": false,
		"missiles": 0,
		"altitude_preference": 1,  # PREFER_LOW
	})
	var p := TacticalPlanner.plan(s)
	_assert_eq("alt_low_cruise.intent", TacticalPlan.Intent.CRUISE, p.intent)
	_assert_eq("alt_low_cruise.tier", CombatUnit.AltitudeTier.LOW, p.target_altitude_tier)

## 玩家"低空优先" + 航点移动 → tier 仍 LOW
static func test_altitude_preference_low_in_waypoint() -> void:
	var s := Situation.new_for_test({
		"has_target": false,
		"my_pos": Vector2.ZERO, "my_heading": 0.0,
		"altitude_preference": 1,
	})
	var p := TacticalPlanner.plan(s, Vector2(0, -2000.0))
	_assert_eq("alt_low_wp.intent", TacticalPlan.Intent.WAYPOINT_MOVE, p.intent)
	_assert_eq("alt_low_wp.tier", CombatUnit.AltitudeTier.LOW, p.target_altitude_tier)

## 僚机互补 LAG：长机在 TAIL_CHASE 同目标，奇数 index 僚机改 LAG_PURSUIT 内切
static func test_wingman_complementary_lag_when_leader_tail_chase() -> void:
	# 几何：rear hemisphere + aim aligned + dist 在射程内 → 默认会走 TAIL_CHASE
	var dist_px: float = 800.0 * CombatUnit.PIXELS_PER_METER
	var s := Situation.new_for_test({
		"has_target": true,
		"my_pos": Vector2.ZERO,
		"tgt_pos": Vector2(0, -dist_px),  # 正北 800m
		"my_heading": 0.0, "tgt_heading": 0.0,
		"my_speed_ms": 250.0, "tgt_speed_ms": 100.0,
		"tgt_bank_deg": 75.0,  # 急转，让 lag 不退化为 lead
		"missiles": 0,  # 走 GUN
		"is_wingman": true, "squad_index": 1, "following_leader_target": true,
		"leader_intent": TacticalPlan.Intent.TAIL_CHASE,
	})
	var p := TacticalPlanner.plan(s)
	_assert_eq("comp_lag.intent", TacticalPlan.Intent.LAG_PURSUIT, p.intent)

## 僚机互补 LEAD：偶数 index 改 LEAD_PURSUIT 侧前拦截
static func test_wingman_complementary_lead_when_leader_tail_chase() -> void:
	var dist_px: float = 800.0 * CombatUnit.PIXELS_PER_METER
	var s := Situation.new_for_test({
		"has_target": true,
		"my_pos": Vector2.ZERO,
		"tgt_pos": Vector2(0, -dist_px),
		"my_heading": 0.0, "tgt_heading": 0.0,
		"my_speed_ms": 250.0, "tgt_speed_ms": 100.0,
		"missiles": 0,
		"is_wingman": true, "squad_index": 2, "following_leader_target": true,
		"leader_intent": TacticalPlan.Intent.TAIL_CHASE,
	})
	var p := TacticalPlanner.plan(s)
	_assert_eq("comp_lead.intent", TacticalPlan.Intent.LEAD_PURSUIT, p.intent)

## 僚机跟随长机撤离：长机 EXTEND_RECOVER → 僚机也 EXTEND
static func test_wingman_follows_leader_extend() -> void:
	var dist_px: float = 800.0 * CombatUnit.PIXELS_PER_METER
	var s := Situation.new_for_test({
		"has_target": true,
		"my_pos": Vector2.ZERO,
		"tgt_pos": Vector2(0, -dist_px),
		"my_heading": 0.0, "tgt_heading": 0.0,
		"my_speed_ms": 250.0, "tgt_speed_ms": 100.0,
		"missiles": 0,
		"is_wingman": true, "squad_index": 1, "following_leader_target": true,
		"leader_intent": TacticalPlan.Intent.EXTEND_RECOVER,
	})
	var p := TacticalPlanner.plan(s)
	_assert_eq("follow_ext.intent", TacticalPlan.Intent.EXTEND_RECOVER, p.intent)

## 玩家点击航点移动 + 雷达锁住敌机 → 移动 + 自动发射并行
## 之前 bug：waypoint_move intent 不允许 auto-fire，必须等飞到航点才发
static func test_waypoint_move_allows_passive_fire() -> void:
	var s := Situation.new_for_test({
		"has_target": false,  # 无 combat_target（玩家点的是地图位置）
		"my_pos": Vector2.ZERO,
		"my_heading": 0.0,
		"missiles": 4,
		"missile_auto_fire": true,
		"has_radar_lock": true,
	})
	# 航点在前方 1km
	var p := TacticalPlanner.plan(s, Vector2(0, -2000.0))
	_assert_eq("wp_passive.intent", TacticalPlan.Intent.WAYPOINT_MOVE, p.intent)
	# 关键：weapon_mode 应为 MISSILE，allow_missile_fire = true
	_assert_eq("wp_passive.weapon=MSL", TacticalPlan.WeaponMode.MISSILE, p.weapon_mode)
	_assert_eq("wp_passive.fire_msl", true, p.allow_missile_fire)

## boom-zoom：combat intent 持续 >8s 且 aspect 仍 > 80° → 触发 BOOM_ZOOM_OUT 拉远重整
static func test_boom_zoom_triggers_on_stalemate() -> void:
	# 几何：前半球（aspect ~ 100°），勉强够触发 lead_pursuit 但持续未推进
	var s := Situation.new_for_test({
		"has_target": true,
		"my_pos": Vector2.ZERO,
		"tgt_pos": Vector2(800.0, 0),  # 正东侧翼
		"my_heading": deg_to_rad(90.0),  # 朝东
		"tgt_heading": 0.0,  # 朝北
		"my_speed_ms": 200.0, "tgt_speed_ms": 250.0,
		"missiles": 0,
		"prev_intent": TacticalPlan.Intent.LEAD_PURSUIT,
		"prev_intent_held_for": 9.0,  # 持续 9 秒
	})
	# aspect: -tgt_fwd · to_me_dir = (0,1)·(-1,0) = 0 → acos(0) = 90°，刚好 > 80°
	var p := TacticalPlanner.plan(s)
	_assert_eq("bz.intent", TacticalPlan.Intent.BOOM_ZOOM_OUT, p.intent)
	_assert_true("bz.trigger>0", p.trigger_extend_seconds > 0.0)

## Gladiator 风格（aggression > 0.85）拒绝 BOOM_ZOOM —— 设计上不撤退的近战机型
## SU27/F86/F47 BOSS 等高攻击欲 AI 即使 8 秒咬不上尾也要继续缠斗
static func test_boom_zoom_skipped_for_gladiator() -> void:
	var s := Situation.new_for_test({
		"has_target": true,
		"my_pos": Vector2.ZERO,
		"tgt_pos": Vector2(800.0, 0),
		"my_heading": deg_to_rad(90.0),
		"tgt_heading": 0.0,
		"my_speed_ms": 200.0, "tgt_speed_ms": 250.0,
		"missiles": 0,
		"prev_intent": TacticalPlan.Intent.LEAD_PURSUIT,
		"prev_intent_held_for": 9.0,
		"ai_aggression": 0.95,  # Gladiator
	})
	var p := TacticalPlanner.plan(s)
	# 即使 9 秒咬不上尾也不撤离
	_assert_true("gladiator.no_bz", p.intent != TacticalPlan.Intent.BOOM_ZOOM_OUT)

## 已经咬到尾后（aspect < 80°）则不触发 boom-zoom
static func test_boom_zoom_skipped_if_aspect_improved() -> void:
	var s := Situation.new_for_test({
		"has_target": true,
		"my_pos": Vector2.ZERO,
		"tgt_pos": Vector2(0, -800.0),  # 正北，敌也朝北 → 我在敌正后
		"my_heading": 0.0, "tgt_heading": 0.0,
		"my_speed_ms": 300.0, "tgt_speed_ms": 200.0,
		"missiles": 0,
		"prev_intent": TacticalPlan.Intent.TAIL_CHASE,
		"prev_intent_held_for": 9.0,
	})
	# aspect: -tgt_fwd·to_me = (0,1)·(0,1) = 1 → 0° → 已咬尾，不应 boom_zoom
	var p := TacticalPlanner.plan(s)
	_assert_true("bz_skip.not_bz", p.intent != TacticalPlan.Intent.BOOM_ZOOM_OUT)

## 关键回归：crank 角度必须留余量小于雷达半角，否则目标飞出锥丢锁
## 模拟玩家朝 pursuit_pos 转向后（用 atan2 算新 heading），目标 off_axis 必须 < radar_half
static func test_crank_stays_in_radar_cone() -> void:
	# F-16 默认 radar_half = 30°，已锁定才会触发 crank
	var s := Situation.new_for_test({
		"has_target": true,
		"my_pos": Vector2.ZERO,
		"tgt_pos": Vector2(0, -1000.0),  # 正北 2000m，落在包络中段
		"my_heading": 0.0,
		"tgt_heading": 0.0,
		"my_speed_ms": 250.0, "tgt_speed_ms": 50.0,
		"missiles": 4,
		"missile_max_range_m": 8000.0, "missile_min_range_m": 500.0,
		"radar_half_angle_deg": 30.0,
		"target_locked": true,
	})
	var p := TacticalPlanner.plan(s)
	# 假设玩家瞬时转到 pursuit_pos 方向，target 应仍在 30° 锥内
	var to_pursuit := p.pursuit_pos - s.my_pos
	var heading_to_pursuit: float = atan2(to_pursuit.x, -to_pursuit.y)
	var to_tgt: Vector2 = s.tgt_pos - s.my_pos
	var heading_to_tgt: float = atan2(to_tgt.x, -to_tgt.y)
	var off_axis_after_turn_deg: float = rad_to_deg(absf(Situation._angle_diff(heading_to_pursuit, heading_to_tgt)))
	_assert_true("crank_in_cone", off_axis_after_turn_deg < 30.0)

## 锁定建立段（远距）→ 应保持 LOS 直瞄，pursuit_pos = tgt_pos
## 不在这段就 crank 会让 lock 进度永远累不到阈值（用户原始 bug）
static func test_lock_band_keeps_los() -> void:
	# dist=4000m，落在 lock_band（max×0.4=3200 ~ max×0.7=5600）
	var s := Situation.new_for_test({
		"has_target": true,
		"my_pos": Vector2.ZERO,
		"tgt_pos": Vector2(0, -2000.0),  # 4000m
		"my_heading": 0.0, "tgt_heading": 0.0,
		"my_speed_ms": 250.0, "tgt_speed_ms": 50.0,
		"missiles": 4,
		"missile_max_range_m": 8000.0, "missile_min_range_m": 500.0,
	})
	var p := TacticalPlanner.plan(s)
	# pursuit_pos 应该 = tgt_pos（LOS 直瞄帮助锁累积）
	_assert_true("lock_band.pursuit_eq_tgt", p.pursuit_pos.distance_to(s.tgt_pos) < 1.0)

## 构造尾追几何：玩家在敌正后 dist 米，同向，慢目标
static func _build_tail_situation(dist_m: float) -> Situation:
	var dist_px: float = dist_m * CombatUnit.PIXELS_PER_METER
	return Situation.new_for_test({
		"has_target": true,
		"my_pos": Vector2.ZERO,
		"tgt_pos": Vector2(0, -dist_px),  # 敌在正北
		"my_heading": 0.0,  # 我朝北
		"tgt_heading": 0.0,  # 敌朝北（同向追尾）
		"my_speed_ms": 250.0, "tgt_speed_ms": 100.0,
		"tgt_bank_deg": 0.0,
		"gun_range_m": 1000.0, "missile_max_range_m": 8000.0,
		"missiles": 0,  # 无导弹保证走机炮路径
	})

# ══════════════════════════════════════════════
#  断言工具
# ══════════════════════════════════════════════

static func _assert_eq(name: String, expected, actual) -> void:
	if expected == actual:
		_passed += 1
	else:
		_failures.append("%s: 期望 %s 实际 %s" % [name, str(expected), str(actual)])

static func _assert_true(name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failures.append("%s: 期望 true 实际 false" % name)
