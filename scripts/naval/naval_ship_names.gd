class_name NavalShipNames

## 舰船命名池 —— 仿 CallsignDB 模式
## 5 个舰种独立词库 + 舷号 1..999 随机 roll，已用编号集合在局内去重
## 返回形式："DDG-187 Valkyrie" / "CV-05 Tempest"
##
## 主题：
##   CV  气候/风暴  — 庞大威压
##   CG  雷霆/神祇  — 远距压制
##   DDG 猎食动物/战士 — 机动狩猎
##   FFG 海洋生物/轻快 — 轻量护卫
##   SS  深海生物/神话巨兽 — 隐秘威胁

# ── 已使用的完整舰名集合（局内去重）──
static var _used: Dictionary = {}  # full_name -> true

## 重置（重启/返回主菜单时调用）
static func reset() -> void:
	_used.clear()

## 分配一个舰名
## ship_class ∈ {"CV","CG","DDG","FFG","SS"}
## 返回如 "DDG-187 Valkyrie"
static func roll(ship_class: String) -> String:
	var pool: PackedStringArray = NAME_POOLS.get(ship_class, PackedStringArray())
	if pool.is_empty():
		return "%s-000 Unknown" % ship_class

	# 最多尝试 100 次随机组合
	for i in 100:
		var ship_name: String = pool[randi() % pool.size()]
		var hull_no: int = randi_range(1, 999)
		var full_name := "%s-%03d %s" % [ship_class, hull_no, ship_name]
		if not _used.has(full_name):
			_used[full_name] = true
			return full_name

	# 太多重复 → 顺序查找
	for ship_name in pool:
		for hull_no in range(1, 1000):
			var full_name := "%s-%03d %s" % [ship_class, hull_no, ship_name]
			if not _used.has(full_name):
				_used[full_name] = true
				return full_name

	# 全用完（不可能发生但兜底）
	return "%s-000 %s" % [ship_class, pool[0]]

## 回收舰名（船被摧毁时调用）
static func release(full_name: String) -> void:
	_used.erase(full_name)

# ── 舰名词库（按主题分开）──
## GDScript 的 const 不接受 PackedStringArray 作为 Dictionary 值（非编译期常量），
## 所以用 static var + lazy init，效果等价。
static var NAME_POOLS: Dictionary = {
	"CV": PackedStringArray([
		"Tempest", "Cyclone", "Typhoon", "Maelstrom", "Monsoon",
		"Tornado", "Hurricane", "Blizzard", "Squall", "Gale",
	]),
	"CG": PackedStringArray([
		"Thunderhead", "Valhalla", "Olympus", "Aegis", "Vanguard",
		"Sovereign", "Titan", "Colossus", "Juggernaut", "Ironclad",
	]),
	"DDG": PackedStringArray([
		"Valkyrie", "Raptor", "Viking", "Corsair", "Reaver",
		"Sentinel", "Warden", "Marauder", "Spartan", "Gladius",
	]),
	"FFG": PackedStringArray([
		"Skimmer", "Barracuda", "Stingray", "Mantis", "Piranha",
		"Falcon", "Harpoon", "Swift", "Cutlass", "Dart",
	]),
	"SS": PackedStringArray([
		"Leviathan", "Kraken", "Nautilus", "Abyss", "Triton",
		"Nessie", "Hydra", "Wyrm", "Void", "Phantom",
	]),
}
