## 加力模式充能资源（spec afterburner-mode）
## 小队级单实例·充能制（电池模型）：只要有能量就能一键启动，激活中持续耗能，
## 耗尽自动结束，玩家可随时再按 E 提前关闭（剩余能量保留）。被动充能 + 击杀充能。
## 由 survivor_mode 建实例并驱动 update(delta)（升级 UI 暂停时不被驱动 → 计时自然冻结）。
## 不缓存长机引用（SEAM-019：toggle 传参即用）；窗口成员是激活瞬间快照，
## 中途换帅/新僚机入场不改变本次加力的 buff 归属。
class_name AfterburnerCharge
extends RefCounted

const CHARGE_MAX: float = 6.0         ## 能量池上限（秒）= 满能量下最多连烧 6s 加力（对齐旧窗口时长）
const CHARGE_RATE: float = 0.2        ## 被动充能速率（/s），空 → 满 ≈ 30s（6 ÷ 0.2）
const DRAIN_RATE: float = 1.0         ## 激活时耗能速率（/s），能量按秒 1:1 消耗
const KILL_CHARGE: float = 0.8        ## 小队击杀 1 个敌人（空中/地面）+0.8s（占满池 13%，满池仍需 ~7.5 杀）

var charge: float = CHARGE_MAX        ## 当前能量（开局满格，让新机制第一时间可用）
var active: bool = false              ## 加力是否正在启用（true = 正在耗能）
var _window_members: Array = []       ## 激活瞬间全队快照（Aircraft），关闭时统一清 flag

## ── 720 批技能修正（队级单实例语义：survivor_mode 按账本同步，不逐机应用）──
var kill_charge_bonus: float = 0.0    ## 检讨：击杀充能奖励 +0.6s/层（基线 KILL_CHARGE=0.8）
var duration_mult: float = 1.0        ## 强化加力：耗能减慢 ×(1+0.5/层)，同能量烧更久

## 有效耗能速率：duration_mult 越大 → 耗得越慢 → 加力越持久
func _effective_drain() -> float:
	return DRAIN_RATE / maxf(duration_mult, 0.01)

## 主循环驱动：激活中耗能（期间被动充能暂停）→ 耗尽自动关闭；否则被动充能。
## rate_mult：722 签名技能的充能倍率（公路机场·未被锁 ×1.5 / 地形跟随·低空 ×1.5，
## 由 survivor_mode 每帧按 ACE 状态计算传入；默认 1.0 = baseline 不变）
func update(delta: float, rate_mult: float = 1.0) -> void:
	if active:
		charge -= _effective_drain() * delta
		# 722 sig_su34·鸭嘴兽厨房：加力期间成员每秒回 2 HP（逐机字段判定）
		for m in _window_members:
			if m != null and is_instance_valid(m) and not m.is_destroyed \
					and m.sig_su34_active and m.params:
				m.hp = minf(m.hp + 2.0 * delta, m.params.max_hp)
		if charge <= 0.0:
			charge = 0.0
			_deactivate()  # 能量耗尽 → 自动结束
		return
	charge = minf(charge + CHARGE_RATE * rate_mult * delta, CHARGE_MAX)

## 击杀充能（空中走 kill_recorded / 地面走 spawner 击杀检测，挂点见 survivor_mode）
## 激活中击杀同样入账（边烧边攒，只是被动充能暂停）
func on_kill_charge() -> void:
	charge = minf(charge + KILL_CHARGE + kill_charge_bonus, CHARGE_MAX)

## 玩家触发（E 键 / HUD 按钮）——开关切换。
##   激活中按下 → 立即关闭（剩余能量保留），返回 false。
##   未激活且有能量（charge > 0）→ 启动，返回 true；能量为 0 时失败静默（条状态即反馈）。
## 启动链路：全队快照置窗口标志（强 buff 层）+ 长机走既有 set_evasion_mode(true, suppress_radio=true)
## （planner EVADE max+AB、escort_cover_active 广播、§1.2 技能钩子全保留；无线电改喊"加力冲刺"而非"break"）
func toggle(leader: Aircraft) -> bool:
	if leader == null or not is_instance_valid(leader) or leader.is_destroyed:
		return false
	if active:
		_deactivate()  # 玩家提前关闭
		return false
	if charge <= 0.0:
		return false   # 无能量，启动失败
	active = true
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
	leader.set_evasion_mode(true, true)  # suppress_radio：加力另走 afterburner_engaged，不喊 break
	# 无线电"加力冲刺"呼叫（玩家主动，语义非躲导弹）——上升沿只播一次，冷却/概率在订阅方
	if leader.callsign != "" and leader.can_speak_on_radio():
		EventLogger.afterburner_engaged.emit(leader.callsign, leader.team)
	EventLogger.log_event("AFTERBURNER", leader._log_name(),
		"activate, charge %.1fs, squad size %d" % [charge, _window_members.size()])
	return true

## 关闭加力：清全队标志 + 长机对称退出 evasion（玩家中途下令已退出则为 no-op）
## 由玩家提前关闭 / 能量耗尽 / 长机销毁（成员数组有 valid 守卫）共用
func _deactivate() -> void:
	active = false
	for m in _window_members:
		if m != null and is_instance_valid(m):
			m.afterburner_window_active = false
	if not _window_members.is_empty():
		var leader = _window_members[0]
		if leader != null and is_instance_valid(leader) and not leader.is_destroyed:
			leader.set_evasion_mode(false)
	_window_members.clear()

# ── HUD 查询器 ──

func is_active() -> bool:
	return active

func is_full() -> bool:
	return not active and charge >= CHARGE_MAX

## 充能进度 0..1（激活中随耗能实时收缩，做电池放空的可视）
func ratio() -> float:
	return clampf(charge / CHARGE_MAX, 0.0, 1.0)

## 当前能量还能烧多少秒加力（考虑 duration_mult 减耗）
func remaining_seconds() -> float:
	return charge / _effective_drain()
