# 更新日志 — 2026-04-10

本次提交累计自 `f737423` (2026-04-09) 以来的所有改动。

## 1. 编队系统（Squad / Formation）

### 阵型与僚机托管

新增 `scripts/squad.gd` — 编队数据结构与阵型计算。支持 6 种阵型：

- **Combat Spread** — 战斗展开（并排大间距）
- **Wedge** — 楔形编队（后方 45°）
- **Echelon** — 梯形编队（右侧阶梯）
- **Trail** — 纵列编队（正后方）
- **Finger Four** — 指尖四点（不对称历史经典）
- **Fluid Four** — 流体四机（两对战斗翼展开）

### 快捷键

| 按键 | 功能 |
|------|------|
| F1 | 生成 4 机友方编队 |
| F2 | 生成 2 机友方编队 |
| F3 | 生成 2 机敌方编队 |
| F4 | 生成 4 机敌方编队 |
| F5 | 切换当前编队阵型 |
| F9 | 导出战斗日志 |

### 僚机 AI 行为

- `AIController` 新增 `SQUAD_FOLLOW` 状态和 `squad_index` 属性
- 僚机自动跟随长机阵型槽位
- 长机锁定敌机时，僚机按**反应延迟**（0.3~1.5 秒，每架飞机不同）进入协同攻击
- 独立交战结束后触发**归队模式**（`_rejoining`），从自主飞行渐变回编队托管
- 僚机还会周期性**扫描长机后半球威胁**（掩护扫描，每 0.5 秒），发现后半球敌机自动掩护交战

### 编队托管物理（本次关键优化）

重写编队跟随的位置控制，解决僚机振荡和平移问题：

**三段式航向控制：**

| 距离 | 行为 |
|------|------|
| `>800px` 或过渡初期 | 纯追击归队（航向直指槽位 + 激进银行） |
| `50~800px` | 航向追踪槽位 + **自然银行转弯**（走真实飞行物理） |
| `<50px` | 航向同步长机 + 极弱漂移修正 |

**关键改进：**
- 中距离位置变化全部通过**实际转弯飞过去**，不再用 `position +=` 直接瞬移
- 近距漂移强度从 `0.35×speed` 降到 `0.15×speed` 且仅在 <50px 生效
- 之前版本在 80~300px 区间混合航向造成的追击振荡（∞ 字形飞行）彻底消除

**阵型变换个体化反应延迟：**

- 检测阵型切换（本地坐标系偏移变化 > 30px）
- 每架僚机随机反应延迟 0.3~1.3 秒（由个体扰动相位 `_formation_jitter_phase` 决定）
- 延迟期间 `target_position` 不更新（继续向旧槽位飞）
- 延迟结束后槽位突变 → 自动进入中距追击分支 → 自然曲线转弯至新位置

## 2. 地面单位系统

新增 `GroundUnit` 基类（继承 `CombatUnit`）和三种地面单位：

### SAMUnit（防空导弹车）
- `scripts/sam_unit.gd` + `scenes/sam_unit.tscn`
- **360° 圆形雷达**（覆写 `is_in_radar_cone` 只检查距离）
- HQ-7 导弹（`resources/sam_missile.tres`）：4 发，射程 6km，伤害 60

### AAGunUnit（高射炮）
- `scripts/aa_gun_unit.gd` + `scenes/aa_gun_unit.tscn`
- **独立炮塔转向**（`turret_heading` 独立于底盘）
- ZU-23 机炮（`resources/aa_gun.tres`）：1200 发/分，射程 600m
- 宽松开火判定（25° 内即开火，象征性射击）

### RadarStation（雷达站）
- `scripts/radar_station.gd` + `scenes/radar_station.tscn`
- **超大范围雷达**：10km，360°
- 无武器
- **数据链共享**：将锁定信息注入 4km 内友方地面单位（cap 在对方 lock_time - 0.5，不立刻触发开火）
- 旋转雷达盘动画

### 地面单位支持设施
- `scripts/ground_convoy.gd` — 车队系统（前车/后车跟随）
- `scripts/combat_unit.gd` — 战斗单位基类，统一 Aircraft 与 GroundUnit 接口
- 高度档位系统 `AltitudeTier { GROUND, LOW, MID, HIGH }`
- 低空目标锁定速率衰减（地面 ×0.5, 低空 ×0.7）模拟杂波干扰

## 3. 事件日志系统

新增 `scripts/event_logger.gd`（Autoload 单例）：

- 环形缓冲区保留最近 60 秒游戏事件
- `EventLogger.log_event(category, subject, message)` 全局调用
- 按 F9 导出到 `user://combat_log_YYYYMMDD_HHMMSS.txt`
- 记录：AI 状态切换、交战/脱离、命中、击毁、发射、规避、升级等

## 4. 呼号分配器

新增 `scripts/callsign_db.gd`：

- 从呼号库（Laser, Vista, Freight, Rogue, ...）中分配唯一标识
- 每架飞机 `_ready()` 时自动获取 `callsign`
- 击毁后归还回收池（避免耗尽）

## 5. 指挥 UAV 系统（生存模式）

新增 Sentinel 指挥无人机：

- `scripts/survivor/commander_aura.gd` — 指挥光环：buff 附近友方（skill/composure/aggression/roll_rate/max_g）
- `scripts/survivor/commander_overlay.gd` — 指挥圈可视化
- 自动招募落单 UAV/UCAV 加入编队（最多 6 架）
- 无武装，HP 55，击杀经验 50
- 解锁等级 4

## 6. 生存模式增强

### 敌机类型解锁
- UAV（始终出现）
- UCAV 导弹型（等级 3+）
- Sentinel 指挥（等级 4+）
- J-7 截击机（等级 5+）
- MiG-29（等级 7+）

### 动态性能控制
- 每 0.5s 采样 FPS，保留最近 6 次
- 平均 FPS < 30 → 降低敌机上限
- 恢复后逐渐提升上限

### 猎手指派
- 每 5 秒从空闲敌机中指派猎手追踪玩家
- 每 8 秒更新敌机巡逻航点跟踪玩家位置

### 导弹限制
- 同时飞向玩家的导弹不超过 3 枚
- 防止被瞬间秒杀

### 扁平高度模式
- `CombatUnit.flat_altitude = true` 启用三/四档位高度
- 生存模式 HUD 用档位显示（LOW/MID/HIGH），简化视角
- BulletManager / MissileManager 在扁平模式下跳过高度容差检查

## 7. 升级系统扩展

`survivor_data.gd` 新增多项升级和**进化机制**：

### 进化技能
基础技能满级后自动进化为强化版：

- `flare_cooldown` → ★ **电子对抗套件**（释放热诱弹解除所有锁定+3秒免疫）
- `missile_tracking` → ★ **连锁弹头**（导弹命中后弹跳至另一敌机）
- `gun_damage` → ★ **多管齐射**（同时射出三道机炮）

### 新增升级
- `pilot_stamina` — 耐力上限 ×2、恢复 ×2
- `kill_heal` — 击杀回血 10 HP
- `gun_multishot` / `missile_bounce` — 进化专属
- `dogfight` — 格斗大师（失速-12%、减速+30%、低速机动增强）
- `multi_lock` — 多目标同时锁定+1

## 8. Debug 面板重构

`scripts/debug_panel.gd` 大幅扩展：

- 显示所有飞机的完整状态
- 策略文本按 AI 状态精细区分：
  - `编队跟随` / `归队` / `阵型调整`（本次新增）
  - `协同攻击 → 目标` / `交战 [战术名]`
  - `规避导弹` / `巡逻 (航点 X/Y)`
- 飞行员信息：技能、抗压、专注、自保、精神（压力条）
- 地面单位生成按钮：敌/友 SAM、AAA、雷达站
- 编队生成按钮（F1/F2/F3/F4/F5 的 GUI 版）

## 9. HUD 重写（生存模式）

`scripts/survivor/hud.gd` 全面重写：

- 中央状态面板：HP 条、经验条、等级、导弹/弹药/热诱弹计数
- 战术按钮：武器偏好（导弹/机炮）、高度偏好（爬升/低空）、规避模式
- 悬停提示显示战术解释
- Game Over 界面显示等级、时间、击杀数

## 10. 项目文档体系

新增完整文档：

- `docs/code-index.md` — **代码索引**：按功能主题直接映射到文件:行号
- `docs/scripts-reference.md` — 脚本 API 参考（类继承、变量、方法）
- `docs/ai-system.md` — AI 系统（状态机、BFM、压力、态势感知）
- `docs/survivor-mode.md` — 生存模式（波次、升级、进化）
- `docs/ground-units.md` — 地面单位（SAM/AAA/雷达站、数据链）
- `docs/resources-catalog.md` — 资源参数总表
- `docs/squad-tactics-design.md` — 编队战术设计

更新 `CLAUDE.md` 文档索引分为"快速检索"与"核心参考"两层。

## 11. Bug 修复

### commander_aura.gd:221 — Identifier "squad" not declared
`_try_recruit()` 函数内局部变量是 `sq`，误用了未声明的 `squad`。修正为 `sq.leader`。

### 编队僚机预测线不准
僚机处于 `formation_mode = true` 时，`target_position` 是阵型槽位（移动目标），但实际飞行通过航向同步+漂移修正，预测线完全失准。  
修复：`_draw_target_line` 在 `formation_mode` 时直接 return，不绘制预测线和槽位航点标记。只有长机显示预测线。

### 编队振荡与平移（见第 1 节）
- 僚机在 80~300px 区间追击移动的槽位 → ∞ 字形振荡
- 阵型变换时直接 `position +=` 平移 → 不自然的侧移感

两个问题均在本次一并修复。

---

## 涉及文件总结

**新增脚本（15个）：**
- `scripts/squad.gd`
- `scripts/combat_unit.gd`
- `scripts/ground_unit.gd`
- `scripts/sam_unit.gd`
- `scripts/aa_gun_unit.gd`
- `scripts/radar_station.gd`
- `scripts/ground_convoy.gd`
- `scripts/event_logger.gd`
- `scripts/callsign_db.gd`
- `scripts/survivor/commander_aura.gd`
- `scripts/survivor/commander_overlay.gd`

**新增场景（3个）：**
- `scenes/sam_unit.tscn`
- `scenes/aa_gun_unit.tscn`
- `scenes/radar_station.tscn`

**新增资源（7个）：**
- `resources/sam_params.tres`, `sam_missile.tres`
- `resources/aa_gun_params.tres`, `aa_gun.tres`
- `resources/radar_station_params.tres`
- `resources/agm_missile.tres`
- `resources/enemy_uav_commander.tres`

**新增文档（7个）：**
- `docs/code-index.md`
- `docs/scripts-reference.md`
- `docs/ai-system.md`
- `docs/survivor-mode.md`
- `docs/ground-units.md`
- `docs/resources-catalog.md`
- `docs/squad-tactics-design.md`

**修改主要脚本：**
- `scripts/aircraft.gd`（编队托管、战术偏好、多目标锁定、进化武器）
- `scripts/ai_controller.gd`（编队跟随、归队、协同攻击、反应延迟）
- `scripts/main.gd`（编队生成、LOD、地形绘制）
- `scripts/debug_panel.gd`（状态文本重构）
- `scripts/survivor/survivor_mode.gd`（猎手、导弹限制、动态性能）
- `scripts/survivor/survivor_hud.gd`（全面重写）
