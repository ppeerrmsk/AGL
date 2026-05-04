# 2026-04-29 — 第四批便利贴（4 张）反向索引 / 光环 / F-14 协同

承接 [batch-3](2026-04-29-skill-batch-3.md)。本次完成白板剩余的几张需要新基础设施的便利贴。

## 4 张新技能

| id | 稀有度 | 关键词 | 效果 |
|---|---|---|---|
| `evasion_overstock` | CLA | evasion_mode, missile | 规避模式中每 4s 装填 1 发导弹，突破上限至 2× max_count |
| `fear_on_dogfight` | EXP | fear, dogfight | 与你缠斗的敌人累积 5s 后获得 FEAR |
| `rear_aura_slow` | CLA | slow, aura | 后半球 2.4km 内敌人持续 SLOW |
| `f14_squad_lock_slow` | NEXT_GEN | slow, wingman, f14 | F-14 专属：全僚机锁同一敌机则该敌机持续 SLOW（前置 data_link）|

## 关键基础设施

### `Aircraft.engaging_me: Dictionary`（反向索引）
AIController 在 `_physics_process` 顶层每帧比对 `_current_target` 与 `_prev_target_for_reverse_idx`：
- 切换时差量更新目标飞机的 `engaging_me[atk_id] = atk`
- AI 销毁时清掉自己在他人 `engaging_me` 里的 entry
- **0 扫描**，仅写入；只维护 team==0 玩家系飞机的索引（其它阵营不需要）

性能：每帧每 AI 一次 dict 比对 + 偶尔的差量写入。20+ AI × 60Hz ≈ 1200 次/秒比对 + 极少写入。<5μs。

### Evasion Overstock 4s 装填
- `evasion_overstock_interval` 字段（0=禁用）
- `_evasion_overstock_timer` 仅在 `evasion_mode` 为 true 时累加
- 进入 evasion 重置 timer（避免短停短进取巧）
- `cap = max_count × 2`，超出停止装填

### 缠斗累计恐惧
- 每帧扫 `engaging_me`，每 atk_id 累加 `_dogfight_fear_seconds[atk_id] += delta`
- 达 `fear_on_dogfight_threshold` 即 `AOEBroadcast.apply_status_in_radius(50px, FEAR)` 给该敌人 + 累积归零（可重复）
- 失效 entry 在循环中收集后批量删除（避免遍历时改 dict）

### 后半球 SLOW 光环
- 每 0.5s 节流（`_rear_aura_accum`），不每帧扫
- 用 `dot(my_back, to_enemy) > 0.3` 几何判定（约 ±70° 后半球容差）
- 命中敌人 apply SLOW 1.5s（0.5s 间隔内自动刷新）
- 视觉脉冲：冰蓝色 AOE 圈，0.5s 短淡出（避免堆积）

### F-14 全僚机协同锁定
- `survivor_mode._update_radar_locks` 末追加（紧跟 data_link aura 后）
- 算法：从玩家 `radar_targets`（accum ≥ lock_time）开始求交集，逐个僚机过滤
- 交集 size == 1 时给那架敌机 SLOW 3s
- 每 0.2s（`RADAR_LOCK_INTERVAL`）刷新 → 持续锁定时持续 SLOW
- 前置 `data_link`（用 `requires_skill` 字段，没数据链无法保持 lock 同步）

## 文件清单

**改动**：
- `scripts/aircraft.gd` — 7 个新字段（evasion_overstock_interval / _evasion_overstock_timer / engaging_me / fear_on_dogfight_threshold / _dogfight_fear_seconds / rear_aura_slow_radius_px / _rear_aura_accum / f14_squad_lock_slow_active）；`set_evasion_mode` 重置 overstock timer；`_update_evasion` 新增 4 处分支（overstock / dogfight fear / rear aura inline）
- `scripts/ai_controller.gd` — `_prev_target_for_reverse_idx` 字段；`_physics_process` 顶层差量同步；销毁时清除自己在 engaging_me 的 entry
- `scripts/survivor/survivor_mode.gd` — `_update_radar_locks` 末追加 F-14 squad-lock SLOW 检查
- `scripts/survivor/survivor_data.gd` — 4 张新 UPGRADES
- `scripts/survivor/survivor_player.gd` — 4 个新 stat case
- `i18n/translations.csv` — 8 条翻译

## UPGRADES 总数

约 **67 张**，覆盖白板便利贴的 **80%+**。

剩余便利贴（已决定跳过 / 需要更大改造）：
- 持久 flare 实体（已决定跳过）
- 一些状态触发状态的细节（如 FEAR → 同步 SLOW，已实装为 fear_chills）

## 下一步建议

1. 跑一局生存模式 Lv12+ 测试这批：
   - F4 看 `pity` / `steering` 在 60+ 张技能下是否正常分布
   - 选满 evasion build（cobra + speed + cd + stealth + herbst + overstock）测试是否互不干扰
   - 选满 fear build（gun_kill / squad_spread / chills / on_lock / on_dogfight / head_on_aoe）测试视觉/性能
2. 数值平衡微调：
   - `MAX_BULLET_DODGE_CAP = 0.85` 可能偏高，根据玩家反馈调到 0.75/0.80
   - `RARITY_BASE_WEIGHT` 50/25/15/8/2 看分布是否合理
   - `PITY_THRESHOLD` 5/8/12 看玩家拿到顶级技能的频率
3. 基础设施最后两块（如要继续）：
   - 4 标签 TabContainer F4（目前是单 RichTextLabel）
   - i18n CSV 改 .po（数量已经接近上限）
