class_name NavalParams
extends Resource

## 船体参数 Resource —— 定义一艘船的身份 / 几何 / 机动 / 挂点 / 弱点
## 每种舰种（CarrierShip / CruiserShip / DestroyerShip / FrigateShip / SubmarineShip）
## 至少有一个对应的 .tres 文件存放在 resources/naval/

## 舰种代号 —— 影响命名池选择 + HUD 状态栏显示
## 对应 NavalShipNames.NAME_POOLS 的 key
enum ShipClass {
	FFG,  # 护卫舰
	DDG,  # 驱逐舰
	CG,   # 巡洋舰
	CV,   # 航母
	SS,   # 潜艇
}

@export_group("身份")
@export var ship_class: ShipClass = ShipClass.FFG
@export var display_name_prefix: String = "FFG"  ## 舷号前缀，与 ship_class 呼应（CV / CG / DDG / FFG / SS）

@export_group("几何")
@export var hull_length: float = 80.0    ## 像素，从船尾到船头的总长（用于绘制 + 挂点坐标参考）
@export var hull_width: float = 20.0     ## 像素，最大船体宽度
@export var icon_color: Color = Color(0.7, 0.3, 0.3)  ## 敌方红，实际绘制时会按 team 替换

@export_group("机动")
@export var max_sea_speed: float = 9.0   ## m/s 海面移动速度；内部乘 PIXELS_PER_METER(0.5) 得视觉 px/s
                                         ## 参考：FFG 9.0 (18kn) / DDG 10.0 (20kn) / CG 10.0 (20kn) / CV 13.0 (25kn)
@export var turn_rate: float = 0.15      ## rad/s 转弯速率（船都转得很慢）

@export_group("雷达（简化）")
@export var radar_range: float = 0.0     ## 像素。船本身不做雷达扫描，仅供被锁定时显示
@export var lock_time: float = 3.0       ## 被玩家锁定所需照射时间（秒）

@export_group("生存性")
@export var mount_configs: Array[WeaponMountParams] = []  ## 所有挂点配置（2-6 个，取决于舰种）
@export var weak_point_enabled: bool = true              ## FFG/SS 设为 false（无弱点，挂点清完即死）
@export var weak_point_threshold: int = 2                ## 死亡挂点数 ≥ 该值 → 弱点暴露
@export var weak_point_hp: float = 60.0                  ## 弱点血量（约等于一发导弹伤害）
@export var weak_point_radius: float = 300.0             ## 玩家点击命中判定半径（像素）

## 船体总血量（所有路径伤害累积；归零直接摧毁船）
## 0 = 禁用此机制，只靠"挂点全清 / 弱点死"致死（FFG 可以这样）
## > 0 = 无论打中哪个部位都会累加到船体，设的值 = 需要多少总伤害才沉船
##   例如 DDG=240 → 4 发 60 伤害的导弹必死
@export var hull_hp_max: float = 0.0

@export_group("团队")
@export var default_team: int = 1        ## 1=敌方（本次实装默认敌方），0=友方
