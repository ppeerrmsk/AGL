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
func take_damage(amount: float) -> void:
	if is_destroyed:
		return
	hp -= amount
	if hp <= 0.0:
		hp = 0.0
		_on_destroyed()

## 击毁回调（子类覆写）
func _on_destroyed() -> void:
	is_destroyed = true

## 判断目标世界坐标是否在本单位雷达锥内（子类覆写提供参数）
func is_in_radar_cone(_target_global_pos: Vector2) -> bool:
	return false

## 锁定免疫检查（子类覆写）
func is_lock_immune() -> bool:
	return false
