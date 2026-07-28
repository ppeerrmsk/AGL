## 敌人图鉴注册表（spec career-archive §2.6 呈现层数据源）
##
## **加新敌人 = 本表加一行**（+ i18n 两个 key）。它是"玩家见过什么"的唯一展示清单，
## 数据全部来自 CareerArchive（击坠/击破/遭遇计数），本表只登记"有哪些敌人 + 怎么归类"。
##
## 解锁语义（与王牌档案统一）：**击败过才认识它**——计数 0 = 剪影 "???"，
## 计数 >0 = 名称 + 简介 + 战绩。王牌额外解锁 lore 全文与徽章。
##
## ⚠ 王牌专属机型（F-15/F-16/Mirage 2000/Su-47/Cre）不单列——它们只随所属王牌中队出现，
##   编成写在该中队条目的简介里。BOSS 机型（F-47/F-14）同理归 BOSS 条目。
class_name EnemyCodex

enum Kind { AIR, ADDS, GROUND, ACE, BOSS }

## 分组顺序 = 页面渲染顺序
const SECTIONS: Array = [
	{"kind": Kind.AIR, "title_key": "CODEX_SECTION_AIR"},
	{"kind": Kind.ADDS, "title_key": "CODEX_SECTION_ADDS"},
	{"kind": Kind.GROUND, "title_key": "CODEX_SECTION_GROUND"},
	{"kind": Kind.ACE, "title_key": "CODEX_SECTION_ACE"},
	{"kind": Kind.BOSS, "title_key": "CODEX_SECTION_BOSS"},
]

## 条目：id（AIR/ADDS = enemy_type tag；GROUND = 地面 tag；ACE = profile id；BOSS = boss_id）
## AIR 段按登场威胁递增排序（≈解锁等级序），玩家翻图鉴时能读出"敌情演进"
const ENTRIES: Array = [
	# ── 常规空中敌人（杂兵 → 精英）──
	{"id": "uav", "kind": Kind.AIR},
	{"id": "ucav", "kind": Kind.AIR},
	{"id": "f4e", "kind": Kind.AIR},
	{"id": "f86", "kind": Kind.AIR},
	{"id": "a7", "kind": Kind.AIR},
	{"id": "mig23", "kind": Kind.AIR},
	{"id": "interceptor", "kind": Kind.AIR},
	{"id": "q5", "kind": Kind.AIR},
	{"id": "f100", "kind": Kind.AIR},
	{"id": "f4", "kind": Kind.AIR},
	{"id": "mig", "kind": Kind.AIR},
	{"id": "f104", "kind": Kind.AIR},
	{"id": "su27", "kind": Kind.AIR},
	{"id": "su35", "kind": Kind.AIR},
	{"id": "mig31", "kind": Kind.AIR},
	{"id": "fa18", "kind": Kind.AIR},
	{"id": "uav_commander", "kind": Kind.AIR},
	{"id": "af03", "kind": Kind.AIR},
	{"id": "uav_laser", "kind": Kind.AIR},
	# ── Adds 杂兵（族群波次，不反击或只对地）──
	{"id": "tu160", "kind": Kind.ADDS},
	{"id": "ah64", "kind": Kind.ADDS},
	{"id": "ch47", "kind": Kind.ADDS},
	# ── 地面单位（战区 TGT）──
	{"id": "sam", "kind": Kind.GROUND},
	{"id": "aa", "kind": Kind.GROUND},
	{"id": "radar", "kind": Kind.GROUND},
	# ── 王牌中队（按登场时段序；名称/lore/主色/徽章走 AceSquadProfiles）──
	{"id": "2ndwave", "kind": Kind.ACE},
	{"id": "marathon", "kind": Kind.ACE},
	{"id": "gimmick", "kind": Kind.ACE},
	{"id": "goofighters", "kind": Kind.ACE},
	{"id": "orion", "kind": Kind.ACE},
	{"id": "vulture", "kind": Kind.ACE},
	# ── BOSS（击败即过关的王牌中队子集）──
	{"id": "WRAITH_SQUADRON", "kind": Kind.BOSS},
	{"id": "CARRIER_STRIKE_GROUP", "kind": Kind.BOSS},
	{"id": "MOTHER_GOOSE", "kind": Kind.BOSS},
]

## BOSS 主色（王牌 tier §2.7：BOSS 统一精英红，不占紫红系队色）
const BOSS_COLOR := Color(0.91, 0.208, 0.18)

static func entries_of(kind: int) -> Array:
	var out: Array = []
	for e in ENTRIES:
		if int(e["kind"]) == kind:
			out.append(e)
	return out

## 名称 i18n key（王牌走 profile 的 name_key，其余走 CODEX_<ID>_NAME）
static func name_key(entry: Dictionary) -> String:
	var id := String(entry["id"])
	if int(entry["kind"]) == Kind.ACE:
		return String(AceSquadProfiles.get_profile(id).get("name_key", ""))
	return "CODEX_%s_NAME" % id.to_upper()

## 简介 i18n key（王牌解锁后显示的是 lore 全文，其余是一行定位）
static func desc_key(entry: Dictionary) -> String:
	var id := String(entry["id"])
	if int(entry["kind"]) == Kind.ACE:
		return String(AceSquadProfiles.get_profile(id).get("lore_key", ""))
	return "CODEX_%s_DESC" % id.to_upper()

## 击败计数（AIR/ADDS = 击坠数 / GROUND = 摧毁数 / ACE = 全灭次数 / BOSS = 击败次数）
static func defeat_count(entry: Dictionary) -> int:
	var id := String(entry["id"])
	match int(entry["kind"]):
		Kind.GROUND:
			return CareerArchive.get_ground_kills_by_type(id)
		Kind.ACE:
			return CareerArchive.get_ace_defeats(id)
		Kind.BOSS:
			return CareerArchive.get_boss_defeats(id)
		_:
			return CareerArchive.get_air_kills(id)

## 遭遇计数（仅 ACE/BOSS 有意义——"打过照面但没赢"）；其余返回 0
static func encounter_count(entry: Dictionary) -> int:
	var id := String(entry["id"])
	match int(entry["kind"]):
		Kind.ACE:
			return CareerArchive.get_ace_encounters(id)
		Kind.BOSS:
			return CareerArchive.get_boss_encounters(id)
		_:
			return 0

## 条目配色：王牌用中队主色，BOSS 用精英红，常规敌人用威胁橙
static func color_of(entry: Dictionary) -> Color:
	match int(entry["kind"]):
		Kind.ACE:
			return AceSquadProfiles.color(String(entry["id"]))
		Kind.BOSS:
			return BOSS_COLOR
		_:
			return GameConstants.COL_ENEMY_REGULAR

## 徽章 id（仅王牌有线框徽章；其余返回 "" → UI 画通用图标）
static func emblem_of(entry: Dictionary) -> String:
	return String(entry["id"]) if int(entry["kind"]) == Kind.ACE else ""

## 图鉴完成度：已解锁条目数 / 总条目数
static func progress() -> Vector2i:
	var done := 0
	for e in ENTRIES:
		if defeat_count(e) > 0:
			done += 1
	return Vector2i(done, ENTRIES.size())
