# 2026-07-29 小队指挥 UI 与机型解绑 + F-14 起手弹数拉平

用户两条：
1. 「小队指挥 UI 只在玩家使用 F-14 的时候有用不应该，只要有僚机入队就该启动这个小队指挥 UI」
2. 「F-14 初始只有两发导弹，不该是 4 发」

---

## 一、小队指挥 UI：真源是"队伍有没有登记"，不是机型

### 症状与根因

面板（`SurvivorHUD._squad_panel`，标题 `SQUAD_HEADER`，含交战模式 / 武器偏好按钮 + 逐机
武器状态）本身**没有任何机型门**——它的显隐条件就是 `_get_wingmen().is_empty()`。

问题出在上游的**反查链路**：

```
SurvivorHUD._update_squad_panel
  → _get_wingmen
    → _get_player_squad          # 扫 _spawner.get_squads() 找 leader == player_aircraft
      → SurvivorSpawner._squads  # ← 玩家队从来没进这张表
```

玩家队的登记语句 `_spawner.get_squads().append(sq)` 原先**只挂在 `_spawn_starting_wingmen`
末尾**，而那条路径的调用条件是 `profile.wingman_count > 0` —— 41 架可驾驶机里**只有
F-14** 满足。其余 40 架起手无小队，靠 `_ensure_player_squad()` 懒建队：

- 战区 +1 僚机奖励（`_claim_wingman_reward`）
- 停靠送僚机（`_on_dock_docked`，生涯商店 `dock_wingman`）
- 双子星 `sig_ax00` 克隆

这三条都会把僚机真的塞进 `Squad`，队伍也真的建起来了，**但永远不入 `_squads` 表**。后果两条：

1. `_get_player_squad()` 恒返回 null → 有僚机也看不到小队指挥面板（用户报的现象）
2. `SurvivorSpawner._cleanup_squads()` 只清理表内队伍 → 玩家队的阵亡僚机永不从
   `members` 剔除，`Squad.cleanup()` 里的 ACE 继任逻辑也从不对玩家队生效

### 修法

登记点上移到 `_ensure_player_squad()` —— 这是玩家队装配的**唯一公共入口**，起手僚机路径
（`_spawn_starting_wingmen`）本来就是先调它再干活：

```gdscript
# scripts/survivor/survivor_mode.gd  _ensure_player_squad
if _spawner and not _spawner.get_squads().has(sq):
    _spawner.get_squads().append(sq)
```

`has()` 守卫保证幂等（`_ensure_player_squad` 本身对已建队直接 early-return，这里是双保险）；
`_spawn_starting_wingmen` 末尾的旧 append 删掉，换成一行说明注释。

### 顺带修的同源缺口

`sig_ax00`（双子星，AX-00 签名技：立即复制 3 架同型僚机入队）直接调
`_spawn_reward_wingman()`，而那个函数的第一行是 `if not _squad ... return`。AX-00 的
`wingman_count = 0`，玩家若没先从别处拿过僚机，这一技就**整段静默失效**——复制 0 架，
EventLogger 却照记「复制 3 架」。补上先 `_ensure_player_squad()`。

### 验收

新增 `scripts/tests/test_squad_command_ui.gd`（bench key `squad_cmd_ui`，10 断言）：

| 组 | 断言 |
|---|---|
| A 懒建队登记 | 建队前表空 / 返回队伍 / 玩家是长机 / **队伍已入表** |
| B 幂等 | 二次调用同一队 / 表仍只有 1 条 |
| C HUD 反查 | 无僚机时看不到僚机 / 找得到玩家队 / 看得到 1 架僚机 / 列表不含长机自己 |

夹具不挂进场景树（不触发 `survivor_mode._ready` 的整局初始化），直接对裸实例设
`player_aircraft` / `_spawner` 后调用被测方法。

---

## 二、F-14 起手弹数 4 → 2

`resources/player/player_f14.tres` 内联主导弹 `max_count` **4 → 2**。

理由：F-14 是 [player-aircraft-power-curve](../specs/systems/player-aircraft-power-curve.md)
§1.1 明写的**全谱最弱锚点**，强度补偿在"开局送 3 僚机"，却在弹数这一轴独自比其余三张 T1
起手卡（F-15 / A-6E / 幻影 III 均为 2）高出一档；选机卡文案 `AIRCRAFT_F14_CARDDESC`
本来就写着「导弹/热诱弹/机炮均缩水」，与数据自相矛盾。改后文案不用动——反而变准确了。

僚机档案 `playable_f14_wingman.tres` 用的是共享 `default_missile.tres`，不在本次改动范围。

---

## 三、改动清单

| 文件 | 改动 |
|---|---|
| `scripts/survivor/survivor_mode.gd` | `_ensure_player_squad` 补队伍登记（幂等）；`_spawn_starting_wingmen` 末尾去重复 append；`sig_ax00` 补懒建队 |
| `resources/player/player_f14.tres` | 主导弹 `max_count` 4 → 2 |
| `scripts/tests/test_squad_command_ui.gd` | 新增（10 断言） |
| `scripts/tests/test_player_params.gd` | F-14 锚点断言弹数 4→2；弹数抽查同步；新增「T1 起手四卡弹数齐平 = 2」 |
| `scripts/bench/bench_runner.gd` | 注册 `squad_cmd_ui` |
| `docs/reference/code-index.md` | 新增「小队指挥面板」小节；survivor_mode.gd 全量锚点行号随位移重映射 |
| `docs/reference/script-index.md` | survivor_mode 入口补 `_ensure_player_squad`；新增测试行 |
| `docs/specs/systems/rts-command.md` | §8 加 v7 变更行 |
| `docs/specs/systems/player-aircraft-power-curve.md` | §2 T1 矩阵 F-14 导弹列 4→2；§8 加 v13 变更行 |

## 四、验收状态

- `--bench=squad_cmd_ui` 10/10 ✓
- `--bench=all` **回归门 PASS ✓：47 项测试，失败 0**
- `python tools/verify_doc_anchors.py` → 全部锚点与代码一致 ✓
- `python tools/verify_player_ref_holders.py` → 无漏登记 ✓
- ⏳ 差 playtest：非 F-14 机型拿到第一架僚机后，右下角小队指挥面板应立刻出现
