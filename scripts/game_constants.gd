class_name GameConstants
extends RefCounted

## 全局物理与世界常量（单一来源）
## 其他文件通过 GameConstants.PIXELS_PER_METER 等方式引用

# ── 物理 ──
const PIXELS_PER_METER: float = 0.5   ## 1 米 = 0.5 像素
const GRAVITY: float = 9.81           ## m/s²
const SPEED_OF_SOUND_KMH: float = 1225.0  ## km/h，用于马赫数计算

# ── 队伍主色（RGB，alpha 由调用处按需设置）──
const TEAM_COLOR_BLUE := Color(0.3, 0.6, 1.0)   ## team 0
const TEAM_COLOR_RED  := Color(1.0, 0.3, 0.2)    ## team 1

# ── 队伍尾迹色（飞机+导弹通用）──
const TEAM_TRAIL_BLUE := Color(0.3, 0.5, 1.0, 0.6)
const TEAM_TRAIL_RED  := Color(1.0, 0.25, 0.25, 0.6)

# ── 队伍雷达锥色（地面单位扇形/圆形填充）──
const TEAM_RADAR_BLUE := Color(0.2, 0.7, 0.8)   ## alpha 由调用处设置
const TEAM_RADAR_RED  := Color(0.8, 0.2, 0.2)

# ── 队伍数据链色（雷达站虚线圆）──
const TEAM_DATALINK_BLUE := Color(0.3, 0.6, 1.0, 0.15)
const TEAM_DATALINK_RED  := Color(1.0, 0.3, 0.3, 0.15)

# ── 导弹信息标签背景/文字色 ──
const MISSILE_LABEL_BG_BLUE   := Color(0.1, 0.2, 0.3, 0.75)
const MISSILE_LABEL_TEXT_BLUE  := Color(0.7, 0.85, 1.0)
const MISSILE_LABEL_BG_RED    := Color(0.3, 0.08, 0.08, 0.75)
const MISSILE_LABEL_TEXT_RED   := Color(1.0, 0.8, 0.8)

# ── 导弹弹体色 ──
const MISSILE_BODY_BLUE := Color(1.0, 0.5, 0.1)
const MISSILE_BODY_RED  := Color(1.0, 0.2, 0.2)

# ── 高射炮射程圈色（team 1 用橙色区别于 SAM 红色）──
const AA_RANGE_BLUE := Color(0.2, 0.7, 0.8)
const AA_RANGE_ORANGE := Color(0.8, 0.5, 0.1)

# ── 飞机信息标签色 ──
const AIRCRAFT_LABEL_BG_BLUE   := Color(0.1, 0.15, 0.35, 0.85)
const AIRCRAFT_LABEL_TEXT_BLUE  := Color(0.8, 0.9, 1.0)
const AIRCRAFT_LABEL_BG_RED    := Color(0.35, 0.08, 0.08, 0.85)
const AIRCRAFT_LABEL_TEXT_RED   := Color(1.0, 0.85, 0.85)

# ── 地面单位信息标签色 ──
const GROUND_LABEL_TEXT_BLUE := Color(0.5, 0.8, 1.0)
const GROUND_LABEL_BG_BLUE   := Color(0.0, 0.1, 0.2, 0.6)
const GROUND_LABEL_TEXT_RED  := Color(1.0, 0.6, 0.4)
const GROUND_LABEL_BG_RED    := Color(0.2, 0.05, 0.0, 0.6)

## 根据 team 索引返回队伍色（便捷方法）
static func team_color(team: int) -> Color:
	return TEAM_COLOR_BLUE if team == 0 else TEAM_COLOR_RED

static func team_trail_color(team: int) -> Color:
	return TEAM_TRAIL_BLUE if team == 0 else TEAM_TRAIL_RED

static func team_radar_color(team: int, alpha: float = 0.12) -> Color:
	var c := TEAM_RADAR_BLUE if team == 0 else TEAM_RADAR_RED
	return Color(c.r, c.g, c.b, alpha)

static func team_datalink_color(team: int) -> Color:
	return TEAM_DATALINK_BLUE if team == 0 else TEAM_DATALINK_RED

static func missile_label_colors(team: int) -> Array:
	## 返回 [bg_color, text_color]
	if team == 0:
		return [MISSILE_LABEL_BG_BLUE, MISSILE_LABEL_TEXT_BLUE]
	return [MISSILE_LABEL_BG_RED, MISSILE_LABEL_TEXT_RED]

static func missile_body_color(team: int) -> Color:
	return MISSILE_BODY_BLUE if team == 0 else MISSILE_BODY_RED

static func aa_range_color(team: int, alpha: float = 0.08) -> Color:
	var c := AA_RANGE_BLUE if team == 0 else AA_RANGE_ORANGE
	return Color(c.r, c.g, c.b, alpha)

static func ground_label_colors(team: int) -> Array:
	## 返回 [text_color, bg_color]
	if team == 0:
		return [GROUND_LABEL_TEXT_BLUE, GROUND_LABEL_BG_BLUE]
	return [GROUND_LABEL_TEXT_RED, GROUND_LABEL_BG_RED]

static func aircraft_label_colors(team: int) -> Array:
	## 返回 [bg_color, text_color]
	if team == 0:
		return [AIRCRAFT_LABEL_BG_BLUE, AIRCRAFT_LABEL_TEXT_BLUE]
	return [AIRCRAFT_LABEL_BG_RED, AIRCRAFT_LABEL_TEXT_RED]
