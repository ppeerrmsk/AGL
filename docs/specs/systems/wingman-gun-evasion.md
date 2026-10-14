---
id: wingman-gun-evasion
kind: system
status: done
schema_version: 1
spec_version: 1
owner: 用户
depends_on: [wingman-escort-evasion, gun-burst-fire, rts-command]
reconstruction_complete: true
---

# 僚机机炮咬尾自保

## 1. 设计意图（Why）

用户批准普通僚机在有效机炮咬尾时短暂打断进攻/编队、机动脱险后恢复任务。
弥补只能躲导弹或依赖特殊技能的缺口，尤其覆盖正在攻击 A 却被 B 从背后开火。
遵守设计哲学的可见反应、真实飞行、60 FPS 与玩家操控优先；不瞬移、不授予无敌或特殊机动技能。

## 2. 数据定义（What）

| 项 | 值 | 语义 |
|---|---|---|
| 受威胁源 | instance ID，0=无 | 复用 Aircraft.report_gun_tailed 发布，不持有攻击者 Object |
| 威胁复核间隔 | 1/3 秒 | 当前 ID 的 O(1) 正式火控查询，不全场扫描；首次上报后下个 AI tick 即可进入 |
| 最短承诺 | 0.6 秒 | 避免一过射界立刻折返；攻击者死亡/释放立即允许终止 |
| 安全延迟 | 0.35 秒 | 正式威胁消失持续至此，且超过最短承诺后退出 |
| 最长持续 | 3.0 秒 | 单次不得无限延续 |
| 退出再入冷却 | 0.8 秒 | 与既有 leash 再入抑制共同限制 |
| 转向目标 | 入场机头侧向 90° | 当前坡度绝对值>0.05rad 时沿该侧，否则选朝长机的侧向，平局按实例 ID 奇偶 |
| 追踪点距离 | 1600 px | 每个 AI tick 在当前机位加同一固定世界方向向量 |
| 目标速度 | effective_corner_speed_kmh | 真实有效角点速度；加力开启，仅用既有性能，无额外物理 buff |

状态组件仅持标量、Vector2 与 ID：active、elapsed、safe_time、check_timer、cooldown、direction。
共享 EVADE 模态的 true/false 仍只由 MissileEvasion.enter_evade/exit_evade 写入。

## 3. 行为与公式（How）

- 适用：TEAM_PLAYER、有存活长机且自身不是长机、非手控、非 simple/kamikaze/BOSS 的普通 AI 僚机。
- 威胁由现有敌机火控更新调用 report_gun_tailed 发布；无须掉血，也无须该敌机是僚机自己的攻击目标。
- 每次消费 ID 都先转 Variant，再 TYPE_OBJECT → is_instance_valid → Aircraft 检查。
- 正式判断复用 AircraftWeapons.is_gun_tailed_by：敌对、存活、可见、目标确为本机、有炮有弹、武器模式为机炮、后方点积<-0.3、有效射程内、高差≤500m（非扁平）、前置射向在机炮锥内。
- 入场调用共享 EVADE 入口：退出 formation/LOD 托管、武器静默、清 combat_target；保留 commanded_target 和 AI 目标所有权。提交 EVADE 意图，速度/方向/加力都由同一槽主张，固定世界侧向不逐 tick 重选。
- 现有 evasion_mode 自带的普通闪避加成继续生效；不设置 afterburner-mode 无敌窗口、不消耗或伪造小队加力池。
- 规避中出现需要运动学规避的真实导弹时，取消机炮子状态并交还现有导弹路径，EVADE 模态不中断。
- 达到安全延迟或最长持续时退出、撤销 sticky EVADE 槽，重置旧战术计划；现存有效目标恢复 ENGAGE，否则归队，无长机时巡逻。
- 玩家切控、事件 directive 接管、特殊机动启动、阵营改变或长机死亡/解绑立即取消机炮子状态；取消不覆盖新操控者的命令。攻击者死亡/释放后最迟下一 AI tick 清 ID 并正常恢复。
- 小队 leash/区域约束沿用现有分发前裁决；禁止借机炮躲避绕过空间约束。
- 反馈复用现有 GUN_TAILED、真实坡度/航向/加力尾焰及 evasion_started 无线电；新增 GUN_EVADE 起止日志，供诊断读取。

## 4. 结构与组成（Structure）

Aircraft 保存上报 ID；AIController 持有轻量 GunEvasion 组件。
GunEvasion 负责机炮条件、固定 break 方向与有界计时；MissileEvasion 继续独占公共 EVADE 进出及任务恢复。
AI 分发在命令铁律和编队路由前消费机炮自保，directive/手控优先。不增加节点、draw 或全场扫描。

## 5. 验收标准（Acceptance）

- [x] focused：第三方尾追触发、编队让位、命令保留与恢复、固定转向、角点速度提交；正面/远距/无炮/高差/手控不误触发。
- [x] focused：安全退出、3 秒上限、冷却、导弹接管；特殊机动/手控/directive 接管清理。
- [x] 真实 SceneTree：生产威胁上报 → AI 模态 → Aircraft 真实物理产生航向变化；真实伤害击毁来源并跨帧释放后，规避 ID/意图清理、目标恢复；长机死亡时取消自保。
- [x] 默认 all（含 lifecycle_gauntlet）。
- [x] Shadow Visual 专项：真实飞机、机炮、固定方向急转与任务恢复可见；记录触发/退出和受击量，不能只看静态状态。
- [x] 性能 C1：battlefield_atmosphere_stress_36 30s Shadow Visual，36 名混合演员、8/8 镜头巡检、frames_below_60=0。成本为每个僚机 O(1) 标量更新与最多 3Hz 的单目标几何查询；独立机炮飞行专项实际触发新行为。
- 完整局体感由玩家验收；不以短场景替代完整局。C2 无新增全场扫描/多战线调度，按成本形状豁免。

2026-09-06 实测（Godot 4.7.2 Steam）：focused 23/23；all 97 项零失败，LifecycleGauntlet 90/90 与嵌入机炮案例 12/12；独立 Shadow Visual 13/13。真实飞行专项航向变化 24.58°、弹丸峰值 10、受伤 0，仅证明该受控场景，不代表完整局死亡率。
性能报告 `bench/results/battlefield_atmosphere_stress_36_20260906_130810.txt`：30 秒、36/36 演员、8/8 巡检，平均 119.37 FPS、最慢帧 60.66 FPS、低于 60 FPS 为 0 帧。专项截图 `tmp/gun_evasion_visual.png`，日志 `tmp/gun_evasion_focused.txt` / `tmp/gun_evasion_all_final.txt` / `tmp/gun_evasion_visual.txt`（本地临时证据，不纳入资源）。

## 6. 实现计划

1. 接通威胁 ID 发布与 GunEvasion 组件，扩展共享 EVADE 入口/退出生命周期。
2. 新增 focused/SceneTree/Visual 验收并注册生命周期门。
3. focused → all → 专项 Visual → C1；同步索引和实际证据。

## 7. 索引锚点

- scripts/ai/gun_evasion.gd：报告消费、tick、process、clear。
- scripts/ai/missile_evasion.gd：共享模态进出与导弹接管。
- scripts/ai_controller.gd：分发与手控/directive 取消。
- scripts/aircraft.gd：report_gun_tailed。

## 8. 变更记录

| 日期 | 版本 | 内容 |
|---|---|---|
| 2026-09-06 | 1 | 用户确认加入普通僚机机炮自保，按已接受的短暂打断与恢复原任务方案实现。 |
