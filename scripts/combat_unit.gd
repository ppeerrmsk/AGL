class_name CombatUnit
extends Node2D

## 战斗单位基类：Aircraft 和 GroundUnit 的公共接口
## 提供 team/hp/altitude/heading/speed/雷达/锁定 等共享属性

const GRAVITY: float = GameConstants.GRAVITY
const PIXELS_PER_METER: float = GameConstants.PIXELS_PER_METER

# ── 全局唯一 ID 分配器 ──
static var _next_id: int = 1           ## 下一个可用 ID
static var _recycled_ids: Array = []  ## 已回收的 ID（死亡后归还）
var callsign: String = ""              ## 唯一标识，如 "飞机01"

## 分配一个唯一 ID，优先复用回收的
static func _allocate_id() -> int:
	if _recycled_ids.size() > 0:
		_recycled_ids.sort()
		return _recycled_ids.pop_front()
	var id := _next_id
	_next_id += 1
	return id

## 回收 ID
static func _recycle_id(id: int) -> void:
	if id > 0 and not _recycled_ids.has(id):
		_recycled_ids.append(id)

## 重置 ID 分配器（重启/返回主菜单时调用）
static func reset_id_allocator() -> void:
	_next_id = 1
	_recycled_ids.clear()

## 全场战斗单位共享列表（由主场景 survivor_mode / main 每帧写入）
## 用途：避免 AI / Aircraft 里 get_parent().get_children() 的 O(N) 扫描（N=节点数，远大于单位数）
## 消费方：ai_controller._try_engage_simple、aircraft._auto_gun_scan、main/survivor_mode.radar 等
static var all_units: Array[CombatUnit] = []

## 锁定时间硬上限（秒）：不管被玩家叠加多少隐身/云雾/吊舱，敌人从 0 累到 lock_time 阈值
## 不得超过此时间。即 effective_lock_rate ≥ lock_time_threshold / MAX_EFFECTIVE_LOCK_TIME_S
## 保证"最慢也能锁上，只是要等久"，不会变成完全锁不上。
const MAX_EFFECTIVE_LOCK_TIME_S: float = 12.0

## 高度档位系统（含地面）
enum AltitudeTier { GROUND = -1, LOW = 0, MID = 1, HIGH = 2 }
const TIER_ALTITUDE := {
	AltitudeTier.GROUND: 0.0,
	AltitudeTier.LOW: 2000.0,
	AltitudeTier.MID: 5500.0,
	AltitudeTier.HIGH: 10000.0,
}
const TIER_NAMES := {
	AltitudeTier.GROUND: "GND",
	AltitudeTier.LOW: "LOW",
	AltitudeTier.MID: "MID",
	AltitudeTier.HIGH: "HIGH",
}

# --- 基础属性 ---
@export var team: int = 0  ## 0=友方, 1=敌方
var altitude: float = 5000.0        ## 米
var heading: float = 0.0            ## 弧度, 0=上(北)
var speed: float = 0.0              ## m/s
var hp: float = 100.0
var is_destroyed: bool = false
var flat_altitude: bool = false     ## 生存模式：扁平高度（三档/四档）

# --- 雷达/锁定 ---
var radar_targets: Dictionary = {}       ## { CombatUnit: float } 累计照射时间
var is_locked: bool = false              ## 被至少一个敌方单位锁定
var locked_by: Array[CombatUnit] = []    ## 锁定自己的单位列表
var incoming_lock_progress: float = 0.0  ## 被敌方锁定的最大进度 (0..1)，用于表现层动画
var is_hovered: bool = false             ## 鼠标悬停时为 true，显示雷达锥
var is_mission_target: bool = false      ## 是否为当前战区/事件的必杀目标（UI 显示 TGT 括号）

# --- 云层采样缓存（雷达锁定循环内会高频调用 WeatherSystem.is_in_cloud，按位置缓存 0.3s） ---
var _cloud_cache_time: float = -1.0
var _cloud_cache_pos: Vector2 = Vector2.INF
var _cloud_cache_result: bool = false

# --- 状态效果：通用容器（StatusEffects 模块管理）---
## 注意：除 JAM 外的状态（INVINCIBLE / STEALTH / BLOODLUST / OVERLOAD / FEAR / SLOW）
## 仅对 Aircraft（含 BOSS 飞行体）生效。地面单位 / 船 / 巨型 BOSS 等只识别 JAM。
## 容器和 API 统一放在基类，方便外部"挂状态"代码不区分目标类型。
var status_effects: Dictionary = {}            ## id(String) → 剩余秒数(float)
var status_initial_durations: Dictionary = {}   ## id(String) → 施加时的初始秒数(float)，渲染条进度基准
var status_jam_active: bool = false             ## 唯一对所有 CombatUnit 子类生效的派生标记

## 施加状态。
## mode 语义：
##   "max"（默认）= 取 max(剩余, duration)，常规状态：FEAR/SLOW/JAM/STEALTH/BLOODLUST/OVERLOAD
##   "no_refresh" = 状态已存在期间忽略后续 apply（只在状态结束后才能再触发）
##                  典型用途：被导弹命中后无敌 2s —— 无敌期间反复被命中不延长
func apply_status(id: String, duration: float, mode: String = "max") -> void:
	if duration <= 0.0:
		return
	# 免疫检查：免疫单位不进入该状态（HUD 状态栏不显示 + 派生标记不写）
	# 例：fear_immune meta（Mother Goose UAV 等硬件平台无飞行员 → FEAR 无来源）
	if id == "fear" and has_meta(&"fear_immune"):
		return
	var prev: float = float(status_effects.get(id, 0.0))
	if mode == "no_refresh" and prev > 0.0:
		# 状态仍在持续 → 不刷新、不延长
		return
	if duration > prev:
		status_effects[id] = duration
		# 重置 baseline：用最长一次施加值作为进度条满刻度（更直观）
		status_initial_durations[id] = duration

func remove_status(id: String) -> void:
	status_effects.erase(id)
	status_initial_durations.erase(id)

func has_status(id: String) -> bool:
	return status_effects.has(id)

func clear_all_statuses() -> void:
	status_effects.clear()
	status_initial_durations.clear()

## 从当前 altitude 数值推算高度档位
func get_altitude_tier() -> int:
	if altitude < 3500.0:
		return AltitudeTier.LOW
	elif altitude < 7500.0:
		return AltitudeTier.MID
	else:
		return AltitudeTier.HIGH

## 计算含高度差的有效距离（像素）
## 将高度差（米）转换为像素并与2D距离合成3D距离
static func effective_distance_px(pos_a: Vector2, alt_a: float, pos_b: Vector2, alt_b: float) -> float:
	var dist_2d := pos_a.distance_to(pos_b)
	var alt_diff_px := (alt_a - alt_b) * PIXELS_PER_METER
	return sqrt(dist_2d * dist_2d + alt_diff_px * alt_diff_px)

## 受到伤害（子类可覆写）
## damage_kind 枚举字符串："gun" / "missile" / "aoe" / "rocket" / "laser" / "railgun" / "ground_crash" / "collision" / ""(未知)
## 写入 `_last_damage_kind` meta 供 _apply_damage / on_kill / on_hit 钩子链消费
## （技能：机炮闪避 / 机炮发射时减伤 / 导弹命中无敌 / 机炮击杀恐惧 等都按 kind 分流）
func take_damage(amount: float, attacker: Node = null, kind: String = "") -> void:
	if is_destroyed:
		return
	if attacker != null:
		set_meta("_pending_attacker", attacker)
	if kind != "":
		set_meta("_last_damage_kind", kind)
	hp -= amount
	if hp <= 0.0:
		hp = 0.0
		_on_destroyed()

## 受伤 + 归因：保留旧 API 名作为兼容入口（薄壳，转发到 take_damage）
## 所有直接伤害武器（机炮 / 导弹 / 电磁炮 / 激光 / 撞击 / 未来武器）都应携带 kind
## 归因机制：致死时 `_record_kill_attribution()` 读 `_pending_attacker` → 写入 kill_attacker_*
func take_damage_from(amount: float, attacker: Node, kind: String = "") -> void:
	take_damage(amount, attacker, kind)

## 击毁回调（子类覆写）
func _on_destroyed() -> void:
	is_destroyed = true

## 判断目标世界坐标是否在本单位雷达锥内（子类覆写提供参数）
func is_in_radar_cone(_target_global_pos: Vector2) -> bool:
	return false

## 锁定免疫检查（子类覆写）
func is_lock_immune() -> bool:
	return false

# ── 锁定攻击警告线（飞机 / SAM / 海军共用） ──
## 状态机/计时常量/绘制 全部模块化在 LockWarning（scripts/lock_warning.gd）
## 子类只需覆写 has_missile_capability() 和 _lock_line_can_engage_player()
## 干扰/ECM 等机制接入：调 LockWarning.suppress(state, seconds) 或 LockWarning.clear(state)
var lock_warning_state: LockWarning.State = LockWarning.State.new()

## 子类是否装载导弹（无导弹的单位不显示锁定线，因为不会发射）
func has_missile_capability() -> bool:
	return false

## 子类是否能/会向玩家发射导弹（决定锁定线是否触发）
## - Aircraft：combat_target == 玩家 + has_missile_capability + cooldown ≤ 0
## - SAMUnit：combat_target == 玩家 + missiles_remaining > 0 + cooldown ≤ 0
## - NavalUnit：任意导弹挂点存活 + 玩家在雷达内
func _lock_line_can_engage_player() -> bool:
	return false

## 每帧由子类 _physics_process 调用
func update_lock_line_state(delta: float) -> void:
	var pref: Aircraft = AircraftRenderer.player_ref
	var pref_valid: bool = pref != null and is_instance_valid(pref) and not pref.is_destroyed
	var skip: bool = is_destroyed or team == 0 or not pref_valid
	var locked: bool = pref_valid and pref.locked_by.has(self)
	var can_engage: bool = pref_valid and _lock_line_can_engage_player()
	LockWarning.update(lock_warning_state, locked, can_engage, skip, delta)

## 武器路径在导弹生成后调用
func notify_missile_fired_at(target: CombatUnit) -> void:
	var pref: Aircraft = AircraftRenderer.player_ref
	if pref == null or not is_instance_valid(pref) or target != pref:
		return
	LockWarning.notify_fired(lock_warning_state)

## ── 接入挂钩（供干扰 / ECM / 隐身机制调用） ──

## 屏蔽 N 秒内的新警告（不影响当前 show_timer 自然衰减）
func suppress_lock_warning(seconds: float) -> void:
	LockWarning.suppress(lock_warning_state, seconds)

## 立即清空当前显示（隐身激活 / 干扰生效瞬间）
func clear_lock_warning() -> void:
	LockWarning.clear(lock_warning_state)
