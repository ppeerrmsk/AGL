## 加力模式充能资源（spec afterburner-mode）
## 小队级单实例：满格才能激活，窗口 6s 固定不可提前退出，击杀 +4s，约 30s 被动充满。
## 由 survivor_mode 建实例并驱动 update(delta)（升级 UI 暂停时不被驱动 → 计时自然冻结）。
## 不缓存长机引用（SEAM-019：try_activate 传参即用）；窗口成员是激活瞬间快照，
## 中途换帅/新僚机入场不改变本窗口 buff 归属。
class_name AfterburnerCharge
extends RefCounted

const CHARGE_MAX: float = 30.0        ## 满格容量（秒）；激活条件 = 满格
const CHARGE_RATE: float = 1.0        ## 被动充能速率（/s），空格 → 满 ≈ 30s
const KILL_CHARGE: float = 4.0        ## 小队击杀 1 个敌人（空中/地面）的充能反馈
const WINDOW_DURATION: float = 6.0    ## 加力窗口时长，固定；激活中再按无效

var charge: float = CHARGE_MAX        ## 当前充能（开局满格，让新机制第一时间可用）
var window_left: float = 0.0          ## 加力窗口剩余时间（>0 = ACTIVE）
var _window_members: Array = []       ## 激活瞬间全队快照（Aircraft），窗口结束统一清 flag

## ── 720 批技能修正（队级单实例语义：survivor_mode 按账本同步，不逐机应用）──
var kill_charge_bonus: float = 0.0    ## 检讨：击杀充能奖励 +3s/层（基线 KILL_CHARGE=4）
var window_duration_mult: float = 1.0 ## 强化加力：窗口时长 ×(1+0.5/层)，6→9→12s
var _window_total: float = WINDOW_DURATION  ## 本窗口总时长（HUD 比例分母）

## 主循环驱动：ACTIVE 倒计时（期间被动充能暂停），否则被动充能
func update(delta: float) -> void:
	if window_left > 0.0:
		window_left -= delta
		if window_left <= 0.0:
			_end_window()
		return
	charge = minf(charge + CHARGE_RATE * delta, CHARGE_MAX)

## 击杀充能（空中走 kill_recorded / 地面走 spawner 击杀检测，挂点见 survivor_mode）
## 窗口内击杀同样入账（为下一轮攒，ACTIVE 只暂停被动充能）
func on_kill_charge() -> void:
	charge = minf(charge + KILL_CHARGE + kill_charge_bonus, CHARGE_MAX)

## 玩家触发（E 键 / HUD 按钮）。满格且不在窗口中才生效；失败静默（条/按钮状态即反馈）。
## 激活链路：全队快照置窗口标志（强 buff 层）+ 长机走既有 set_evasion_mode(true)
## （planner EVADE max+AB、escort_cover_active 广播、radio break、§1.2 技能钩子全保留）
func try_activate(leader: Aircraft) -> bool:
	if leader == null or not is_instance_valid(leader) or leader.is_destroyed:
		return false
	if window_left > 0.0 or charge < CHARGE_MAX:
		return false
	charge = 0.0
	_window_total = WINDOW_DURATION * maxf(window_duration_mult, 0.01)
	window_left = _window_total
	_window_members = [leader]
	# 与 Aircraft._propagate_evasion_to_squad 同判据收集僚机（squad.leader == 长机；drone 除外）
	for u in CombatUnit.all_units:
		if u == null or not is_instance_valid(u) or u.is_destroyed:
			continue
		if not (u is Aircraft) or u == leader or u.team != leader.team:
			continue
		var ac: Aircraft = u
		if ac.is_drone:
			continue
		for child in ac.get_children():
			if child is AIController:
				var ai_ctrl: AIController = child
				if ai_ctrl.squad and ai_ctrl.squad.leader == leader:
					_window_members.append(ac)
				break
	for m in _window_members:
		m.afterburner_window_active = true
	leader.set_evasion_mode(true)
	EventLogger.log_event("AFTERBURNER", leader._log_name(),
		"window %.0fs, squad size %d" % [_window_total, _window_members.size()])
	return true

## 窗口到期：清全队标志 + 长机对称退出 evasion（玩家中途下令已退出则为 no-op）
func _end_window() -> void:
	window_left = 0.0
	for m in _window_members:
		if m != null and is_instance_valid(m):
			m.afterburner_window_active = false
	if not _window_members.is_empty():
		var leader = _window_members[0]
		if leader != null and is_instance_valid(leader) and not leader.is_destroyed:
			leader.set_evasion_mode(false)
	_window_members.clear()

# ── HUD 查询器 ──

func is_ready() -> bool:
	return window_left <= 0.0 and charge >= CHARGE_MAX

func is_window_active() -> bool:
	return window_left > 0.0

## 充能进度 0..1（ACTIVE 期间 = 0 起步的击杀存量）
func ratio() -> float:
	return clampf(charge / CHARGE_MAX, 0.0, 1.0)

## 窗口剩余进度 1→0（非 ACTIVE 返回 0）
func window_ratio() -> float:
	return clampf(window_left / maxf(_window_total, 0.01), 0.0, 1.0)
