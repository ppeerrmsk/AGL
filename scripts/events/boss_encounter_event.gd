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
var boss_id_override: String = ""    ## Boss Debug 强制指定 boss id，绕过地图池随机
var _was_active: bool = false

func _init(p_anchor: Vector2, p_heading_deg: float, p_map_id: String, p_boss_id_override: String = "") -> void:
	name = "boss_encounter"
	anchor = p_anchor
	heading_deg = p_heading_deg
	map_id = p_map_id
	boss_id_override = p_boss_id_override

# ──────────────── 生命周期 ────────────────

func _start() -> void:
	active = true
	# 1. 选 encounter（boss_debug 路径走 instantiate 强制指定；否则按地图池 roll）
	if boss_id_override != "":
		encounter = BossRegistry.instantiate(boss_id_override)
	else:
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
	elif encounter is MotherGooseBoss:
		_spawn_mother_goose()
		_apply_pre_stage_directives_mother_goose()
	else:
		push_error("BossEncounterEvent: unsupported encounter type %s" % encounter.get_class())
		end()
		return

	# 3. 登场演出（spec ui-transition §2.8）。成功则台词与镜头全部由序列编排，
	#    跳过下面的横幅/无线电旧路径；失败（无演出定义 / 缺演员）则回落原行为
	if _try_play_arrival_cinematic():
		EventLogger.log_event("EVENT", name,
			"PRE_STAGE: %s 走登场演出" % encounter.display_name)
		return

	# 3b. UI：WARNING + 持久提示
	var hint = director.mode.get("_zone_hint") if director and director.mode else null
	if hint:
		hint.show_warning_banner("WARNING  WARNING")
		hint.show_persistent(tr("ZONE_HINT_BOSS_UNLOCKED"))

	# 4. 无线电：BOSS 中队登场挑衅（spec radio-chatter §3.3）
	# 说话人呼号由 encounter 的 callsign_prefix 合成，不依赖机体 _ready() 是否已分配呼号。
	var radio = director.mode.get("_radio") if director and director.mode else null
	if radio:
		radio.say_boss_sequence(encounter.boss_id, "spawn", encounter.callsign_prefix)

	EventLogger.log_event("EVENT", name,
		"PRE_STAGE: %s staged at %s" % [encounter.display_name, anchor])

## 尝试播 <boss_id 小写>_arrival 演出。返回 false 表示没有该 BOSS 的演出定义，
## 调用方回落到"横幅 + 无线电"的旧登场路径。
##
## ⚠ 演员指令的所有权【留在本事件】：只把 self 作为 owner 传给导演，导演转手调
##    self.set_directive() 下发。事件结束时 EventDirector 会自动 clear_all_directives()
##    兜底 —— 绝不让导演自建第二套所有权（spec §3.3）
func _try_play_arrival_cinematic() -> bool:
	if not (encounter is AceSquad):
		return false
	var seq_name: String = "%s_arrival" % encounter.boss_id.to_lower()
	var members: Array = (encounter as AceSquad).get_all_members()
	if members.is_empty():
		return false
	var pres = Engine.get_main_loop().root.get_node_or_null("Presentation")
	if pres == null or not pres.has_method("play_cinematic"):
		return false
	if not pres.has_sequence(seq_name):
		return false

	# 进场方向：从玩家指向锚点的【反】向 —— 让 BOSS 从玩家机头前方飞来，
	# 而不是从背后冒出来（守"事件刷在沿途"约定）
	var player = director.player if director else null
	var inbound := Vector2.RIGHT
	if player and is_instance_valid(player):
		var to_anchor: Vector2 = anchor - player.global_position
		if to_anchor.length_squared() > 1.0:
			inbound = to_anchor.normalized()
	var extra: Array = []
	if director and director.mode:
		for key in ["_map_features", "hud", "_zone_arrow"]:
			var n = director.mode.get(key)
			if n != null and is_instance_valid(n):
				extra.append(n)

	var ok: bool = pres.play_cinematic(seq_name, {
		"owner": self,
		"actors": members,
		"anchor": anchor,
		"cp": anchor + inbound * 250.0,      ## 交汇点：锚点前方 250px（按 1.8s 交汇窗 × 机体包线反推）
		"inbound": inbound,
		"extra_layers": extra,
		"callsign_prefix": encounter.callsign_prefix,
		"scatter_seed": inbound.angle(),
		# BGM 快照：audio 通道在演出开场切 BOSS 曲（导演只拿字符串，不认识 encounter）
		"bgm_layers": encounter.bgm_layers,
		"bgm_track": encounter.bgm_track,
	})
	if ok:
		# 演出收尾时恢复 PRE_STAGE 契约（见 _on_arrival_cinematic_done）。
		# release 步骤会 clear_all_directives —— 不接这钩子，事件仍在 PRE_STAGE
		# 但四机既无 directive 又没 engage()，AceSquad 状态机停摆、AI 乱飞
		pres.sequence_finished.connect(_on_arrival_cinematic_done.bind(seq_name),
			CONNECT_ONE_SHOT)
	return ok

## 登场演出结束：重下 PRE_STAGE 巡逻指令（飞回锚点绕环，隐身状态下自然完成
## 分镜的"散开 → 重新合并成阵型"），并补上被演出路径跳过的持久提示
func _on_arrival_cinematic_done(finished_name: String, expected_name: String) -> void:
	if finished_name != expected_name:
		# 理论上不可能（演出期间世界冻结、无其他序列），防御性重挂
		var pres = Engine.get_main_loop().root.get_node_or_null("Presentation")
		if pres:
			pres.sequence_finished.connect(_on_arrival_cinematic_done.bind(expected_name),
				CONNECT_ONE_SHOT)
		return
	if not active or phase != Phase.PRE_STAGE or encounter == null:
		return
	_apply_pre_stage_directives_ace()
	var hint = director.mode.get("_zone_hint") if director and director.mode else null
	if hint:
		hint.show_persistent(tr("ZONE_HINT_BOSS_UNLOCKED"))

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
	# 通用 engage()：AceSquad → PURSUIT；CSG → 启动 F/A-18 弹射循环；其他子类按需覆盖
	encounter.engage()
	# HUD + BGM。幂等守卫：登场演出可能已切过 BOSS 曲（audio 通道），
	# crossfade_music 没有同曲早退 —— 不守卫会把正在播的 BOSS 曲重启一遍
	encounter.hud_visible = true
	var want_bgm: String = String(encounter.bgm_layers[0]) if not encounter.bgm_layers.is_empty() 			else encounter.bgm_track
	if want_bgm != "" and AudioManager.current_music_id() != want_bgm:
		if not encounter.bgm_layers.is_empty():
			AudioManager.play_layered_music(encounter.bgm_layers, 2.0, 0)
		else:
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

func _spawn_mother_goose() -> void:
	var goose := encounter as MotherGooseBoss
	director.spawner._spawn_boss(goose, anchor, true)  # skip_bgm

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

## Mother Goose：v1 简单处理 — 自身已在 patrol ring 上飞，不下 directive；
## UAV 蜂群在 spawn() 时已起飞，自然奔向玩家。事件系统不干预。
func _apply_pre_stage_directives_mother_goose() -> void:
	pass
