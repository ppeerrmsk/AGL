class_name EvasionModule
extends EquipmentParams

## 规避模块基类（热诱弹 / 干扰箔条 / 眼镜蛇 / 赫尔贝特轮 等）。
##
## 与攻击装备共享 EquipmentParams 接口，额外覆写 should_trigger / execute_evasion。
## TacticalPlanner 在 EVADE_MISSILE 分支收集所有 EvasionModule 投票，
## 按 priority 选最高的执行。
##
## 注意：cobra / herbst 的实际机动逻辑仍在对应 Node 子节点
## (cobra_maneuver.gd / herbst_maneuver.gd) 里。
## EvasionModule 子类只是"声明式触发"，execute_evasion 调子节点的 activate()。

## 评估当前是否值得触发本规避手段。
## 返回 0.0 = 不触发。>0 = 投票分数（priority），最高者执行。
func should_trigger(_ac, _incoming_missile) -> float:
	return 0.0


## 实际执行规避（释放热诱弹 / 触发眼镜蛇 / J-Turn）
func execute_evasion(_ac, _incoming_missile) -> void:
	pass
