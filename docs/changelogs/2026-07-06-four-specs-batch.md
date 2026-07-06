# 2026-07-06 · 四 spec 批量落地：60km 扩图 / 增援入场 / 机炮梭射 / 命令轮盘

> 上游 spec：[map-expansion](../specs/systems/map-expansion.md) /
> [reinforcement-ingress](../specs/systems/reinforcement-ingress.md) /
> [gun-burst-fire](../specs/weapons/gun-burst-fire.md) /
> [command-wheel](../specs/systems/command-wheel.md)（均 in-progress，代码主体落地）。
> 验收：`--bench=all` 回归门 **17 项 0 失败**（新增 gun_burst 9 断言）+
> `test_map_expansion.gd` 独立无头回归全绿。四者均**差 playtest**（清单见文末）。

## ① 60km 扩图 ×2 + 战区重排（commit 8b534ce）

- 世界半宽 7500→15000 px 主开关落地，出生点/相机/雷达派生量自动适配；
  用户手改 + 二次复审决定保留（编辑器整合退为后续 converter 吃现状，PNG=过渡资产）。
- 战区 ×2 外推重排；B 区初值落湾里（land_mask 占比 0.00，回归抓出）经网格扫描
  修正到市川/船桥湾岸 (6000,-11000)（占比 0.65）。任两区缘距 ≥2000 / 离边 ≥1500。
- A/D 的 ±7500 时代手画刷怪多边形作废删除，暂走散布 fallback；如需精修按
  manual-map-editing.md 对新底图重描。
- 60km 重烘焙：矢量地理 + 36MB 过渡 PNG 底图（编辑器管线接管后退役）。

## ② 增援入场（commit 2c0c551）

根治旅途刷怪双根因：镜头挪回一片敌机凭空出现（刷怪锚定玩家而非镜头）+
`ZOOM_MIN=0.2` 下"屏幕外"软约束必然失败当面刷怪。

- **边缘入场**：边界周长 16 候选采样（距玩家 ≥5000 / 不可见 / 距锚点最近），
  生成点永远在边界线外 400 px——可见性从软约束升格为结构保证。
- **中队生命周期**：TRANSIT 飞向中央锚点 → ONSTATION 绕环驻空（1400±400）→
  token 饿着且 45s 无交战时 EGRESS 物理飞离（被打回头应战），取代远距删除。
  锚点避开全部战区圆 +800（比 spec 更严：防 LOCKED 战区随后开放坐圈里）。
- **开局驻防**：t≈0 预置 2 中队 ONSTATION，开局拉镜头就有敌情。
- **离屏冻结豁免**：TRANSIT/EGRESS 位移任务不可冻（同 adds 理由，否则刷出即
  冻结原地杵）；ONSTATION 被点名交战不可冻；仅驻空闲置巡逻允许冻。
- survivor-loop §4.2 位置机制标注被取代（节奏 45→25s 仍以原表为准）。
- ⚠ 测试文件 `scripts/tests/test_map_expansion.gd` 同时覆盖 ①② 的可自动化子集
  （几何/陆地占比/BOSS 锚点/入场纯函数），跟本 commit 走。

## ③ 机炮梭射（commit 20d1da1）

- 敌我机炮从"每发 60/fire_rate 匀速滴弹"改梭射状态机：梭起始（装填
  `burst_count` 发）→ 梭内密集出弹（平均间隔 × DUTY 0.3）→ 梭间 CD（守恒推出）。
- 两条铁律：fire_rate 越高梭内越密 + 梭间越短；**平均射速严格守恒** =
  fire_rate，DPS/弹药/装填与旧版一致，零重平衡，gun_firerate 升级自动透传。
- 梭承诺：火控窗口只开一帧也打完整梭（根治"一闪只漏一发孤弹"）；lead 偏移
  每梭抽一次。硬中止：JAM/弹尽/装填/规避掐残梭；累加器一帧最多补 3 发防追帧。
- `--bench=gun_burst` 9/9：梭结构 / 600 vs 1800 发分对比 / 守恒 / 承诺 / 掐断。

## ④ 命令轮盘阶段 1-3（commit ff03048）

操作语法铁则（用户定稿）：**单点 = 只操控自机 / 轮盘 = 永远全队广播**。

- 手势层 `scripts/rts/command_wheel.gd`：按住左键 + 拖方向呼出 marking menu
  （位置=参数 / 方向=动词，0.3x 子弹时间），快速松开按普通单击回放，右键中止。
- 小队轮盘（按空地）：紧急集合 / 撤离此区（3km 圈径向散出 + 20s 禁入）/
  防守此区（3km 紧拴绳 `_tick_guard`：只打圈内、出圈停追不散阵）/ 三开关。
- 攻击轮盘（按敌机）：STANDOFF/ASSAULT（姿态差异归阶段 4，先统一铁律集火）×
  火力分配（集火/分火）× 阵型纪律开关；目标走 `commanded_target` 铁律通道。
- UI：二级面板（开关拉深选值）/ 左上取消槽 / 悬停世界范围圈 / 教程说明条
  （i18n 34 个 WHEEL_* 三语 key）/ 压暗 35% / 目标高亮；EventLogger 留痕。
- 前置修复（spec §3.8）：移动指示线只画当前操控机——旧 `formation_mode`
  宽条件致僚机误显示 + AI tick 闪烁，改判 `player_ref`（切控原子更新）。

## 待办（playtest 清单，下次进引擎一起验）

- [ ] ① 扩图节奏：一局 ≥3 战区可达性 / 旅途时长体感（spec map-expansion §5）
- [ ] ② 增援可信度：镜头拉边看中队入场 / 驻空绕环 / EGRESS 回头应战；
      Sentinel + Lv5+ 压力测试 FPS（性能验收未跑）
- [ ] ③ 梭射手感：600 / 1500 / 3000 发分三档听感 + 观感（spec gun-burst-fire §5）
- [ ] ④ 轮盘全手势路径：呼出/回放/中止/二级面板/范围圈；防守拴绳实战；
      formation-discipline（draft）依赖的阵型纪律开关联动
- [ ] 全部通过后各 spec 补 §7 锚点 + §8 变更记录 → status: done

---

另：`formation-discipline.md`（阵型纪律与齐射）为纯 draft spec 同批入库，
零代码，待 review 定稿后按 §6 派生（依赖 command-wheel 阶段 4 姿态差异）。
