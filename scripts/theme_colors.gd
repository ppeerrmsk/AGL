class_name ThemeColors
extends RefCounted

## 生存模式 UI 统一调色板
## 所有生存 UI 界面共享的颜色常量

# ── 场景背景 / 网格 ──
const SCENE_BG := Color(0.02, 0.03, 0.02)
const GRID_COLOR := Color(0.15, 0.2, 0.15, 0.3)
const GRID_LINE := Color(0.3, 0.7, 0.3, 0.5)

# ── 面板背景 ──
## 主界面语义色；与 docs/specs/systems/ui-design-guidelines.md 颜色表对齐。
const UI_BLOCK_BACKGROUND := Color(0.0, 0.0, 0.0, 0.7)
const UI_TERMINAL_WHITE := Color("e8f2e8")
const UI_TERMINAL_GREEN := Color("00ff41")
const UI_TERMINAL_INVERSE := Color("000000")
const UI_INACTIVE_DIGIT := Color("404040")
const UI_WARNING_YELLOW := Color("f2d34f")
const UI_DANGER_RED := Color("ff493d")
const UI_WRAITH_BLUE := Color("36a7ff")
const UI_WRAITH_ICE := Color("9edcff")
const UI_WRAITH_DEEP_BLUE := Color("315dff")
const UI_WRAITH_INVERSE := Color("010611")
const UI_WRAITH_BACKGROUND := Color(0.005, 0.018, 0.055, 0.9)
const PANEL_BG := Color(0.02, 0.04, 0.02, 0.75)
const PANEL_BG_SOLID := Color(0.02, 0.04, 0.02, 0.95)
const PANEL_BG_TOOLTIP := Color(0.03, 0.05, 0.03, 0.9)
const PANEL_BG_GAMEOVER := Color(0.02, 0.03, 0.02, 0.92)
const PANEL_BG_OVERLAY := Color(0.0, 0.0, 0.0, 0.6)   ## 升级选择遮罩
const PANEL_BG_DEBUG := Color(0.0, 0.0, 0.0, 0.7)

# ── 面板边框 ──
const PANEL_BORDER := Color(0.25, 0.5, 0.25, 0.35)
const PANEL_BORDER_ACCENT := Color(0.3, 0.6, 0.3, 0.4)
const PANEL_BORDER_TOOLTIP := Color(0.4, 0.6, 0.3, 0.5)
const PANEL_BORDER_GAMEOVER := Color(1.0, 0.3, 0.3, 0.6)
const PANEL_BORDER_DEBUG := Color(0.3, 0.8, 0.3, 0.6)

# ── 卡片（选择界面通用）──
const CARD_LOCKED_BG := Color(0.03, 0.04, 0.03, 0.6)
const CARD_LOCKED_BORDER := Color(0.2, 0.3, 0.2, 0.3)
const CARD_UNLOCKED_BG := Color(0.04, 0.07, 0.04, 0.8)
const CARD_UNLOCKED_BORDER := Color(0.3, 0.6, 0.3, 0.4)
const CARD_SEPARATOR_UNLOCKED := Color(0.3, 0.6, 0.3, 0.3)
const CARD_SEPARATOR_LOCKED := Color(0.2, 0.3, 0.2, 0.3)

# ── 战术/HUD 按钮 ──
const BTN_NORMAL_BG := Color(0.06, 0.1, 0.06)
const BTN_NORMAL_BORDER := Color(0.3, 0.6, 0.3, 0.5)
const BTN_HOVER_BG := Color(0.1, 0.18, 0.1)
const BTN_HOVER_BORDER := Color(1.0, 0.8, 0.3, 0.6)
const BTN_PRESSED_BG := Color(0.15, 0.25, 0.15)
const BTN_PRESSED_BORDER := Color(1.0, 0.9, 0.4, 0.7)
const BTN_TEXT := Color(0.7, 0.9, 0.7)
const BTN_HOVER_TEXT := Color(1.0, 0.9, 0.5)
const BTN_PRESSED_TEXT := Color(1.0, 1.0, 0.6)

# ── 选择界面按钮（绿色调，与战术按钮区分）──
const SELECT_BTN_NORMAL_BG := Color(0.08, 0.15, 0.08, 0.9)
const SELECT_BTN_NORMAL_BORDER := Color(0.4, 0.8, 0.4, 0.5)
const SELECT_BTN_HOVER_BG := Color(0.12, 0.25, 0.12, 0.95)
const SELECT_BTN_HOVER_BORDER := Color(0.5, 1.0, 0.5, 0.8)
const SELECT_BTN_PRESSED_BG := Color(0.18, 0.35, 0.18, 1.0)
const SELECT_BTN_PRESSED_BORDER := Color(0.6, 1.0, 0.6, 1.0)
const SELECT_BTN_DISABLED_BG := Color(0.05, 0.06, 0.05, 0.5)
const SELECT_BTN_DISABLED_BORDER := Color(0.2, 0.25, 0.2, 0.4)
const SELECT_BTN_DISABLED_TEXT := Color(0.3, 0.4, 0.3, 0.5)

# ── 文字色 ──
const TEXT_PRIMARY := Color(0.85, 0.95, 0.85)
const TEXT_PRIMARY_ALT := Color(0.8, 0.9, 0.8)     ## 略暗版本
const TEXT_ACCENT := Color(1.0, 0.8, 0.3)           ## 金色标题
const TEXT_TITLE_GREEN := Color(0.4, 1.0, 0.4)      ## 大标题绿
const TEXT_SUBTITLE := Color(0.3, 0.6, 0.3, 0.6)
const TEXT_MUTED := Color(0.6, 0.7, 0.6, 0.7)
const TEXT_LOCKED := Color(0.4, 0.45, 0.4, 0.6)
const TEXT_LOCKED_INDEX := Color(0.3, 0.35, 0.3, 0.5)
const TEXT_UNLOCKED_INDEX := Color(0.4, 0.6, 0.4, 0.5)
const TEXT_TAG_UNLOCKED := Color(0.5, 0.9, 0.5, 0.7)
const TEXT_DESC_UNLOCKED := Color(0.6, 0.7, 0.6, 0.8)
const TEXT_STATS := Color(0.5, 0.65, 0.5, 0.6)
const TEXT_CODENAME := Color(0.5, 0.75, 0.5, 0.7)
const TEXT_WHITE := Color(1.0, 1.0, 1.0)
const TEXT_DEBUG := Color(0.0, 1.0, 0.4)

# ── XP 条 ──
const XP_BAR_BG := Color(0.1, 0.1, 0.1, 0.7)
const XP_BAR_FILL := Color(1.0, 0.8, 0.3)

# ── 编队面板 ──
const SQUAD_PANEL_BG := Color(0.02, 0.04, 0.02, 0.78)
const SQUAD_PANEL_BORDER := Color(0.35, 0.55, 0.75, 0.45)
const SQUAD_TITLE := Color(0.5, 0.75, 1.0)
const SQUAD_SEPARATOR := Color(0.3, 0.5, 0.7, 0.35)

# ── BOSS 面板 ──
const BOSS_PANEL_BG := Color(0.08, 0.02, 0.02, 0.82)
const BOSS_PANEL_BORDER := Color(0.85, 0.25, 0.2, 0.5)
const BOSS_TITLE := Color(1.0, 0.35, 0.3)

# ── HP 警告色 ──
const HP_LOW := Color("ff4444")
const HP_MID := Color("ffcc44")
const HP_OK := Color("44ff44")

# ── 技能分类色（survivor_hud 战术按钮 + upgrade_ui）──
const CATEGORY_WEAPON := Color("ffcc44")
const CATEGORY_DEFENSE := Color("55aa66")
const CATEGORY_MOBILITY := Color("4488dd")
const CATEGORY_SYSTEM := Color("cc6655")

# ── 小雷达 ──
const RADAR_BG := Color(0.02, 0.06, 0.02, 0.8)
const RADAR_RING := Color(0.15, 0.35, 0.15, 0.5)
const RADAR_SWEEP := Color(0.2, 0.8, 0.2, 0.5)
const RADAR_PLAYER := Color(0.3, 0.7, 1.0, 0.9)
const RADAR_ENEMY := Color(1.0, 0.3, 0.2, 0.85)
const RADAR_LOCKED := Color(1.0, 0.8, 0.2, 0.95)
const RADAR_MISSILE := Color(1.0, 0.15, 0.1, 0.95)
const RADAR_BORDER := Color(0.2, 0.5, 0.2, 0.6)

# ── 威胁指示 ──
const THREAT_ARROW := Color(1.0, 0.3, 0.2, 0.8)
const LOCK_WARNING := Color(1.0, 0.15, 0.1, 0.95)

# ── 地图缩略图（survivor_map_select 专用）──
const THUMB_LOCKED_BG := Color(0.06, 0.08, 0.06, 0.6)
const THUMB_LOCKED_BORDER := Color(0.2, 0.3, 0.2, 0.4)
const THUMB_UNLOCKED_BG := Color(0.10, 0.18, 0.13, 0.8)
const THUMB_UNLOCKED_BORDER := Color(0.35, 0.7, 0.4, 0.5)
const THUMB_LOCKED_TEXT := Color(0.3, 0.4, 0.3, 0.5)
const THUMB_UNLOCKED_TEXT := Color(0.5, 0.8, 0.5, 0.5)
