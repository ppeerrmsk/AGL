## 王牌中队线框徽章（spec ace-squadron-tier §2.7 包装五件套之"徽章"）
##
## 极简线框美术：每队一个几何图形，概念权威在各队 spec 的包装节。
## 用途：交战血条代号旁（survivor_hud）+ 王牌档案页（ace_archive_ui）。
## 性能：静态内容——只在 set_emblem 变化时 queue_redraw 一次，绝不逐帧重画。
class_name AceEmblemIcon
extends Control

var emblem_id := ""
var emblem_color := Color(1.0, 0.4, 0.4)
var radius := 14.0:
	set(v):
		radius = v
		custom_minimum_size = Vector2(v, v) * 2.2
		queue_redraw()

func _init(id: String = "", col: Color = Color(1.0, 0.4, 0.4), r: float = 14.0) -> void:
	emblem_id = id
	emblem_color = col
	radius = r

## 换队 / 换色时调用；内容没变就不重画
func set_emblem(id: String, col: Color) -> void:
	if id == emblem_id and col.is_equal_approx(emblem_color):
		return
	emblem_id = id
	emblem_color = col
	queue_redraw()

func _draw() -> void:
	var c := size * 0.5
	var r := radius
	var col := emblem_color
	var w := maxf(1.5, r * 0.12)   # 线宽随尺寸
	match emblem_id:
		"marathon":
			# 不闭合的跑道环 + 缺口处终点线竖杠（"终点线永远画在猎物坠机的地方"）
			draw_arc(c, r * 0.85, 0.5, TAU, 28, col, w)
			var gap_a := 0.25   # 缺口中心角
			var p := c + Vector2(cos(gap_a), sin(gap_a)) * r * 0.85
			var perp := Vector2(cos(gap_a), sin(gap_a))
			draw_line(p - perp * r * 0.28, p + perp * r * 0.28, col, w)
		"2ndwave":
			# 双叠浪：后浪高过前浪
			_draw_wave(c + Vector2(0, r * 0.35), r * 0.9, r * 0.25, col, w)
			_draw_wave(c - Vector2(0, r * 0.25), r * 0.9, r * 0.45, col, w)
		"orion":
			# 猎户座：腰带三星连线 + 肩足四点（外围点淡一档）
			var belt_dir := Vector2(1.0, 0.32).normalized()
			for i in range(3):
				var bp := c + belt_dir * r * 0.55 * float(i - 1)
				draw_circle(bp, r * 0.11, col)
			draw_line(c - belt_dir * r * 0.75, c + belt_dir * r * 0.75, col, w * 0.7)
			var dim := Color(col.r, col.g, col.b, col.a * 0.55)
			for corner in [Vector2(-0.75, -0.8), Vector2(0.7, -0.85), Vector2(-0.7, 0.85), Vector2(0.75, 0.8)]:
				draw_circle(c + corner * r, r * 0.09, dim)
		"gimmick":
			# 调包双箭头 ⇄：上箭头向右、下箭头向左
			var y1 := c.y - r * 0.35
			var y2 := c.y + r * 0.35
			draw_line(Vector2(c.x - r * 0.8, y1), Vector2(c.x + r * 0.8, y1), col, w)
			draw_line(Vector2(c.x + r * 0.8, y1), Vector2(c.x + r * 0.45, y1 - r * 0.3), col, w)
			draw_line(Vector2(c.x + r * 0.8, y1), Vector2(c.x + r * 0.45, y1 + r * 0.3), col, w)
			draw_line(Vector2(c.x + r * 0.8, y2), Vector2(c.x - r * 0.8, y2), col, w)
			draw_line(Vector2(c.x - r * 0.8, y2), Vector2(c.x - r * 0.45, y2 - r * 0.3), col, w)
			draw_line(Vector2(c.x - r * 0.8, y2), Vector2(c.x - r * 0.45, y2 + r * 0.3), col, w)
		"goofighters":
			# 两簇并飞的鬼火：一大一小空心圆 + 芯点
			var big := c + Vector2(-r * 0.35, r * 0.2)
			var small := c + Vector2(r * 0.45, -r * 0.35)
			draw_arc(big, r * 0.45, 0.0, TAU, 20, col, w)
			draw_circle(big, r * 0.1, col)
			draw_arc(small, r * 0.28, 0.0, TAU, 16, col, w)
			draw_circle(small, r * 0.07, col)
		"vulture":
			# 俯冲展翼 V（三线）+ 翼下一点（猎物永远在下方）
			var apex := c + Vector2(0, r * 0.3)
			draw_line(c + Vector2(-r * 0.9, -r * 0.4), apex, col, w)
			draw_line(c + Vector2(r * 0.9, -r * 0.4), apex, col, w)
			draw_line(apex, c + Vector2(0, -r * 0.15), col, w)
			draw_circle(c + Vector2(0, r * 0.75), r * 0.1, col)
		"whitetea":
			# 三片茶叶围绕中心，叶脉末端折成 J 形，呼应三机编队与 J-turn。
			draw_circle(c, r * 0.09, col)
			for i in range(3):
				var a := -PI * 0.5 + TAU * float(i) / 3.0
				var outward := Vector2(cos(a), sin(a))
				var sideways := Vector2(-outward.y, outward.x)
				var root := c + outward * r * 0.12
				var tip := c + outward * r * 0.86
				var shoulder := c + outward * r * 0.52
				draw_line(root, tip, col, w * 0.75)
				draw_polyline(PackedVector2Array([
					tip,
					shoulder + sideways * r * 0.30,
					root,
					shoulder - sideways * r * 0.30,
					tip,
				]), col, w)
				var hook_center := tip - outward * r * 0.08 + sideways * r * 0.10
				draw_arc(hook_center, r * 0.16, a - PI * 0.15, a + PI * 0.85, 8, col, w)
		_:
			draw_arc(c, r * 0.7, 0.0, TAU, 24, col, w)

## 单段折线波浪（2NDWAVE 用）
func _draw_wave(center: Vector2, half_w: float, amp: float, col: Color, w: float) -> void:
	var pts := PackedVector2Array()
	var n := 12
	for i in range(n + 1):
		var t := float(i) / float(n)
		var x := lerpf(-half_w, half_w, t)
		pts.append(center + Vector2(x, -sin(t * PI * 2.0) * amp * 0.5 - amp * 0.3 * sin(t * PI)))
	draw_polyline(pts, col, w)
