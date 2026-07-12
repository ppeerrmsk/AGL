class_name GameConstants
extends RefCounted

## 全局物理与世界常量（单一来源）
## 其他文件通过 GameConstants.PIXELS_PER_METER 等方式引用

# ── 物理 ──
const PIXELS_PER_METER: float = 0.5   ## 1 米 = 0.5 像素
const GRAVITY: float = 9.81           ## m/s²
const SPEED_OF_SOUND_KMH: float = 1225.0  ## km/h，用于马赫数计算

# ══════════════════════════════════════════════════════════════
#  阵营色板 FactionPalette（spec global-awareness-roe §2.7，单一源）
#  规则：冷色（蓝/青/绿）只属于友好单位（玩家小队=亮青 / 第三方与中立=海绿）；
#  敌方一律暖色，内部用"橙 → 红"表达威胁层级（常规 → 精英/BOSS）。
#  任何 HUD / kill feed / 雷达锥 / 尾迹 / 小地图 / 新增单位配色一律引用本表，
#  禁止再散写颜色字面量。team 语义：0=PLAYER 1=HOSTILE 2=ALLY（CombatUnit.TEAM_*）。
# ══════════════════════════════════════════════════════════════
const COL_FRIEND_PLAYER := Color(0.243, 0.878, 0.784)   ## #3EE0C8 玩家小队 亮青
const COL_FRIEND_ALLY   := Color(0.247, 0.663, 0.557)   ## #3FA98E 第三方/中立 海绿
const COL_ENEMY_REGULAR := Color(1.0, 0.541, 0.239)     ## #FF8A3D 敌常规（机体色域基准）
const COL_ENEMY_ELITE   := Color(0.910, 0.208, 0.180)   ## #E8352E 敌精英/BOSS

# ── 队伍主色（强调色；RGB，alpha 由调用处按需设置）──
const TEAM_COLOR_PLAYER := COL_FRIEND_PLAYER
const TEAM_COLOR_ALLY   := COL_FRIEND_ALLY
const TEAM_COLOR_RED    := Color(1.0, 0.3, 0.2)    ## HOSTILE（既有暖红，本就合规）

# ── 队伍尾迹色（飞机+导弹通用）──
const TEAM_TRAIL_PLAYER := Color(0.24, 0.82, 0.72, 0.6)
const TEAM_TRAIL_ALLY   := Color(0.25, 0.62, 0.52, 0.6)
const TEAM_TRAIL_RED    := Color(1.0, 0.25, 0.25, 0.6)

# ── 队伍雷达锥色（地面单位扇形/圆形填充）──
const TEAM_RADAR_PLAYER := Color(0.2, 0.78, 0.70)   ## alpha 由调用处设置
const TEAM_RADAR_ALLY   := Color(0.24, 0.62, 0.52)
const TEAM_RADAR_RED    := Color(0.8, 0.2, 0.2)

# ── 队伍数据链色（雷达站虚线圆）──
const TEAM_DATALINK_PLAYER := Color(0.24, 0.85, 0.75, 0.15)
const TEAM_DATALINK_ALLY   := Color(0.25, 0.65, 0.55, 0.15)
const TEAM_DATALINK_RED    := Color(1.0, 0.3, 0.3, 0.15)

# ── 导弹信息标签背景/文字色 ──
const MISSILE_LABEL_BG_FRIEND   := Color(0.05, 0.22, 0.19, 0.75)
const MISSILE_LABEL_TEXT_FRIEND := Color(0.72, 1.0, 0.93)
const MISSILE_LABEL_BG_RED      := Color(0.3, 0.08, 0.08, 0.75)
const MISSILE_LABEL_TEXT_RED    := Color(1.0, 0.8, 0.8)

# ── 导弹弹体色（弹药非阵营单位：友方通用橙、敌红，维持既有轨迹可读性）──
const MISSILE_BODY_FRIEND := Color(1.0, 0.5, 0.1)
const MISSILE_BODY_RED    := Color(1.0, 0.2, 0.2)

# ── 高射炮射程圈色（敌方用橙色区别于 SAM 红色）──
const AA_RANGE_PLAYER := Color(0.2, 0.78, 0.70)
const AA_RANGE_ALLY   := Color(0.24, 0.62, 0.52)
const AA_RANGE_ORANGE := Color(0.8, 0.5, 0.1)

# ── 飞机信息标签色 ──
const AIRCRAFT_LABEL_BG_PLAYER   := Color(0.05, 0.20, 0.18, 0.85)
const AIRCRAFT_LABEL_TEXT_PLAYER := Color(0.80, 1.0, 0.95)
const AIRCRAFT_LABEL_BG_ALLY     := Color(0.04, 0.16, 0.13, 0.85)
const AIRCRAFT_LABEL_TEXT_ALLY   := Color(0.72, 0.93, 0.85)
const AIRCRAFT_LABEL_BG_RED      := Color(0.35, 0.08, 0.08, 0.85)
const AIRCRAFT_LABEL_TEXT_RED    := Color(1.0, 0.85, 0.85)
## 当前操控机的白底（避免纯白刺眼，spec squad-control-switching §2.2）
const PLAYER_CTRL_LABEL_BG := Color(0.91, 0.94, 1.0, 0.90)
## 白底上的深色基础文字
const PLAYER_CTRL_LABEL_TEXT := Color(0.08, 0.10, 0.18, 1.0)

# ── 地面单位信息标签色 ──
const GROUND_LABEL_TEXT_FRIEND := Color(0.55, 0.95, 0.85)
const GROUND_LABEL_BG_FRIEND   := Color(0.0, 0.14, 0.11, 0.6)
const GROUND_LABEL_TEXT_RED    := Color(1.0, 0.6, 0.4)
const GROUND_LABEL_BG_RED      := Color(0.2, 0.05, 0.0, 0.6)

## 阵营强调色统一入口（team：0=玩家小队 亮青 / 2=第三方 海绿 / 其它=敌 暖红）
static func team_color(team: int) -> Color:
	if team == 0:
		return TEAM_COLOR_PLAYER
	if team == 2:
		return TEAM_COLOR_ALLY
	return TEAM_COLOR_RED

static func team_trail_color(team: int) -> Color:
	if team == 0:
		return TEAM_TRAIL_PLAYER
	if team == 2:
		return TEAM_TRAIL_ALLY
	return TEAM_TRAIL_RED

static func team_radar_color(team: int, alpha: float = 0.12) -> Color:
	var c := TEAM_RADAR_RED
	if team == 0:
		c = TEAM_RADAR_PLAYER
	elif team == 2:
		c = TEAM_RADAR_ALLY
	return Color(c.r, c.g, c.b, alpha)

static func team_datalink_color(team: int) -> Color:
	if team == 0:
		return TEAM_DATALINK_PLAYER
	if team == 2:
		return TEAM_DATALINK_ALLY
	return TEAM_DATALINK_RED

static func missile_label_colors(team: int) -> Array:
	## 返回 [bg_color, text_color]（友好阵营 0/2 共用一套）
	if team != 1:
		return [MISSILE_LABEL_BG_FRIEND, MISSILE_LABEL_TEXT_FRIEND]
	return [MISSILE_LABEL_BG_RED, MISSILE_LABEL_TEXT_RED]

static func missile_body_color(team: int) -> Color:
	return MISSILE_BODY_FRIEND if team != 1 else MISSILE_BODY_RED

static func aa_range_color(team: int, alpha: float = 0.08) -> Color:
	var c := AA_RANGE_ORANGE
	if team == 0:
		c = AA_RANGE_PLAYER
	elif team == 2:
		c = AA_RANGE_ALLY
	return Color(c.r, c.g, c.b, alpha)

static func ground_label_colors(team: int) -> Array:
	## 返回 [text_color, bg_color]（友好阵营 0/2 共用一套）
	if team != 1:
		return [GROUND_LABEL_TEXT_FRIEND, GROUND_LABEL_BG_FRIEND]
	return [GROUND_LABEL_TEXT_RED, GROUND_LABEL_BG_RED]

static func aircraft_label_colors(team: int) -> Array:
	## 返回 [bg_color, text_color]
	if team == 0:
		return [AIRCRAFT_LABEL_BG_PLAYER, AIRCRAFT_LABEL_TEXT_PLAYER]
	if team == 2:
		return [AIRCRAFT_LABEL_BG_ALLY, AIRCRAFT_LABEL_TEXT_ALLY]
	return [AIRCRAFT_LABEL_BG_RED, AIRCRAFT_LABEL_TEXT_RED]

## 把高亮/浅色文字压暗到能在白底上读清，同时保留色相（buff/状态/武器/高度等彩色行用）。
## 仅当文字绘制在玩家白底标签上时调用；非玩家（蓝/红底）走原色不变。
static func darken_for_light_bg(c: Color) -> Color:
	return Color(c.r * 0.42, c.g * 0.42, c.b * 0.42, 1.0)
