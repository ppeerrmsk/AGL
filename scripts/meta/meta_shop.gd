extends Node

## MetaShop — 生涯商店（AutoLoad；spec career-shop + doctrine-unlocks）
##
## 局外购买态账本：用功勋购买持久商品（起手机 / 停靠僚机 / 行动时长）
## + 6 张战术学说（doctrine 词条解锁件，决定 in-run 升级池里哪些牌可抽）。
## 解锁条件与上架条件**不落盘**——全部实时推导（CareerArchive / 已购集合即真源）；
## 本账本只存"已购集合"（生涯商品与学说共用同一集合，id 不冲突）。
##
## 铁律（沿 career-shop §3.3）：
##   - 不持有任何 Node 引用；主菜单删存档必须调 debug_reset()
##   - 门控在非正式局一律放行（is_upgrade_gated 对 boss debug 局 fail-open）
##   - 刻意不用 EquipmentPart/.tres：商品效果不在 AircraftParams 上（doctrine 的
##     消费点在升级池），常量表即全部真源（spec doctrine-unlocks §4）

signal owned_changed(item_id: String)

const SECTION := "shop"

const ITEM_MIRAGE3 := "mirage3_starter"
const ITEM_DOCK_WINGMAN := "dock_wingman"
const ITEM_OP_TIME := "op_time_30s"

## 行动时长商品的加成秒数（消费点：survivor_mode 开局注入）
const OP_TIME_BONUS_S := 30.0
## A-6E 起手解锁所需地面击杀数（spec career-shop §2.1）
const A6E_GROUND_KILLS_REQUIRED := 30

## 商品目录（spec career-shop §2.2；价格为草案，playtest 后校准）。
## locked_hint_key = "" 表示恒上架
const CATALOG: Dictionary = {
	ITEM_MIRAGE3: {
		"price": 2000,
		"name_key": "METASHOP_ITEM_MIRAGE3_NAME",
		"desc_key": "METASHOP_ITEM_MIRAGE3_DESC",
		"locked_hint_key": "",
	},
	ITEM_DOCK_WINGMAN: {
		"price": 3000,
		"name_key": "METASHOP_ITEM_DOCK_WINGMAN_NAME",
		"desc_key": "METASHOP_ITEM_DOCK_WINGMAN_DESC",
		"locked_hint_key": "METASHOP_LOCKED_HINT_DOCK_WINGMAN",
	},
	ITEM_OP_TIME: {
		"price": 2500,
		"name_key": "METASHOP_ITEM_OP_TIME_NAME",
		"desc_key": "METASHOP_ITEM_OP_TIME_DESC",
		"locked_hint_key": "METASHOP_LOCKED_HINT_OP_TIME",
	},
}

## ── 战术学说（doctrine 词条解锁件；spec doctrine-unlocks §2）──
## 唯一有效字段是 keyword：拥有该学说 → 对应 keyword 的 in-run 升级进随机池。
## 永久拥有制（无装备/卸载概念）。定价公式 price = 100 × 门控技能数 + 300。
const DOCTRINES: Dictionary = {
	"doctrine_chivalry": {
		"price": 800, "keyword": "chivalry",   ## 100×5+300（headon_xp 补标 chivalry 后 4→5 张）
		"name_key": "EQUIPMENT_DOCTRINE_CHIVALRY_NAME",
		"desc_key": "EQUIPMENT_DOCTRINE_CHIVALRY_DESC",
		"flavor_key": "EQUIPMENT_DOCTRINE_CHIVALRY_FLAVOR",
		"kw_key": "LOADOUT_KEYWORD_CHIVALRY",
		"color": Color(0.95, 0.85, 0.5, 1.0),
	},
	"doctrine_bloodlust": {
		"price": 1000, "keyword": "bloodlust",
		"name_key": "EQUIPMENT_DOCTRINE_BLOODLUST_NAME",
		"desc_key": "EQUIPMENT_DOCTRINE_BLOODLUST_DESC",
		"flavor_key": "EQUIPMENT_DOCTRINE_BLOODLUST_FLAVOR",
		"kw_key": "LOADOUT_KEYWORD_BLOODLUST",
		"color": Color(1.0, 0.30, 0.30, 1.0),
	},
	"doctrine_fear": {
		"price": 1000, "keyword": "fear",
		"name_key": "EQUIPMENT_DOCTRINE_FEAR_NAME",
		"desc_key": "EQUIPMENT_DOCTRINE_FEAR_DESC",
		"flavor_key": "EQUIPMENT_DOCTRINE_FEAR_FLAVOR",
		"kw_key": "LOADOUT_KEYWORD_FEAR",
		"color": Color(0.75, 0.45, 1.0, 1.0),
	},
	"doctrine_overload": {
		"price": 1100, "keyword": "overload",
		"name_key": "EQUIPMENT_DOCTRINE_OVERLOAD_NAME",
		"desc_key": "EQUIPMENT_DOCTRINE_OVERLOAD_DESC",
		"flavor_key": "EQUIPMENT_DOCTRINE_OVERLOAD_FLAVOR",
		"kw_key": "LOADOUT_KEYWORD_OVERLOAD",
		"color": Color(1.0, 0.6, 0.2, 1.0),
	},
	"doctrine_jam": {
		"price": 1200, "keyword": "jam",
		"name_key": "EQUIPMENT_DOCTRINE_JAM_NAME",
		"desc_key": "EQUIPMENT_DOCTRINE_JAM_DESC",
		"flavor_key": "EQUIPMENT_DOCTRINE_JAM_FLAVOR",
		"kw_key": "LOADOUT_KEYWORD_JAM",
		"color": Color(0.4, 0.85, 1.0, 1.0),
	},
	"doctrine_stealth": {
		"price": 1400, "keyword": "stealth",
		"name_key": "EQUIPMENT_DOCTRINE_STEALTH_NAME",
		"desc_key": "EQUIPMENT_DOCTRINE_STEALTH_DESC",
		"flavor_key": "EQUIPMENT_DOCTRINE_STEALTH_FLAVOR",
		"kw_key": "LOADOUT_KEYWORD_STEALTH",
		"color": Color(0.6, 0.65, 0.7, 1.0),
	},
}

## 入门学说：开局即上架；其余 4 张在两张都买齐后才上架（spec §3.2）
const STARTER_DOCTRINES: Array = ["doctrine_bloodlust", "doctrine_chivalry"]

## 受 doctrine 门控的 in-run 升级 keyword（spec doctrine-unlocks §2.3 权威表）。
## 注意：故意不门控 evasion_mode / panic_save（evasion_herbst 同时含两词，
## 门控 panic_save 会连带卡住规避模式技能，违反"不锁规避模式"原则）。
const GATED_KEYWORDS: PackedStringArray = [
	"fear", "overload", "bloodlust", "chivalry", "jam", "stealth",
]

## 存档路径（var 而非 const：无头单测注入临时路径，不碰真存档）
var config_path := "user://meta_shop.cfg"
## 老配件系统 legacy 存档（var：单测注入；spec §3.4 一次性迁移后删除）
var legacy_loadout_path := "user://loadout.cfg"

var _owned: Dictionary = {}

func _ready() -> void:
	reload_from_disk()
	migrate_legacy_loadout()

# ── 纯静态判定（spec §3.1；无头单测覆盖）──

## 起手机解锁判定。未列入门控表的机型默认不锁（向后兼容新增起手机）
static func aircraft_unlock_ok(aircraft_id: String, csg_defeats: int,
		ground_kills: int, mirage_owned: bool) -> bool:
	match aircraft_id:
		"f15": return true
		"f14": return csg_defeats >= 1
		"a6e": return ground_kills >= A6E_GROUND_KILLS_REQUIRED
		"mirage3": return mirage_owned
		_: return true

## 商品上架判定
static func item_listed_ok(item_id: String, airfield_dockings: int, retreats: int) -> bool:
	match item_id:
		ITEM_MIRAGE3: return true
		ITEM_DOCK_WINGMAN: return airfield_dockings >= 1
		ITEM_OP_TIME: return retreats >= 1
		_: return false

## 学说上架纯判定（spec doctrine-unlocks §3.2）：入门两张恒上架，
## 进阶四张在两张入门都拥有后才上架
static func doctrine_listed_ok(doctrine_id: String, starters_owned: bool) -> bool:
	if not DOCTRINES.has(doctrine_id):
		return false
	if doctrine_id in STARTER_DOCTRINES:
		return true
	return starters_owned

# ── 实例 API（读 CareerArchive 真档案）──

func is_aircraft_unlocked(aircraft_id: String) -> bool:
	return aircraft_unlock_ok(aircraft_id,
		CareerArchive.get_boss_defeats("CARRIER_STRIKE_GROUP"),
		CareerArchive.get_ground_kills(),
		is_owned(ITEM_MIRAGE3))

func is_listed(item_id: String) -> bool:
	if DOCTRINES.has(item_id):
		return doctrine_listed_ok(item_id, all_starter_doctrines_owned())
	return item_listed_ok(item_id,
		CareerArchive.get_dockings("airfield"),
		CareerArchive.get_retreats())

func is_owned(item_id: String) -> bool:
	return _owned.has(item_id)

func get_price(item_id: String) -> int:
	if DOCTRINES.has(item_id):
		return int((DOCTRINES[item_id] as Dictionary).get("price", 0))
	return int((CATALOG.get(item_id, {}) as Dictionary).get("price", 0))

## 购买：未知商品/已拥有/未上架/功勋不足 → false；成功扣费落盘发信号
func buy(item_id: String) -> bool:
	var known: bool = CATALOG.has(item_id) or DOCTRINES.has(item_id)
	if not known or is_owned(item_id) or not is_listed(item_id):
		return false
	if not MeritLedger.spend(get_price(item_id)):
		return false
	_owned[item_id] = true
	_save()
	EventLogger.log_event("METASHOP", "Buy", "%s -%d" % [item_id, get_price(item_id)])
	owned_changed.emit(item_id)
	return true

# ── 学说门控（spec doctrine-unlocks §3.1；消费点=升级三选一/三轴卡池/战区 NEXT_GEN 池）──

func all_starter_doctrines_owned() -> bool:
	for did in STARTER_DOCTRINES:
		if not is_owned(String(did)):
			return false
	return true

## 给定 keyword 是否已被某张已购学说解锁。
## 未在 GATED_KEYWORDS 中的 keyword 默认放行（不受门控）。
func is_keyword_unlocked(kw: String) -> bool:
	if kw not in GATED_KEYWORDS:
		return true
	for did in DOCTRINES:
		if String((DOCTRINES[did] as Dictionary).get("keyword", "")) == kw and is_owned(String(did)):
			return true
	return false

## 给定 in-run 升级（含 keywords 数组）是否被门控阻挡。
## AND 语义：keywords 中任一词属于 GATED_KEYWORDS 且对应学说未购 → true。
## 豁免：sig_* 机体签名技（已被"驾驶该机型"门控一层，spec §0 D3）。
## fail-open：boss debug 局不受局外存档门控（非正式局铁律）。
func is_upgrade_gated(upgrade: Dictionary) -> bool:
	if String(upgrade.get("id", "")).begins_with("sig_"):
		return false
	if is_inside_tree() and get_tree().has_meta("boss_debug_mode"):
		return false
	for k in upgrade.get("keywords", []):
		var kw := String(k)
		if kw in GATED_KEYWORDS and not is_keyword_unlocked(kw):
			return true
	return false

## 调试/测试：免费授予（不扣功勋、不查上架）
func debug_grant(item_id: String) -> void:
	if _owned.has(item_id):
		return
	_owned[item_id] = true
	_save()
	owned_changed.emit(item_id)

# ── 老配件系统迁移（spec doctrine-unlocks §3.4；一次性，幂等标志=legacy 文件存在）──

## 把 user://loadout.cfg 的 [owned] parts 里的 doctrine_* 搬进本账本，
## 数值配件直接丢弃（D2 用户拍板：不退款）。迁移完成后删除 legacy 文件。
func migrate_legacy_loadout() -> void:
	if not FileAccess.file_exists(legacy_loadout_path):
		return
	var cfg := ConfigFile.new()
	var moved: int = 0
	if cfg.load(legacy_loadout_path) == OK:
		var parts: Array = cfg.get_value("owned", "parts", [])
		for pid in parts:
			var s := String(pid)
			if DOCTRINES.has(s) and not _owned.has(s):
				_owned[s] = true
				moved += 1
		if moved > 0:
			_save()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(legacy_loadout_path))
	EventLogger.log_event("METASHOP", "MigrateLoadout",
		"moved %d doctrines, legacy cfg removed" % moved)

# ── 持久化 ──

func reload_from_disk() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(config_path) != OK:
		return
	var v: Variant = cfg.get_value(SECTION, "owned", {})
	_owned = v if v is Dictionary else {}

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "owned", _owned)
	cfg.save(config_path)

## 调试/主菜单删存档：清内存 + 重写空档案
func debug_reset() -> void:
	_owned = {}
	_save()
