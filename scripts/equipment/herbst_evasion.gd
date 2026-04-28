class_name HerbstEvasion
extends EvasionModule

## 赫尔贝特轮 J-Turn 装备包装器（commit 6/13）
##
## 同 CobraEvasion 的设计：装备声明 + 自动挂载 HerbstManeuver Node 子节点。
##
## 当前唯一实际使用者是 F-14 Poltergeist BOSS（poltergeist_squad.gd:234 手动挂载）。
## 未来 F-47 重写或新 BOSS 可以通过 .tres 的 equipment 数组声明此装备。
##
## should_trigger 评估 J-Turn 适用条件（BVR 被追 + 后半球距离不远）；
## execute_evasion 调 ac.get_herbst().activate()。等 commit 7 投票模型实装。


func _init() -> void:
	equipment_kind = "herbst"
