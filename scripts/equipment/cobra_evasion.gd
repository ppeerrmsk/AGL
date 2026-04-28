class_name CobraEvasion
extends EvasionModule

## 眼镜蛇机动装备包装器（commit 6/13）
##
## 与机炮/导弹/热诱弹不同，cobra 没有 params 资源 —— 它是挂载到 Aircraft
## 子节点的 CobraManeuver Node。装备只是"声明 + 自动挂载"的桥：
##
## - .tres 里写 `equipment = [CobraEvasion]` → Aircraft._publish_equipment_to_legacy
##   检测到时自动 add_child(CobraManeuver.new())
## - 现存手动挂载路径（survivor_player.gd:232 / survivor_spawner.gd:1398 /
##   poltergeist_squad.gd:234）保留，publish 检测到已存在 CobraManeuver 子节点
##   则跳过，不会重复挂载
##
## should_trigger / execute_evasion 暂留 base no-op，等 commit 7 投票模型
## 上线时实装：should_trigger 评估 cobra 适用条件（被追 + 低能量 + 后半球），
## execute_evasion 调 ac.get_maneuver().activate()。
## 当前实际触发仍由 aircraft.gd._update_cobra_skill 自己跑。


func _init() -> void:
	equipment_kind = "cobra"
