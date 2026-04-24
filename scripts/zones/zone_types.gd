class_name ZoneType

## 战区类型枚举 + 元数据注册表
## 加新战区子类时必须在两处同步：
##   1. 在 TYPE_* 常量追加新值
##   2. 在 META 字典追加配置（显示名 / 类脚本 / 星级 / 是否 BOSS）
##   3. 在 ZoneManager.spawn_zone 的 match 里加 instantiate 分支
##
## 本枚举不用 `enum` 关键字，因为要携带元数据。用 int 常量 + 查表更灵活。

const TYPE_NONE: int = 0

# ── 海上战区 ──
const NAVAL_1S: int = 10       ## 1★ 护卫巡逻队（3 FFG 直线巡逻）
const NAVAL_2S: int = 11       ## 2★ 驱逐舰编队（DDG + 2 FFG 8 字轨迹）
const NAVAL_3S: int = 12       ## 3★ 航母战斗群（CSG 圆周 BOSS）

# ── 未来类型预留 ──
#const AERIAL_DOGFIGHT: int = 20
#const GROUND_ASSAULT: int = 30
#const STORY_BOSS: int = 40

## 元数据表：每个类型对应的显示名 / 脚本路径 / 星级 / BOSS 标识
## 脚本路径用字符串，spawn_zone 时通过 load() 拿到实际 Script 对象
## （避免文件级 preload 循环依赖）
static var META: Dictionary = {
	NAVAL_1S: {
		"display_name": "1★ 海上巡逻队",
		"script_path": "res://scripts/zones/naval_zone.gd",
		"star": 1,
		"is_boss": false,
		"config": {"star_level": 1, "patrol_mode": "linear", "radius": 7000.0},
	},
	NAVAL_2S: {
		"display_name": "2★ 海上驱逐编队",
		"script_path": "res://scripts/zones/naval_zone.gd",
		"star": 2,
		"is_boss": false,
		"config": {"star_level": 2, "patrol_mode": "eight", "radius": 8000.0},
	},
	NAVAL_3S: {
		"display_name": "3★ 海上航母战斗群",
		"script_path": "res://scripts/zones/naval_zone.gd",
		"star": 3,
		"is_boss": true,
		"config": {"star_level": 3, "patrol_mode": "orbit", "radius": 10000.0},
	},
}

## 获取所有已注册的类型 id（按元数据表顺序）
static func all_types() -> Array:
	return META.keys()

## 查显示名
static func display_name(type_id: int) -> String:
	var m: Dictionary = META.get(type_id, {})
	return m.get("display_name", "Unknown")

## 查脚本路径
static func script_path(type_id: int) -> String:
	var m: Dictionary = META.get(type_id, {})
	return m.get("script_path", "")

## 查星级（0 = 非海上/无星级）
static func star(type_id: int) -> int:
	var m: Dictionary = META.get(type_id, {})
	return m.get("star", 0)

## 是否 BOSS 类型（Skip to BOSS 用）
static func is_boss(type_id: int) -> bool:
	var m: Dictionary = META.get(type_id, {})
	return m.get("is_boss", false)

## 获取默认配置字典
static func default_config(type_id: int) -> Dictionary:
	var m: Dictionary = META.get(type_id, {})
	return (m.get("config", {}) as Dictionary).duplicate(true)

## 查找当前阶段的 BOSS 类型（Skip to BOSS 实现）
## 简单版：返回第一个 is_boss=true 的类型
static func find_boss_type() -> int:
	for t in META.keys():
		if is_boss(t):
			return t
	return TYPE_NONE
