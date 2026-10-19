extends RefCounted
## 地面装备制作源：共享网格、固定尺寸、只读外观。车身与可动设备分批提交。
const Factory := preload("res://scripts/experiments/volume_mesh_factory.gd")
const ARMOR := Color(0.56, 0.62, 0.66)
const EDGE := Color(0.80, 0.86, 0.88)
const DARK := Color(0.10, 0.13, 0.16)
const DECK_HEIGHT := 24.0
const TRAIN_DECK_HEIGHT := 16.0
static var _cache: Dictionary = {}


static func keys() -> Array[String]:
	var result: Array[String] = ["artillery", "aa", "flak", "sam", "radar", "siege_tank",
		"land_carrier", "gun_turret", "aa_turret", "flak_turret", "sam_launcher",
		"radar_head", "railgun_turret", "vls_mount", "train_bogie",
		"super_cannon", "super_cannon_turret", "bunker", "warehouse", "missile_silo"]
	for i in 14:
		result.append("train_%d" % i)
	return result


static func key_for(unit: GroundUnit) -> String:
	if unit is Tier3SuperCannonPart:
		return "super_cannon"
	if unit is StrategicTarget:
		return ["bunker", "warehouse", "missile_silo"][unit.target_kind]
	if unit is ArmoredTrainSegment:
		return "train_%d" % clampi(unit.segment_index, 0, 13)
	if unit is LandCarrierUnit:
		return "land_carrier"
	if unit is Tier3SiegeTank:
		return "siege_tank"
	if unit is AtmosphereArtilleryUnit:
		return "artillery"
	if unit is RadarStation:
		return "radar"
	if unit is SAMUnit:
		return "sam"
	if unit is AirburstAAUnit:
		return "flak"
	if unit is AAGunUnit:
		return "aa"
	return ""


static func build(key: String, detailed: bool = true) -> ArrayMesh:
	var cache_key := key + ("_full" if detailed else "_simple")
	if _cache.has(cache_key):
		return _cache[cache_key]
	if key not in keys():
		return null
	var b := Factory.new()
	if key in ["super_cannon", "super_cannon_turret", "bunker", "warehouse", "missile_silo"]:
		_strategic(b, key, detailed)
	elif key == "land_carrier":
		_carrier(b, detailed)
	elif key == "train_bogie":
		b.box(Vector3(0, 4, 0), Vector3(84, 8, 20), DARK)
		for x in [-44.0, 44.0]:
			b.box(Vector3(x, 4, 0), Vector3(4, 8, 18), ARMOR)
	elif key.begins_with("train_"):
		_train(b, key.trim_prefix("train_").to_int(), detailed)
	elif key in ["gun_turret", "aa_turret", "flak_turret", "railgun_turret"]:
		_turret(b, key, detailed)
	elif key == "sam_launcher":
		_cylinder(b, Vector3(0, 0.7, 0), 4.0, 1.4, DARK)
		for x in [-3.4, -1.1, 1.1, 3.4]:
			# 架体与底盘连接；四个箱式发射管保持相同支架，不制造悬空弹体。
			b.box(Vector3(x, 3, 0), Vector3(1.8, 3, 16), ARMOR)
			b.box(Vector3(x, 3, -8.1), Vector3(1.5, 2.5, .3), DARK)
		b.box(Vector3(0, 1.5, 0), Vector3(9, 2, 6), EDGE)
	elif key == "vls_mount":
		b.box(Vector3(0, 2, 0), Vector3(16, 4, 24), ARMOR)
		_cells(b, Vector3(0, 4.2, 0), Vector2(5, 5), 2, 4, 1.0)
	elif key == "radar_head":
		b.box(Vector3(0, 2, 0), Vector3(1.2, 4, 1.2), EDGE)
		# 斜面阵列有背架厚度，正反面都可读，不是一张无厚度贴片。
		b.prism(PackedVector2Array([Vector2(-7, -2), Vector2(7, -2),
			Vector2(6, 1.5), Vector2(-6, 1.5)]), 3, 9, ARMOR)
		b.box(Vector3(0, 6, -2.1), Vector3(12, 4.5, .4), DARK)
		if detailed:
			for x in [-4.5, -1.5, 1.5, 4.5]:
				b.box(Vector3(x, 6, -2.4), Vector3(.3, 4.2, .2), EDGE)
	else:
		var size := Vector2(18, 24) if key in ["sam", "radar"] else Vector2(14, 16)
		if key == "siege_tank":
			size = Vector2(70, 48)
		_chassis(b, size, detailed)
		if key == "flak":
			for x in [-4.0, 4.0]:
				b.box(Vector3(x, 6.5, 5), Vector3(4, 3, 4), EDGE.darkened(.25))
		if key == "radar":
			b.box(Vector3(0, 6, 5), Vector3(12, 6, 8), ARMOR)
			b.box(Vector3(0, 10, -3), Vector3(2, 12, 2), EDGE)
		elif key == "sam":
			b.box(Vector3(0, 5, -8), Vector3(12, 5, 6), ARMOR)
			b.box(Vector3(0, 6, -11.1), Vector3(9, 2, .3), DARK)
	var mesh := b.mesh()
	_cache[cache_key] = mesh
	return mesh


static func _cylinder(b: RefCounted, center: Vector3, radius: float, height: float, color: Color) -> void:
	var polygon := PackedVector2Array()
	for i in 8:
		var angle := TAU * float(i) / 8.0
		polygon.append(Vector2(center.x, center.z) + Vector2(cos(angle), sin(angle)) * radius)
	b.prism(polygon, center.y - height * .5, center.y + height * .5, color)


static func _strategic(b: RefCounted, key: String, detailed: bool) -> void:
	# 与原目标占地一致；炮架单独提交，固定基座不跟随瞄准方向旋转。
	match key:
		"super_cannon":
			_cylinder(b, Vector3(0, 3, 0), 42, 6, DARK)
			_cylinder(b, Vector3(0, 7, 0), 32, 8, ARMOR)
			if detailed:
				for x in [-28.0, 28.0]:
					b.box(Vector3(x, 6, 0), Vector3(7, 8, 42), EDGE)
		"super_cannon_turret":
			_cylinder(b, Vector3(0, 4, 0), 20, 8, DARK)
			for x in [-18.5, 18.5]:
				b.box(Vector3(x, 9, -14.5), Vector3(11, 18, 45), ARMOR)
				b.box(Vector3(x, 7, 25), Vector3(5, 14, 34), EDGE)
			for x in [-8.0, 8.0]:
				b.box(Vector3(x, 12, -58), Vector3(3, 7, 80), EDGE)
			b.box(Vector3(0, 12, -106), Vector3(10, 8, 20), ARMOR)
			b.box(Vector3(0, 12, -116.1), Vector3(6, 4, .3), DARK)
			b.box(Vector3(0, 7, 40), Vector3(42, 6, 4), EDGE)
			if detailed:
				for z in range(-92, -27, 13):
					b.box(Vector3(0, 12, z), Vector3(16, 3, 3), ARMOR)
		"bunker":
			b.prism(PackedVector2Array([Vector2(-24, 12), Vector2(-18, -10),
				Vector2(-8, -18), Vector2(8, -18), Vector2(18, -10), Vector2(24, 12)]), 0, 10, ARMOR)
			b.box(Vector3(0, 5, 12.2), Vector3(10, 9, .5), DARK)
			if detailed:
				b.box(Vector3(0, 11, -2), Vector3(27, 2, 18), EDGE)
		"warehouse":
			b.box(Vector3(0, 7, 0), Vector3(68, 14, 40), ARMOR)
			b.quad(Vector3(-34, 14, -20), Vector3(-34, 21, 0), Vector3(34, 21, 0), Vector3(34, 14, -20), DARK)
			b.quad(Vector3(-34, 21, 0), Vector3(-34, 14, 20), Vector3(34, 14, 20), Vector3(34, 21, 0), ARMOR)
			b.triangle(Vector3(-34, 14, 20), Vector3(-34, 21, 0), Vector3(-34, 14, -20), ARMOR)
			b.triangle(Vector3(34, 14, -20), Vector3(34, 21, 0), Vector3(34, 14, 20), ARMOR)
			b.box(Vector3(0, 6, 20.2), Vector3(20, 12, .5), DARK)
			if detailed:
				for x in [-26.0, -13.0, 13.0, 26.0]:
					b.box(Vector3(x, 10, -20.2), Vector3(8, 4, .5), EDGE)
		"missile_silo":
			_cylinder(b, Vector3(0, 2, 0), 24, 4, DARK)
			_cylinder(b, Vector3(0, 4, 0), 20, 4, ARMOR)
			b.box(Vector3(0, 6.2, 0), Vector3(.8, .4, 38), DARK)
			if detailed:
				for x in [-19.0, 19.0]:
					b.box(Vector3(x, 6, 0), Vector3(3, 4, 10), EDGE)


static func _chassis(b: RefCounted, size: Vector2, detailed: bool) -> void:
	var half := size * .5
	b.prism(PackedVector2Array([Vector2(-half.x * .78, -half.y),
		Vector2(half.x * .78, -half.y), Vector2(half.x, -half.y * .7),
		Vector2(half.x, half.y), Vector2(-half.x, half.y),
		Vector2(-half.x, -half.y * .7)]), 1, 5, ARMOR)
	for side in [-1.0, 1.0]:
		b.box(Vector3(side * (half.x - 1.3), 2, 0), Vector3(2.6, 4, size.y), DARK)
		if detailed:
			for z in [-.65, -.22, .22, .65]:
				_wheel(b, Vector3(side * half.x, 2, z * half.y), 1.6, .6)
			for i in 6:
				b.box(Vector3(side * (half.x - 1.3), 4.1, lerpf(-half.y + 1, half.y - 1, float(i) / 5)),
					Vector3(2.7, .35, .5), EDGE.darkened(.3))
			b.box(Vector3(side * half.x * .5, 5.2, half.y * .55), Vector3(2, .5, size.y * .24), DARK)


static func _turret(b: RefCounted, key: String, detailed: bool) -> void:
	var radius := 4.0
	var length := 15.0
	if key == "flak_turret":
		radius = 5.0
		length = 18.0
	if key == "railgun_turret":
		radius = 18.0
		length = 72.0
	_cylinder(b, Vector3(0, 1.4, 0), radius, 2.8, DARK)
	b.box(Vector3(0, 3.1, 1), Vector3(radius * 1.5, 3.8, radius * 1.6), ARMOR)
	var twin := key != "gun_turret"
	var gap := 8.0 if key == "railgun_turret" else 1.8
	var width := 4.0 if key == "railgun_turret" else .9
	if key == "flak_turret":
		width = 1.5
	for x in ([-gap, gap] if twin else [0.0]):
		b.box(Vector3(x, 4.0, -length * .5), Vector3(width, width, length), EDGE)
		b.box(Vector3(x, 4.0, -length), Vector3(width * 1.35, width * 1.35, 1.2), DARK)
	if detailed:
		b.box(Vector3(radius * .55, 6, 2), Vector3(1.5, 3, 2), DARK)
		if key in ["aa_turret", "flak_turret"]:
			b.box(Vector3(-radius * .5, 6, 2), Vector3(3.2, 2, 1), EDGE)


static func _cells(b: RefCounted, center: Vector3, size: Vector2, columns: int, rows: int, gap: float) -> void:
	for x in columns:
		for z in rows:
			var position := center + Vector3((x - (columns - 1) * .5) * (size.x + gap), 0,
				(z - (rows - 1) * .5) * (size.y + gap))
			b.box(position, Vector3(size.x, .7, size.y), DARK)
			b.box(position + Vector3(0, .5, 0), Vector3(size.x * .78, .3, size.y * .8), EDGE)


static func _wheel(b: RefCounted, center: Vector3, radius: float, width: float) -> void:
	# 有端面的八棱负重轮，横轴与履带方向正交。
	for i in 8:
		var a := TAU * float(i) / 8
		var c := TAU * float(i + 1) / 8
		var p := center + Vector3(-width * .5, sin(a) * radius, cos(a) * radius)
		var q := center + Vector3(-width * .5, sin(c) * radius, cos(c) * radius)
		var offset := Vector3(width, 0, 0)
		b.quad(p, p + offset, q + offset, q, EDGE.darkened(.4))
		b.triangle(center - offset * .5, p, q, DARK.lightened(.1))
		b.triangle(center + offset * .5, q + offset, p + offset, DARK.lightened(.1))


static func _carrier(b: RefCounted, detailed: bool) -> void:
	# 用户 GIF 的层叠甲板和指挥结构；轮廓保持短宽装甲陆战平台，不使用船体水线。
	b.prism(PackedVector2Array([Vector2(-105, -310), Vector2(105, -310), Vector2(140, -270),
		Vector2(140, 275), Vector2(110, 310), Vector2(-110, 310),
		Vector2(-140, 275), Vector2(-140, -270)]), 8, DECK_HEIGHT, ARMOR)
	for x in [-121.0, 121.0]:
		b.box(Vector3(x, 9, 0), Vector3(38, 18, 512), DARK)
		b.box(Vector3(x, 23, 0), Vector3(38, 4, 520), EDGE.darkened(.2))
		if detailed:
			for z in range(-240, 241, 24):
				b.box(Vector3(x, 18, z), Vector3(39, 2.5, 6), ARMOR)
			for z in range(-210, 211, 60):
				_wheel(b, Vector3(139 if x > 0 else -139, 10, z), 8, 2)
	b.box(Vector3(0, 24.5, -10), Vector3(202, 1, 510), Color(.30, .36, .40))
	# 驻机孔位读取正式 PARK_OFFSETS，指挥舱放在其后方，不遮挡四架真实飞机。
	for point in LandCarrierUnit.PARK_OFFSETS:
		b.box(Vector3(point.x, 25.1, point.y), Vector3(54, .3, 64), DARK)
		for side in [-1.0, 1.0]:
			b.box(Vector3(point.x + side * 26, 25.4, point.y), Vector3(1.5, .3, 60), EDGE)
		b.box(Vector3(point.x, 25.4, point.y - 30), Vector3(50, .3, 1.5), EDGE)
	b.box(Vector3(26, 34, 205), Vector3(110, 20, 80), ARMOR)
	b.box(Vector3(32, 50, 208), Vector3(72, 12, 52), EDGE.darkened(.15))
	b.box(Vector3(32, 53, 181), Vector3(60, 5, 1.0), DARK)
	b.box(Vector3(32, 69, 208), Vector3(4, 26, 4), EDGE)
	b.box(Vector3(32, 81, 208), Vector3(36, 5, 6), ARMOR)
	if detailed:
		for x in [-65.0, 0.0, 65.0]:
			for z in [-228.0, -194.0, -160.0]:
				b.box(Vector3(x, 25.4, z), Vector3(2, .4, 20), EDGE)
		for x in [-64.0, -36.0]:
			b.box(Vector3(x, 31, 242), Vector3(20, 12, 52), DARK)


static func _train(b: RefCounted, index: int, detailed: bool) -> void:
	var half_w := ArmoredTrainSegment.SEGMENT_WIDTH_PX * .5
	var half_l := ArmoredTrainSegment.SEGMENT_LENGTH_PX * .5
	b.prism(PackedVector2Array([Vector2(-half_w + 8, -half_l), Vector2(half_w - 8, -half_l),
		Vector2(half_w, -half_l + 12), Vector2(half_w, half_l - 12), Vector2(half_w - 8, half_l),
		Vector2(-half_w + 8, half_l), Vector2(-half_w, half_l - 12), Vector2(-half_w, -half_l + 12)]),
		7, TRAIN_DECK_HEIGHT, ARMOR)
	for z in [-half_l - 4, half_l + 4]:
		b.box(Vector3(0, 5, z), Vector3(5, 5, 8), DARK)
	if index == 0:
		b.box(Vector3(0, 27, -72), Vector3(60, 22, 60), ARMOR)
		b.box(Vector3(0, 31, -103), Vector3(48, 7, 1), DARK)
		b.box(Vector3(0, 24, 32), Vector3(62, 16, 120), EDGE.darkened(.28))
	elif index == 1:
		for x in [-21.0, 21.0]:
			b.box(Vector3(x, 23, 0), Vector3(26, 14, 180), ARMOR)
	elif index == 2:
		for z in [-82.0, 82.0]:
			b.box(Vector3(0, 22, z), Vector3(58, 12, 30), DARK)
	elif index in [3, 4]:
		# 正式 VLS 子挂点位于甲板上 22；基座承接 16 高的车体，避免悬空。
		b.box(Vector3(0, 19, 0), Vector3(40, 6, 60), ARMOR)
		for z in [-64.0, 64.0]:
			b.box(Vector3(0, 20, z), Vector3(64, 8, 66), ARMOR)
			_cells(b, Vector3(0, 24.4, z), Vector2(20, 20), 2, 2, 8)
	elif index == 5:
		b.box(Vector3(0, 26, 22), Vector3(60, 20, 140), ARMOR)
		b.box(Vector3(0, 39, -60), Vector3(5, 46, 5), EDGE)
	elif index == 6:
		b.box(Vector3(0, 25, 0), Vector3(56, 18, 180), ARMOR)
		for z in [-58.0, 58.0]:
			b.box(Vector3(0, 40, z), Vector3(28, 12, 8), EDGE)
	elif index in [7, 8, 9, 10, 12, 13]:
		_cylinder(b, Vector3(0, 19, 0), 27, 6, DARK)
		for z in [-80.0, 80.0]:
			b.box(Vector3(0, 23, z), Vector3(58, 14, 32), ARMOR)
		if index == 13:
			b.box(Vector3(0, 25, 99), Vector3(66, 18, 18), EDGE.darkened(.2))
	else:
		for z in [-76.0, -38.0, 0.0, 38.0, 76.0]:
			b.box(Vector3(0, 24, z), Vector3(62, 16, 30), ARMOR)
	if detailed:
		for side in [-1.0, 1.0]:
			b.box(Vector3(side * 39, 17, 0), Vector3(2, 2, 208), EDGE)
			for z in [-90.0, -45.0, 0.0, 45.0, 90.0]:
				b.box(Vector3(side * 40, 11, z), Vector3(3, 9, 8), DARK)
		if index in [0, 1]:
			for z in range(-20, 90, 12):
				b.box(Vector3(0, 33 if index == 0 else 30, z), Vector3(46, 1, 4), DARK)
