class_name UnitGrid
extends RefCounted

## 均匀网格空间哈希 —— 把"每颗子弹扫全场单位"从 O(bullets × units) 降到 O(bullets × 近邻)。
##
## 背景（2026-07-24 航母群掉帧修复）：BulletManager 命中循环里每颗真弹都遍历整个
## combat_unit_list 做距离判定。航母战 = 舰队狂喷 CIWS/AA 真弹 + 大混战 100+ 架飞机同场，
## 两个因子同时爆炸，bullet_phys 实测冲到 80ms/帧。空间网格把候选集从"全场"缩到"3×3 邻格"。
##
## 大/小单位分治：
##   - 小单位（飞机 / 地面 / MountTarget，命中半径 ≤ 20px）→ 按位置塞进网格
##   - 大单位（NavalUnit，命中半径随 hull_length 扩到 ~140px）→ 进 large_units 线性表，逐弹全扫
##   这样正好化解命中半径悬殊：船数量少（≤~13），线性扫无所谓；飞机数量多，走网格。
##
## 语义保证（无漏判前提）：query_into 返回 pos 所在格 3×3 邻域内的全部小单位，
## 是"距 pos < cell_size 的小单位"的超集。只要 cell_size >= 最大小单位命中半径（当前 20px），
## 任何真正会命中的小单位一定在候选集里 —— 碰撞结果与暴力全扫等价（见 test_bullet_grid）。

var cell_size: float = 256.0
var _cells: Dictionary = {}      ## Vector2i(cx,cy) -> Array（该格内的小单位）
var large_units: Array = []      ## NavalUnit 等大命中半径单位，调用方每弹全扫

## 每物理帧重建一次：小单位入格，大单位进 large_units。
## units 为 combat_unit_list（含僵尸引用可能）——本函数负责 is_instance_valid + is_destroyed 过滤。
## ⚠ 网格是本帧快照：子弹循环中途击毁的单位仍留在候选集里，调用方命中循环内必须保留
##   per-candidate 的 is_instance_valid + is_destroyed 守卫（不能因为"进过网格"就省掉）。
func rebuild(units: Array, p_cell_size: float = 256.0) -> void:
	cell_size = p_cell_size
	_cells.clear()
	large_units.clear()
	for u in units:
		if u == null or not is_instance_valid(u) or u.is_destroyed:
			continue
		if u is NavalUnit:
			large_units.append(u)
			continue
		var key := Vector2i(floori(u.global_position.x / cell_size), floori(u.global_position.y / cell_size))
		# 用 has() 而非 get(key, []) —— 后者每次调用都分配一个临时空数组，抵消网格收益
		if _cells.has(key):
			_cells[key].append(u)
		else:
			_cells[key] = [u]

## 把 pos 所在格 3×3 邻域的小单位追加进 out（不清空 out —— 调用方负责 clear 并可先塞 large_units）。
## 单位在网格中恰好属于一个格 → 9 格互不重叠 → 无重复计数。
func query_into(pos: Vector2, out: Array) -> void:
	var bx := floori(pos.x / cell_size)
	var by := floori(pos.y / cell_size)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var key := Vector2i(bx + dx, by + dy)
			if _cells.has(key):
				out.append_array(_cells[key])
