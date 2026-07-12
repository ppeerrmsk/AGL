extends Node

## MeritLedger — 局外货币"功勋"账本（AutoLoad）
##
## 局内总收获 XP 按结算系数折算成功勋写入 user://merit.cfg。
## 后续改装系统从这里读 / 扣。

signal merit_changed(new_total: int, delta: int)

const CONFIG_PATH := "user://merit.cfg"
const SECTION := "merit"

## 本局结算系数（与设计文档一致）
const SETTLE_RETREAT := 1.0    ## 撤退：100% 回收
const SETTLE_KIA := 0.8        ## 阵亡：80% 回收
const SETTLE_VICTORY := 1.0    ## 通关：100% 回收

var _total: int = 0

func _ready() -> void:
	_load()

# ── 公共 API ──

func get_total() -> int:
	return _total

## 本局 XP 折算并入账。返回实际入账数。
func settle_run(total_xp_earned: int, multiplier: float) -> int:
	var earned := int(floor(float(maxi(total_xp_earned, 0)) * maxf(multiplier, 0.0)))
	if earned <= 0:
		return 0
	_total += earned
	_save()
	merit_changed.emit(_total, earned)
	EventLogger.log_event("MERIT", "Settle",
		"xp=%d × %.2f → +%d (total=%d)" % [total_xp_earned, multiplier, earned, _total])
	return earned

## 局内即时奖励入账（护送任务等直接功勋，不走 XP 折算；spec global-awareness-roe §2.6a）
func award(amount: int, why: String = "") -> int:
	if amount <= 0:
		return 0
	_total += amount
	_save()
	merit_changed.emit(_total, amount)
	EventLogger.log_event("MERIT", "Award", "%s +%d (total=%d)" % [why, amount, _total])
	return amount

## 改装系统购买扣费。成功返回 true。
func spend(amount: int) -> bool:
	if amount <= 0 or _total < amount:
		return false
	_total -= amount
	_save()
	merit_changed.emit(_total, -amount)
	return true

## 调试：直接加（不走结算）
func debug_add(amount: int) -> void:
	_total += amount
	_save()
	merit_changed.emit(_total, amount)

## 调试：清零
func debug_reset() -> void:
	var d := -_total
	_total = 0
	_save()
	merit_changed.emit(_total, d)

# ── 持久化 ──

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		_total = 0
		return
	_total = int(cfg.get_value(SECTION, "total", 0))
	if _total < 0:
		_total = 0

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "total", _total)
	cfg.save(CONFIG_PATH)
