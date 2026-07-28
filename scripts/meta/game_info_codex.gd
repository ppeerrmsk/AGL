## 游戏信息手册注册表（spec career-archive §2.7 资料库「游戏信息」分类）
##
## 玩家能查的**全部机制说明**：鼠标/键位每个操作干什么、加力模式怎么用、
## 飞行与武器的门道、战区循环怎么走。资料库里与「敌人图鉴」并列的第二个分类。
##
## ★ 单一数据源约定：战术地图（Tab）轮播的 `TACTICAL_TIP_*` 小技巧**不复制文本**，
##   条目声明 `tip` 字段即直接复用那条译文 —— 改一处两边同步，不会出现
##   "手册说 A、Tab 说 B" 的分裂。新增小技巧同理：加进 tactical_map._TIP_KEYS
##   的同时在本表挂一条，玩家就能在资料库里回看。
##
## 加新条目：本表加一行 + i18n 补 `INFO_<ID>_TITLE`（tip 条目只需标题；
## 非 tip 条目还要 `INFO_<ID>_BODY`）。bench 有断言守译文齐全。
class_name GameInfoCodex

## 分组（顺序 = 页面渲染顺序：先手上的操作，再飞机本身，最后一局怎么打）
const SECTIONS: Array = [
	{"id": "mouse", "title_key": "INFO_SECTION_MOUSE"},
	{"id": "keys", "title_key": "INFO_SECTION_KEYS"},
	{"id": "squad", "title_key": "INFO_SECTION_SQUAD"},
	{"id": "flight", "title_key": "INFO_SECTION_FLIGHT"},
	{"id": "weapon", "title_key": "INFO_SECTION_WEAPON"},
	{"id": "run", "title_key": "INFO_SECTION_RUN"},
	{"id": "intel", "title_key": "INFO_SECTION_INTEL"},
]

## 条目：id → i18n 键前缀；`key` = 该条对应的按键/操作标签（无则不显示徽标）；
## `tip` = 复用的战术地图小技巧 key（有则正文取它，不再单独写 BODY）
const ENTRIES: Array = [
	# ── 鼠标操作 ──
	{"id": "lmb_move", "sec": "mouse", "key": "LMB"},
	{"id": "lmb_target", "sec": "mouse", "key": "LMB"},
	{"id": "lmb_double", "sec": "mouse", "key": "LMB ×2"},
	{"id": "lmb_wheel", "sec": "mouse", "key": "LMB ↓"},
	{"id": "rmb_cancel", "sec": "mouse", "key": "RMB"},
	{"id": "rmb_brake", "sec": "mouse", "key": "RMB ↓"},
	{"id": "camera", "sec": "mouse", "key": "MMB / WASD"},
	# ── 键盘 ──
	{"id": "key_num", "sec": "keys", "key": "1-9"},
	{"id": "key_e", "sec": "keys", "key": "E"},
	{"id": "key_r", "sec": "keys", "key": "R"},
	{"id": "key_f", "sec": "keys", "key": "F"},
	{"id": "key_q", "sec": "keys", "key": "Q"},
	{"id": "key_t", "sec": "keys", "key": "T"},
	{"id": "key_c", "sec": "keys", "key": "C"},
	{"id": "key_v", "sec": "keys", "key": "V"},
	{"id": "key_tab", "sec": "keys", "key": "Tab"},
	{"id": "key_space", "sec": "keys", "key": "Space"},
	{"id": "key_esc", "sec": "keys", "key": "ESC"},
	# ── 小队指挥 ──
	{"id": "squad_grammar", "sec": "squad"},
	{"id": "squad_wheel", "sec": "squad"},
	{"id": "squad_attack", "sec": "squad"},
	{"id": "squad_iron", "sec": "squad"},
	{"id": "squad_switch", "sec": "squad"},
	# ── 飞行与机动 ──
	{"id": "flight_corner", "sec": "flight", "tip": "TACTICAL_TIP_CORNER_SPEED"},
	{"id": "flight_turn", "sec": "flight", "tip": "TACTICAL_TIP_TURN_RADIUS"},
	{"id": "flight_tier", "sec": "flight"},
	{"id": "flight_alt_high", "sec": "flight", "tip": "TACTICAL_TIP_ALT_HIGH"},
	{"id": "flight_alt_low", "sec": "flight", "tip": "TACTICAL_TIP_ALT_LOW"},
	{"id": "flight_cloud", "sec": "flight", "tip": "TACTICAL_TIP_ALT_CLOUDS"},
	{"id": "flight_stall", "sec": "flight"},
	# ── 武器与交战 ──
	{"id": "weapon_oneshot", "sec": "weapon"},
	{"id": "weapon_lock", "sec": "weapon"},
	{"id": "weapon_range", "sec": "weapon", "tip": "TACTICAL_TIP_MISSILE_RANGE"},
	{"id": "weapon_sweet", "sec": "weapon", "tip": "TACTICAL_TIP_MISSILE_SWEET_SPOT"},
	{"id": "weapon_crank", "sec": "weapon", "tip": "TACTICAL_TIP_CRANK"},
	{"id": "weapon_flare", "sec": "weapon", "tip": "TACTICAL_TIP_FLARE"},
	{"id": "weapon_gun", "sec": "weapon"},
	{"id": "weapon_reload", "sec": "weapon", "tip": "TACTICAL_TIP_RELOAD"},
	{"id": "weapon_swap", "sec": "weapon", "tip": "TACTICAL_TIP_WEAPON_SWAP"},
	# ── 一局怎么打 ──
	{"id": "run_loop", "sec": "run"},
	{"id": "run_boundary", "sec": "run", "tip": "TACTICAL_TIP_BOUNDARY"},
	{"id": "run_time", "sec": "run", "tip": "TACTICAL_TIP_DIFFICULTY"},
	{"id": "run_dock", "sec": "run"},
	{"id": "run_upgrade", "sec": "run"},
	{"id": "run_evolve", "sec": "run"},
	# ── 战场情报 ──
	{"id": "intel_ace", "sec": "intel"},
	{"id": "intel_boss", "sec": "intel"},
	{"id": "intel_sentinel", "sec": "intel", "tip": "TACTICAL_TIP_SENTINEL"},
]

static func entries_of(sec_id: String) -> Array:
	var out: Array = []
	for e in ENTRIES:
		if String(e.get("sec", "")) == sec_id:
			out.append(e)
	return out

static func title_key(entry: Dictionary) -> String:
	return "INFO_%s_TITLE" % String(entry["id"]).to_upper()

## 正文 key：tip 条目复用战术地图小技巧（单一数据源），其余走自己的 BODY
static func body_key(entry: Dictionary) -> String:
	var tip := String(entry.get("tip", ""))
	return tip if tip != "" else "INFO_%s_BODY" % String(entry["id"]).to_upper()

## 该条是否来自战术地图小技巧（UI 用它打「情报」角标，让玩家认出这是 Tab 里见过的那条）
static func is_tip(entry: Dictionary) -> bool:
	return String(entry.get("tip", "")) != ""

static func key_label(entry: Dictionary) -> String:
	return String(entry.get("key", ""))
