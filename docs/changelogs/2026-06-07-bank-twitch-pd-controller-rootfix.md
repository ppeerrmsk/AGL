# 2026-06-07 — 战斗转弯控制器重写为临界阻尼 PD（SEAM-012 治本）

seam: [docs/architecture/known-seams.md](../architecture/known-seams.md) SEAM-012 ·
承接: [2026-06-07-bank-twitch-rootfix-and-test-harness.md](2026-06-07-bank-twitch-rootfix-and-test-harness.md)（第一轮治标）

## 起因
第一轮把"每帧猛翻 buzz"从 501→个位数（连续斜坡 + 滚出精确积分补偿 + 翻转去抖等 ~7 层补丁），
但慢速机（F-86）在激进缠斗/硬转机动目标时仍有少数**大坡度反转**。本质是转弯控制器**欠阻尼**的位置式(P)
控制——bank 追 heading_diff 缺有效速度阻尼项，高 bank 时航向过冲→heading_diff 翻号→bank 翻号→来回。
本轮按 SEAM-012 计划把控制器**重写成临界阻尼 PD**根治。

## 控制律
旧（位置式 P）：`target_bank = smoothstep(heading_diff) → max_bank`（纯位置映射，无速度阻尼）
新（临界阻尼 PD）：
```
target_turn_rate = kp·heading_diff − kd·current_turn_rate      # PD：P 项追误差，D 项阻尼当前转速
bank = atan(target_turn_rate · v / g)                         # 协调转弯反推坡度
```
- **D 项（−kd·ω）** 是旧控制缺失的关键：接近目标航向且转速高时自动提前滚出 → 不过冲 → 不翻号。
- **命令转速再反推坡度**：(g/v) 与 (v/g) 抵消 → 闭环阻尼与速度无关，跨机型/速度天然稳健。

删掉的治标补丁：`compute_target_bank` 的连续斜坡分支映射、bank-flip 守卫（BANK_FLIP_*）、
target_bank 翻转时间去抖（TB_FLIP_*）、滚出航向精确积分过冲补偿 —— 全部由 PD 的 D 项统一取代。

## 实现踩坑（三个非平凡点）
| # | 问题 | 现象 | 解法 |
|---|---|---|---|
| 1 | **单帧代数环** | 协调转弯下 ω 几乎一帧跟上指令 → 反馈裸 ω 形成 `ω_n=kp·e−kd·ω_{n-1}` → `(−kd)^n` 每帧符号交替 Nyquist 抖（F-86 800 圈追 59 次） | D 项输入改用**低通滤波转速** `_turn_rate_filt`（α=0.30，~3 帧时间常数）破环；保留真实滚出时标阻尼 |
| 2 | **跨机型阻尼** | 慢滚机若用统一 kd 会欠阻尼 | `kd = clamp(PD_KD_SCALE/roll_rate, 0.35, 1.6)`：滚转越慢 kd 越大 |
| 3 | **LOS 前馈反效果** | 理论上尾追转弯目标(e≈0 仍需稳态转速)需要 LOS 角速度前馈，否则同向 bank 幅度"呼吸" | 无头扫参实测前馈在离散物理 + AI 分频跳变参考下尖刺过冲**恒为害**（总反转 240→700+）→ 默认 `PD_LOS_FF=0` 关闭；管线保留待将来抗跳变 LOS 估计 |

## 度量重构（关键认知）
原 harness 只数"bank 大摆幅反向"（≥8° 摆幅的任意极值反转），把**符号反转**（左↔右硬翻＝用户痛点）
和**同向呼吸**（持续单向转、bank 幅度脉动）混为一谈。新增独立的**符号反转**指标（bank 过零且两侧极值
都 ≥15°）。结论：
- **符号反转（用户真正的"大坡反转"）**：PD 全场景压到 **≤2**（4 机型 × 12 场景，总 33），随 kp/kd/α 扫参
  恒定 32~33 → **根治目标达成**。
- **同向呼吸**：残留 ~206（集中在"等速追内圈出转目标"这种退化几何），是 P 控制结构性弛豫，非用户痛点；
  盲优化"总反转"会被它误导。

## 调参 / 验证
- 旋钮：`aircraft_physics.gd` 顶部 `PD_*`（用 static var 方便 harness 扫参，定稿值即默认）。
  逐机型经 `combat_bank_aggression` → kp 缩放透传。终值 kp_base=3.0 / kd_scale=3.0 / kd∈[0.35,1.6] / α=0.30 / ff=0。
- 无头量化：`godot --headless --path . -- --bench=turn_physics`（看"符号反转"列，全场景 ≤2）
- 扫参：`--bench=turn_physics --pd-sweep`（符号反转/同向呼吸 双指标网格）
- 确定性战斗：`--bench=mixed --duration=45`（无 SCRIPT ERROR，FPS 无回归：ac_phys.kine 61µs/帧/18 机）
- 可视：`--bench=demo`（不加 --headless）

## 改动文件
- `scripts/aircraft/aircraft_physics.gd`：`compute_target_bank` 重写为 PD + LOS 前馈（默认关）；
  `update_bank` / `step_bank` 计算滤波转速 + LOS 率并传入；删 bank-flip / tb-flip / 滚出补偿；新增 `PD_*` 常量
- `scripts/aircraft.gd`：新增 `_turn_rate_filt` / `_prev_tgt_heading_pd` / `_los_rate_filt`；删 `_tb_sign` / `_tb_flip_timer`
- `scripts/aircraft/flight_state.gd`：镜像新增 3 个滤波/LOS 字段（populate + write_back）
- `scripts/combat_params.gd`：`combat_full_bank_diff` 标弃用；`combat_half_bank_diff`→PD 死区；`combat_bank_aggression`→kp 缩放（注释更新）
- `scripts/tests/test_turn_physics.gd`：新增符号反转指标 + AI 分频追击场景 + S 转基线扣除 + `--pd-sweep` 网格扫参
