class_name ObjectiveContext
extends RefCounted

## 战场引力共享上下文（spec systems/battlefield-gravity §2/§4）
##
## 队级共享的"当前主战场"空间锚 + 三带优先级判据，全 static（与 AircraftRenderer.player_ref 同惯例）。
## 生存模式低频填充（survivor_mode._update_objective_context，0.5s）；沙盒不启用（enabled=false
## → 全部判据退化为无操作，评分行为与本 spec 落地前逐位一致）。
##
## 三带（叠在可命中性 base∈[0,1] 上，带间严格隔离）：
##   ① 生存  +SURVIVAL_BONUS×threat01（60~100）—— 候选正在咬**当前操控机**（只对空：
##      engaging_me 仅飞机 AIController 写入；地面/航母威胁走 scan_leader_threat_ground / 任务层）
##   ② 任务  +OBJECTIVE_BONUS(40) —— 候选 ∈ BossEncounter 实际成员表 / 最近 triggered 战区单位
##   ③ 顺手  base × gravity_mult —— 离锚越远越被压（R_CORE 内 1.0 → R_FAR 外 FLOOR）
##
## 消费方：仅友方玩家小队 AI 的 TS_SCORED 自主评分（TargetSelection / SquadCoordination 自由扫描）。
## 敌方 AI / 玩家命令（TS_COMMANDED 铁律）/ BOSS 攻击手不读本上下文。

# ── 三带量级（§2.1；带间隔离：顺手上限 1 < 任务 40 < 生存下限 60）──
const SURVIVAL_BONUS := 100.0     ## 生存层加分基数（× threat01 ∈ [0.6,1.0]）
const OBJECTIVE_BONUS := 40.0     ## 任务层加分（BOSS 成员 / 战区目标）

# ── 引力衰减曲线（§2.2）──
const R_CORE_PX := 2000.0         ## 锚心半径：以内不衰减（≈4km）
const R_FAR_PX := 6000.0          ## 远界：以外压到 FLOOR（≈12km）
const GRAVITY_FLOOR := 0.10       ## 顺手层最低乘子

# ── 生存判据（§2.3）──
const SURVIVAL_RANGE_PX := 3000.0 ## 咬操控机 + 此范围内才算急威胁（≈6km）

# ── 交战地板 / 可行性门 / 带感知粘性（§2.1.1~§2.1.3，v2 三件套）──
const ENGAGE_MIN_SCORE := 0.15    ## 最佳候选低于此分 → 这仗不值得打，留在编队/巡逻
const LEASH_FEAS_MARGIN := 0.9    ## 候选距长机 > leash×此值 → 评分即拒（追不到，别咬了再被拽回）
const SURVIVAL_STICKY := 8.0      ## 当前目标是生存候选时的粘性（≈600px 滞回，防带内横跳）

# ── 阶段 2 预留（§3.4 leash 放宽 = SURVIVAL_RANGE + BRACKET_SLACK）──
const BRACKET_SLACK_PX := 1200.0  ## 包抄外绕余量

# ── 运行时状态（survivor_mode 填充；沙盒恒 disabled）──
static var enabled: bool = false            ## 总开关：仅生存模式 _ready 置 true、_exit_tree 复位
static var has_objective: bool = false      ## 当前是否有生效任务（BOSS / triggered 战区）
static var member_ids: Dictionary = {}      ## objective 成员 instance_id → true（O(1) 判 +40）
static var anchor: Vector2 = Vector2.INF    ## 引力锚（BOSS 存活质心 / 战区 center）；INF=未设
static var protectee: Aircraft = null       ## 生存层保护对象=当前操控机（SEAM-019 chokepoint 重定向）


## 新局初始化 / 退局清理（static 跨场景存活，必须显式复位防残留——同 UgcLoader.clear 惯例）
static func reset() -> void:
	enabled = false
	has_objective = false
	member_ids = {}
	anchor = Vector2.INF
	protectee = null


## BOSS objective：成员表来自 BossEncounter.get_display_members()（实例判定，禁字符串匹配——
## category=="ace_support" 含 "ace" 会误伤）。含已击毁成员（HUD DOWN），此处过滤 → 质心只算存活。
static func set_boss_objective(members: Array) -> void:
	member_ids = {}
	var centroid := Vector2.ZERO
	var n := 0
	for m in members:
		# ⚠ is_instance_valid 必须在 `is` 之前：`is` 对已释放实例求值会直接抛
		# "Left operand of 'is' is a previously freed instance" 并中断脚本
		if is_instance_valid(m) and m is CombatUnit and not (m as CombatUnit).is_destroyed:
			member_ids[(m as CombatUnit).get_instance_id()] = true
			centroid += (m as CombatUnit).global_position
			n += 1
	if n > 0:
		has_objective = true
		anchor = centroid / float(n)
	else:
		set_no_objective()


## 战区 objective：锚=战区 center（固定），成员=该战区已刷单位（TGT + 驻守）
static func set_zone_objective(units: Array, center: Vector2) -> void:
	member_ids = {}
	for u in units:
		# ⚠ 同上：战区 units 表（_spawned_zones/_garrison_zones）不即时剔除阵亡单位，
		# 必然含 freed 引用，判序写反会闪退
		if is_instance_valid(u) and u is CombatUnit and not (u as CombatUnit).is_destroyed:
			member_ids[(u as CombatUnit).get_instance_id()] = true
	has_objective = true
	anchor = center


## 无任务：锚退化为操控机（gravity_mult 内实时读，不吃 0.5s 刷新延迟）
static func set_no_objective() -> void:
	has_objective = false
	member_ids = {}
	anchor = Vector2.INF


## 当前生效锚：有任务 → 任务锚；无任务 → 操控机实时位置；都没有 → INF（无引力）
static func effective_anchor() -> Vector2:
	if has_objective and anchor != Vector2.INF:
		return anchor
	if protectee != null and is_instance_valid(protectee) and not protectee.is_destroyed:
		return protectee.global_position
	return Vector2.INF


## 顺手层引力乘子（§2.2）：R_CORE 内 1.0，线性衰减到 R_FAR 外 FLOOR。
## 锚不可得（未启用/无锚）→ 1.0（评分不变）。
static func gravity_mult(pos: Vector2) -> float:
	var a := effective_anchor()
	if a == Vector2.INF:
		return 1.0
	var d := a.distance_to(pos)
	if d <= R_CORE_PX:
		return 1.0
	if d >= R_FAR_PX:
		return GRAVITY_FLOOR
	var t := (d - R_CORE_PX) / (R_FAR_PX - R_CORE_PX)
	return 1.0 - t * (1.0 - GRAVITY_FLOOR)


## 候选 ∈ objective 成员集？（类型无关：Aircraft/NavalUnit/MountTarget/GroundUnit 皆可，只查 id）
static func is_objective(unit: Object) -> bool:
	return unit != null and is_instance_valid(unit) and member_ids.has(unit.get_instance_id())


## 候选是生存威胁？（§2.3：敌方**飞机** + 正在咬操控机 + SURVIVAL_RANGE 内）
static func is_survival_threat(cand: Object) -> bool:
	# ⚠ is_instance_valid 必须在 `is` 之前（同 setter）：_sticky_for 传入的 ai._current_target
	# 可能已 freed，freed 实例过 `is` 直接抛错中断
	if cand == null or not is_instance_valid(cand):
		return false
	if not (cand is Aircraft):
		return false  # 只对空：地面/航母不写 engaging_me，走各自既有路径
	if protectee == null or not is_instance_valid(protectee) or protectee.is_destroyed:
		return false
	var ac := cand as Aircraft
	if ac.is_destroyed:
		return false
	if not protectee.engaging_me.has(ac.get_instance_id()):
		return false
	return protectee.global_position.distance_to(ac.global_position) <= SURVIVAL_RANGE_PX


## 生存威胁强度（§2.3）：0.6 地板（保证压过任务层）+ 0.4×贴脸近度
static func threat01(cand: CombatUnit) -> float:
	if protectee == null or not is_instance_valid(protectee):
		return 0.0
	var d := protectee.global_position.distance_to(cand.global_position)
	var prox := 1.0 - clampf(d / SURVIVAL_RANGE_PX, 0.0, 1.0)
	return 0.6 + 0.4 * prox


## 三带加性合计（§3.2 共享 helper：TargetSelection 评分与 SquadCoordination 自由扫描同源，防公式漂移）
static func band_bonus(cand: CombatUnit) -> float:
	var b := 0.0
	if is_objective(cand):
		b += OBJECTIVE_BONUS
	if is_survival_threat(cand):
		b += SURVIVAL_BONUS * threat01(cand)
	return b
