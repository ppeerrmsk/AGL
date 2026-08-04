## BossEncounterEvent —— BOSS 战完整剧本
##
## 三段生命周期（用 phase 驱动 + AIDirective 命令各成员）：
##
##   PRE_STAGE：BOSS 实体生成后立即触发登场演出
##     - 选 encounter（CSG / AceSquad）
##     - 刷出全员
##     - 给所有成员下 directive：
##         · CSG 舰船 → HOLD_POSITION（不开火、保持当前点；旗舰沿初始 waypoints 缓行）
##         · AceSquad → PASSIVE（同帧由演出 actor 指令接管）
##     - 表演导演清舞台、切镜、播无线电、回玩家；演出开场切 BOSS 曲，血条暂隐
##
##   ENGAGED：登场演出收尾后立即进入
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
## 猎手进场（spec boss-hunter-doctrine §2.4）：出生在玩家【机头前方】扇面内的固定距离上。
## 取代旧的"离玩家最远的地图角落"—— 60km 图上那能有 40km+，纯粹的空转时间。
const INBOUND_SPAWN_DISTANCE_PX := 6000.0 ## 12 km；F-47 巡航下约 27s 闭合
const INBOUND_SPAWN_FAN_DEG := 30.0       ## 机头前方 ±30° 扇面（守"事件刷在沿途"约定）

var phase: int = Phase.PRE_STAGE
var encounter: BossEncounter = null
var anchor: Vector2 = Vector2.INF
var heading_deg: float = 0.0
var map_id: String = "default"
var boss_id_override: String = ""    ## Boss Debug 强制指定 boss id，绕过地图池随机
## 生涯档案 BOSS 轮换 history（spec career-archive §3.1；mode 在正式局注入，
## 空 = 旧纯随机。事件层不直读 CareerArchive autoload，保持可测）
var boss_history: Dictionary = {}
var _was_active: bool = false
## 上次推给 encounter 的玩家引用（换人检测，避免每帧重复下推）
var _last_pushed_player: Aircraft = null

func _init(p_anchor: Vector2, p_heading_deg: float, p_map_id: String, p_boss_id_override: String = "",
		p_boss_history: Dictionary = {}) -> void:
	name = "boss_encounter"
	anchor = p_anchor
	heading_deg = p_heading_deg
	map_id = p_map_id
	boss_id_override = p_boss_id_override
	boss_history = p_boss_history

# ──────────────── 生命周期 ────────────────

func _start() -> void:
	active = true
	# 1. 选 encounter（boss_debug 路径走 instantiate 强制指定；否则按地图池 roll）
	if boss_id_override != "":
		encounter = BossRegistry.instantiate(boss_id_override)
	else:
		encounter = BossRegistry.pick_for_map(map_id, anchor, boss_history)
	if encounter == null:
		push_error("BossEncounterEvent: BossRegistry returned null for map '%s'" % map_id)
		end()
		return
	# 通关强化层必须在任何实体生成前注入；本局胜利写档发生在 encounter 结束后，
	# 因此不会出现战斗中途换编成（spec boss-clear-progression §3.1）。
	var defeat_counts: Dictionary = boss_history.get("defeat_counts", {})
	encounter.configure_progression(int(defeat_counts.get(encounter.boss_id, 0)))
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

	# 3. 登场演出（spec ui-transition §2.8/2.13）。所有 BOSS 都走同一表演导演：
	#    Wraith 有专属飞行分镜；CSG / Mother Goose 为镜头切主体 + 无线电 + 回玩家。
	#    成功则台词与镜头全部由序列编排，
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
	# 序列缺失只允许退化表现，不能把玩法卡死在 PRE_STAGE；无演出时立即接战。
	_enter_engaged()

## 尝试播 <boss_id 小写>_arrival 演出。返回 false 表示没有该 BOSS 的演出定义，
## 调用方回落到"横幅 + 无线电"的旧登场路径。
##
## ⚠ 演员指令的所有权【留在本事件】：只把 self 作为 owner 传给导演，导演转手调
##    self.set_directive() 下发。事件结束时 EventDirector 会自动 clear_all_directives()
##    兜底 —— 绝不让导演自建第二套所有权（spec §3.3）
func _try_play_arrival_cinematic() -> bool:
	var seq_name: String = "%s_arrival" % encounter.boss_id.to_lower()
	# get_display_members 是 BossEncounter 的通用演员协议：Wraith=全中队，
	# CSG=旗舰航母，Mother Goose=母机主体。简单镜头演出不要求演员一定是 Aircraft。
	var members: Array = encounter.get_display_members()
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
		# 演出收尾即接战（见 _on_arrival_cinematic_done）。release 会先还原舞台/镜头/指令，
		# 然后 callback 统一打开武器、血条和战斗状态。
		pres.sequence_finished.connect(_on_arrival_cinematic_done.bind(seq_name),
			CONNECT_ONE_SHOT)
	return ok

## 登场演出结束：所有 BOSS 统一立即进入 ENGAGED。
## 镜头与舞台已由 Presentation 在 sequence_finished 之前还原，因此玩家看到的是
## "镜头回到自己 → 战斗开始"，不会在 BOSS 特写镜头中突然开火。
func _on_arrival_cinematic_done(finished_name: String, expected_name: String) -> void:
	if finished_name != expected_name:
		# Presentation 允许 PLAYING → PLAYING 覆盖，且只会为替代序列发完成信号。
		# 边界补给恰在 10 分钟闸门触发 BOSS 时，panel_out 与 arrival 会撞在一起；
		# 若此处重挂，已经被覆盖的 arrival 永远不会再完成，事件会卡在 PRE_STAGE，血条不亮。
		# sequence_finished 发出前导演已完成舞台/暂停清理，所以安全地退化为立即接战。
		push_warning("BossEncounterEvent: arrival '%s' 被 '%s' 打断，退化为立即接战" % [
			expected_name, finished_name])
		if active and phase == Phase.PRE_STAGE and encounter != null:
			_enter_engaged()
		return
	if not active or phase != Phase.PRE_STAGE or encounter == null:
		return
	_enter_engaged()

func _update(delta: float) -> void:
	if encounter == null:
		end()
		return

	# 玩家引用保鲜（spec boss-hunter-doctrine §3.6 / SEAM-019）。encounter 的 _player 是
	# spawn 时缓存的，而 survivor_mode._set_player_aircraft() 这个 chokepoint 扫不到它
	# （校验脚本只扫 survivor_mode.gd，够不着经 spawner 传参的缓存）。旧模型下这是慢性病，
	# 猎手模型下 BOSS 全程追 _player —— 玩家一切控就会去追一架不再是玩家的飞机
	_refresh_encounter_player()

	# encounter 自己也要 tick（CSG Phase 2 触发 / AceSquad cloak / role assignment）
	encounter.update(delta)

	# BOSS 圈跟着 BOSS 走（spec boss-hunter-doctrine §2.6）。猎手模型下 BOSS 不在锚点上了，
	# 钉死在锚点的洋红圈 + 指向它的 HUD 箭头是假信息。战术地图与 ZoneArrow 都读
	# boss_zone["center"]，故这里同步一次即两处自动跟随，零改动
	_sync_boss_zone_to_members()

	# 阶段推进
	match phase:
		Phase.PRE_STAGE:
			# 演出是 PRE_STAGE 的唯一出口；演出收尾回调统一切 ENGAGED。
			# Wraith 演出期间演员指令自管，简单特写演出则世界硬暂停，无需猎手软维护。
			pass
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

## 玩家机的【活引用】（spec boss-hunter-doctrine §3.6 / SEAM-019）。
## 猎手全程追玩家，绝不能读 spawn 时的快照 —— 玩家按 1-4 切控或长机阵亡换帅后，
## 快照会指向一架不再是玩家的飞机，甚至一个已释放的实例（SEAM-020 硬崩）。
## director.player 已在 survivor_mode._set_player_aircraft() chokepoint 登记，是活的。
func _live_player() -> Aircraft:
	var p: Aircraft = director.player if director else null
	if p == null or not is_instance_valid(p) or p.is_destroyed:
		return null
	return p

## 把活的玩家引用推给 encounter（各子类在 set_player_ref 里负责自己的全部缓存）
func _refresh_encounter_player() -> void:
	var p := _live_player()
	if p == null or p == _last_pushed_player:
		return
	_last_pushed_player = p
	encounter.set_player_ref(p)

## BOSS 圈中心同步到存活成员质心（spec §2.6）。无存活成员时不写入，保留上次值 ——
## CSG 二阶段的"航母已沉、F-14 尚未揭幕"窗口靠这条保住它的 _cv_death_position 兜底
func _sync_boss_zone_to_members() -> void:
	if director == null or director.mode == null:
		return
	if not ("_zone_data" in director.mode) or director.mode._zone_data == null:
		return
	var sum := Vector2.ZERO
	var n := 0
	for m in encounter.get_display_members():
		if not is_instance_valid(m) or not (m is CombatUnit):
			continue
		if (m as CombatUnit).is_destroyed:
			continue
		sum += (m as Node2D).global_position
		n += 1
	if n > 0:
		director.mode._zone_data.boss_zone["center"] = sum / float(n)

# ──────────────── 刷出（包装 spawner.._spawn_boss 但走自己路径，不切 BGM / 不打通用 _boss）────────────────

func _spawn_csg() -> void:
	var csg := encounter as CarrierStrikeGroup
	director.spawner._spawn_boss(csg, anchor, true)  # skip_bgm

func _spawn_ace() -> void:
	var ace := encounter as AceSquad
	# 猎手进场起点：玩家机头前方扇面 12km（spec boss-hunter-doctrine §2.4）
	var pp: Vector2 = anchor
	var phdg: float = 0.0
	var player := _live_player()
	if player:
		pp = player.global_position
		phdg = player.heading
	ace.entry_origin_override = _inbound_spawn_origin(pp, phdg)
	director.spawner._spawn_boss(ace, anchor, true)  # skip_bgm

func _spawn_mother_goose() -> void:
	var goose := encounter as MotherGooseBoss
	director.spawner._spawn_boss(goose, anchor, true)  # skip_bgm

## 猎手进场起点（spec boss-hunter-doctrine §2.4）：玩家【机头前方】±30° 扇面、12 km 处。
## 守"事件刷在玩家沿途"约定 —— 不从背后冒出、不逼玩家掉头。
## 越界时改指向地图中心（复用 AceSquad.spawn 的同款防越界策略）。
func _inbound_spawn_origin(pp: Vector2, player_heading: float) -> Vector2:
	var ang: float = player_heading \
			+ deg_to_rad(randf_range(-INBOUND_SPAWN_FAN_DEG, INBOUND_SPAWN_FAN_DEG))
	var dir := Vector2(sin(ang), -cos(ang))
	var origin := pp + dir * INBOUND_SPAWN_DISTANCE_PX
	if not MapBoundary.is_safe_inside(origin, 1500.0):
		var inward := Vector2.ZERO - pp
		if inward.length_squared() > 1.0:
			origin = pp + inward.normalized() * INBOUND_SPAWN_DISTANCE_PX
	return origin

# ──────────────── PRE_STAGE Directive 下发 ────────────────

## CSG 全舰：HOLD_POSITION（combat_disabled=true）—— 不开火，旗舰仍跑 waypoints 缓行
## 注：HOLD_POSITION 对舰船的语义是"不变更目标位置"，旗舰原始 waypoints 仍走（CSG 巡逻效果）
##     combat_disabled 才是关键 —— NavalWeapons.update 被跳过
func _apply_pre_stage_directives_csg() -> void:
	var csg := encounter as CarrierStrikeGroup
	for ship in csg.get_all_ships():
		set_directive(ship, AIDirective.passive())

## AceSquad 全员：PASSIVE。演出在 spawn 同帧立即接管演员走位；这里仅提供一层
## combat_disabled 安全垫，避免镜头/actor step 接管前抢先开火。
func _apply_pre_stage_directives_ace() -> void:
	var ace := encounter as AceSquad
	for member in ace.get_all_members():
		set_directive(member, AIDirective.passive())

## Mother Goose：spawn 后同帧立刻硬暂停演出；母机与蜂群冻结到回镜，随后统一 ENGAGED。
func _apply_pre_stage_directives_mother_goose() -> void:
	pass
