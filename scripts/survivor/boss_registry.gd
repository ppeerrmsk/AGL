## BOSS 注册表 + 地图池
##
## 每个 BOSS 在 BOSS_DEFS 定义：class_path / bgm / display_name / callsign_prefix。
## 每张地图在 MAP_POOLS 声明可刷 BOSS 列表，进 BOSS 阶段时按地图 roll。
##
## 加新 BOSS 的步骤：
##   1. 写 BossEncounter 子类（extends AceSquad 或独立继承 BossEncounter）
##   2. 在 BOSS_DEFS 加一条
##   3. 在 MAP_POOLS 的对应地图数组里加 boss id（可上多张地图）
class_name BossRegistry
extends RefCounted

## BOSS 定义：id → { class_path, bgm, display_name, callsign_prefix }
const BOSS_DEFS: Dictionary = {
	"WRAITH_SQUADRON": {
		"class_path": "res://scripts/survivor/f47_ace_squad.gd",
		"bgm": "boss",
		"display_name": "WRAITH SQUADRON",
		"callsign_prefix": "WRAITH",
		"requires_water": false,            ## 飞机 BOSS 陆地海上都行
	},
	"CARRIER_STRIKE_GROUP": {
		"class_path": "res://scripts/survivor/carrier_strike_group.gd",
		"bgm": "boss_csg",                  ## Phase 1 BGM id（AudioManager 注册）
		"display_name": "CARRIER STRIKE GROUP",
		"callsign_prefix": "CSG",
		"requires_water": true,             ## 舰队只能刷海上
	},
	"MOTHER_GOOSE": {
		"class_path": "res://scripts/survivor/mother_goose_boss.gd",
		"bgm": "boss",                      ## v1 复用 F-47 BGM；v2 单独配
		"display_name": "MOTHER GOOSE",
		"callsign_prefix": "GOOSE",
		"requires_water": false,            ## 飞机型，陆海皆可
	},
}

## 地图 BOSS 池：map_id → [boss_id]（等权随机）
## 地图 id 来自 survivor_map_select.MAP_LIST 的 "id" 字段
const MAP_POOLS: Dictionary = {
	"default": ["WRAITH_SQUADRON", "CARRIER_STRIKE_GROUP"],
}

## 按地图从池子里 roll 一个 BOSS 实例（未 spawn，调用方自行调 spawn）
## 未知 map_id 或空池子回退 default 池
## spawn_pos != INF 时会按地形过滤（陆地位置跳过 requires_water=true 的 BOSS）
static func pick_for_map(map_id: String, spawn_pos: Vector2 = Vector2.INF) -> BossEncounter:
	var pool: Array = MAP_POOLS.get(map_id, [])
	if pool.is_empty():
		pool = MAP_POOLS.get("default", [])
	if pool.is_empty():
		push_error("BossRegistry: no boss in pool for map '%s'" % map_id)
		return null
	# 地形过滤：若 spawn 点在陆地，剔除需要水面的 BOSS（例如 CSG）
	var filtered: Array = pool
	if spawn_pos != Vector2.INF and MapGeography.is_on_land(spawn_pos):
		filtered = []
		for id in pool:
			var def: Dictionary = BOSS_DEFS.get(id, {})
			if not bool(def.get("requires_water", false)):
				filtered.append(id)
		if filtered.is_empty():
			# 所有 BOSS 都要求水面但 spawn 点在陆地 —— 退回原池保底（视觉出戏好过游戏崩）
			filtered = pool
			push_warning("BossRegistry: spawn_pos on land, no non-naval boss available, falling back")
	var boss_id: String = filtered[randi() % filtered.size()]
	return instantiate(boss_id)

## 按 id 实例化（供 Debug 面板 / 脚本事件直接指定 BOSS 用）
static func instantiate(boss_id: String) -> BossEncounter:
	var def: Dictionary = BOSS_DEFS.get(boss_id, {})
	if def.is_empty():
		push_error("BossRegistry: unknown boss id '%s'" % boss_id)
		return null
	var script: Script = load(def["class_path"])
	if script == null:
		push_error("BossRegistry: failed to load '%s'" % def["class_path"])
		return null
	var enc: BossEncounter = script.new()
	enc.boss_id = boss_id
	# 用注册表的元数据覆盖（子类可在 _init 自己再设，但 registry 是 single source of truth）
	if def.has("display_name"):
		enc.display_name = String(def["display_name"])
	if def.has("callsign_prefix"):
		enc.callsign_prefix = String(def["callsign_prefix"])
	if def.has("bgm"):
		enc.bgm_track = String(def["bgm"])
	return enc
