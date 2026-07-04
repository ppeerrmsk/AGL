class_name ControlIntent
extends RefCounted

## 控制意图值类型（重构计划 Phase 1，docs/planning/physics-ai-control-refactor.md §5）
##
## 所有"想让飞机去哪/多快/开不开加力"的控制者不再直写 Aircraft 的 target_* 字段，
## 而是提交一份 ControlIntent 到 Aircraft 的意图槽（sticky slot，AI 分频写入者的主张
## 在两次 tick 之间保持有效）。每物理帧决策系统跑完后，Aircraft._resolve_intents()
## **按字段**取"主张了该字段的最高优先级槽位"写入 target_* —— 物理链只消费仲裁结果。
##
## 按字段仲裁（不是按槽位整体）让分权协作自然表达：EVADE 槽只主张方向，
## planner 的 EVADE intent 只主张速度+AB —— 与迁移前行为零改动。
##
## 哨兵约定：pursuit_pos=INF / target_speed_kmh<0 / afterburner<0 = 不主张该字段。
## 要主张"清空 pursuit（保持当前航向）"用 clear_pursuit=true。
##
## Phase 1 Step 1 首批仲裁字段只有 3 个（pursuit / speed / AB）；
## weapon_mode / is_firing / 高度 tier 仍由各控制者直写，后批迁移。

## 意图来源（优先级见 PRIORITY；后批迁移 MANUAL / MANEUVER / DIRECTIVE / FORMATION 等）
enum {
	SOURCE_TACTIC = 0,  ## TacticalPlanner 输出（60Hz，Aircraft 帧顶提交）
	SOURCE_EVADE = 1,   ## 规避几何（玩家 _update_evasion 60Hz / AI process_evade AI-tick，互斥）
	SOURCE_BRAKE = 2,   ## 玩家右键急刹（事件式旗桥接，见 Aircraft._resolve_intents）
}

## 源优先级：大者胜。固化"谁覆盖谁"，取代散布的 early-return/帧序默契。
const PRIORITY := {
	SOURCE_TACTIC: 20,
	SOURCE_EVADE: 30,
	SOURCE_BRAKE: 40,
}

var pursuit_pos: Vector2 = Vector2.INF  ## 追踪点主张；INF = 不主张
var clear_pursuit: bool = false          ## 主张"清空追踪点"（写 INF，保持当前航向）
## pursuit 字段的优先级特例（-1 = 用源优先级）。
## BRAKE 用 25：急刹的"清航点"要压过 TACTIC(20) 但让位 EVADE(30) 的蛇形几何——
## 与迁移前"planner 帧顶写 INF → _update_evasion 稍后覆盖"的帧序行为精确等价。
var pursuit_pri: int = -1
var target_speed_kmh: float = -1.0       ## 目标速度主张；<0 = 不主张
var afterburner: int = -1                ## 加力主张；-1 不主张 / 0 关 / 1 开
