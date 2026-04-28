class_name EngagementPreference
extends RefCounted

## TacticalPlanner 收集装备投票时的值类型。
##
## 每件攻击装备的 desired_engagement(situation) 返回此对象，
## planner 按 priority 排序选最高票，用 preferred_intent 驱动 BFM。

## 期望与目标保持的距离（米）。<0 表示无偏好。
var preferred_range_m: float = -1.0

## 期望执行的 intent。引用 ai/tactical/tactical_plan.gd 的 Intent 枚举。
## 例：TacticalPlan.Intent.TAIL_CHASE / CLOSE_TAIL / LEAD_PURSUIT。
var preferred_intent: int = -1

## 是否需要雷达锁定（true → planner 不能 crank 出锥）
var needs_lock: bool = false

## 是否需要视线（false → 可隔云/隔山发射，例 BVR 导弹数据链制导）
var needs_los: bool = true

## 投票优先级。同帧多件装备投票时取最高。0.0-1.0。
## 约定：导弹 0.7、电磁炮 0.8、机炮 0.6、激光 0.6
var priority: float = 0.5

## 本装备如果开火，期望使用的速度（km/h）。<0 表示无偏好。
var preferred_speed_kmh: float = -1.0

## 本装备开火是否倾向加力。
var prefers_afterburner: bool = false

## 调试 / EventLogger 标签
var rationale: String = ""


static func make(kind: String, range_m: float, intent: int, prio: float) -> EngagementPreference:
	var p := EngagementPreference.new()
	p.rationale = kind
	p.preferred_range_m = range_m
	p.preferred_intent = intent
	p.priority = prio
	return p
