extends RefCounted
## 全面战争的有限资源/损失账本。只保存 WeakRef，不持有已释放战斗实体。
signal dispatched(kind: String, sector: int, request_id: int)
signal ended(won: bool)

const PACKAGES := {
	"fighter": {"cost": 60, "count": 4, "delay": 6.0, "stock": 4},
	"strike": {"cost": 45, "count": 2, "delay": 4.0, "stock": 4},
	"frigate": {"cost": 90, "count": 1, "delay": 10.0, "stock": 2},
	"ace": {"cost": 60, "count": 4, "delay": 6.0, "stock": 1},
}
const LIVE_CAP := 24
const SIDE_CAP := 12
var points: Array[float] = [240.0, 240.0]
var supply := 120.0
var elapsed := 0.0
var stock := {"fighter": 4, "strike": 4, "frigate": 2, "ace": 1}
var orders: Array[Dictionary] = []
var records: Dictionary = {}
var losses: Array[int] = [0, 0]
var active := true
var victory := false
var _next_id := 1

func register_unit(unit: CombatUnit, side: int, weight: float) -> void:
	records[unit.get_instance_id()] = {"ref": weakref(unit), "side": side, "weight": weight}

func living_units() -> Array[CombatUnit]:
	var result: Array[CombatUnit] = []
	for record: Dictionary in records.values():
		var candidate: Variant = record["ref"].get_ref()
		if typeof(candidate) == TYPE_OBJECT and is_instance_valid(candidate) \
				and candidate is CombatUnit and not candidate.is_destroyed:
			result.append(candidate as CombatUnit)
	return result

func request(kind: String, sector: int) -> bool:
	if not active or not PACKAGES.has(kind) or sector < 0 or sector > 2:
		return false
	var package: Dictionary = PACKAGES[kind]
	if orders.size() >= 2 or stock[kind] <= 0 or supply < package.cost:
		return false
	supply -= float(package.cost)
	stock[kind] -= 1
	orders.append({"id": _next_id, "kind": kind, "sector": sector,
		"remaining": float(package.delay)})
	_next_id += 1
	return true

func live_count(side: int) -> int:
	var count := 0
	for unit: CombatUnit in living_units():
		if (1 if unit.team == CombatUnit.TEAM_HOSTILE else 0) == side:
			count += 1
	return count

func cancel(request_id: int) -> bool:
	if not active:
		return false
	for i in range(orders.size()):
		if int(orders[i].id) == request_id:
			refund(String(orders[i].kind))
			orders.remove_at(i)
			return true
	return false

func refund(kind: String) -> void:
	supply = minf(240.0, supply + float(PACKAGES[kind].cost))
	stock[kind] += 1

func tick(delta: float, control: Array[int]) -> void:
	if not active:
		return
	elapsed += delta
	supply = minf(240.0, supply + delta)
	for id: int in records.keys():
		var record: Dictionary = records[id]
		var candidate: Variant = record["ref"].get_ref()
		if typeof(candidate) == TYPE_OBJECT and is_instance_valid(candidate) \
				and candidate is CombatUnit and not candidate.is_destroyed:
			continue
		var side: int = record.side
		points[side] = maxf(0.0, points[side] - float(record.weight))
		losses[side] += 1
		if side == 1:
			supply = minf(240.0, supply + 3.0)
		records.erase(id)
	for owner: int in control:
		if owner >= 0:
			points[1 - owner] = maxf(0.0, points[1 - owner] - delta)
	if points[0] <= 0.0 or points[1] <= 0.0:
		finish(points[0] > 0.0)
		return
	var population := living_units().size()
	var allied_population := live_count(0)
	var ready: Array[Dictionary] = []
	for order: Dictionary in orders:
		order.remaining = maxf(0.0, float(order.remaining) - delta)
		var count: int = PACKAGES[order.kind].count
		if float(order.remaining) <= 0.0 and population + count <= LIVE_CAP \
				and allied_population + count <= SIDE_CAP:
			population += count
			allied_population += count
			ready.append(order)
	# 先移除，再发信号；消费端失败可返还，不会重复入场。
	for order: Dictionary in ready:
		orders.erase(order)
		dispatched.emit(String(order.kind), int(order.sector), int(order.id))

func finish(won: bool) -> void:
	if not active:
		return
	active = false
	victory = won
	orders.clear()
	ended.emit(won)

func shutdown() -> void:
	active = false
	orders.clear()
	records.clear()
