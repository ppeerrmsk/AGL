extends RefCounted
## 只认可完成来源闭包/唯一归属/精确布局的边界版本；不接受任意扩框。
const SOURCE_SHA := "262568505c9cbbc10b22921a7751be9de7013c00eff65e0fd52b89b096401860"
const REGISTRY_SHA := "5650ac9519642c95e09272802b1e1bea58d4ddf4b445fc98bcea1d80a04fcfad"
const LAYOUT_SHA := "47105f717856f5137d32d5d82e1d1e6596b63df8ce87e538f3a1c141888e2b20"
const HIERARCHY_SHA := "b4d49b55e7f89a1a9e3bfd9788fd4f0b21e07fd3a28962ffaf6a3a6842ddec63"
const LEGACY := Rect2(-16300,-15700,32000,32000)
const EXPANDED := Rect2(-16300,-16300,32600,32600)


static func bounds(source_sha: String = "") -> Rect2:
	if source_sha==SOURCE_SHA: return EXPANDED
	return LEGACY if source_sha.is_empty() else Rect2()


static func page_bounds(depth: int, id_value: int, source_sha: String = "") -> Array:
	if depth<0 or depth>2 or not bounds(source_sha).has_area(): return []
	var count:=4<<depth
	if id_value<0 or id_value>=count*count: return []
	var x:=id_value%count
	var y:=id_value/count
	var span:=32000.0/count
	var low:=LEGACY.position+Vector2(x,y)*span
	var high:=low+Vector2.ONE*span
	if source_sha==SOURCE_SHA:
		if y==0: low.y=EXPANDED.position.y
		if x==count-1: high.x=EXPANDED.end.x
	return [low.x,low.y,high.x,high.y]


static func full_grid(value: Dictionary) -> bool:
	return value.get("layout_sha256")==LAYOUT_SHA and value.get("hierarchy_sha256")==HIERARCHY_SHA \
		and value.get("regional_registry_sha256")==REGISTRY_SHA and value.get("source_count")==3018595 \
		and value.get("bounds")==EXPANDED


static func checks() -> bool:
	if bounds()!=LEGACY or bounds(SOURCE_SHA)!=EXPANDED or bounds("bad").has_area(): return false
	for depth in 3:
		var count:=4<<depth
		var area:=0.0
		for id_value in count*count:
			var old:=page_bounds(depth,id_value)
			var current:=page_bounds(depth,id_value,SOURCE_SHA)
			if current.size()!=4: return false
			var box:=Rect2(current[0],current[1],current[2]-current[0],current[3]-current[1])
			if not EXPANDED.encloses(box): return false
			if id_value/count>0 and id_value%count<count-1 and current!=old: return false
			area+=box.get_area()
		if area!=EXPANDED.get_area(): return false
	return page_bounds(-1,0).is_empty() and page_bounds(2,256).is_empty() and page_bounds(0,0,"bad").is_empty()
