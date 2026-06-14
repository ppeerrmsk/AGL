# 2026-06-13 编队归队提速（僚机"飞回长机身边龟速、不踩油门"根治）

诊断来源：`logs/combat_log_20260613_145025.txt`（用户反馈：最后僚机飞回长机身边不踩油门）。

## 诊断（三个龟速因，全在 `aircraft_formation.gd:_update_speed`）

编队跟随是 LOD 1 路径，速度不走推力物理，而是 `ac.speed = lerp(ac.speed, chase_target, rate·dt)`，
`chase_target = ldr.speed × 倍率`。所以"加力/油门"在这条路径里本就不存在——只有相对长机的倍率。

1. **唯一冲刺档 1.4× 只在 slot_d>400px 有效**：一进 400px 倍率即塌到 1.05~1.15×（仅比长机快 5~15%），
   "飞回长机身边"这段恰在 400px 内 → 最后 350px 龟速蹭。
2. **追赶倍率以纵向 `fwd_offset` 为判据**：横向落后（fwd_offset≈0）落进 1.0× 纯跟速、零追赶。
3. **速度全相对长机**：长机巡航不快（日志 ≈850km/h）时归队全程都慢，离 2000 上限差得远。

日志铁证：Grim FAR 457px=1190km/h(=850×1.4)，一进 MID 掉到 980(×1.15)；Pike 7 秒只挪 52px。

### 量化基线（`--bench=rejoin`，长机匀速 850km/h，F-14）
```
尾后 600px → >30s 未归队     横向落后 slot_d=300 fwd=0 → chase ×1.00（零追赶）
尾后 400px → >30s 未归队     横向落后 slot_d=150 fwd=0 → chase ×1.00
尾后 200px → 23.6s
```

## 修复（一次接三处，`_update_speed` 追赶段重写）

把"分档相对倍率"换成**按总距离 `slot_dist` 连续插值 长机速度 → 本机满速**：
```gdscript
if fwd_offset < -50:        chase = ldr.speed*0.92        # 超前减速（bug#7 保留，防振荡）
elif slot_dist > CLOSE_DIST:
    t = clamp((slot_dist-CLOSE_DIST)/(REJOIN_DIST-CLOSE_DIST), 0,1)
    chase = lerp(ldr.speed*1.05, max_ms, t)               # 贴近→1.05× 平滑停靠；远距→满速冲刺
else:                       chase = ldr.speed             # CLOSE 匹配长机
```
- **① 满速冲刺**：远距直接朝 `max_speed_at_altitude`（绝对速度，不再被长机巡航封顶）= 踩满油门。
- **② 无 400px 悬崖**：从 CLOSE 到 400px 连续插值，强追赶一路延续到贴近槽位才收敛。
- **③ 以总距离为判据**：横向落后也触发追赶（不再只看纵向 fwd_offset）。
- `clampf(chase, 0, max_ms)`（bug#3 防 Mach8 暴走）与 `target_speed_kmh` 同步（bug#6）均保留。
- **只改速度，不碰 bank/heading** → 不引入新抖动（编队 heading 仍 rate-limited，bank 仍由实际航迹推出）。

### 修复后（同一 `--bench=rejoin`）
```
尾后 600px → 8.0s（原 >30s）   横向 slot_d=300 → chase ×1.99（原 ×1.00）
尾后 400px → 6.7s（原 >30s）   横向 slot_d=150 → chase ×1.43（原 ×1.00）
尾后 200px → 5.1s（原 23.6s）  超调=0px（连续收尾，无冲过槽位/振荡）   末速回落 ×1.0 长机
```

## 验证
- 新增隔离沙盒 `scripts/tests/test_formation_rejoin.gd`（`--bench=rejoin`）：1D 闭合仿真量化归队耗时 +
  超调 + 横向追赶倍率。先跑基线再跑修复后，对比见上。**超调全 0**，确认提速未引入超调/振荡。
- `--bench=stress_mixed --duration=20` 实战：编译干净、无 SCRIPT/Parse/Compile Error，正常出报。

---

## 2026-06-14 回归修复：满速归队"转不回来、越飞越远"（航向对齐门）

诊断来源：`logs/combat_log_20260614_145743.txt`（用户：没操作但僚机全飞到很远、不知在干嘛）。

### 症状 / 根因
上面的提速把"远距归队"直接冲到 max 速度。但转弯率 **ω = g·tan(bank)/v 与速度成反比**：
满速 555m/s + 77° bank ≈ **4°/s**。当槽位在僚机【侧/后】（需要大角度掉头）时，僚机满速冲出去却
转不动机头 → 在大圈上越飞越远，slot_d 不减反增。日志 Yard 实证：max 速度(1999)、max bank(-77°)、
航向误差冻在 ~-130° 不收敛、slot_d 3670→**5821px(≈12km)** 持续增大，长机还在 8~10g 盘旋让槽位快速移动。
（上面的 1D 测试只测了"槽位在正前方"的对齐场景，航向误差≈0，所以没抓到这个掉头工况。）

### 修复：航向对齐门（"先转向再加速"）
`_update_speed` 远距档加一道对齐门：按机头与"指向槽位方向"的夹角缩放目标速度——
```
align = clamp(1 − head_err / 90°, 0, 1)         # 对准→1, ≥90°→0
chase_target = lerp(角点速度, 距离档满速, align)   # 未对准→角点速度(最佳转弯率)先转, 对准→全速冲刺
```
角点速度下 ω 高 5×（700kmh→~20°/s），僚机能把机头转向槽位，对准后再松到满速闭合。
**修正上文 fix③**：原"横向落后也满速冲刺"是错的（横向=需转向，满速反而转不动）——对齐门取而代之：
横向/背对 → 角点速度先转向。纯尾后对齐场景不变（align=1 仍满速，归队耗时不变）。

### 验证（`--bench=rejoin` 新增"掉头归队"2D 仿真 + 对齐门档位）
2D 仿真：僚机机头背对槽位（需 ~180° 掉头），转向用 ω=min(maxG·g/v, 编队转速上限) 捕捉 ω∝1/v 耦合。
```
对齐门：方位 0°→2000kmh(满速) / 90°→704 / 180°→786(≈角点)   （期望：对准冲刺、侧后转向）
掉头归队  长机 850kmh(疾飞): 2000px → 峰值 5987→2869px（不再飞到 12km）; 1000px → >30s→24.7s
          长机 250kmh(未操作): 2000px → 21.4s 收敛(峰值 2351px); 1000px → 17.1s   ← 用户场景
```
修复前：背对槽位**永远归不了队、峰值飞到 ~6000px(12km)**；修复后**收敛回归、excursion 有界**。
纯尾后对齐归队仍 8.0/6.7/5.1s 不变。`--bench=stress_mixed` 实战编译干净、无报错。

---

## 2026-06-14 (2)：FAR 归队放开 bank 到满 G（僚机不再"只能用 4G"）

诊断来源：`logs/combat_log_20260614_154255.txt`（用户：玩家轻松 9G+ 转弯去目的地，僚机归队却像只准用 4G）。

### 根因
`compute_target_bank` 的 `formation_mode` 分支恒把坡度钳到 **0.9×max_bank**（`cap_frac=0.9`）。因 G=1/cos(bank)
在近 90° 极度非线性，**砍 10% 角度 = 砍掉一大截 G**：玩家满坡 85°→12.5G，编队 0.9× = 77°→**仅 4.4G**。
日志实证：玩家峰值 g=12.5（bank≈85°），僚机归队恒 bank=±77°（=4.4G）→ 转弯半径大、归队慢。
（注释原写"编队 bank 由 AircraftFormation 接管、此分支基本不触发"，实为陈旧——`_update_bank_via_pd`
仍调 `update_bank`→命中此分支，一直在限 G。）

### 修复
新增瞬时标志 `Aircraft._formation_full_bank`，由 `AircraftFormation._update_bank_via_pd` 按 branch 写：
**FAR（归队硬转）= true → 放开到满 bank/满 G（像玩家一样硬转回阵）；MID/CLOSE 站位 = false → 保留
柔和 0.9 cap 防颤抖**（站位时航向误差小、bank 命令本就小，满 cap 也不会变粗暴）。
`update_bank` 与 `step_bank`（预测线，SEAM-012 要求双份同步）的 `compute_target_bank` 调用都改为
传 `formation_mode and not _formation_full_bank`。

### 验证（`--bench=rejoin` 新增 `compute_target_bank` 直测）
```
✓ FAR 满bank: bank=85° G=12.5   旧编队cap: bank=77° G=4.4
```
FAR 归队 G 从 4.4 提到 12.5（追平玩家）。配合上面的角点速度对齐门：角点速度 194m/s + 满坡 85° →
ω≈33°/s（旧 77° 仅 12.5°/s），归队转弯快 ~2.6×。`--bench=stress_mixed` 实战编译干净、无报错
（update_bank/step_bank 热路径改动）。MID/CLOSE 站位走柔和 cap 不变，不引入站位颤抖。
