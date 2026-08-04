class_name WeaponMountParams
extends Resource

## 挂点配置 Resource —— 定义一个武器挂点的几何 + 武器类型 + 血量
## 由 NavalParams 以数组形式持有，NavalUnit._ready 时实例化成 WeaponMount 运行时对象

## 武器类型枚举
## VLS_SALVO  — 垂直发射齐射系统（DDG/CG 主力，一次 4-12 枚低精度齐射）
## SAM_SHORT  — 短程单发防空导弹（FFG 近程 RAM）
## CIWS       — 近防武器系统（拦导弹 + 对空扫射双用途）
## NAVAL_AA   — 舰载对空机炮（类似陆基 ZU-23 AA，中距对飞机精准打击；weapon_params 走 GunParams）
## NAVAL_FLAK — 舰载定时空爆炮（DDG 区域拒止；不拦截导弹）
enum WeaponType {
	VLS_SALVO,
	SAM_SHORT,
	CIWS,
	NAVAL_AA,
	NAVAL_FLAK,
}

@export_group("几何")
@export var local_offset: Vector2 = Vector2.ZERO  ## 相对船首朝向的像素偏移（+X=船头方向, +Y=右舷）
@export var facing: float = 0.0                   ## 挂点朝向（弧度，相对船体 heading）
@export var arc: float = TAU                      ## 射界半角（TAU=全向，PI/2=前向 ±90°）

@export_group("武器")
@export var weapon_type: WeaponType = WeaponType.CIWS
@export var weapon_params: Resource               ## 指向 missile_params.tres / gun_params.tres 等，具体类型由 weapon_type 决定

@export_group("生存性")
@export var max_hp: float = 30.0                  ## 挂点独立血量（CIWS 30 / SAM_SHORT 50 / VLS 100-150）

@export_group("显示")
@export var display_symbol: String = "C"          ## 绘制时的单字符标识（C=CIWS, V=VLS, S=SAM），仅测试期使用
