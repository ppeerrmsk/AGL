extends RefCounted
## 2px 单元的近景楼体占地；一次加载，局部矩形查询，不扫描全城或依赖镜头 LOD。
const PATH := "res://resources/maps/tokyo_ground_obstacles.bin"
const SHA256 := "8f8a87858e86a31f54d0cb321f96b199f1b7a414077726858ae628889620d1ea"
const ORIGIN := Vector2(-16500, -16500)
const STEP := 2.0
const WIDTH := 16504
const BYTES := WIDTH * WIDTH / 8
static var _bits := PackedByteArray()
static var _attempted := false

static func ready() -> bool:
	if not _attempted:
		_attempted = true
		if FileAccess.get_sha256(PATH) == SHA256:
			_bits = FileAccess.get_file_as_bytes(PATH).decompress(BYTES, FileAccess.COMPRESSION_DEFLATE)
		if _bits.size() != BYTES:
			push_error("Ground obstacles: missing or invalid baked city footprint")
	return _bits.size() == BYTES

static func clear_at(point: Vector2, radius: float = 5.0) -> bool:
	if not point.is_finite() or not ready():
		return false
	# 多扩一单元：栅格化取整及车身/炮管半径都不能穿进建筑边缘。
	var low := Vector2i(((point - Vector2.ONE * (radius + STEP) - ORIGIN) / STEP).floor())
	var high := Vector2i(((point + Vector2.ONE * (radius + STEP) - ORIGIN) / STEP).floor())
	if low.x < 0 or low.y < 0 or high.x >= WIDTH or high.y >= WIDTH:
		return false
	for y in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			var bit := y * WIDTH + x
			if (_bits[bit >> 3] & (128 >> (bit & 7))) != 0:
				return false
	return true
