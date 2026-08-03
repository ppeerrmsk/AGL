## 王牌支援中队（spec events/ace-support-squadron）—— 非 BOSS 王牌中队的第一个实例
##
## 与 BOSS（F47AceSquad / PoltergeistSquad）的区别：
##   - category = "ace_support"（不打 "boss" —— 不触发 BOSS 血条 / BGM / 击败过关语义）
##   - tier 待遇（LOD 豁免 / 无等级缩放 / 王牌枪法 / jam=1.00）走 AceTier **实例打标**；
##     非 BOSS 仍服从一击必杀 HP cap
##     （spec ace-squadron-tier §4.1：非 BOSS 王牌不得假设 category=="boss"）
##   - 生存档位：flare 数由 profile 声明（默认 1；VULTURE 因追击成本为 0）
##   - 通用机型 Su-35：_create_enemy 按杂兵路径生成 → _configure_spawn 后处理覆写
##     （血量 / 机炮 / 热诱弹 / 涂装 / 导弹挂载），普通旅途杂兵 Su-35 不受任何影响
class_name AceSupportSquad
extends AceSquad

const SUPPORT_FLARE_RES := "res://resources/ace_support_flare.tres"
const ACE_GUN_RES := "res://resources/ace_gun.tres"
const SU35_BASE_RES := "res://resources/enemy_su35.tres"

## 编成 profile（spec ace-squadron-tier §2.7/§4.3：编成/包装/装备/战术全部单点登记在
## AceSquadProfiles，本类只消费——加新队=表里加一行，不再写子类）
var profile_id := "marathon"
var line_spacing := 600.0                  ## 横列间距（lancer 阵型/战术共用）
var _lancer: LancerSquadTactics = null     ## 骑士掠袭战术（有 lancer 成员即挂）
var _gun_mode := "ace"                     ## "ace"=挂 ace_gun / "none"=无炮 / "keep"=保留原装
var _missile_count := -1                   ## >0 覆写载弹；-1 = 撤销等级加弹回 base_res
var _base_res := ""
var _formation := "diamond"
var _tactics := "gladiator"                ## 队级默认风格（elements 可逐段覆写）
var _elements: Array = []                  ## 混编分段（tier §3.7 混编条款；空 = 全队同型同风格）

func _init(pid: String = "marathon") -> void:
	profile_id = pid
	var prof: Dictionary = AceSquadProfiles.get_profile(pid)
	display_name = AceSquadProfiles.codename(pid)   # kill feed / EventLogger 用代号
	enemy_type = int(prof.get("enemy_type", SurvivorSpawner.EnemyType.SU35))
	cloak_enabled = false   # 隐形是 F-47 专属第二防御层；非 BOSS 王牌无隐形
	xp_per_kill = int(prof.get("xp_per_kill", 100))  # 王牌档（_detect_kills 按 AceTier.is_ace 判定）
	_gun_mode = String(prof.get("gun", "ace"))
	_missile_count = int(prof.get("missile_count", -1))
	_base_res = String(prof.get("base_res", SU35_BASE_RES))
	_formation = String(prof.get("formation", "diamond"))
	_tactics = String(prof.get("tactics", "gladiator"))
	line_spacing = float(prof.get("line_spacing", 600.0))
	_elements = prof.get("elements", [])
	# 编成规模：混编 = elements 计数和；否则 squad_size 字段
	if _elements.is_empty():
		squad_size = int(prof.get("squad_size", 5))
	else:
		squad_size = 0
		for e in _elements:
			squad_size += int(e.get("count", 1))
	# 有任何 lancer 成员（整队或 element）→ 挂掠袭战术模块
	if _tactics == "lancer" or _has_lancer_element():
		_lancer = LancerSquadTactics.new(self)

func _has_lancer_element() -> bool:
	for e in _elements:
		if String(e.get("style", "")) == "lancer":
			return true
	return false

## 第 i 架成员所属的 element 配置（空字典 = 无混编，走 profile 级默认）
func _element_of(i: int) -> Dictionary:
	var acc := 0
	for e in _elements:
		acc += int(e.get("count", 1))
		if i < acc:
			return e
	return {}

## 第 i 架成员的风格（element 覆写 → 队级默认）
func _style_of(i: int) -> String:
	var e := _element_of(i)
	return String(e.get("style", _tactics))

func _member_type(i: int) -> int:
	var e := _element_of(i)
	return int(e.get("type", enemy_type))

## 风格 → 基类角色：斗士=KNIGHT（近战死咬）/ 狙击=SNIPER（bvr_only 站位带 4~6km，
## 复用 Wraith SNIPER 基建）/ 导弹骑士与机炮骑士=NONE（中性掠袭，专属配置在 _apply_role）。
## 无混编且非骑士（MARATHON）沿用基类"前 2 KNIGHT 后排 SNIPER"既有行为
func _member_role(i: int) -> int:
	if _elements.is_empty() and _tactics == "gladiator":
		return super._member_role(i)
	match _style_of(i):
		"lancer", "gun_lancer":
			return AceRole.NONE
		"schemer":
			return AceRole.SNIPER
		_:
			return AceRole.KNIGHT

## spawn 后处理钩子（基类逐成员调用，在 _apply_role 之后）
func _configure_spawn(ac: Aircraft, i: int, _sq: Squad, _ai: AIController) -> void:
	# ── 非 BOSS 化：改写基类打的 boss category ──
	ac.set_meta("category", "ace_support")
	ac.set_meta("token_cost", 0)   # 事件供给，不挤占普通敌机 Token 预算（tier 契约）
	ac.remove_meta("boss_intro")   # 无 INTRO 演出（事件 spawn 后立即 engage）
	AceTier.mark(ac)

	# ── 包装（spec ace-squadron-tier §2.7，728 实装批）──
	var prof: Dictionary = AceSquadProfiles.get_profile(profile_id)
	# 固定呼号：逐机绑槽位（长机=表首）。回收 _ready 时随机分到的池名；
	# 固定名开局已 reserve_permanent，杂鱼抽不到、死亡也不 recycle 回池
	var fixed: Array = prof.get("callsigns", [])
	if i < fixed.size():
		CallsignDB.recycle(ac.callsign)
		ac.callsign = String(fixed[i])
	# 机炮闪避（tier §2.2 分档；注入既有 bullet_dodge_chance 骰）
	ac.bullet_dodge_chance = float(prof.get("dodge", 0.20))

	var p: AircraftParams = ac.params
	if p == null:
		return
	# ── 一发死（2026-07-23 用户定：除 BOSS 外所有空中敌人一击必杀）──
	# 不再 AceTier.apply_hp(100) —— HP cap 豁免是 BOSS 专属。支援中队 HP 落回
	# _create_enemy 的一击必杀 cap（≤75），主导弹一发解决；防御全靠那 1 枚必定躲的 flare。
	# ac.hp 同步到 cap 值（p.max_hp 此时已是 _create_enemy 缩放+cap 后的 ≤75）。
	ac.hp = p.max_hp

	# ── element 覆写（tier §3.7 混编条款）：无混编时回落 profile 级默认 ──
	var e := _element_of(i)
	var style := _style_of(i)
	var prof_d: Dictionary = AceSquadProfiles.get_profile(profile_id)
	var gun_mode := String(e.get("gun", _gun_mode))
	var gun_res := String(e.get("gun_res", prof_d.get("gun_res", ACE_GUN_RES)))
	var mcount := int(e.get("missile_count", _missile_count))
	var base_res := String(e.get("base_res", _base_res))
	var flares := int(e.get("flares", prof_d.get("flares", 1))) # profile 默认，可按 element 覆写
	var ai_level := float(e.get("ai_level", prof_d.get("ai_level", 0.0)))
	var joust: Dictionary = e.get("joust", prof_d.get("joust", {}))
	var herbst: Dictionary = e.get("herbst", prof_d.get("herbst", {}))
	# element 级机炮闪避覆写（tier §2.2 分档：Teacher 特高 0.50 等）
	if e.has("dodge"):
		ac.bullet_dodge_chance = float(e["dodge"])

	# 骑士成员：交战状态归队级掠袭战术全权（基类 PURSUIT 不下 ENGAGE、软维护跳过）
	if style == "lancer":
		ac.set_meta(&"ace_tactics_owned", true)
	elif style == "gun_lancer" and _ai:
		# WhiteTea：逐机走既有空对空 joust，保留 ENGAGE 才能让 J-turn 在 joust 前抢占。
		ac.prefer_gun_mode = true
		_ai.boss_attacker = true
		_ai.bvr_only = false
		_ai.aggression = 0.95
		_ai.self_preservation = 0.20
		_ai.joust_enabled = bool(joust.get("enabled", true))
		_ai.joust_run_speed_kmh = p.max_speed * float(joust.get("run_speed_mult", 0.90))
		_ai.joust_giveup_closing_mps = float(joust.get("giveup_closing_mps", 60.0))
		_ai.joust_run_max_s = float(joust.get("run_max_s", 15.0))

	# ── 导弹载量：显式覆写（骑士波次预算，弹尽即弹尽）或撤销等级加弹回 base 原值 ──
	if p.missile != null:
		if mcount > 0:
			p.missile.max_count = mcount
			ac.enable_missile_reload = false
		else:
			var base_p: AircraftParams = load(base_res)
			if base_p != null and base_p.missile != null:
				p.missile.max_count = base_p.missile.max_count
		ac.missiles_remaining = p.missile.max_count
	# ── 机炮（spec ace-squadron-tier §2.4）：斗士/狙击挂专属 ace_gun（顺带覆掉伤害缩放）；
	#    骑士无炮豁免（纯导弹，火力表达在齐射节奏）──
	match gun_mode:
		"ace":
			p.gun = load(gun_res).duplicate(true)
			ac.ammo = p.gun.max_ammo
		"none":
			p.gun = null
			ac.ammo = 0
		_:
			pass   # "keep"：保留原装
	# ── 生存模型：flare 数量完全由 profile/element 声明；0 = 无 flare。
	#    VULTURE 用速度/回转窗口支付接近成本，因此不再叠确定性命数。──
	if flares <= 0:
		p.flare = null
		ac.flares_remaining = 0
	else:
		p.flare = load(SUPPORT_FLARE_RES).duplicate(true)
		p.flare.max_flares = flares
		ac.flares_remaining = p.flare.max_flares
	ac.enable_flare_reload = false
	# ── 机动规避个体（保留扩展口；当前六支非宿敌队无人声明 evade）：
	#    ace_evader 让基类不打 boss_attacker，既有 beam/notch 行为链对其放行。──
	if bool(e.get("evade", false)) and _ai:
		ac.set_meta(&"ace_evader", true)
		_ai.boss_attacker = false
		_ai.evade_missiles = true
	# ── AI 四维（王牌档；0 = 保留 _create_enemy 机型分支既有配置，如 MARATHON Su-35）──
	if ai_level > 0.0 and _ai:
		_ai.skill_level = clampf(ai_level, 0.0, 1.0)
		_ai.composure = clampf(ai_level, 0.0, 1.0)
		_ai.focus = clampf(ai_level, 0.0, 1.0)
		_ai.situational_awareness = clampf(ai_level, 0.0, 1.0)
	# ── 可配置 J-turn：默认配置空，不影响既有队；WhiteTea 每机一次且 flare 耗尽后解锁。──
	if not herbst.is_empty():
		var hm := HerbstManeuver.new()
		hm.name = "HerbstManeuver"
		hm.max_uses = int(herbst.get("max_uses", -1))
		hm.requires_flares_empty = bool(herbst.get("requires_flares_empty", false))
		ac.add_child(hm)
	# ── 专属涂装：中队主色（727 包装批紫红系，金橙退役）──
	p.icon_color = AceSquadProfiles.color(profile_id)

# ══════════════════════════════════════════════
#  骑士（lancer）分支：角色 / 阵型 / PURSUIT / 战术钩子
# ══════════════════════════════════════════════

## 角色：骑士成员（role=NONE）不吃 KNIGHT/SNIPER 分工——那是缠斗/站位语义，
## 会毁掉横列掠袭（SNIPER 的 bvr_only 站位带会让成员在齐射圈里掉头逃）。中性掠袭配置。
## 斗士/狙击成员走基类 KNIGHT/SNIPER 既有配置（狙击=Wraith SNIPER 站位带复用）
func _apply_role(member: Aircraft, ai: AIController, role: int) -> void:
	if role == AceRole.NONE:
		ai.boss_attacker = true
		member.prefer_gun_mode = false   # 无炮
		ai.bvr_only = false
		ai.aggression = 0.95
		ai.self_preservation = 0.2
		return
	super._apply_role(member, ai, role)

## 阵型：骑士=横列 line abreast（冲锋读感）；斗士=基类菱形 + 尾随槽补足 >4 机
func _get_formation_offsets(entry_dir: Vector2, lateral_axis: Vector2) -> Array[Vector2]:
	if _formation == "line":
		var offs: Array[Vector2] = []
		for i in range(squad_size):
			offs.append(lateral_axis * (float(i) - float(squad_size - 1) * 0.5) * line_spacing)
		return offs
	var base := super._get_formation_offsets(entry_dir, lateral_axis)
	while base.size() < squad_size:
		base.append(-entry_dir * (400.0 + 200.0 * float(base.size() - 3)))
	return base

# PURSUIT 进入/软维护：基类已按成员 meta 分流（ace_tactics_owned=战术模块全权跳过 /
# ace_evader=不打 boss_attacker），混编与纯骑士队都不再需要整段覆写

# ── 队级战术钩子（基类 _tactics_* 通道，同 wraith/poltergeist 挂法）──

func _tactics_enter() -> void:
	if _lancer:
		_lancer.enter()

func _tactics_update(delta: float) -> void:
	if _lancer:
		_lancer.update(delta)

func _tactics_exit() -> void:
	if _lancer:
		_lancer.exit()

## 弹尽（骑士语义；spec ace-lancer-mig31 §2.3）：**存活成员全是骑士且导弹全空** →
## 事件层转撤离（打完就走）。混编队（2NDWAVE）只要有非骑士成员在场就绝不撤——
## Teacher 死战不退；Teacher 阵亡且学员弹尽 → 剩下的人自然满足条件转撤离
func is_ammo_dry() -> bool:
	if _lancer == null or members.is_empty():
		return false
	var any_alive := false
	for m in members:
		if not is_instance_valid(m) or m.is_destroyed:
			continue
		any_alive = true
		if not m.has_meta(&"ace_tactics_owned"):
			return false   # 非骑士成员在场（机炮在，永不"打完就走"）
		if m.missiles_remaining > 0:
			return false
	return any_alive
