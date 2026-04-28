class_name WeakPoint
extends RefCounted

## 船体弱点运行时对象 —— 挂点死到阈值后暴露
## 每艘船最多一个弱点，位置固定在船体中央（local_offset=0,0）
## 数据由 NavalParams.weak_point_* 字段初始化
## HP 经过设计：单发玩家导弹（90 dmg）一发不死，最弱舰也至少 2 发命中才能击沉

var revealed: bool = false        ## 暴露前不可锁、不可点
var local_offset: Vector2 = Vector2.ZERO  ## 相对船首的像素偏移（默认船体中央）
var hp: float = 100.0             ## 默认值，被 NavalParams.weak_point_hp 覆盖
var radius: float = 300.0         ## 玩家点击命中判定半径

## 应用伤害，返回是否被摧毁
func apply_damage(amount: float) -> bool:
	if not revealed:
		return false
	hp -= amount
	if hp <= 0.0:
		hp = 0.0
		return true
	return false

## 检查某世界坐标是否落在弱点命中半径内
## center_world: 弱点所在的世界坐标（船体中央经过 heading 旋转后的位置）
func contains_point(center_world: Vector2, hit_pos: Vector2) -> bool:
	if not revealed:
		return false
	return hit_pos.distance_to(center_world) <= radius
