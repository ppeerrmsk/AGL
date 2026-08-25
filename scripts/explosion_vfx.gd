class_name ExplosionVFX
extends RefCounted

## 统一的爆炸闪光效果调用入口
##
## 所有会让物体爆炸/被摧毁的效果都必须通过本接口触发，保证全场视觉一致。
## 实际绘制宿主是场景中的 MissileManager（加入了 "explosion_vfx" group），
## 外部无需知道宿主是谁。普通爆点调用 emit；只有大型飞机结构解体调用 emit_airframe_wave。
##
## 设计原则：爆炸物命中与小单位坠毁终点都只播放一次普通方框。
##   - 爆炸物 = 导弹 / 火箭弹 / AOE 近炸引信 / 未来的炸弹、鱼雷、地雷等
##   - 每次爆炸物命中目标时 emit 一次（击中/击毁统一，不分致命与否）
##   - 命中点 = 真实接触点或按入射方向映射到机体表面的点，heading 取目标 heading
##
## 任意死亡开始时都不立即播放机体殉爆波；普通飞机／无人机／导弹也永不排入连续波。
## 爆炸物致命只保留伤害源已有的命中点反馈，真实机体仍完整进入坠毁过程。
## 大型轰炸机／运输机可在失控终点按受击分区排入一次结构波。
##
## 具体触发点：
##   1. 导弹直接命中战斗单位   missile_manager _physics_process
##   2. 导弹 AOE 命中单位      missile_manager _update_aoe_zones
##   3. 火箭弹命中单位         bullet_manager _physics_process (is_rocket 分支)
##   4. 未来新增爆炸物         统一走 ExplosionVFX.emit，禁止各模块自行绘制爆炸
##
## scale 语义：1.0 = 默认 22px 基准方块。

static func emit(tree: SceneTree, pos: Vector2, heading: float = 0.0,
		scale: float = 1.0) -> void:
	if tree == null:
		return
	var host := tree.get_first_node_in_group("explosion_vfx")
	if host and host.has_method("spawn_flash"):
		host.spawn_flash(pos, heading, scale)


## 大型飞机结构解体专用：沿当前机体半长/半翼展的五个结构点连续点火。
## route < 0 时由统一宿主确定性轮转；显式 0..3 仅供 Visual QA / 导演指定。
static func emit_airframe_wave(tree: SceneTree, pos: Vector2, heading: float,
		half_length_px: float, half_span_px: float, scale: float = 1.0,
		route: int = -1, initial_delay: float = 0.0) -> void:
	if tree == null:
		return
	var host := tree.get_first_node_in_group("explosion_vfx")
	if host and host.has_method("spawn_airframe_wave"):
		host.spawn_airframe_wave(pos, heading, half_length_px, half_span_px,
			scale, route, initial_delay)
