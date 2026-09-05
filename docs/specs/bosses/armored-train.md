---
id: armored-train
kind: boss
status: in-progress
schema_version: 1
spec_version: 12
owner: user
depends_on: [systems/desert-theater, systems/boss-hunter-doctrine, systems/tier-3-zone-global-threats]
reconstruction_complete: true
---

# 超级武器列车 BOSS

> 一列严格沿沙漠底图真实矿区铁路行驶的十四节超尺度武装列车。玩家只能从车尾开始逐节打断；每次断节都会关闭该车厢功能、缩短编组，并令剩余列车加速。

## 1. 设计意图（Why）

- **体验目标**：读起来首先是一列真实相连、能在弯道活动的武装列车，其次才是超级兵器；不能再是一串横向宽板组成的移动块。
- **战斗解法**：顺序装甲把十四节编组变成“从尾到头剥洋葱”的长度战；当前尾段是唯一合法目标，断节同时改变敌方火力与追击时间窗。
- **地图身份**：Boss 路线必须贴合沙漠正式底图横贯战区、玩家截图中最醒目的金色双线铁路走廊。`railway` 字段名称或另一条细灰支线都不是证据，Visual 必须验证车轮实际压在玩家所见主线上。
- **造型边界**：车体长轴沿铁路切线；每节宽度显著小于长度，节间保留车钩和清楚的活动空隙。禁止停机甲板、舰载机、超宽设备平台和陆地航母语汇。
- **包装边栏**：固定英文标语为 `Seven sticks of dynamite`；三语环境均保持原文，不翻译、不改大小写。
- **Litmus 自检**：十四段不同功能、尾段递进弱点、断节加速与移动电磁炮 AOE 都直接改变打法；拿掉这些机制后不再只是高 HP 地面单位。

## 2. 数据定义（What）

### 2.1 编组总览

| 字段 | 值 | 说明 |
|---|---:|---|
| Boss id | `ARMORED_TRAIN` | 沙漠正式 Boss 池之一；与 `THE_CRUCIBLE` 等权随机 |
| 战术名 | `SUPERWEAPON TRAIN` | 菜单/Boss 身份；各节世界状态栏用独立英文名 |
| 总 HP | 1800 | 十四段 HP 之和；Boss HUD 只做汇总，不存在共享伤害池 |
| 模块数 | 14 | 固定，不可缩回七节或扩成十五节 |
| 单节几何 | 236×84 px | 纵向长度×横向宽度；长度与宽度均为 v7 的 2 倍，长宽比 2.81:1 |
| 节间空隙 | 18 px | 内含跨段活动车钩；弯道逐节独立采样航向 |
| 总视觉长度 | 3538 px | 十四节车体 + 十三个车钩间隙，约为 v7 整列的 3.79 倍 |
| 初速 | 420 km/h | 超级兵器抽象速度 |
| 断节加速 | +60 km/h/节 | 每断一节立即作用于全部剩余编组 |
| 最高速度 | 1200 km/h | 十三次断节后只剩车头时达到 |
| XP | 0 | Boss 胜利结算，不重复发普通击杀 XP |
| Boss 音乐 | `Midnight March` | 规范化 id `boss_midnight_march`；素材缺失时回退既有 `boss` 曲 |

### 2.2 十四节主题（前 → 后）

| # | 英文状态栏名 | HP | 可见主题 | 存活功能 | 打断结果 |
|---:|---|---:|---|---|---|
| 1 | `ARMORED LOCOMOTIVE` | 240 | 斜切装甲车鼻、驾驶窗、双动力栅 | 驱动/逃脱主体 | 最后打断，整列击毁并胜利 |
| 2 | `DRIVE TENDER` | 170 | 辅助动力舱、纵向冷却管 | 编组动力冗余 | 打断并触发下一档加速 |
| 3 | `RAILGUN CAR` | 170 | 双轨长炮管与电容舱 | 移动直线 AOE 电磁炮 | 立刻取消预警/弹迹，永久停炮 |
| 4 | `VLS ALPHA` | 130 | 前组 2×4 发射井阵列 | 1 个远程 VLS/SAM 挂点 | 所属挂点退场 |
| 5 | `VLS BRAVO` | 130 | 后组错位发射井阵列 | 1 个远程 VLS/SAM 挂点 | 所属挂点退场 |
| 6 | `COMMAND RADAR` | 130 | 指挥舱、桅杆、大型雷达盘 | 电磁炮 44,000px 远距火控 | 电磁炮最大射程降至 14,000px |
| 7 | `FIRE CONTROL` | 110 | 双小型火控盘、测距阵列 | 武器指挥主题段 | 打断并暴露前段 |
| 8 | `FLAK ALPHA` | 110 | 前双联空爆炮塔 | 1 个空爆炮挂点 | 所属挂点退场 |
| 9 | `FLAK BRAVO` | 100 | 后双联空爆炮塔 | 1 个空爆炮挂点 | 所属挂点退场 |
| 10 | `CIWS ALPHA` | 100 | 前旋转近防炮与传感器 | 1 个 CIWS 挂点 | 所属挂点退场 |
| 11 | `CIWS BRAVO` | 90 | 后旋转近防炮与传感器 | 1 个 CIWS 挂点 | 所属挂点退场 |
| 12 | `ARMORED MAGAZINE` | 90 | 加固弹药舱、爆炸隔舱 | 装甲缓冲段 | 打断并暴露前段 |
| 13 | `TAIL BATTERY` | 90 | 后向空爆炮位 | 1 个尾部空爆炮挂点 | 所属挂点退场 |
| 14 | `REAR GUARD` | 140 | 后向装甲尾楔与尾炮 | 1 个尾部空爆炮挂点；初始唯一弱点 | 尾炮退场，第 13 节暴露 |

HP 总和仍固定为 `1800`，不因视觉体量增大而翻倍。每节都是直接进入 `CombatUnit.all_units` 的正式 `GroundUnit`，玩家的雷达、锁定、导弹、机炮、火箭、电磁炮与激光都命中真实分段目标，而不是点击整列共享假碰撞体。

### 2.3 路线 SSOT

路线唯一权威为沙漠 MapDocument 的 `railways[id=iron_serpent_main]`。该折线由正式 `desert` strategic 底图上横贯战区的醒目金色双线中心线描摹，声明 `source=desert_basemap_primary_rail_corridor` 与 `strategic_lod_max_error_px=3`；像素点必须通过 `desert_railway_bg_v2.json` 的经纬度 bbox 换算为世界坐标，禁止假定底图就是 `-16000..16000`。路线从西侧场外进入，在 Newman 城区前收束。底图另有细灰矿区支线，但它不是本 Boss 的玩家可读主路线。

禁止用道路折线、镜像道路或手写对角线冒充铁路。地图数据与正式底图同时变化时，先重新描摹并做叠图 QA，再更新路线；测试仅证明数学贴合 MapDocument，不能替代底图 Visual。

## 3. 行为与公式（How）

### 3.1 尾段递进伤害门

```text
active_tail = 13                      # 初始 REAR GUARD
targetable(i) = engaged and not destroyed(i) and i <= active_tail
can_accept_new_hit(i) = targetable(i) and (i == active_tail)
is_lock_immune(i) = not targetable(i)

on_break(active_tail):
    disable_function(active_tail)
    active_tail -= 1
    speed_kmh = min(420 + broken_count × 60, 1200)
    make_breakable(active_tail)
```

- 接战后所有存活车厢均为独立 `TGT`，可被雷达发现、锁定与查看，视觉上全部保持暴露；只有当前最后一节为可打断弱点。
- 非尾节即使被锁定，仍在 `can_accept_new_hit` 与 `take_damage/take_missile_damage/take_atmosphere_damage` 两层拒伤，防止机炮、导弹、AOE 或遗漏命中源绕过顺序门。
- 导弹对暴露段按实际伤害扣 HP，不继承普通 `GroundUnit` 的软目标一发必杀。
- 断节当帧调用目标引用释放、关闭该节挂点/电磁炮；断节不再接受铁路姿态注入，以断开瞬间的向前惯性、侧向偏移与旋转脱离编组。紧邻前段转为新的可打断尾节，整个剩余编组立即 +60 km/h。
- Boss HUD 显示十四段剩余 HP 汇总和当前可打断尾节；世界中常态只显示当前可打断节、悬停节或当前锁定节的状态栏，避免十四块标签堆叠。尾节显示 `BREAKABLE`，其他存活节显示 `LINKED ARMOR` 并指向当前需要先打断的节号。

### 3.2 铁路运动与活动车钩

车头按铁路弧长前进；第 `i` 节以 `head_distance - i×254px` 为弧长中心。236px 长车厢禁止继续使用“中心单点切线”定姿：每节在中心前后各 `88px` 采样一个转向架落轨点，车体中心取两点中点，航向取后转向架指向前转向架的弦向。这样弯道上前后轮组始终压住 railway，车体以真实长刚体自然内弦，避免折线拐点处整节横移脱轨。车钩仍由编组控制器连接相邻车体端点并保留 18px 活动空间。

```text
distance_step_px = (speed_kmh / 3.6) × 0.5 × delta
tail_rear_offset_px = active_tail × 254 + 118
escape_distance_px = railway_polyline_px + tail_rear_offset_px
route_progress = traveled_px / escape_distance_px
```

断节后 `active_tail` 变小，列车既更短又更快；只在当前最后一节的尾端完全越过路线终点时逃脱失败。击毁与逃脱同帧时，最后车头击毁优先，不能双结算。

### 3.3 移动电磁炮 AOE

电磁炮沿用海岸线 `AURORA LANCE` 的核心承诺，不做无预警 hitscan：

| 字段 | 值 |
|---|---:|
| 最近射程 | 2,500 px |
| 雷达车存活最大射程 | 44,000 px |
| 雷达车打断后最大射程 | 14,000 px |
| 转速 / 对准容差 | 12°/s / ±3° |
| 侧舷射界 | 左右侧各 ±50°；车头/车尾锥区不可锁定 |
| 目标锁定 | 对准后持续锁定 1.0s；目标离开侧舷射界则重置 |
| 预警 | 4.0s 从 4px 填宽到 180px + 1.5s 满宽闪烁 |
| AOE | 90px 半径 / 180px 全宽的直线危险带 |
| 伤害 | 45 |
| 冷却 | 首发 5s；后续 14s |
| 弹迹 | 12,000px/s，仅负责表现，不重复伤害 |

电磁炮是侧舷武器：以炮车当前铁路切线为纵轴，只能在左舷或右舷扇区选取目标，不能朝车头或车尾射击。炮塔对准目标后先进入 1.0s `LOCKING`；锁定完成才锁存该侧的世界起终点并进入 `CHARGING`。列车继续移动不拖动已承诺危险带。蓄力结束同拍扫描带内全部存活玩家小队飞机并各结算一次 `aoe` 伤害。电磁炮段打断时，无论处于锁定、蓄力还是弹迹阶段都立即清空并停止。

### 3.4 进场演出

`armored_train_arrival` 保留系统入侵身份横幅；横幅完全退场后才播放列车主体镜头。列车在 `PRE_STAGE` 生成后立即进入专用进场态：切镜前十四节已经完整位于地图西侧正式 railway 上，随后沿轨继续前进，速度由 330 km/h 平滑提升到正式接战初速 420 km/h。镜头以第 7 节 `FIRE CONTROL` 作为十四节编组中部的稳定演员持续跟随，0.26 广角必须让首尾车厢及安全边距同时落在视口内；世界边界进场 inset 固定为 420 px，使 0.26 镜头下车节中心至少保留约 180 屏幕 px 安全区。画面必须保留铁路，禁止 `stage.clear` 把地图压暗成空舞台。

进场期间全体分段不可锁定/受伤，挂点与电磁炮不工作；只有编组控制器在硬暂停下以 `PROCESS_MODE_ALWAYS` 继续推进铁路弧长。镜头归还玩家、解除暂停并 `actor.release` 后，`sequence_finished` 触发 `BossEncounterEvent._enter_engaged()`；`ArmoredTrainBoss.engage()` 必须保证整列尾端已经进入正式世界边界，再暴露第 14 节并恢复正常 420 km/h 战斗运动。缺序列、演员失效或演出被覆盖时仍 fail-open 接战，但同样先把整列推进到“完整入图”距离，不能让玩家在场外开打。

### 3.5 终态

| 状态 | 进入 | 行为 | 退出 |
|---|---|---|---|
| `INBOUND` | BossEncounterEvent 生成 | 十四节已完整位于地图西侧铁路并沿轨加速 | 接战后 `RUNNING` |
| `RUNNING` | 横幅收尾 | 贴轨运动、尾段递进伤害、剩余武器自动作战 | 车头打断 → `DESTROYED`；当前车尾越过终点 → `ESCAPED` |
| `DESTROYED` | 第 1 节 HP=0 | 清理全部段/挂点/锁定引用，BossEncounterEvent 胜利 | 胜利结算 |
| `ESCAPED` | 当前车尾完整驶离 | 失败优先于 active 下降胜利沿 | Game Over |

## 4. 结构与组成（Structure）

- `ArmoredTrainUnit extends Node2D`：铁路弧长、十四段双转向架姿态、车钩、暴露段、加速、功能账本、电磁炮 AOE 与逃脱 signal。
- `ArmoredTrainSegment extends GroundUnit`：每节真实锁定/HP/伤害/销毁目标与主题矢量绘制；可锁定层与可承伤层独立，断节有独立惯性脱离。
- `ArmoredTrainBoss extends BossEncounter`：spawn、十四段显示成员、汇总 Boss HUD、失败优先级。
- 既有 `Tier3SiegeCIWS/SAM/Flak`：按车厢 owner 绑定真实挂点，车厢终态自动退场。
- `BossEncounterEvent`：通用 custom spawn；逃脱失败在胜利检测前分流。
- `BossRegistry` / Boss Debug：沙漠固定池与直接验收入口。

## 5. 验收标准（Acceptance / Litmus）

- [x] 正式沙漠倒计时结束若抽中列车分支，只生成 `ARMORED_TRAIN`；同池允许等权抽中 `THE_CRUCIBLE`。
- [x] 十四节固定且一眼可辨；每节 236×84px、整列 3538px，单节长宽均为 v7 的两倍。
- [x] 相邻车节之间始终保留可见车钩/活动空隙；弯道上每节由前后转向架双点定姿，两组轮严格贴轨且车体转向连续自然。
- [x] 底图叠图确认整列转向架压在玩家截图所指的金色双线主铁路上；strategic/operational/detail 与正式游戏镜头均不能改走上方细灰支线或荒地。
- [x] 接战后 14 节存活车厢全部可锁定且视觉暴露；只有当前最后一节可伤害/打断，中前段即使锁定，盲射/AOE/导弹仍不掉血。
- [x] 尾节打断后以惯性向外脱离编组，该段武器/雷达/电磁炮功能当帧消失，紧邻前段转为新的可打断尾节，整车速度每节 +60 km/h，十三次后达到 1200 km/h。
- [x] 电磁炮仅向左右侧舷各 ±50° 选取目标，车头/车尾目标不进入锁定；对准后锁定 1.0s，随后才开始 4.0s 填宽 + 1.5s 闪烁蓄力。
- [x] 电磁炮保持 90px 半径、45 伤害；带内多机同拍受伤，带外不受伤；打断炮车立即取消。
- [x] `armored_train_arrival` 在横幅退场后切到编组中部并持续跟随；使用 ≤0.30 广角让首尾及安全边距完整入画，列车仍从 330→420 km/h 加速驶入且铁路可见。
- [x] 切镜前整列尾端已经进入正式边界；演出期间十四节均不可锁定/受伤，挂点与电磁炮不得提前开火。
- [x] 十四段总 HP 仍为 1800，Boss HUD 汇总不制造共享伤害池；状态明确显示当前可打断尾节与剩余段数。
- [x] 第 1 节最后打断触发胜利；当前车尾完整驶离且仍存活触发 Game Over；不双结算。
- [x] 生命周期 focused 走真实 SceneTree：断节后至少继续一帧并跨下一次单位缓存刷新，断言旧锁定引用清空、挂点退场、下一段已暴露；整列终态同样越过 deferred free。
- [x] 性能：十四段 + 八挂点仍为该 Boss 的固定 O(1) 成本；v12 Visual 有效样本 120 帧平均 8.33ms、P95 8.33ms、低于 60 FPS 的帧为 0。
- [x] 列车 focused、导演 focused 与真实 Visual 构图通过。
- [x] 全量 runtime error gate 与 i18n 已恢复；91 项测试、真实 lifecycle gauntlet 全部通过。

### 5.1 证据记录

| 等级 | 场景 / 命令 / 产物 | 结论 |
|---|---|---|
| E0 静态 | spec / route overlay / index / docs | 路线按底图真实 bbox 重投影；docs、anchors、player-ref 与 diff 校验通过 |
| E1 聚焦 Shadow | `armored_train` / `presentation` | v12 列车 32/32；接战后 14 节全可锁定/恰好 1 节可承伤、尾节惯性脱离、新尾节可打断与整车 +60km/h 通过；十四节 / 236×84px / 3538px、28 个转向架采样点最大贴轨误差 0.001px。导演 296/296；0.26 广角、横幅后切镜、编组中部持续跟随、保留铁路、回镜再释放通过。 |
| E2 集成 / 压力 Shadow | `lifecycle_gauntlet` / `all` | v11 lifecycle 86/86；断节同拍脱离、旧目标引用释放、挂点 deferred free 与下一缓存 tick 通过。全量 91/91，runtime error gate 退出码 0。 |
| E3 Visual / 性能 | `boss_debug_armored_train_arrival.png` / `boss_debug_armored_train_desert.png`；`boss_debug_select_visual` | v12 真实进场确认 `state_ready=true`、`cine_target=第7节`、`all_in_frame=true`、zoom 0.26、铁路保留且 ingress 激活；到场门等待真实演员、镜头与 canvas 边界状态，不依赖固定帧数。列车段 120 帧 avg/P95 8.33ms、below60 0，组合 Visual 退出码 0。 |
| E4 完整局 | 沙漠正式局 | 待用户验收 |

## 6. 实现计划（Task Pipeline）

### 阶段 1 — 路线与编组
- [x] 从正式 strategic 底图描摹玩家实际可读的金色双线主铁路并写回 MapDocument railway SSOT；首轮细灰支线候选经游戏截图否决。
- [x] 把旧宽板共享本体重构为十四个细长真实 GroundUnit + 活动车钩。

### 阶段 2 — 分段战斗
- [x] 实现全车可锁定、尾段唯一可打断弱点、双层拒伤、断节惯性脱离、逐段功能退场、长度缩短与整车加速。
- [x] Boss HUD 改为十四段 HP 汇总 + 当前暴露段，不再显示共享单体 HP。

### 阶段 3 — 电磁炮
- [x] 接入海岸巨炮同款预警/AOE/弹迹承诺；雷达车与炮车分别控制射程/存活。

### 阶段 4 — 回归与 Visual
- [x] 扩展 focused 与 lifecycle gauntlet。
- [x] 跑 Visual 贴轨/弯折/十四主题、电磁炮行为、全量与性能门。

### 阶段 5 — 十四节超尺度改造
- [x] 编组扩到十四节、单节延长到 236px，并保持总 HP 1800。
- [x] 用前后转向架双点定姿替换中心单点切线，补贴轨误差回归。
- [x] 进场镜头改为十四节广角，并重跑 focused / lifecycle / Visual / 性能门。

## 7. 索引锚点（Where）

| 关注点 | 文件 |
|---|---|
| 编组/路线/加速/电磁炮 | `scripts/survivor/armored_train_unit.gd` |
| 分段目标/主题绘制/拒伤 | `scripts/survivor/armored_train_segment.gd` |
| Encounter / HUD | `scripts/survivor/armored_train_boss.gd` |
| 地图铁路 SSOT | `resources/maps/desert_railway_preview.aglmap` |
| 注册与 Debug | `scripts/survivor/boss_registry.gd` · `scripts/survivor/boss_debug_select.gd` |
| 事件分流 | `scripts/events/boss_encounter_event.gd` |
| 失败结算 | `scripts/survivor/survivor_mode.gd` |
| 聚焦回归 | `scripts/tests/test_armored_train.gd` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---:|---|
| 2026-08-30 | 1 | 把火车从旧关卡机制候选提升为沙漠固定 BOSS；锁定未击毁逃脱失败。 |
| 2026-08-30 | 2 | 首轮 Visual 后尝试 15 节、宽版重装平台与地图 railway 数据；该方案随后被用户否决。 |
| 2026-08-30 | 3 | 列车与陆地航母拆为两个单位，删除列车停机/舰载机语义。 |
| 2026-08-30 | 4 | 固定包装边栏 `Seven sticks of dynamite`。 |
| 2026-08-30 | 5 | 用户否决 15 节横向宽板与伪铁路路线：重构为七节 118×42px 细长真实目标、18px 活动车钩、尾到头逐段破坏、每段功能退场、断节 +60km/h；首轮细灰支线经游戏截图再次否决，最终路线改为玩家截图所指的正式底图金色双线主走廊；第 2 节加入海岸巨炮同款 90px 半径/45 伤害移动电磁炮 AOE。 |
| 2026-08-31 | 6 | 电磁炮改为左右侧舷武器：两侧各 ±50° 射界，禁止向车头/车尾锁定；炮塔对准后持续锁定 1.0s，锁定完成才锁存射线并开始蓄力。 |
| 2026-08-31 | 7 | 新增正式进场：身份横幅结束后镜头持续跟随车头，编组在 PRE_STAGE 硬暂停下仍沿铁路以 330→420 km/h 轻度加速驶入；接战前强制保证整列完整进入地图，进场期间关闭受伤与全部武器。 |
| 2026-08-31 | 8 | 按用户反馈把编组扩为十四节、单节长度翻倍至 236px、整列增至 3538px；总 HP 仍为 1800，断节仍每次 +60km/h。长车厢姿态改为前后转向架双点采样，进场镜头改用 ≤0.30 广角适配整体尺度。 |
| 2026-08-31 | 9 | 按截图反馈把车宽从 42px 加倍至 84px，并同步车鼻、动力舱、VLS、雷达、炮塔与弹药舱横向构图；进场起点改为整列已完整位于地图西侧铁路，镜头从车头改跟第 7 节编组中部，Visual 新增十四节首尾含安全边距完整入画门。 |
| 2026-08-31 | 10 | 沙漠 Boss 池加入 The Crucible 并与列车等权随机；列车 Boss 音乐改用 Midnight March 槽位，资源缺失时回退既有 Boss 曲。 |
| 2026-09-01 | 11 | 接战后改为十四节全部可发现/锁定且视觉暴露，但只有当前尾节可承伤；尾节打断后以惯性侧向旋出编组，新尾节转为可打断状态并让剩余整车 +60 km/h。 |
| 2026-09-04 | 12 | 修正 0.26 广角进场构图：边界 inset 从 32px 提升到 420px；Visual 不再按固定帧截图，而是等待 14 节、真实跟随演员、实际 zoom、ingress 与 180 屏幕 px 安全区同时就绪。 |
