## SwarmDirector 可调参数包
##
## 通过 .tres 文件让策划在 Inspector 里直接调蜂群协同行为，无需重编。
## 默认资源：res://resources/ace_swarm_director.tres
##
## 与 SwarmDirector 的关系：director._params 在构造时注入，每 tick 读取
## attacker_pct / wedge_half_deg / hysteresis_score_pct 等字段做角色 + lane 分配。

class_name SwarmDirectorParams
extends Resource

## Director tick 频率（Hz）。1Hz 是默认战略节拍 —— 既不抖动（滞回保护）也不滞后
## 玩家位姿变化。Ace 档位可在子资源里抬到 2Hz/4Hz。
@export var director_hz: float = 1.0

## 角色比例（按总活 UAV 数的百分比；MQ-111 强制 GUARD 不计入此分母）
@export_range(0.0, 1.0) var attacker_pct: float = 0.60   ## 4 个 ATTACKER_* 楔形合计占比
@export var shooter_count: int = 1                          ## 同一时刻持 SHOOTER 角色的数量
@export_range(0.0, 1.0) var decoy_pct: float = 0.10       ## DECOY 拉空当
@export_range(0.0, 1.0) var guard_pct: float = 0.20       ## 绕 boss 转，反导拦截
                                                           ## 剩余配额 = RESERVE（恢复能量）

## DESIGNATION 相切换：boss 的 designation 窗口期内全力突击，guard/reserve 让位
@export_range(0.0, 1.0) var designation_attacker_pct: float = 0.85

## Lane 楔形半宽（度）。30° = 楔形覆盖 60°，4 个楔形 360°/4=90° 互不重叠 + 留 30° 缓冲。
@export var wedge_half_deg: float = 30.0

## ATTACKER 攻击点的距离衰减：从 converge_distance_far 衰减到 converge_distance_close
## 控制突击切入的"楔形尖端"在玩家附近多远 —— 太远会被玩家轻松甩开，太近会过度集中
@export var converge_distance_far: float = 1500.0
@export var converge_distance_close: float = 600.0

## DECOY 延伸阈值：UAV 沿玩家航向垂直方向跑到该距离后切回 CONVERGE
@export var extend_threshold_px: float = 2500.0

## SHOOTER 评分权重（aspect_align × dist_inv × ammo_ok）
@export var shooter_weight_aspect: float = 1.0
@export var shooter_weight_dist: float = 1.0
@export var shooter_weight_ammo: float = 0.5

## 滞回：prev_role 若得分在最佳 hysteresis_score_pct 以内则保留，避免 1Hz 翻牌
@export_range(0.0, 0.5) var hysteresis_score_pct: float = 0.15

## RESERVE 角色：能量比 < 此阈值时强制进入 RESERVE 恢复
@export_range(0.0, 1.0) var reserve_energy_threshold: float = 0.40

## RESERVE 绕 boss 转的环形半径（像素）
@export var reserve_orbit_radius_px: float = 800.0

## ATTACKER 进入"楔形内 + aspect < threshold"切回 LEAD_CHASE 的角度阈值（度）
@export var attacker_to_chase_aspect_deg: float = 60.0
