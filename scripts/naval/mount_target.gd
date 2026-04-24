class_name MountTarget
extends CombatUnit

## 挂点锁定代理 —— 让船上的每个挂点 / 弱点成为雷达锁定系统里的独立目标
##
## 设计：
##   - 作为 survivor_mode 的子节点（不是 NavalUnit 子节点），避免继承 NavalUnit 的 rotation transform
##   - 每帧同步 global_position 到对应挂点的世界坐标 + 同步 HP
##   - 不主动扫描（is_in_radar_cone 返回 false），只承担"被锁定"角色
##   - 伤害走 take_damage → 转发到 parent_ship.take_damage_at（保持位置感知路由一致）
##   - 挂点死亡 / 弱点消失 / 船销毁 → 自行 queue_free
##
## 不参与 hover（camera_controller 里特判跳过），让 hover 仍作用于整艘船
## 不参与 bullet_manager 的子弹命中判定？—— 实际上 MountTarget 小尺寸 + 船的
##   hull_length 扩展命中半径先触发，bullet 不会先打到 MountTarget，可以留着

var parent_ship: NavalUnit = null
var mount_ref: WeaponMount = null       ## 代理的挂点（与 weak_point_ref 二选一）
var weak_point_ref: WeakPoint = null    ## 代理的弱点（二选一）

# ── 视觉（只绘制锁定指示）──
const LOCK_BOX_SIZE: float = 14.0


func _ready() -> void:
	flat_altitude = true
	altitude = 0.0
	if parent_ship and is_instance_valid(parent_ship):
		team = parent_ship.team
	# 初次位置对齐，避免首帧出现在原点
	_sync_position()


func _physics_process(_delta: float) -> void:
	# 已经开始销毁 —— 不再跑任何逻辑（防止 queue_free 生效前再跑一帧）
	if is_destroyed:
		return

	# 失效检查：父船没了 / 被销毁 → 自毁
	if parent_ship == null or not is_instance_valid(parent_ship) or parent_ship.is_destroyed:
		_self_destruct()
		return

	# 挂点代理：挂点死了 → 自毁
	if mount_ref != null:
		if mount_ref.destroyed:
			_self_destruct()
			return
		hp = mount_ref.hp

	# 弱点代理：未暴露或已死 → 自毁
	if weak_point_ref != null:
		if not weak_point_ref.revealed or weak_point_ref.hp <= 0.0:
			_self_destruct()
			return
		hp = weak_point_ref.hp

	_sync_position()
	queue_redraw()


## 标记为 destroyed + 主动通知所有飞机清空 combat_target 引用 + queue_free
## 目的：避免 queue_free 生效前还被飞机的 combat_target 字段握着 → 下一帧
##   `combat_target is Aircraft` 等检查访问已释放节点报 "freed instance"
func _self_destruct() -> void:
	if is_destroyed:
		return
	is_destroyed = true
	_notify_clear_combat_target_refs()
	queue_free()

## 广播：任何 Aircraft.combat_target == self 的都要清掉（防止下一帧访问已释放实例）
func _notify_clear_combat_target_refs() -> void:
	for u in CombatUnit.all_units:
		if u == null or not is_instance_valid(u):
			continue
		if not u is Aircraft:
			continue
		var ac: Aircraft = u
		if ac.combat_target == self:
			ac.clear_combat_target()


## 把自身位置对齐到对应挂点 / 弱点的世界坐标，同时同步 heading
## heading 同步很重要：导弹 TAA（目标纵横角）计算用它判定攻击方位，用于最大射程公式
func _sync_position() -> void:
	if parent_ship == null or not is_instance_valid(parent_ship):
		return
	heading = parent_ship.heading
	speed = parent_ship.speed
	if mount_ref != null:
		global_position = mount_ref.world_position(parent_ship.global_position, parent_ship.heading)
	elif weak_point_ref != null:
		var fwd := Vector2(sin(parent_ship.heading), -cos(parent_ship.heading))
		var stb := Vector2(cos(parent_ship.heading), sin(parent_ship.heading))
		var lo: Vector2 = weak_point_ref.local_offset
		global_position = parent_ship.global_position + fwd * lo.x + stb * lo.y


## 伤害转发给船（位置感知路由）
func take_damage(amount: float) -> void:
	if parent_ship and is_instance_valid(parent_ship):
		parent_ship.take_damage_at(amount, global_position)


## 导弹伤害：和普通伤害走同一路径
func take_missile_damage(amount: float) -> void:
	take_damage(amount)


## 挂点 / 弱点本身永远可被锁定
## ⚠ 不要继承 parent_ship.is_lock_immune()：船的免疫是"锁定框不出现在船中心"的路由 trick，
## 不是真的免疫。挂点代理必须保持可锁定，否则雷达循环会跳过它们。
func is_lock_immune() -> bool:
	return false


## 不主动扫描
func is_in_radar_cone(_target_global_pos: Vector2) -> bool:
	return false


func get_altitude_tier() -> int:
	return AltitudeTier.GROUND


## ============ 绘制（只画锁定指示，船本体由 NavalUnit 绘制）============

func _draw() -> void:
	# 被锁定 / 正在被锁定 → 画锁定框
	var p: float = clampf(incoming_lock_progress, 0.0, 1.0)
	if p > 0.0 or is_locked:
		AircraftRenderer.draw_lock_box(self, p, is_locked)
