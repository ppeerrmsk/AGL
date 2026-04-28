## AIDirective —— 事件系统下发给 AI 的声明式指令
##
## 设计目标：让 GameEvent 用一组通用 verb 命令任意 AI / NavalUnit 做事，
## 不用绕到 AIController._state 内部。directive 存在期间 AI 完全跳过常规
## PATROL/ENGAGE/SQUAD_FOLLOW 路由，只执行 directive 行为；directive 释放后
## 无缝回到正常 AI。
##
## 一架单位同时只能持有一个 directive；新 directive 直接覆盖旧的。
##
## ── 通用执行模型 ──
##   AIController._physics_process 顶层：
##     if _directive: _process_directive(); return
##   NavalUnit._update_subsystems 顶层：
##     if _directive and _directive.combat_disabled: return
##     ...
##
## 子类化没必要 —— 把所有需要的状态塞进 params Dictionary 即可，让事件层灵活注入。

class_name AIDirective
extends RefCounted

enum Type {
	FLY_TO_POINT,    ## 飞向 params.target，到达 (距离 < arrival_radius) 触发 on_arrival
	PATROL_RING,     ## 绕 params.center 半径 params.radius 盘旋，沿圆周匀速移动
	FOLLOW_PATH,     ## 沿 params.waypoints 飞，可 loop=true
	HOLD_POSITION,   ## 保持当前位置不动（极少飞机用，主要给舰船 / 地面单位）
	ENGAGE_TARGET,   ## 强制 combat_target = params.target，进入 ENGAGE 状态（不锁其他敌方）
	PASSIVE,         ## 不开火、不交战，仍按 waypoints 飞行（裸 directive，常用于"驻泊"）
}

## 抵达后行为（仅 FLY_TO_POINT 用）
enum OnArrival {
	HOLD,            ## 抵达后切换为 HOLD_POSITION
	PATROL,          ## 抵达后切换为 PATROL_RING（params.radius 沿用 arrival_radius）
	RELEASE,         ## 抵达后清空 directive，AI 回到正常状态
	CALLBACK,        ## 调 on_complete，由事件层决定下一步
}

# ──────────────── 字段 ────────────────

var type: int = Type.PASSIVE
var params: Dictionary = {}
## 下发指令的事件 ——
## 当事件 active=false 时本 directive 自动失效，AI 回到正常逻辑（防内存泄漏）
var owner_event: WeakRef = null
## 是否允许交战 ——
## false：directive 期间无视雷达锁定 / 来袭目标，专心执行 directive
## true ：directive 行为之上仍允许 ENGAGE_TARGET（暂不展开，预留未来组合行为）
var combat_disabled: bool = true
## 优先级（0=普通；高优先级 directive 不被低优先级覆盖）
var priority: int = 0
## 抵达半径（仅 FLY_TO_POINT；默认 400px ≈ 800m）
var arrival_radius: float = 400.0
## FLY_TO_POINT 抵达后行为
var on_arrival: int = OnArrival.RELEASE
## CALLBACK 时调用（owner = AI/NavalUnit 自身）
var on_complete: Callable = Callable()

# ──────────────── 工厂方法 ────────────────

## FLY_TO_POINT 工厂：飞到 target，抵达后由 on_arrival 决定下一步
static func fly_to(target: Vector2, on_arrival_kind: int = OnArrival.RELEASE,
		arrival_radius_px: float = 400.0) -> AIDirective:
	var d := AIDirective.new()
	d.type = Type.FLY_TO_POINT
	d.params = {"target": target}
	d.on_arrival = on_arrival_kind
	d.arrival_radius = arrival_radius_px
	return d

## PATROL_RING 工厂：绕 center 半径 radius 盘旋
static func patrol_ring(center: Vector2, radius: float, n_waypoints: int = 6) -> AIDirective:
	var d := AIDirective.new()
	d.type = Type.PATROL_RING
	d.params = {"center": center, "radius": radius, "n_waypoints": n_waypoints}
	return d

## FOLLOW_PATH 工厂
static func follow_path(waypoints: PackedVector2Array, loop: bool = false) -> AIDirective:
	var d := AIDirective.new()
	d.type = Type.FOLLOW_PATH
	d.params = {"waypoints": waypoints, "loop": loop}
	return d

## HOLD_POSITION 工厂（飞机会原地盘旋，舰船保持航向）
static func hold_position() -> AIDirective:
	var d := AIDirective.new()
	d.type = Type.HOLD_POSITION
	return d

## ENGAGE_TARGET 工厂：强制目标 = target（combat_disabled 置 false）
static func engage_target(target: CombatUnit) -> AIDirective:
	var d := AIDirective.new()
	d.type = Type.ENGAGE_TARGET
	d.params = {"target": target}
	d.combat_disabled = false
	return d

## PASSIVE 工厂：不交战，照原 waypoints 走（兜底）
static func passive() -> AIDirective:
	var d := AIDirective.new()
	d.type = Type.PASSIVE
	return d

# ──────────────── 查询 ────────────────

## directive 是否仍由活跃 event 持有 —— 事件结束自动失效
func is_owner_alive() -> bool:
	if owner_event == null:
		return true   ## 没绑事件 = 永久 directive（debug / 测试用）
	var ev = owner_event.get_ref()
	if ev == null:
		return false
	if "active" in ev and not ev.active:
		return false
	return true
