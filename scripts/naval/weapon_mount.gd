class_name WeaponMount
extends RefCounted

## 挂点运行时对象 —— 持有 WeaponMountParams 引用 + 动态状态
## 由 NavalUnit._ready 根据 params.mount_configs 实例化
##
## 本次实装只建状态 / 伤害接口，武器开火逻辑在步骤 3+（DDG / CG）接入
## CIWS 的双模式（导弹拦截 + 对空扫射）在步骤 2（FFG 跑通）时实装

var params: WeaponMountParams           ## 配置引用（只读）
var hp: float = 0.0                     ## 当前血量（从 params.max_hp 初始化）
var destroyed: bool = false             ## 被打掉后永久禁用

# ── CIWS 导弹拦截状态 ──
var engaged_missile: Node2D = null      ## 当前正在拦截的玩家导弹（null=空闲）
var engage_cooldown: float = 0.0        ## 导弹拦截冷却，>0 时第二发导弹无视本挂点
var tracer_timer: float = 0.0           ## (legacy，保留字段避免破坏 .tres，可清)

# ── 武器开火冷却（VLS 齐射 / SAM 单发 / CIWS 连射）──
var fire_cooldown: float = 0.0          ## 下一次开火倒计时（秒）

# ── CIWS 目标获取节流 ──
## CIWS 每帧都跑 _find_aircraft / _find_incoming_missile / _find_player 三次全场扫描
## 改为每 ~0.15s 才重做一次决策（仍以 fire_cooldown 节奏 ~33Hz 开火），
## 单舰 12 CIWS × 60Hz 全场扫降到 12 × 6.7Hz，CSG 时省 ~90% 扫描开销
var acquire_cooldown: float = 0.0
## 缓存扫描结果，acquire_cooldown 期间复用（避免每帧扫描）
## kind: 0=无目标, 1=近距反飞机, 2=对空扫射玩家
var cached_aircraft_target: Node2D = null
var cached_aircraft_kind: int = 0

# ── CIWS 射击计数（用于每 N 发中夹 1 发真弹，其余是视觉装饰）──
var ciws_shot_counter: int = 0

# ── VLS 齐射状态 ──
## salvo_remaining > 0 表示齐射进行中，正在连续射出剩余导弹
var salvo_remaining: int = 0
var salvo_delay: float = 0.0            ## 距离下一发齐射弹发射的倒计时（秒）

# ── Flak 空爆炮组状态 ──
var flak_remaining: int = 0             ## 当前冻结炮组尚未出膛的炮弹数
var flak_delay: float = 0.0             ## 距离下一发炮弹的组内计时
var flak_solution_pos: Vector2 = Vector2.ZERO
var flak_solution_altitude: float = 0.0
var flak_fuse_error: float = 0.0
var flak_burst_id: int = 0

## 从 params 初始化血量
func initialize(p: WeaponMountParams) -> void:
	params = p
	if p:
		hp = p.max_hp
	destroyed = false
	engaged_missile = null
	engage_cooldown = 0.0
	tracer_timer = 0.0
	fire_cooldown = 0.0
	flak_remaining = 0
	flak_delay = 0.0
	flak_solution_pos = Vector2.ZERO
	flak_solution_altitude = 0.0
	flak_fuse_error = 0.0
	flak_burst_id = 0

## 应用伤害，返回是否刚被摧毁（true 仅在本次调用击穿时返回）
func apply_damage(amount: float) -> bool:
	if destroyed:
		return false
	hp -= amount
	if hp <= 0.0:
		hp = 0.0
		destroyed = true
		# 挂点死亡清理拦截状态
		engaged_missile = null
		engage_cooldown = 0.0
		flak_remaining = 0
		flak_delay = 0.0
		return true
	return false

## 在世界坐标系中计算本挂点的位置
## ship_pos: 船体 global_position
## ship_heading: 船体朝向（弧度）
func world_position(ship_pos: Vector2, ship_heading: float) -> Vector2:
	if params == null:
		return ship_pos
	# 船头朝向 +X(船本地)，世界坐标系要把本地 offset 按 ship_heading 旋转
	# ship_heading 约定：0 = 北 = 世界 -Y 方向
	# 所以船头方向世界向量 = (sin(h), -cos(h))；船右舷方向 = (cos(h), sin(h))
	var forward := Vector2(sin(ship_heading), -cos(ship_heading))
	var starboard := Vector2(cos(ship_heading), sin(ship_heading))
	var lo := params.local_offset
	return ship_pos + forward * lo.x + starboard * lo.y
