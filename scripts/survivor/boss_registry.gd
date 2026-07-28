## BOSS 注册表 + 地图池
##
## 每个 BOSS 在 BOSS_DEFS 定义：class_path / bgm / display_name / name_key / callsign_prefix。
## 每张地图在 MAP_POOLS 声明可刷 BOSS 列表，进 BOSS 阶段时按地图 roll。
##
## 加新 BOSS 的步骤：
##   1. 写 BossEncounter 子类（extends AceSquad 或独立继承 BossEncounter）
##   2. 在 BOSS_DEFS 加一条
##   3. 在 MAP_POOLS 的对应地图数组里加 boss id（可上多张地图）
class_name BossRegistry
extends RefCounted

## BOSS 定义：id → { class_path, bgm, display_name, name_key, callsign_prefix }
## display_name = EventLogger/调试用原值（不 tr）；name_key = 玩家可见 i18n key（复用图鉴条目名）
const BOSS_DEFS: Dictionary = {
	"WRAITH_SQUADRON": {
		"class_path": "res://scripts/survivor/f47_ace_squad.gd",
		"bgm": "boss",
		"display_name": "WRAITH SQUADRON",
		"name_key": "CODEX_WRAITH_SQUADRON_NAME",
		"callsign_prefix": "WRAITH",
		"requires_water": false,            ## 飞机 BOSS 陆地海上都行
	},
	"CARRIER_STRIKE_GROUP": {
		"class_path": "res://scripts/survivor/carrier_strike_group.gd",
		"bgm": "boss_csg",                  ## Phase 1 BGM id（AudioManager 注册）
		"display_name": "LADON STRIKE GROUP",
		"name_key": "CODEX_CARRIER_STRIKE_GROUP_NAME",
		"callsign_prefix": "CSG",
		"requires_water": true,             ## 舰队只能刷海上
	},
	"MOTHER_GOOSE": {
		"class_path": "res://scripts/survivor/mother_goose_boss.gd",
		"bgm": "boss",                      ## v1 复用 F-47 BGM；v2 单独配
		"display_name": "MOTHER GOOSE",
		"name_key": "CODEX_MOTHER_GOOSE_NAME",
		"callsign_prefix": "GOOSE",
		"requires_water": false,            ## 飞机型，陆海皆可
	},
}

## BOSS 的玩家可见名 i18n key（结算面板等 UI 用）。未知 id → 空串，调用方回退通用文案
static func name_key_for(boss_id: String) -> String:
	var def: Dictionary = BOSS_DEFS.get(boss_id, {})
	return String(def.get("name_key", ""))

## 地图 BOSS 池：map_id → [boss_id]（无档案 history 时等权随机）
## 地图 id 来自 survivor_map_select.MAP_LIST 的 "id" 字段
## 2026-07-26 MOTHER_GOOSE 随生涯档案轮换正式上线（spec career-archive §3.1，此前一直池外）
const MAP_POOLS: Dictionary = {
	"default": ["WRAITH_SQUADRON", "CARRIER_STRIKE_GROUP", "MOTHER_GOOSE"],
}

## 生涯递进顺序（spec career-archive §2.3）：新玩家按此序初见每个 BOSS；
## 打赢当前 BOSS 下次必换（下一个优先），没打赢则按概率推进/重复。加新 BOSS 追加表尾
const BOSS_ROTATION: Array = ["WRAITH_SQUADRON", "CARRIER_STRIKE_GROUP", "MOTHER_GOOSE"]
## 未击败当前 BOSS 时，下次仍推进到下一个的概率（单杠杆；击败则 100% 换）
const ROTATION_ADVANCE_CHANCE := 0.5

## 按地图 roll 一个 BOSS 实例（未 spawn，调用方自行调 spawn）
## 未知 map_id 或空池子回退 default 池
## spawn_pos != INF 时会按地形过滤（陆地位置跳过 requires_water=true 的 BOSS）
## history 非空时走生涯档案轮换（CareerArchive.build_boss_history() 的形状：
## { "last": String, "defeated": {boss_id: bool} }）；空 = 旧纯随机（bench/debug 兼容）
static func pick_for_map(map_id: String, spawn_pos: Vector2 = Vector2.INF,
		history: Dictionary = {}) -> BossEncounter:
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
	var boss_id: String
	if history.is_empty():
		boss_id = filtered[randi() % filtered.size()]
	else:
		boss_id = pick_by_rotation(filtered, history)
	return instantiate(boss_id)

## 档案轮换选择：候选偏好序里第一个通过地图池∩地形过滤的 id。
## filtered ⊆ ROTATION 时必命中（候选序含全部 ROTATION 成员）；
## 将来某图池含 ROTATION 外 BOSS 且过滤后只剩它们 → 回退随机
static func pick_by_rotation(filtered: Array, history: Dictionary) -> String:
	var candidates: Array = rotation_candidates(history, randf())
	for id in candidates:
		if filtered.has(id):
			return String(id)
	return String(filtered[randi() % filtered.size()])

## 纯函数：由档案 history 与一次 roll 给出 BOSS 偏好序（无副作用，无头单测覆盖）。
## 语义（spec career-archive §3.1）：
##   生涯首遇 → ROTATION 原序（雷斯中队最优先）
##   打过(击败过) last → 下次必换：下一个起环绕，last 垫底只作地形过滤兜底
##   没打过 last → roll < ROTATION_ADVANCE_CHANCE 推进（同上），否则重复 last 优先
static func rotation_candidates(history: Dictionary, advance_roll: float) -> Array:
	var n: int = BOSS_ROTATION.size()
	var last := String(history.get("last", ""))
	var idx: int = BOSS_ROTATION.find(last)
	if idx < 0:
		return BOSS_ROTATION.duplicate()
	var defeated: Dictionary = history.get("defeated", {})
	var out: Array = []
	if bool(defeated.get(last, false)) or advance_roll < ROTATION_ADVANCE_CHANCE:
		for k in range(1, n):
			out.append(BOSS_ROTATION[(idx + k) % n])
		out.append(last)
	else:
		for k in range(0, n):
			out.append(BOSS_ROTATION[(idx + k) % n])
	return out

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
