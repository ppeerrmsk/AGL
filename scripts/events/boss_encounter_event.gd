## BossEncounterEvent —— BOSS 战完整剧本
##
## 三段生命周期（用 phase 驱动 + AIDirective 命令各成员）：
##
##   PRE_STAGE：BOSS 区诞生瞬间触发
##     - 选 encounter（CSG / AceSquad）
##     - 刷出全员
##     - 给所有成员下 directive：
##         · CSG 舰船 → HOLD_POSITION（不开火、保持当前点；旗舰沿初始 waypoints 缓行）
##         · AceSquad → FLY_TO_POINT(anchor, on_arrival=PATROL)（飞到 BOSS 区→巡逻）
##     - 显示 WARNING 横幅 + "BOSS 区域已出现"持久提示
##     - 不切 BGM、不亮血条
##
##   ENGAGED：玩家进入 BOSS 圆 OR 贴近 BOSS 成员（< BOSS_ENGAGE_DISTANCE）
##     - 释放所有 directive → CSG 开火 / AceSquad 进入角色分配（CLOSE_FIGHTER/RANGED_STRIKER）
##     - 切 BOSS 曲、亮 HUD 血条
##     - encounter.hud_visible = true
##     - selected_id = BOSS（启用 boss phase：刷怪/猎手/常规战区任务停摆）
##     - 临时提示 "BOSS 进入战场"
##
##   VICTORY：encounter.active 从 true → false
##     - 触发 mode._on_victory
##     - 事件 end()
##
## 与旧实现对比：
##   - 删掉 AceSquad.TRANSIT/PATROL 状态机（合并到 directive 系统）
##   - 删掉 NavalUnit.passive_mode 路径（统一走 directive.combat_disabled）
##   - 删掉 survivor_mode._update_boss_phase 里的两段 stage if 大块（事件 _update 内聚）

class_name BossEncounterEvent
extends GameEvent

enum Phase { PRE_STAGE, ENGAGED, VICTORY }

# ── 配置（director 启动时由 mode 注入）──
const BOSS_ENGAGE_DISTANCE_PX := 2500.0   ## 玩家距 BOSS 成员的交战触发距离
const FAR_EDGE_INSET_PX := 600.0          ## AceSquad 远端进场起点的边缘内缩
const ANCHOR_PATROL_RADIUS := 1600.0      ## AceSquad 抵达后盘旋半径

var phase: int = Phase.PRE_STAGE
var encounter: BossEncounter = null
var anchor: Vector2 = Vector2.INF
var heading_deg: float = 0.0
var map_id: String = "default"
var _was_active: bool = false

func _init(p_anchor: Vector2, p_heading_deg: float, p_map_id: String) -> void:
	name = "boss_encounter"
	anchor = p_anchor
	heading_deg = p_heading_deg
	map_id = p_map_id

# ──────────────── 生命周期 ────────────────

func _start() -> void:
	active = true
	# 1. 选 encounter
	encounter = BossRegistry.pick_for_map(map_id, anchor)
	if encounter == null:
		push_error("BossEncounterEvent: BossRegistry returned null for map '%s'" % map_id)
		end()
		return
	encounter.initial_heading_deg = heading_deg

	# 2. 刷出 + 进 PRE_STAGE
	if encounter is CarrierStrikeGroup:
		_spawn_csg()
		_apply_pre_stage_directives_csg()
	elif encounter is AceSquad:
		_spawn_ace()
		_apply_pre_stage_directives_ace()
	else:
		push_error("BossEncounterEvent: unsupported encounter type %s" % encounter.get_class())
		end()
		return

	# 3. UI：WARNING + 持久提示
	var hint = director.mode.get("_zone_hint") if director and director.mode else null
	if hint:
		hint.show_warning_banner("WARNING  WARNING")
		hint.show_persistent(tr("ZONE_HINT_BOSS_UNLOCKED"))
	EventLogger.log_event("EVENT", name,
		"PRE_STAGE: %s staged at %s" % [encounter.display_name, anchor])

func _update(delta: float) -> void:
	if encounter == null:
		end()
		return

	# encounter 自己也要 tick（CSG Phase 2 触发 / AceSquad cloak / role assignment）
	encounter.update(delta)

	# 阶段推进
	match phase:
		Phase.PRE_STAGE:
			if _check_engagement_trigger():
				_enter_engaged()
		Phase.ENGAGED:
			pass

	# 胜利检测：encounter.active true→false 沿
	if _was_active and not encounter.active:
		phase = Phase.VICTORY
		_on_victory()
	_was_active = encounter.active

func _finish() -> void:
	# 通知 mode（survivor_mode 会做 hud / state 清理）
	if director and director.mode and director.mode.has_method("on_boss_event_finished"):
		director.mode.on_boss_event_finished(self)

# ──────────────── 阶段切换 ────────────────

## ENGAGED：释放 directive → 单位回到正常 AI（CSG 开火、AceSquad 角色分配）
func _enter_engaged() -> void:
	_debug_break("BOSS engaged: %s" % encounter.display_name)
	phase = Phase.ENGAGED
	# 释放所有 directive
	clear_all_directives()
	# 飞机 BOSS：调 engage() 打开 enable_combat
	if encounter is AceSquad:
		(encounter as AceSquad).engage()
	# HUD + BGM
	encounter.hud_visible = true
	if not encounter.bgm_layers.is_empty():
		AudioManager.play_layered_music(encounter.bgm_layers, 2.0, 0)
	elif encounter.bgm_track != "":
		AudioManager.crossfade_music(encounter.bgm_track, 2.0)
	# 进入 boss phase（mode 切 selected_id）
	if director and director.mode and director.mode.has_method("on_boss_engaged"):
		director.mode.on_boss_engaged(self)
	EventLogger.log_event("EVENT", name, "ENGAGED at %s" % anchor)

func _on_victory() -> void:
	_debug_break("BOSS victory: %s" % encounter.display_name)
	if director and director.mode and director.mode.has_method("on_boss_victory"):
		director.mode.on_boss_victory(self)
	end()

# ──────────────── 触发判定 ────────────────

func _check_engagement_trigger() -> bool:
	var player: Aircraft = director.player if director else null
	if player == null or player.is_destroyed:
		return false
	# 玩家在 BOSS 圈圆内
	var bz_radius: float = 2200.0   ## TODO: 从 zone_data 拿；目前固定与 BOSS_RADIUS 一致
	if director.mode and "_zone_data" in director.mode and director.mode._zone_data:
		bz_radius = float(director.mode._zone_data.boss_zone.get("radius", 2200.0))
	if player.global_position.distance_to(anchor) <= bz_radius:
		return true
	# 玩家贴近任一 BOSS 成员
	for m in encounter.get_display_members():
		if not is_instance_valid(m):
			continue
		if "is_destroyed" in m and m.is_destroyed:
			continue
		if player.global_position.distance_to(m.global_position) <= BOSS_ENGAGE_DISTANCE_PX:
			return true
	return false

# ──────────────── 刷出（包装 spawner.._spawn_boss 但走自己路径，不切 BGM / 不打通用 _boss）────────────────

func _spawn_csg() -> void:
	var csg := encounter as CarrierStrikeGroup
	director.spawner._spawn_boss(csg, anchor, true)  # skip_bgm

func _spawn_ace() -> void:
	var ace := encounter as AceSquad
	# 远端边缘进场起点
	var pp: Vector2 = anchor
	if director.player and not director.player.is_destroyed:
		pp = director.player.global_position
	ace.entry_origin_override = _far_map_edge_from(pp)
	director.spawner._spawn_boss(ace, anchor, true)  # skip_bgm

func _far_map_edge_from(pp: Vector2) -> Vector2:
	var half := MapBoundary.world_half_px() - FAR_EDGE_INSET_PX
	var sx: float = -1.0 if pp.x >= 0.0 else 1.0
	var sy: float = -1.0 if pp.y >= 0.0 else 1.0
	return Vector2(sx * half, sy * half)

# ──────────────── PRE_STAGE Directive 下发 ────────────────

## CSG 全舰：HOLD_POSITION（combat_disabled=true）—— 不开火，旗舰仍跑 waypoints 缓行
## 注：HOLD_POSITION 对舰船的语义是"不变更目标位置"，旗舰原始 waypoints 仍走（CSG 巡逻效果）
##     combat_disabled 才是关键 —— NavalWeapons.update 被跳过
func _apply_pre_stage_directives_csg() -> void:
	var csg := encounter as CarrierStrikeGroup
	for ship in csg.get_all_ships():
		set_directive(ship, AIDirective.passive())

## AceSquad 全员：FLY_TO_POINT(anchor, on_arrival=PATROL_RING)
## 抵达后自动转 PATROL_RING 绕 anchor 盘旋；combat_disabled=true 不交战
func _apply_pre_stage_directives_ace() -> void:
	var ace := encounter as AceSquad
	for member in ace.get_all_members():
		var d := AIDirective.fly_to(anchor, AIDirective.OnArrival.PATROL,
				ANCHOR_PATROL_RADIUS * 0.6)
		# 抵达后改 PATROL 时半径用 ANCHOR_PATROL_RADIUS
		d.params["_pending_patrol_radius"] = ANCHOR_PATROL_RADIUS
		set_directive(member, d)
