# 2026-06-14 僚机躲弹过激修复（规避只对真威胁加速散开）

诊断来源：`logs/combat_log_20260614_155416.txt` + 用户反馈：僚机对慢速/几乎打不中的导弹也维持
max+AB 加速、快速飞离阵型，且持续不退，很不自然。期望：巡航/待机时最小限度努力（末段 flare 即可），
只有真威胁才进规避散开。

## 诊断

规避触发器 `MissileEvasion.find_nearest_incoming_missile` **没有威胁强度门**：任何瞄着自己、未飞过头、
仍在动力段（或熄火后仍在逼近）的导弹都算威胁 → `enter_evade` → planner 出 `EVADE_MISSILE` intent
→ `target_speed=max + afterburner` 加速散开。于是一发**慢速导弹在它 3s 动力段内**就逼着僚机满加力
飞离阵型，哪怕它永远追不上。`evade_missile` intent 速度恒为 max+AB，无"轻重"之分。

## 修复（仅玩家方 team 0，敌方维持难度不变）

新增规避威胁门 `_is_evasion_threat(ac, m, already_evading)`（纯几何，与智能 flare 同一套 closing/TTI
思路，但门更早一点给机动留提前量）：
```
closing = (v_missile − v_self)·LOS
进入：closing ≥ 60 m/s 且 TTI ≤ 3.5s          # 在逼近(会命中) 且 即将到达 才散开
维持(already_evading)：closing ≥ 30 且 TTI ≤ 5.0   # 滞回，防边界抖
```
- **慢速/追不上**（closing<60）→ 不进规避，留在阵型，靠智能 flare 末段兜底（= 用户要的"最小限度努力"）。
- **还远/未临近**（TTI>3.5）→ 先不散开，等真正逼近。
- **被甩开/TTI 拉远** → 下一 tick 退出散开、归队（不再"持续飞远"）。
- **滞回**：进入门(60/3.5) 比维持门(30/5.0) 严——否则僚机一加速就把 closing 拉到阈值下 → 退出 →
  减速归队 → closing 回升 → 重进，在边界 EVADE↔SQUAD_FOLLOW 来回弹跳（实测 0.3s 一次抖）。

接入：`find_nearest_incoming_missile` 对 team 0 走此门（同时覆盖进入/维持/`missile_aware` 标志）；
team≠0 保留原"熄火追不上即解除"逻辑。

## 验证

### 单元（`--bench=flare`，9/9 通过；新增 4 条规避门用例）
```
慢弹追不上 closing 30<60 → 不散开 ✓       快弹远 TTI5.9s → 不散开 ✓
快弹中距 TTI4.0s → 不散开(再等) ✓          快弹临近 TTI1.9s → 散开 ✓
```

### 实战（`--bench=stress_mixed --duration=40`）
- 友机 EVADE 进入次数 **37 → 2**（同量级压测、不同随机种），过激散开基本消除。
- 残留的 2 次都是真威胁、各持续 2~5s、enter/exit 干净，**无 0.3s 级抖动**（滞回生效）。
- 编译干净、无 SCRIPT/Parse/Compile Error。

## 与既有修复的关系
- 与智能 flare（`2026-06-14-smart-flare-tti.md`）同源：flare 是"末段最后一道"，规避门是"要不要提前散开"。
  两层都按 closing/TTI 判真威胁 → 慢弹两层都不触发（既不散开也不浪费焰，靠机动/自然脱靶化解）。
- 不复活"躲十几秒脱队"老 bug：被甩开 closing 掉 → 立即退出；leash / scatter 超时兜底仍在。
