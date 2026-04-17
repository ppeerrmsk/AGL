class_name ExplosionVFX
extends RefCounted

## 统一的爆炸闪光效果调用入口
##
## 所有会让物体爆炸/被摧毁的效果都必须通过本接口触发，保证全场视觉一致。
## 实际绘制宿主是场景中的 MissileManager（加入了 "explosion_vfx" group），
## 外部无需知道宿主是谁，仅需调用 ExplosionVFX.emit(tree, pos, heading, scale)。
##
## 设计原则：**只有被爆炸物攻击的单位才播放此效果**。
##   - 爆炸物 = 导弹 / 火箭弹 / AOE 近炸引信 / 未来的炸弹、鱼雷、地雷等
##   - 每次爆炸物命中目标时 emit 一次（击中/击毁统一，不分致命与否）
##   - 命中点 = **目标单位本体位置**（不是弹头或 AOE 中心），heading 取目标 heading
##
## 禁止触发的情形（非爆炸死亡，无需特效）：
##   - 机炮 / 子弹致命
##   - 坠地、失速坠毁
##   - 燃油耗尽
##   - 其他无爆炸物接触的死亡
##
## 具体触发点：
##   1. 导弹直接命中战斗单位   missile_manager _physics_process
##   2. 导弹 AOE 命中单位      missile_manager _update_aoe_zones
##   3. 火箭弹命中单位         bullet_manager _physics_process (is_rocket 分支)
##   4. 未来新增爆炸物         统一走 ExplosionVFX.emit，禁止各模块自行绘制爆炸
##
## scale 语义：1.0 = 默认 26px 基准方块。

static func emit(tree: SceneTree, pos: Vector2, heading: float = 0.0, scale: float = 1.0) -> void:
	if tree == null:
		return
	var host := tree.get_first_node_in_group("explosion_vfx")
	if host and host.has_method("spawn_flash"):
		host.spawn_flash(pos, heading, scale)
