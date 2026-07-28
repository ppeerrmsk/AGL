# 2026-07-26 玩家生涯档案系统（spec career-archive）

用户需求：做"档案系统"记录玩家生涯（分机型击坠 / BOSS 战绩 / 通关·死亡·撤离·停机次数），
作为后续全局成长系统的数据地基；并给出两条规则——BOSS 按档案递进轮换、30 UAV 击坠成就解锁忠诚僚机战区奖励。

权威设计见 [specs/systems/career-archive.md](../specs/systems/career-archive.md)（含 §0 用户用词的 8 条落地解释，
其中 "Race" 按 WRAITH_SQUADRON 理解，**待用户确认**）。

## 本批改动

- **新增** `scripts/meta/career_archive.gd` — CareerArchive AutoLoad（user://career.cfg，ConfigFile 4 段 11 键；
  脏标记 + 低频冲刷；`achievement_unlocked` 信号；`build_boss_history()`）。project.godot 注册；
  main_menu 删存档 lambda 补 `CareerArchive.debug_reset()`。
- **记录挂点**（全部一行式，统一 `archive_enabled()` 守卫 = 非 bench 非 boss_debug）：
  - `survivor_spawner._detect_kills`：空中击坠按 `enemy_type` 入档（归因过滤 `kill_attacker_team == TEAM_PLAYER`，
    坠地无归因/ALLY 击坠不计）；地面摧毁总数
  - `survivor_mode`：开局 / 阵亡 / 撤退 / 通关（按 map_id）/ 停机（按 dock_kind）/
    BOSS 接战（on_boss_engaged）/ BOSS 击败（on_boss_victory 的 `_ev` 参数接回改 `ev` 以读 boss_id）
- **BOSS 档案轮换**（boss_registry.gd）：新增 `BOSS_ROTATION`（雷斯→航母→Goose）+
  `ROTATION_ADVANCE_CHANCE=0.5` + `rotation_candidates()` 纯函数 + `pick_for_map` 第 3 参 history；
  `MAP_POOLS.default` 补 **MOTHER_GOOSE**（正式上线，此前 spec done 却池外刷不到）。
  boss_encounter_event `_init` 加第 5 参 `p_boss_history`，`survivor_mode._update_boss_phase` 正式局注入
  `CareerArchive.build_boss_history()`，非正式局传空保持旧纯随机。
- **成就 + 奖池门控**：uav_hunter（UAV 族 {uav,ucav,uav_commander,uav_laser} 累计 30）→
  ZoneHint show_temp 6s toast（刻意不用红横幅，那是 BOSS 专属）；`zone_data._assign_reward` 武器子池
  `loyal_wingman` 按 ctx `loyal_wingman_unlocked` 清零权重（缺键 fail-open 保 bench 旧行为），
  真值由 `_build_reward_roll_context` 注入。
- **i18n**：`ACHIEVEMENT_UAV_HUNTER_TOAST` 三语（新前缀 `ACHIEVEMENT_<ID>_TOAST` 已回填 i18n.md 前缀表）。
- **测试**：新增 `scripts/tests/test_career_archive.gd`（bench key `career_archive`，31 断言：
  轮换偏好序 / 地形过滤顺延 / 存取 roundtrip / 成就幂等；存档隔离 user://career_test.cfg）。
  `--bench=all` 回归门 39 项全 PASS；verify_player_ref_holders ✓；verify_doc_anchors ✓
  （顺手回填了本批插行推移的 code-index 32 处锚点）。

## 遗留

- spec §0 的 8 条语义解释待用户确认（尤其 "Race"=Wraith、"打过"=击败、推进概率 0.5）
- §5 playtest 项未跑（轮换体感 / 成就触发 / 忠诚僚机入池前后对照）
- 档案数据的浏览 UI（生涯页/图鉴）归全局成长系统后续批次
