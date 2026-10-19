extends RefCounted
## 精确矩形覆盖；瓦片间任何正面积缝隙都拒绝接替，不用面积和或总包络。


static func covered(bounds: Rect2, tiles: Array[Rect2]) -> bool:
	if not bounds.position.is_finite() or not bounds.size.is_finite() or not bounds.has_area() or bounds.size.x<=0 or bounds.size.y<=0:
		return false
	var pending: Array[Rect2] = [bounds]
	for tile: Rect2 in tiles:
		if not tile.position.is_finite() or not tile.size.is_finite() or tile.size.x<=0 or tile.size.y<=0:
			return false
		var remaining: Array[Rect2] = []
		for part: Rect2 in pending:
			var hit := part.intersection(tile)
			if not hit.has_area():
				remaining.append(part)
				continue
			for rest: Rect2 in [Rect2(part.position,Vector2(part.size.x,hit.position.y-part.position.y)),
				Rect2(Vector2(part.position.x,hit.end.y),Vector2(part.size.x,part.end.y-hit.end.y)),
				Rect2(Vector2(part.position.x,hit.position.y),Vector2(hit.position.x-part.position.x,hit.size.y)),
				Rect2(Vector2(hit.end.x,hit.position.y),Vector2(part.end.x-hit.end.x,hit.size.y))]:
				if rest.has_area():
					remaining.append(rest)
		pending = remaining
	return pending.is_empty()


static func flat_covered(bounds: AABB, tiles: Array[Rect2]) -> bool:
	return bounds.position.is_finite() and bounds.size.is_finite() and bounds.size.y>=0 and bounds.position.y>=-1.0 and bounds.end.y<=1.0 \
		and covered(Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z)),tiles)


static func visible_flat_covered(bounds: AABB, tiles: Array[Rect2], view: Rect2, roof: Vector2) -> bool:
	if not bounds.position.is_finite() or not bounds.size.is_finite() or not bounds.end.is_finite() \
			or bounds.size.x<=0 or bounds.size.y<0 or bounds.size.z<=0 or bounds.position.y< -1 or bounds.end.y>1 \
			or not view.position.is_finite() or not view.size.is_finite() or not view.end.is_finite() or view.size.x<=0 or view.size.y<=0 or not roof.is_finite():
		return false
	# p+h*roof在视野内，则p在view-h*roof内；合并上下界保守覆盖全部地表高度。
	var visible := Rect2(view.position-roof*bounds.position.y,view.size).merge(Rect2(view.position-roof*bounds.end.y,view.size))
	visible=visible.intersection(Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z)))
	return covered(visible,tiles)
