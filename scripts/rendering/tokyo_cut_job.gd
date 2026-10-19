extends RefCounted
## 后台只访问任务独占容器与只读来源快照；不得读取AutoLoad、SceneTree或GPU。
const Cut := preload("res://scripts/experiments/tokyo_spatial_cut.gd")
const MapProjection := preload("res://scripts/experiments/volume_projection.gd")


static func run(job: Dictionary) -> void:
	var solutions: Array[Dictionary]=[]
	for query: Dictionary in job.queries:
		var canvas := Transform2D(float(query.angle),Vector2.ZERO).scaled(Vector2.ONE*float(query.scale))
		canvas.origin=query.size*0.5-canvas*query.center
		var inverse := canvas.affine_inverse()
		var view := Rect2(inverse*Vector2.ZERO,Vector2.ZERO)
		for corner: Vector2 in [Vector2(query.size.x,0),query.size,Vector2(0,query.size.y)]: view=view.expand(inverse*corner)
		var ray := MapProjection.ground_basis(canvas,deg_to_rad(38)).inverse()*MapProjection.camera_basis(canvas,deg_to_rad(38)).z
		solutions.append(Cut.solve(job.roots,view,canvas,query.size,-Vector2(ray.x,ray.z)/ray.y,Vector2.ZERO,int(query.get("page_limit",16)),false))
	job.result={"generation":job.generation,"source_key":job.get("source_key",""),"queries":job.queries,"solutions":solutions,"submitted_usec":job.submitted_usec}
