# 2026-07-22 全局平衡批 —— 战场节奏 / 王牌支援中队 / 战区奖励军械库

> 用户三联需求驱动（同日 spec-first 定稿 + 落地）：
> ①冷场根治 + 新战区；②"王牌中队"敌军支援机制（全灭 = 局时 +1 分钟）；
> ③战区奖励加武器（电磁炮/火箭弹/激光）+ 次世代技能只走战区奖励。
> 权威 spec：`systems/battlefield-tempo-pass` / `events/ace-support-squadron` / `systems/zone-reward-arsenal`。

## ① 战场节奏批（spec systems/battlefield-tempo-pass）

**根因（实证）**：reinforcement-ingress 改造后全部增援"边缘 → 中央锚点驻空"，没有任何一类
敌机以玩家为目标进场；hunter 热度配额只能抽调场上闲兵，抽调池空时造不出压力 → 冷场 →
XP 停滞。

- **拦截波**：hunter 配额缺口 ≥2（`INTERCEPT_QUOTA_GAP`）时，本波旅途增援改为拦截使命——
  玩家 heading ±90° 前方扇区边缘入场（`_ingress_spawn_point` 扇区参数化）、TRANSIT 航点=
  玩家位置每 8s 修正、永不 ONSTATION（`reinf_intercept` meta），由 ROE 感知圈 / hunter tick
  自然收编。在途拦截队计入占额（`_count_hunter_pressure`）防连刷过压。单杠杆自平衡：
  冷场必来、热闹必不来。选型/token/间隔全不变（只改"去哪"不改"刷什么"）。
- **新战区 F/G**：F 荒川北岸 `(-1500,-11000)` r2200 ground（陆地占比 1.00）/
  G 千叶中部 `(10800,-1800)` r2500 air。候选池 4→6。`test_map_expansion` 全绿
  （7 区几何 + F↔A 缘距 2047 压线合规）。
- **刻意不动**：token 预算 / XP 曲线 / 刷怪间隔 / 任务规模——60km-density-pass 两轮旋钮
  还没 playtest，本批只做结构性增压，保归因能力。

## ② 王牌支援中队（spec events/ace-support-squadron）

ace-squadron-tier 预设的"非 BOSS 王牌中队"第一个实例：

- **编成**：Su-35 ×5（KNIGHT×2 + SNIPER×3），金橙涂装区分杂兵；`AceSupportSquad extends
  AceSquad`，category="ace_support"（不打 boss），tier 待遇全走 `AceTier.mark` **实例打标**
  （§4.1 铁律；`--bench=ace_tier` "Su-35 不是王牌中队"断言守住杂兵零影响）。
- **生存**：支援档热诱弹 **2 命**（`ace_support_flare.tres`；BOSS 档 4 命，命数=tier 唯一
  强度杠杆分档）+ jam 1.00 + HP 100 + 耗尽不规避。击杀序列：2 骗 → 残血 → 第 4 发死。
- **火力**：新建 `ace_gun.tres`（15 伤/1400m/1.0° 散布/600 发，每项 ≥ enemy_gun_v8）。
- **事件**：`AceReinforcementEvent`——前方扇区边缘入场 → spawn 即 `engage()` PURSUIT 锁玩家
  （无待机相）；警告横幅"敌军支援"三语 + Tab 金橙菱形标记（`active_leader()` 静态注册表）；
  **全灭 → `grant_time_extension(60)`**（game_time −60，与补给时间税同语义反方向，HUD 倒计时
  当帧 +1:00）+ 100 XP/架（AceTier.is_ace 走 F-47 档）；BOSS 解锁 → 转撤离（被打回头应战、
  出界外 800px 静默释放、无时间奖励）。
- **调度**：首支 game_time≥240s / 前支结束后 ≥150s / 540s 截止 / 同场 1 支 / BOSS 阶段不刷。
  Debug 面板加 `ACE_SUPPORT` 生成项。
- **未落**：机炮占空比 tier 分支（4.0/1.5）与 BOSS 机型换挂 ace_gun——留 wraith 批。

## ③ 战区奖励军械库（spec systems/zone-reward-arsenal）

- **奖励第四类 nextgen**（★15/★★30/★★★40）：全仓 4 条 NEXT_GEN 技能（导弹蜂群/雾隐机动/
  凝视压迫/数据链）只经战区奖励发放——fear_on_lock / data_link 补 `evolved:true` 出卡池；
  **顺带修复 missile_swarm / evasion_stealth 720 批孤儿**（此前无任何获取途径）。
  候选按可用性/stacks/跨区去重过滤（`nextgen_context` Callable 注入玩家上下文），
  空则降级 weapon；领取走 `upgrade_by_id` → 既有升级分发链（记账/里程碑与选卡一致），
  roll 后换机不可用 → 转发武器兜底。
- **武器子池 +3**：火箭弹（`a10_rocket` legacy 直挂 + `inrun_reward` meta 标记入库继承，
  回答 inrun-weapon-inventory"火箭归类"开放点：奖励火箭=特殊武器待遇、机型自带仍是底线
  武器）/ 电磁炮（`x02_railgun` equipment 泛化）/ 激光（`x02_laser`）。电磁炮/激光 ★ 区
  不出；roll 侧"已持有同类"过滤（`_ctx_owns_weapon`）+ 领取侧降级 QMAAM 兜底。
- zone-reward-docking §0"副系统限定"边界加修订指针（数值权威移交本 spec）。

## 回归

- `test_map_expansion` 全绿（parse 冒烟扩 4 文件：ace_support_squad / ace_reinforcement_event /
  survivor_player / survivor_debug_spawn + 7 区几何 + 200 局奖励 roll 去重）
- `--bench=ace_tier` 20/20
- i18n +10 key 三语（ZONE_F/G、REWARD_WEAPON_×3、EVENT_ACE_SUPPORT_×5）；`--import` 已跑

## Playtest 清单（交用户）

1. 冷场自愈：远离锚点/战区悬停 ≤1 个刷怪周期内拦截队从前方边缘压过来（Tab 可见轨迹）
2. 王牌中队：240s 首支警告横幅 → 金橙 5 机直奔 → 命数序列（2 骗/残血/第 4 发死）→
   全灭 HUD +1:00 跳变；BOSS 解锁时存活王牌撤离可追杀
3. 战区奖励：能开出电磁炮/火箭弹/激光并即领即用、换机继承；次世代技能只在战区奖励出现
   （卡池 roll 不出）
4. 压力观感：王牌 5 机 + hunter 同咬是否过压（spec §9 预案：王牌在场 hunter 配额减半）
5. 性能：Sentinel + Lv5+ + 王牌在场压测 FPS 掉幅 < 15
