# 2026-08-04 战区奖励、四级技能与炮艇模式收口

> 提交主题：`feat: finalize zone rewards and harden gunship skills`
>
> 范围：战区奖励表、四级技能、ESM/海军防空、动态阵营转换、机型专属技能、debug 直达、炮艇模式实机修复、文档维护与回归测试。

## 1. 用户裁定与数据口径

- 战区奖励与技能表去除星号标记。
- “王牌等级 +1”只增加王牌等级，不再附带战斗等级 +1。
- 删除不存在的“穿透弹头”，保留“连锁弹头”；连锁弹头承担命中后继续直穿的功能。
- 航母保底改为第四次。
- ESM 半径参考 Sentinel 范围；文案中的 CD 统一解释为 reload 时间缩短。
- X-44 专属技能改为正面 180°、不可叠加；普通机炮子弹获得单位穿透，CIWS 明确排除。
- 炮艇模式 fantasy 定稿为玩家全队独立的 360° 自动炮塔：当前机和 AI 僚机均可自动攻击射程内 Aircraft / GroundUnit。

权威规格集中在：

- `docs/specs/systems/zone-reward-arsenal.md`
- `docs/specs/skills/gunship-mode.md`
- `docs/specs/skills/heavy-gun.md`
- `docs/specs/skills/hunter.md`
- `docs/specs/skills/flee.md`
- `docs/specs/skills/invasion-algorithm.md`
- `docs/specs/weapons/esm-pod.md`
- `docs/specs/systems/dynamic-faction-conversion.md`

## 2. 战区奖励、装备与技能实现

- 战区奖励池、第四级技能和相关 i18n 文案完成数据化，并同步自动生成的技能表。
- 新增 ESM 吊舱资源与装备逻辑，统一作用于主导弹、次级导弹和机炮 reload 计时。
- 新增海军小口径防空挂点与舰载火控消费点。
- 连锁弹头改为发射时快照；命中后关闭制导、继续直飞，并按单枚导弹记录已穿透目标，避免同目标重复伤害。
- X-44 普通机炮穿透同样按出膛快照；CIWS 子弹不继承穿透。
- 激光黑客、投降和换阵营流程收敛到 `FactionTransition`，补齐新友军的生命周期与火控重绑。
- 相关升级继续通过现有全队/品类/王牌归属分发，不在共享层引入模式判断。

## 3. Debug 直达契约

- F4 技能调试动态覆盖完整技能表，强制授予只受技能自身层数上限约束。
- F4 可直接装载 ESM 等门控装备，不要求先走正常卡池前置。
- F6 覆盖全部战区奖励，并为炮艇模式、重炮、连锁弹头、ESM 等保留明确入口。
- `skill_audit` 把 F4/F6 覆盖度作为硬断言；以后更新技能表或奖励表时，未同步 debug 会直接红灯。

## 4. 闪退与 TypedArray 修复

实机错误集中在阵营转换和小队清理：

- `FactionTransition` 以 `CombatUnit` 静态类型直接传入 `Array[Aircraft].erase()`，Godot 4.7 会在运行时拒绝类型不匹配并连续刷错。
- 小队 successor 强类型数组中残留已释放实例时，直接赋给 `Aircraft` 局部变量会在有效性检查前报错。

修复方式：

- 跨继承层操作 TypedArray 前先验证并收窄为 `Aircraft`。
- 从可能包含 freed object 的容器取值时先以 Variant 接住，`is_instance_valid()` 后再 cast。
- 新增 `faction_conversion` 行为测试，真实执行黑客状态跃迁，不再只检查技能注册和字段存在。

该耦合已登记为 `docs/architecture/known-seams.md` 的 SEAM-029。

## 5. 炮艇模式三轮实机根治

### 5.1 对地目标未进入扫描池

初版自动机炮只扫描 Aircraft。炮艇模式现在显式把 GroundUnit 纳入候选，普通固定机炮仍只做原有对空扫描；锁定免疫、友军、已毁和射程外目标继续过滤。

### 5.2 侧后目标却从正面出弹

根因是 3Hz 扫描写入的 lead 会被 60Hz 战术计划回写为机头方向；梭射只锁弹数、不锁对象，炮口出生点也固定取机体 heading。修复后：

- 扫描和梭射分别保存目标 instance id。
- 整梭承诺同一目标，每个武器 tick 重算提前点。
- 炮艇炮口和双管横轴随实际射向旋转。
- CIWS 改为独立 5° 正面防御锥，并以 `CIWS_FIRE` 与普通 `GUN_BURST` 日志分流。

### 5.3 四机有弹却无人扫地

`combat_log_20260804_220856.txt` 显示炮艇已获得、玩家有四架 F-14、场上有 18 个 GroundUnit，但没有对应的对地自动机炮事件。最终确认有四层静默门：

1. AI 僚机因 `use_tactical_preference == false` 提前退出扫描。
2. planner 的现有 `combat_target` 把扫描池锁死为远处空中目标。
3. planner 选择 MISSILE 主武器模式时，普通机炮纪律会把炮艇一起静默。
4. 编队 LOD0/1/2 在武器主循环前提前返回，只更新编队导弹，根本没有调用机炮。

现在炮艇使用独立被动炮塔入口：无攻击命令、无战术开火许可、主武器为 MISSILE、编队跟随或屏外 LOD 时均继续工作；每次 3Hz 扫描选择最近合法 Aircraft / GroundUnit。普通机炮纪律不变。

该类“慢频率选择、快频率消费、主循环提前返回”的组合陷阱已登记为 SEAM-030。

## 6. 文档与索引维护

- 新增 `docs/README.md`，明确 specs / systems / reference / planning / changelogs / audits / handoffs 分层。
- 扩展 spec 模板和总索引的一致性检查。
- 更新 script index、code index、资源目录、技能实现索引和自动技能表。
- 新增 `tools/verify_docs.ps1`，校验当前文档断链、spec 登记、front matter 和总表状态。
- 强化 `tools/verify_doc_anchors.py` 的符号锚点校验与机械刷新能力。
- `bench/results/` 明确加入 `.gitignore`；bench 数字只在 changelog 中记录，不上传运行产物。

## 7. 本批验证证据

- `weapon`：28/28。覆盖炮艇对地扫描、侧射弹道/炮口、整梭锁存、CIWS 隔离、AI 僚机、MISSILE 模式、四机对地齐射，以及五个编队/屏外 LOD 主循环入口。
- `skill_audit`：166/166。覆盖 152 条升级以及 F4/F6 debug 可达性。
- `gun_aim`：6/6。普通固定机炮仍受机头锥约束。
- `surface_pass`：32/32。常规对地机炮、导弹 standoff、姿态和 AA 警觉流程无回归。
- `naval_formation`：10/10。
- `stress_40`：Godot 4.7.1 headless 运行 20 秒，32 架飞机存活，无 SCRIPT ERROR；末秒武器桶约 10 μs/frame。
- `tools/verify_docs.ps1`：通过。
- `git diff --check`：通过。

Godot 退出时仍可能出现 Windows 根证书读取警告和少量 CanvasItem/ObjectDB 退出泄漏警告；本批未观察到对应运行时脚本错误或压力场闪退。

## 8. 后续修改的硬检查

更新技能表、战区奖励或机型专属技能时，必须同时确认：

1. spec 与数值表已更新。
2. 正常分发路径能把效果下发到正确所有者。
3. 真实消费点执行过状态跃迁，而不是只检查字段存在。
4. F4/F6 能直接调出并复现该功能。
5. 编队、LOD、MISSILE/GUN 模式与已有目标不会意外吞掉独立武器通道。
6. 跑对应专项 bench，并至少保留一条普通行为对照。
