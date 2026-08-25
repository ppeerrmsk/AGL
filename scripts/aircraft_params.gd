class_name AircraftParams
extends Resource

enum FlightModel { FIXED_WING, ROTORCRAFT }
enum RotorcraftRole { NONE, ATTACK, TRANSPORT }

@export_group("基本信息")
@export var display_name: String = "F-16"
@export var is_unmanned: bool = false       ## 无人驾驶标识（可被 Sentinel 招募）

@export_group("飞行模型")
@export var flight_model: FlightModel = FlightModel.FIXED_WING
@export var rotorcraft_role: RotorcraftRole = RotorcraftRole.NONE

@export_group("生存性")
@export var max_hp: float = 100.0
@export var armor: float = 0.0

@export_group("速度")
@export var max_speed: float = 2100.0       ## km/h 海平面最大速度
@export var cruise_speed: float = 900.0     ## km/h 巡航速度
@export var stall_speed_base: float = 220.0 ## km/h 1G海平面失速速度
@export var acceleration: float = 50.0      ## m/s² 加速能力
@export var deceleration: float = 80.0      ## m/s² 减速能力（含减速板）
@export var g_drag_factor: float = 3.0      ## m/s² 每G额外阻力减速

@export_group("机动性")
@export var max_g: float = 9.0              ## 飞行员持续耐受G力（可长期维持）
@export var max_g_structural: float = 12.0  ## 机体结构极限G力（短时可超越max_g）
@export var roll_rate: float = 4.0          ## rad/s 滚转速率

@export_group("高度")
@export var max_altitude: float = 15000.0   ## 米 实用升限
@export var climb_rate_max: float = 250.0   ## m/s 最大爬升率

@export_group("引擎")
@export var thrust_to_weight: float = 1.1
@export var drag_coefficient: float = 0.02
@export var afterburner_thrust_mult: float = 1.5  ## 加力时加速度倍率

@export_group("燃油")
@export var fuel_capacity: float = 3000.0          ## kg 内油量
@export var fuel_rate_normal: float = 1.5          ## kg/s 巡航油耗
@export var fuel_rate_afterburner: float = 8.0     ## kg/s 加力油耗

@export_group("雷达")
@export var radar_range: float = 300.0          ## 探测距离（像素）
@export var radar_half_angle: float = 30.0      ## 扇形半角（度）
@export var lock_time: float = 3.0              ## 锁定所需持续照射时间（秒）
@export var sensor_stealth_enabled: bool = false ## 玩家侧雷达失联后进入传感器隐形

@export_group("机炮")
@export var gun: GunParams

@export_group("火箭弹")
@export var rocket: RocketParams             ## 无制导火箭弹（低命中率副武器，可选）

@export_group("空中鱼雷")
@export var torpedo: TorpedoParams           ## 规避模式下自动从机尾抛出的追踪雷（A-10 实验武器，可选）

@export_group("忠诚僚机（与漂浮雷互斥）")
## 规避模式下从机尾释放的自主无人机；与 torpedo 字段**互斥**（设计约定只填一个）。
## 同时填的话 update_loyal_wingman 在 update_torpedo 之后跑，但二者都会消耗各自 CD —
## 设计上不该出现同时填的 .tres，互斥靠资源编辑约定保证。
@export var loyal_wingman: LoyalWingmanParams

@export_group("导弹")
@export var missile: MissileParams           ## 主导弹（空对空）
@export var secondary_missile: MissileParams ## 副导弹（空对地）

@export_group("热诱弹")
@export var flare: FlareParams

@export_group("战斗风格")
@export var combat: CombatParams

@export_group("视觉")
@export var icon_color: Color = Color.GREEN
@export var visual_length_m: float = 18.0   ## 真机长度，仅用于统一战场视觉尺度
@export var visual_span_m: float = 12.0     ## 固定翼翼展 / 旋翼机旋翼直径
## 机翼配色（可选）—— 设为非零 alpha 时替换机翼为另一种颜色（例如黑机身 + 红翼）
## 默认全透明 → 机翼用 icon_color 绘制
@export var wing_color: Color = Color(0, 0, 0, 0)

@export_group("装备（新模块化系统）")
## 装备列表 —— 新模块化武器/规避抽象。空数组时回退读上方的旧字段（gun/missile/...）。
## 迁移期：新机型（X-02 / AF-03 / 激光 UAV）走这里，老机型字段不动，逐 commit 迁移。
## 详见 docs/changelogs/2026-04-28-equipment-scaffolding.md
@export var equipment: Array[EquipmentParams] = []


## 查询是否装备了某类装备。生存模式升级过滤 + AI 决策都通过此入口判定。
## 同时检查新 equipment 数组和旧字段（兼容迁移期）。
func has_equipment_of_kind(kind: String) -> bool:
	for eq in equipment:
		if eq != null and eq.equipment_kind == kind:
			return true
	# Backward-compat: 老字段直查
	match kind:
		"gun":
			return gun != null
		"missile":
			return missile != null or secondary_missile != null
		"rocket":
			return rocket != null
		"flare":
			return flare != null
		"torpedo":
			return torpedo != null
		"loyal_wingman":
			return loyal_wingman != null
		"secondary_missile":
			return secondary_missile != null   # QAAM 副槽（720 批：qmaam_* 强化门控）
	return false


## 取某类装备的第一件。无则返回 null。
func get_equipment_of_kind(kind: String) -> EquipmentParams:
	for eq in equipment:
		if eq != null and eq.equipment_kind == kind:
			return eq
	return null


## 是否装备了会使用主雷达锁定空中目标的武器。
## 主 AAM、railgun、启用对空的 laser 计入；secondary_missile 使用独立副槽雷达，
## 不计入主雷达锥。渲染与雷达 shooter 过滤共用本入口。
func has_lock_capable_weapon() -> bool:
	if missile != null:
		return true
	for eq in equipment:
		if eq == null:
			continue
		if eq.equipment_kind == "railgun":
			return true
		if eq.equipment_kind == "laser" and "can_target_aircraft" in eq \
				and bool(eq.can_target_aircraft):
			return true
	return false
