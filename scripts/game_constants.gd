class_name GameConstants
extends RefCounted

## 全局物理与世界常量（单一来源）
## 其他文件通过 GameConstants.PIXELS_PER_METER 等方式引用

# ── 物理 ──
const PIXELS_PER_METER: float = 0.5   ## 1 米 = 0.5 像素
const GRAVITY: float = 9.81           ## m/s²
const SPEED_OF_SOUND_KMH: float = 1225.0  ## km/h，用于马赫数计算

# ── 渲染重构 feature flag（2026-05-26 加）──
# 详见 docs/planning/sprite-multimesh-refactor.md
# 默认 false 保持老 _draw 路径；阶段 3 验证通过后再考虑改为默认 true
const USE_SPRITE_AIRCRAFT_ICONS: bool = true   ## 飞机本体图标走 Sprite2D 而不是 _draw 自绘
const USE_MULTIMESH_BULLETS: bool = false      ## 机炮弹走 MultiMeshInstance2D 而不是 _draw 自绘
const SHOW_PERF_HUD: bool = false              ## F10 切换；默认 off 不占屏幕
## 飞机图标烘焙放大倍率（单一来源）：烘焙器按此放大几何，Sprite2D 按 1/此值缩回到 size=16
## bake_icons_runtime.gd 与 aircraft.gd._setup_sprite_icon 共用，避免两边 drift
const SPRITE_ICON_BAKE_SCALE: float = 3.5

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

# ── 单位状态栏标签 — 操控者 / 己方 / 敌方 三档统一配色 ──
# 全程禁纯白：所有"白"都掺一点蓝，避免设计上刺眼
# 玩家正在操控的飞机：冷白底 + 蓝边 + 深蓝字（视觉重心）
const UNIT_LABEL_BG_PLAYER     := Color(0.91, 0.94, 1.0, 0.92)
const UNIT_LABEL_TEXT_PLAYER   := Color(0.10, 0.25, 0.55, 1.0)
const UNIT_LABEL_BORDER_PLAYER := Color(0.30, 0.60, 1.0, 0.95)
# 己方非操控（队友 / 僚机 / 己方导弹 / Sentinel UAV）：蓝底 + 冷白边 + 冷白字
const UNIT_LABEL_BG_ALLY       := Color(0.10, 0.20, 0.45, 0.85)
const UNIT_LABEL_TEXT_ALLY     := Color(0.90, 0.95, 1.0, 1.0)
const UNIT_LABEL_BORDER_ALLY   := Color(0.85, 0.92, 1.0, 0.85)
# 敌方：红底 + 冷白边 + 冷白字（不用暖白，避免与红底融成粉色刺眼）
const UNIT_LABEL_BG_ENEMY      := Color(0.40, 0.10, 0.10, 0.88)
const UNIT_LABEL_TEXT_ENEMY    := Color(0.90, 0.95, 1.0, 1.0)
const UNIT_LABEL_BORDER_ENEMY  := Color(0.85, 0.92, 1.0, 0.85)

## 把高亮/buff 文字色调暗以便在浅色背景（玩家标签白底）下保持可读
## 直接用 darkened 会保留色相，让 BLOODLUST/STEALTH/JAM 等仍能区分
static func darken_for_light_bg(c: Color) -> Color:
	return Color(c.r * 0.42, c.g * 0.42, c.b * 0.42, c.a)

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

## 单位状态栏标签统一配色：返回 [bg, text, border]
## 三档：操控者（玩家）→ 白底蓝边；己方非操控 → 蓝底白边；敌方 → 红底白边
static func unit_label_style(team: int, is_player_controlled: bool) -> Array:
	if is_player_controlled:
		return [UNIT_LABEL_BG_PLAYER, UNIT_LABEL_TEXT_PLAYER, UNIT_LABEL_BORDER_PLAYER]
	if team == 0:
		return [UNIT_LABEL_BG_ALLY, UNIT_LABEL_TEXT_ALLY, UNIT_LABEL_BORDER_ALLY]
	return [UNIT_LABEL_BG_ENEMY, UNIT_LABEL_TEXT_ENEMY, UNIT_LABEL_BORDER_ENEMY]
