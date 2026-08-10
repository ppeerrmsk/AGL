---
id: airfield-sam-network
kind: system
status: in-progress
schema_version: 1
spec_version: 2
owner: 用户（设计）+ Codex（落地）
depends_on: [airfield-liberation-zones, career-shop, friendly-asset-aggro]
reconstruction_complete: true
---

# 机场防空网（Airfield SAM Network）

> 生涯商店“战场支援”页的一次性永久授权。购入后，每一局中每座被解放的机场都会在
> 基础友军 AA×2 之外追加一座友军 SAM；它不再是局内技能，也不会进入任何升级池。

## 1. 设计意图（Why）

- **体验目标**：把机场 SAM 从随机抽到的局内卡改为明确的局外支援授权。购买一次后，之后
  每局解放机场都稳定得到 AA×2 + SAM×1，玩家可把功勋直接换成可见的战场基础设施。
- **Litmus 自检**（DESIGN_PHILOSOPHY）：
  - *信息察觉*：新增单位、导弹尾迹和远程拦截行为直接可见，不是隐藏数值。
  - *局外成长节制*：只增加一座一次性友军设施，不修改玩家基础战力，不形成数值树；价格与
    其它战场支援授权一致，正常约半局到一局可购。
  - *单杠杆*：授权只控制“每座已解放机场是否追加一座 SAM”，不强化 SAM 数值或重生能力。
  - *全自动开火*：复用既有 SAM 自动索敌与发射逻辑，不增加玩家开火按键。
- **反模式规避**：不修改敌占机场强度；不叠层；不周期重生；不新增每帧扫描；不保留同名
  局内升级卡或任何“先解放、后在本局抽卡补建”的路径。

## 2. 数据定义（What —— 全部数值，权威源）

### 2.1 生涯商店商品

| 字段 | 值 | 说明 |
|---|---|---|
| `id` | `support_airfield_sam` | MetaShop 已购集合唯一键 |
| `name` | `METASHOP_ITEM_AIRFIELD_SAM_NAME` | 三语名称 key |
| `desc` | `METASHOP_ITEM_AIRFIELD_SAM_DESC` | 三语描述 key |
| `price` | **3000 功勋** | 与 AWACS / 战区 / 王牌支援授权同价 |
| `category` | `support` | 显示在“战场支援”分页 |
| 上架条件 | 恒上架 | 不依赖 CareerArchive 战绩 |
| 购买规则 | 一次性买断、不可叠加、不可退款 | 写入 `user://meta_shop.cfg` |

### 2.2 机场友军驻防编成

| 正式局条件 | AA | SAM | 总数 |
|---|---:|---:|---:|
| 未购 `support_airfield_sam` | 2 | 0 | 2 |
| 已购 `support_airfield_sam` | 2 | 1 | 3 |

- **非正式局**（bench / boss debug）权益 fail-open，固定按已购处理，保持回归确定性。
- **敌占机场编成不变**：玩家进攻时仍面对敌方 SAM×1 + AA×2；授权只影响解放后的 ALLY 驻防。
- AA 与 SAM 复用既有场景和参数，不修改 HP、射程、伤害、射速、雷达或弹药。
- 全部驻防单位为 `TEAM_ALLY`，不受玩家 RTS 指挥，击杀敌人不给玩家 XP/功勋。
- 每座机场的 SAM 是**一次性部署**：被摧毁后本局不重生、不补建。

### 2.3 部署几何与节奏

| 单位 | 相对机场圆心偏移（px） | 解放后的部署时刻 |
|---|---|---|
| AA #1 | `(-170, 150)` | `t = 0s` |
| AA #2 | `(-170, -150)` | `t = 4s` |
| SAM（仅有授权） | `(240, 0)` | `t = 8s` |

- 部署间隔 `4.0s`；顺序固定为 **AA → AA → 可选 SAM**。
- 三座机场互相独立；固定地图自然限制为每局最多 3 座授权 SAM。

### 2.4 i18n 文案

| key | 中文 | English | 日本語 |
|---|---|---|---|
| `METASHOP_ITEM_AIRFIELD_SAM_NAME` | 机场防空网授权 | Airfield SAM Network Authorization | 飛行場SAM網許可 |
| `METASHOP_ITEM_AIRFIELD_SAM_DESC` | 每次解放机场时，在友军 AA×2 之外追加 1 座一次性 SAM | Each liberated airfield deploys one single-use SAM in addition to two allied AA guns | 飛行場を解放するたび、友軍対空砲2基に加えて使い切りのSAM1基を配備 |

## 3. 行为与公式（How）

### 3.1 机场解放时

```text
on airfield liberated(zone_id):
    entitled = MetaShop.is_airfield_sam_entitled(formal_run)
    立即部署 AA #1
    4 秒后部署 AA #2
    if entitled:
        再等 4 秒
        commit_sam_once(zone_id)
        部署 SAM
```

- 权益在该机场部署计划创建时读取；生涯商店只能在局外访问，因此正式局内不会发生购买竞态。
- 每次等待后沿用 `game_over / is_inside_tree` 守卫；场景退出则停止。
- SAM 生成前先写该机场 `sam_committed`，防止重复调用；生成失败时回滚账本。

### 3.2 生命周期与边界

| 情况 | 结果 |
|---|---|
| 未购授权进入正式局并解放机场 | 只部署 AA×2 |
| 购入授权后进入任意后续正式局 | 每座新解放机场部署 AA×2 + SAM×1 |
| 同局解放三座机场 | 三座机场各自部署一座 SAM |
| SAM 被摧毁 | 不重生；`sam_committed` 保持 true |
| bench / boss debug | fail-open，按已购授权执行 |
| 重放升级 / 切换操控机 / 僚机入队 | 不影响机场授权，不重复部署 |

## 4. 结构与组成（Structure）

- **商品真值**：`MetaShop.CATALOG` 登记 `support_airfield_sam`；`owned` 持久化是正式局唯一真值。
- **权益查询**：`MetaShop.is_airfield_sam_entitled(formal_run)` 统一正式/非正式局语义。
- **唯一消费点**：机场解放后的渐进驻防计划查询权益，决定是否追加第三个 SAM。
- **幂等账本**：按机场 id 保存 `sam_committed`；含义是“本局该机场的授权 SAM 已生成”，
  不是“当前仍有一座活 SAM”，因此战损不会触发重生。
- **友军设施牵连交战**：SAM 与两门 AA 使用同一机场 `asset_group_id` 登记到友方设施仇恨系统。
- **明确删除**：`SurvivorData.UPGRADES` 中不再存在 `airfield_sam_network`；升级分派不再处理它；
  技能实现索引与旧升级翻译 key 一并移除。

## 5. 验收标准（Acceptance / Litmus）

- [ ] `SurvivorData.upgrade_by_id("airfield_sam_network")` 返回空，普通/三轴/战区技能池均不再出现该卡。
- [ ] 生涯商店“战场支援”页显示“机场防空网授权”，恒上架、定价 3000、可永久购买。
- [ ] 正式局未购：机场解放后按 `0s AA / 4s AA` 恰好部署两门 ALLY AA，无 ALLY SAM。
- [ ] 正式局已购：每座机场按 `0s AA / 4s AA / 8s SAM` 恰好部署 AA×2 + SAM×1。
- [ ] 新开多局仍保留授权；同局三机场互相独立，每座最多一座授权 SAM。
- [ ] SAM 战损不重生；敌占机场仍为敌方 SAM×1 + AA×2。
- [ ] 授权 SAM 为 ALLY、不可指挥、击杀不给玩家 XP/功勋，并登记到对应机场资产组。
- [ ] bench / boss debug fail-open；MetaShop、机场部署和技能池定向回归通过。
- [ ] i18n 三语齐全；全部逻辑为商店/解放事件驱动，无新增每帧开销。

## 6. 实现计划（Task Pipeline）

### 阶段 1 — 规格与商品

- [x] 将本 spec 从 skill 改为 system，并同步 career-shop / airfield-liberation-zones。
- [x] MetaShop 新增永久商品、权益查询与三语商品文案。

### 阶段 2 — 移除技能并改消费点

- [x] 从 `SurvivorData.UPGRADES` 删除 `airfield_sam_network`。
- [x] 删除升级选择即时补部署分支；机场渐进部署改读 MetaShop 权益。

### 阶段 3 — 测试与索引

- [x] 改写 MetaShop / zone_rewards 断言，覆盖永久权益、技能池移除、幂等和战损。
- [ ] 同步 specs index、script/code/skill implementation index，跑定向 bench 与校验器。

## 7. 索引锚点（Where —— 落地后回填）

| 关注点 | 文件 |
|---|---|
| 商品目录 / 权益 | `scripts/meta/meta_shop.gd` |
| 机场部署 | `scripts/survivor/survivor_mode.gd` |
| 机场数据与状态 | `scripts/survivor/zone_data.gd` |
| 商店与机场回归 | `scripts/tests/test_meta_shop.gd` · `scripts/tests/test_zone_rewards.gd` |
| i18n | `i18n/gameplay.csv` |
| 相关权威规格 | `docs/specs/systems/career-shop.md` · `docs/specs/systems/airfield-liberation-zones.md` |

## 8. 变更记录

| 日期 | spec_version | 改动 |
|---|---:|---|
| 2026-08-01 | 1 | 初稿并落地：友军机场基础 AA×2；全局技能追加 SAM×1。 |
| 2026-08-02 | 2 | 用户改版：彻底移出局内技能池，改为生涯商店 3000 功勋永久授权；购入后每局每座解放机场自动追加一次性 SAM×1。 |
