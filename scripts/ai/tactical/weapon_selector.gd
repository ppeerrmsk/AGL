class_name WeaponSelector
extends RefCounted

## 武器竞选器（spec weapon-employment-doctrine §2.2，2026-07-04 用户定稿）
## Phase 1 纯函数层：竞选逻辑 + 动态候选表。planner 接入在 spec §6 阶段 2。
##
## 核心规则（用户定稿）：
##   - 距离带动态：build_candidates 每次实时读装备 live params（升级/强化即时生效）
##   - 重叠区按命中率优先：railgun(必中 100) > missile(70) > gun(50) > rocket(40)
##   - 电磁炮有最近射程 → 近带自然只剩机炮（"近距固定机炮"涌现，无特判）
##   - 滞回 1.5s 防带边界抖动换武器
##   - 全部失格 → 维持追击 + 按导弹纪律 crank 等待 CD（wait_doctrine="missile"）

const HIT_PRI := {"railgun": 100, "missile": 70, "gun": 50, "rocket": 40}
const SWITCH_HOLD_S := 1.5  ## 主武器切换滞回（秒）

## 竞选（纯函数，可单测）。
## candidates: Array[Dictionary{kind, band_min, band_max, ready}]（build_candidates 产出）
## prev_kind / prev_hold_s: 上次胜者与其已保持时长（滞回用）
## 返回 {kind: String, wait_doctrine: String}——kind=="" 表示全失格，
## wait_doctrine="missile" = 按导弹纪律机动等待 CD。
static func select(candidates: Array, dist_m: float, prev_kind: String = "",
		prev_hold_s: float = 999.0) -> Dictionary:
	var best_kind := ""
	var best_pri := -1
	var best_band_max := -1.0
	var prev_still_valid := false
	for c in candidates:
		if not bool(c.get("ready", false)):
			continue
		var bmin: float = float(c.get("band_min", 0.0))
		var bmax: float = float(c.get("band_max", 0.0))
		if dist_m < bmin or dist_m > bmax:
			continue
		var kind: String = String(c.get("kind", ""))
		if kind == prev_kind:
			prev_still_valid = true
		var pri: int = int(HIT_PRI.get(kind, 0))
		# 命中率优先；同级平手取距离带上界大者
		if pri > best_pri or (pri == best_pri and bmax > best_band_max):
			best_pri = pri
			best_band_max = bmax
			best_kind = kind
	if best_kind == "":
		return {"kind": "", "wait_doctrine": "missile"}
	# 滞回：上任胜者仍合格且保持未满 SWITCH_HOLD_S → 不换（防带边界抖动）
	if prev_kind != "" and prev_kind != best_kind and prev_still_valid \
			and prev_hold_s < SWITCH_HOLD_S:
		return {"kind": prev_kind, "wait_doctrine": ""}
	return {"kind": best_kind, "wait_doctrine": ""}


## 从飞机实时构建候选表。⚠ 距离带每次调用读 live params（spec §2.2-2：升级即时生效，
## 禁止缓存烘焙）。就绪判定只含弹药/冷却等本机可读项；锁定门（needs_lock）在阶段 2
## 由 planner 结合 Situation.target_locked 收口。
static func build_candidates(ac: Aircraft) -> Array:
	var out: Array = []
	var p := ac.params
	if p == null:
		return out
	# 电磁炮：min_engage ~ 本机雷达距离（RailgunEquipment 本就动态读 radar_range）
	var rg = p.get_equipment_of_kind("railgun")
	if rg != null:
		var rg_state = ac.equipment_state.get("railgun", null)
		var rg_ready: bool = rg_state == null or float(rg_state.get("cooldown", 0.0)) <= 0.0
		out.append({
			"kind": "railgun",
			"band_min": rg.min_engage_range_m,
			"band_max": rg._effective_max_range_m(ac),
			"ready": rg_ready,
		})
	if p.missile != null:
		out.append({
			"kind": "missile",
			"band_min": p.missile.min_range,
			"band_max": p.missile.max_range_rear,
			"ready": ac.missiles_remaining > 0,
			"needs_lock": true,
		})
	if p.gun != null:
		out.append({
			"kind": "gun",
			"band_min": 60.0,
			"band_max": p.gun.max_range,
			"ready": ac.ammo > 0,
		})
	if p.rocket != null:
		out.append({
			"kind": "rocket",
			"band_min": p.rocket.min_range,
			"band_max": p.rocket.max_range,
			"ready": ac.rockets_remaining > 0,
		})
	return out
