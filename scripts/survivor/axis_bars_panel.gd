class_name AxisBarsPanel
extends Control

## 三轴量表控件（spec evolution-attribute-gates §3.2 视觉版，2026-07-19 用户 mockup）：
## 每轴一根分格立柱（10 格 = 点数上限），加点从底部逐格点亮（轴色）；
## 里程碑档位（2/4/6/8/10）在柱右侧画刻度圈——达成=实心亮圈、下一档=大空圈、未达=小空圈；
## 柱顶数字 = 当前点数，柱底 = 轴色圆标 + 轴名。
## 纯静态绘制：只在 show_state() 时 queue_redraw（性能守则 1：无每帧重绘）。
## 用法：var p := AxisBarsPanel.new(); p.show_state(sp.axis_points, profile)

const MAX_PTS: int = 10
const CELL_W: float = 24.0
const CELL_H: float = 10.0
const CELL_GAP: float = 2.5
const COL_GAP: float = 44.0
const TOP_PAD: float = 18.0     ## 柱顶数字空间
const BOTTOM_PAD: float = 34.0  ## 轴标空间

var _axis_points: Dictionary = {}
var _profile: PlayableAircraft = null


func _init() -> void:
	var w: float = 3.0 * CELL_W + 2.0 * COL_GAP + 24.0
	var h: float = TOP_PAD + MAX_PTS * (CELL_H + CELL_GAP) + BOTTOM_PAD
	custom_minimum_size = Vector2(w, h)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## 刷新数据并重绘。profile = 起手机里程碑覆写表来源（可空走基准表）。
func show_state(axis_points: Dictionary, profile: PlayableAircraft = null) -> void:
	_axis_points = axis_points
	_profile = profile
	queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	var base_y: float = TOP_PAD + MAX_PTS * (CELL_H + CELL_GAP)
	for i in SurvivorData.AXES.size():
		var axis: StringName = SurvivorData.AXES[i]
		var col: Color = SurvivorData.AXIS_COLORS.get(axis, Color.WHITE)
		var dim := Color(col.r, col.g, col.b, 0.28)
		var x: float = 6.0 + float(i) * (CELL_W + COL_GAP)
		var pts: int = int(_axis_points.get(axis, 0))

		# ── 分格立柱（自底向上）──
		for c in MAX_PTS:
			var y: float = base_y - float(c + 1) * (CELL_H + CELL_GAP)
			var r := Rect2(x, y, CELL_W, CELL_H)
			draw_rect(r, dim, false, 1.0)
			if c < pts:
				draw_rect(r.grow(-1.5), Color(col.r, col.g, col.b, 0.92), true)

		# ── 里程碑刻度圈（柱右侧，档位高度）──
		var next_found := false
		for m in SurvivorData.milestones_for(axis, _profile):
			var tier: int = int(m["points"])
			if tier > MAX_PTS:
				continue
			var ty: float = base_y - float(tier) * (CELL_H + CELL_GAP) + CELL_H * 0.5
			var cx := Vector2(x + CELL_W + 9.0, ty)
			if pts >= tier:
				draw_circle(cx, 4.0, col)                                   # 达成：实心亮圈
				draw_arc(cx, 6.0, 0.0, TAU, 20, Color(col.r, col.g, col.b, 0.5), 1.0)
			elif not next_found:
				next_found = true
				draw_arc(cx, 5.0, 0.0, TAU, 20, col, 1.6)                   # 下一档：大空圈
			else:
				draw_arc(cx, 3.0, 0.0, TAU, 16, dim, 1.0)                   # 远档：小空圈

		# ── 柱顶点数 ──
		draw_string(font, Vector2(x, TOP_PAD - 6.0), str(pts),
			HORIZONTAL_ALIGNMENT_CENTER, CELL_W, 12, col)
		# ── 柱底轴标（圆 + 名）──
		var icon_c := Vector2(x + CELL_W * 0.5, base_y + 11.0)
		draw_circle(icon_c, 6.0, col if pts > 0 else dim)
		draw_string(font, Vector2(x - COL_GAP * 0.45, base_y + 30.0),
			tr(str(SurvivorData.AXIS_I18N_KEY.get(axis, ""))),
			HORIZONTAL_ALIGNMENT_CENTER, CELL_W + COL_GAP * 0.9, 11,
			Color(col.r, col.g, col.b, 0.9 if pts > 0 else 0.5))
