class_name FlareParams
extends Resource

## 热诱弹参数 + 飞行员释放策略

@export_group("装载")
@export var max_flares: int = 30           ## 携带总量
@export var burst_count: int = 2           ## 每次释放几枚
@export var cooldown: float = 1.5          ## 两次释放最小间隔（秒）
@export var reload_time: float = 12.0      ## 热诱弹耗尽后装填时间（秒）

@export_group("干扰效果")
@export var base_jam_chance: float = 0.55  ## 基础干扰成功率 (0-1)
@export var aspect_bonus: float = 0.2      ## 导弹从侧/后方追来时的额外成功率
@export var maneuvering_bonus: float = 0.15 ## 大幅机动时的额外成功率（G>4）
@export var close_range_penalty: float = 0.35 ## 导弹极近（<150m）时的成功率惩罚
@export var low_energy_bonus: float = 0.2  ## 导弹低能量（发动机熄火后）时的额外成功率

@export_group("释放纪律")
## 面对来袭导弹未能及时释放的纪律权重 (0=必定释放, 1=最易失误)。
## 敌机运行时按 flare-evasion-coupling 缩放为 10% 的实际失误率；玩家方仍直接使用该值。
## 编队低级机设高值（~0.5-0.85），精英单机设低值（~0.15），保留相对等级差。
@export var fail_chance: float = 0.0
## 导弹从正前方来时，失误率降低量（Lancer 型对头冲刺时更警觉）
@export var head_on_fail_reduction: float = 0.0

@export_group("飞行员性格")
## 0.0 = 冷静老练（关键时刻才释放）
## 1.0 = 焦虑慌张（一被锁定就频繁释放）
@export var nervousness: float = 0.5
@export var panic_distance: float = 800.0  ## 慌张型飞行员在此距离开始释放（米）
@export var calm_distance: float = 250.0   ## 冷静型飞行员等到此距离才释放（米）
