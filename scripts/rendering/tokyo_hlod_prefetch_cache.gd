extends RefCounted
## 只缓存投机I/O计划，绝不作为显示切面或跨帧可见性凭据。
const Handoff := preload("res://scripts/rendering/tokyo_hlod_handoff.gd")
const MAX_AGE_USEC := 150000


static func reusable(cache: Dictionary, catalog: Dictionary, index: int, center: Vector2, scale: float, angle: float, size: Vector2, zooming_out: bool, now: int) -> bool:
	if cache.is_empty() or index<0 or cache.get("index",-1)!=index or cache.get("identity",{})!=catalog.get("identity",{}) \
		or cache.get("zooming_out")!=zooming_out or now<int(cache.get("created",0)) or now-int(cache.get("created",0))>MAX_AGE_USEC \
		or not center.is_finite() or not size.is_finite() or size.x<=0 or size.y<=0 or not is_finite(angle) \
		or not Handoff.qualified(catalog,cache.get("cut",{}),scale): return false
	var canvas := Transform2D(angle,Vector2.ZERO).scaled(Vector2.ONE*scale)
	canvas.origin=size*0.5-canvas*center
	var inverse := canvas.affine_inverse()
	var view := Rect2(inverse*Vector2.ZERO,Vector2.ZERO)
	for point: Vector2 in [Vector2(size.x,0),size,Vector2(0,size.y)]: view=view.expand(inverse*point)
	return Handoff.covers_view(catalog,cache.cut,view.intersection(catalog.bounds))


static func checks() -> bool:
	var catalog := {"identity":{"path":"fixture","sha256":"a".repeat(64)},"max_scale":1.0,
		"bounds":Rect2(-10000,-10000,20000,20000),"rows":{"0:0":{"bounds":[-1000,-1000,1000,1000],"max_scale":0.8}}}
	var cache := {"index":4,"identity":catalog.identity,"created":100,"zooming_out":false,"cut":{"keys":PackedStringArray(["0:0"])}}
	if not reusable(cache,catalog,4,Vector2.ZERO,0.8,0,Vector2(800,600),false,1000): return false
	return not reusable(cache,catalog,4,Vector2.ZERO,0.8,0,Vector2(800,600),false,150101) \
		and not reusable(cache,catalog,4,Vector2.ZERO,0.8,0,Vector2(800,600),false,99) \
		and not reusable(cache,catalog,4,Vector2.ZERO,0.8,0,Vector2(800,600),true,1000) \
		and not reusable(cache,catalog,5,Vector2.ZERO,0.8,0,Vector2(800,600),false,1000) \
		and not reusable(cache,catalog,4,Vector2(4000,0),0.8,0,Vector2(800,600),false,1000) \
		and not reusable(cache,catalog,4,Vector2.ZERO,0.9,0,Vector2(800,600),false,1000) \
		and not reusable(cache,catalog,4,Vector2.ZERO,NAN,0,Vector2(800,600),false,1000)
