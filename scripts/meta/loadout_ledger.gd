extends Node

## LoadoutLedger — 局外配件持仓 + 装配档案（AutoLoad）
##
## 持久化在 user://loadout.cfg：
##   [owned] parts = ["gun_dmg_t1", ...]
##   [equipped] f16 = ["gun_dmg_t1", "missile_track_t1", ...]
##                f14 = [...]
##
## 配件配置全部位于 res://resources/equipment/*.tres
## 由 SurvivorPlayableSetup.apply 在主角档案应用之后遍历装备列表，依次乘入 params。

signal owned_changed(part_id: StringName, now_owned: bool)
signal equipped_changed(aircraft_id: StringName)

const CONFIG_PATH := "user://loadout.cfg"
const SECTION_OWNED := "owned"
const SECTION_EQUIPPED := "equipped"
const SECTION_SHOP := "shop"
const DEFAULT_SLOT_BUDGET := 6
const EQUIPMENT_DIR := "res://resources/equipment"

## 货架配方：每次随机抽 3×T1 + 2×T2 + 1×T3，不足时退化成同 tier 全列。
const SHOP_TIER_QUOTA: Array[int] = [3, 2, 1]
## 付费刷新货架的功勋价（约 T1 价格的 60%——比直接买便宜，但也不是白送）
const SHOP_REFRESH_COST: int = 50

## 受 doctrine 解锁件管控的 in-run 升级 keyword。survivor_mode 在升级池筛选时
## 检查：升级若含这些 keyword，必须有对应解锁件已拥有。
## 注意：故意不门控 evasion_mode（规避模式相关技能不需要 doctrine 解锁）。
## 故意不门控 panic_save：因为 evasion_herbst 同时含 evasion_mode + panic_save，
## 门控 panic_save 会连带卡住 evasion_herbst，与"不锁规避模式"原则冲突。
const GATED_KEYWORDS: PackedStringArray = [
	&"fear",       # 恐惧系——skill_gun_kill_fear / fear_squad_spread / fear_chills / fear_on_lock 等
	&"overload",   # 超载系——cloud_overload / overload_duration_4x / 各 overload_* 等
	&"bloodlust",  # 嗜血系——skill_kill_bloodlust / bloodlust_armor_mobility / full_hp_kill_perma_hp 等
	&"chivalry",   # 骑士精神系——head_on_perma_hp / lowest_alt_kill_invul / head_on_gun_dodge 等
	&"jam",        # 干扰系——jam_aura / flare_aoe_jam / gun_kill_flare_drop / missile_hit_aoe_jam 等
	&"stealth",    # 隐身系——vapor_dodge / ecm_pod / evasion_stealth / alt_change_stealth / missile_cd_stealth
]

signal shop_changed

var _owned: Dictionary = {}                   ## StringName -> true
var _equipped: Dictionary = {}                ## StringName(aircraft_id) -> Array[StringName]
var _shop_ids: Array = []                     ## Array[StringName]：当前货架（持久化，玩家进游戏后清空）
var _catalog: Dictionary = {}                 ## StringName -> EquipmentPart（全配件总表，懒加载）
var _catalog_loaded: bool = false


func _ready() -> void:
	_load()


# ── 配件目录（懒加载，扫 res://resources/equipment/） ──

func _ensure_catalog_loaded() -> void:
	if _catalog_loaded:
		return
	_catalog_loaded = true
	var dir := DirAccess.open(EQUIPMENT_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			var path := "%s/%s" % [EQUIPMENT_DIR, fname]
			var part: EquipmentPart = load(path)
			if part != null and part.id != &"":
				_catalog[part.id] = part
		fname = dir.get_next()
	dir.list_dir_end()


func get_catalog() -> Array:
	_ensure_catalog_loaded()
	return _catalog.values()


func get_part(part_id: StringName) -> EquipmentPart:
	_ensure_catalog_loaded()
	return _catalog.get(part_id, null)


# ── 拥有 / 购买 ──

func is_owned(part_id: StringName) -> bool:
	return _owned.get(part_id, false) == true


## 购买配件：成功扣 Merit 并写入 owned，返回 true。
func buy_part(part_id: StringName) -> bool:
	if is_owned(part_id):
		return false
	var part := get_part(part_id)
	if part == null:
		return false
	if not MeritLedger.spend(part.merit_cost):
		return false
	_owned[part_id] = true
	_save()
	owned_changed.emit(part_id, true)
	EventLogger.log_event("LOADOUT", "Buy",
		"%s (cost=%d)" % [String(part_id), part.merit_cost])
	return true


## 调试：免费授予一个配件
func debug_grant(part_id: StringName) -> void:
	_owned[part_id] = true
	_save()
	owned_changed.emit(part_id, true)


# ── 装备槽位 ──

func get_slot_budget(aircraft_id: StringName, profile: PlayableAircraft = null) -> int:
	if profile != null and profile.slot_budget > 0:
		return profile.slot_budget
	return DEFAULT_SLOT_BUDGET


func get_equipped_ids(aircraft_id: StringName) -> Array:
	var arr = _equipped.get(aircraft_id, [])
	# 防御：清掉不再持有 / 不再存在于目录的 id
	var clean: Array = []
	for eid in arr:
		if is_owned(eid) and get_part(eid) != null:
			clean.append(eid)
	if clean.size() != arr.size():
		_equipped[aircraft_id] = clean
		_save()
	return clean


func get_equipped(aircraft_id: StringName) -> Array:
	var out: Array = []
	for eid in get_equipped_ids(aircraft_id):
		var p := get_part(eid)
		if p != null:
			out.append(p)
	return out


func get_used_slots(aircraft_id: StringName) -> int:
	var n: int = 0
	for p in get_equipped(aircraft_id):
		n += int(p.slot_cost)
	return n


## 尝试装备：必须已拥有 + 不重复装 + 槽位预算够。返回成功标志。
func try_equip(aircraft_id: StringName, part_id: StringName, profile: PlayableAircraft = null) -> bool:
	if not is_owned(part_id):
		return false
	var part := get_part(part_id)
	if part == null:
		return false
	var current: Array = get_equipped_ids(aircraft_id)
	if part_id in current:
		return false
	var budget: int = get_slot_budget(aircraft_id, profile)
	var used: int = get_used_slots(aircraft_id)
	if used + part.slot_cost > budget:
		return false
	current.append(part_id)
	_equipped[aircraft_id] = current
	_save()
	equipped_changed.emit(aircraft_id)
	return true


func unequip(aircraft_id: StringName, part_id: StringName) -> void:
	var current: Array = get_equipped_ids(aircraft_id)
	if part_id not in current:
		return
	current.erase(part_id)
	_equipped[aircraft_id] = current
	_save()
	equipped_changed.emit(aircraft_id)


# ── 解锁件（doctrine） ──

## 给定 keyword 是否已被某件已拥有的 doctrine/解锁件激活。
## 未在 GATED_KEYWORDS 中的 keyword 默认视为已激活（不受门控）。
func is_keyword_unlocked(kw: StringName) -> bool:
	if kw not in GATED_KEYWORDS:
		return true
	for pid in _owned.keys():
		var part: EquipmentPart = get_part(pid)
		if part != null and String(kw) in part.unlocks_keywords:
			return true
	return false


## 给定 in-run 升级（含 keywords 数组）是否被门控阻挡。
## 若它的 keywords 中任意一个属于 GATED_KEYWORDS 且对应解锁件未拥有，返回 true。
func is_upgrade_gated(upgrade: Dictionary) -> bool:
	var kws: Array = upgrade.get("keywords", [])
	for k in kws:
		var sn := StringName(k)
		if sn in GATED_KEYWORDS and not is_keyword_unlocked(sn):
			return true
	return false


## 拿到所有未拥有的解锁件（slot_cost=0 且 unlocks_keywords 非空），
## 用于在货架顶部固定显示（不参与随机）。已拥有的从此列表消失。
##
## 解锁顺序门控：
##   开局只摆 STARTER_DOCTRINES（嗜血 / 骑士）
##   两个 starter 都拥有后，剩下 4 个进阶 doctrine（恐惧 / 干扰 / 隐身 / 超载）才进货架
##   这是商店级别的渐进解锁，让玩家先体验入门流派再开桥接 / 高乘法链路
func get_unowned_doctrines() -> Array:
	_ensure_catalog_loaded()
	var starters_unlocked: bool = _all_starter_doctrines_owned()
	var out: Array = []
	for part in _catalog.values():
		var p: EquipmentPart = part
		if p.unlocks_keywords.is_empty():
			continue
		if is_owned(p.id):
			continue
		# 进阶 doctrine：starter 全部拥有后才显示
		if not starters_unlocked and p.id not in STARTER_DOCTRINES:
			continue
		out.append(p)
	out.sort_custom(func(a, b): return a.merit_cost < b.merit_cost)
	return out


## 入门 doctrine：开局即显示在货架。其余 doctrine 在这两个都买齐后才显示。
const STARTER_DOCTRINES: PackedStringArray = [
	&"doctrine_bloodlust",
	&"doctrine_chivalry",
]

func _all_starter_doctrines_owned() -> bool:
	for d in STARTER_DOCTRINES:
		if not is_owned(d):
			return false
	return true


# ── 货架（持久化，进游戏后清空） ──

## 取当前持久化货架。若空则按 SHOP_TIER_QUOTA 随机抽一批并保存（首次进入 / 进过游戏后再访问）。
func get_shop_ids() -> Array:
	if _shop_ids.is_empty():
		_roll_shop()
		_save()
	# 防御：清掉目录中已不存在的旧 id
	var clean: Array = []
	for sn in _shop_ids:
		if get_part(sn) != null:
			clean.append(sn)
	if clean.size() != _shop_ids.size():
		_shop_ids = clean
		_save()
	return _shop_ids


## 玩家付费刷新货架。Merit 不足返回 false。
func refresh_shop_paid() -> bool:
	if not MeritLedger.spend(SHOP_REFRESH_COST):
		return false
	_roll_shop()
	_save()
	shop_changed.emit()
	EventLogger.log_event("LOADOUT", "Refresh",
		"-%d merit, new stock: %s" % [SHOP_REFRESH_COST, str(_shop_ids)])
	return true


## 出击/进入游戏时调用：清空货架，下次进店重新抽。
func clear_shop() -> void:
	if _shop_ids.is_empty():
		return
	_shop_ids.clear()
	_save()
	shop_changed.emit()


## 内部：按 tier 配额随机抽货架，写入 _shop_ids（不保存，由调用方决定）。
## 解锁件（unlocks_keywords 非空）不参与随机——它们在货架顶部固定显示。
func _roll_shop() -> void:
	_ensure_catalog_loaded()
	var by_tier: Dictionary = {1: [], 2: [], 3: []}
	for part in _catalog.values():
		var p: EquipmentPart = part
		if not p.unlocks_keywords.is_empty():
			continue
		if p.tier in by_tier:
			by_tier[p.tier].append(p.id)
	_shop_ids.clear()
	for t in [1, 2, 3]:
		var pool: Array = by_tier[t].duplicate()
		pool.shuffle()
		var quota: int = SHOP_TIER_QUOTA[t - 1]
		for i in range(min(quota, pool.size())):
			_shop_ids.append(pool[i])


# ── 应用到飞机（由 SurvivorPlayableSetup 调用） ──

func apply_to_aircraft(aircraft: Node, profile: PlayableAircraft) -> void:
	if aircraft == null or profile == null:
		return
	var equipped: Array = get_equipped(profile.id)
	if equipped.is_empty():
		return
	for part in equipped:
		(part as EquipmentPart).apply_to(aircraft)
	EventLogger.log_event("LOADOUT", "Apply",
		"%s: %d parts (%d/%d slots)" % [
			String(profile.id), equipped.size(),
			get_used_slots(profile.id), get_slot_budget(profile.id, profile)])


# ── 持久化 ──

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	var raw_owned: Array = cfg.get_value(SECTION_OWNED, "parts", [])
	for v in raw_owned:
		_owned[StringName(v)] = true
	var keys: PackedStringArray = cfg.get_section_keys(SECTION_EQUIPPED) if cfg.has_section(SECTION_EQUIPPED) else PackedStringArray()
	for k in keys:
		var arr: Array = cfg.get_value(SECTION_EQUIPPED, k, [])
		var sn_arr: Array = []
		for v in arr:
			sn_arr.append(StringName(v))
		_equipped[StringName(k)] = sn_arr
	# 货架持久化：玩家退出 / 切换场景不刷货
	var raw_shop: Array = cfg.get_value(SECTION_SHOP, "ids", [])
	_shop_ids.clear()
	for v in raw_shop:
		_shop_ids.append(StringName(v))


func _save() -> void:
	var cfg := ConfigFile.new()
	var owned_arr: Array = []
	for k in _owned.keys():
		owned_arr.append(String(k))
	cfg.set_value(SECTION_OWNED, "parts", owned_arr)
	for ac_id in _equipped.keys():
		var arr: Array = _equipped[ac_id]
		var s_arr: Array = []
		for sn in arr:
			s_arr.append(String(sn))
		cfg.set_value(SECTION_EQUIPPED, String(ac_id), s_arr)
	var shop_str: Array = []
	for sn in _shop_ids:
		shop_str.append(String(sn))
	cfg.set_value(SECTION_SHOP, "ids", shop_str)
	cfg.save(CONFIG_PATH)


## 调试：完全清空持仓 + 装备 + 货架
func debug_reset() -> void:
	_owned.clear()
	_equipped.clear()
	_shop_ids.clear()
	_save()
