# 2026-08-08 玩家仪表 HUD

## 范围

- 以固定左上锚点的模块化仪表替换生存模式旧 TACTICS 与玩家状态栏。
- 显示 HP/G、高度偏好、速度单位、加力、自动接敌/开火、热诱弹、主动特殊机动充能和武器优先状态。
- 僚机信息改为随存活数量增减的独立行；经验条上方加入固定 400×18 三轴进度计数器。
- 主菜单 Audio 旁加入 kt/km/h 切换与 HUD 线框色设置。
- 热诱弹资源逻辑不变；一次资源释放仍保持原六波节奏，但视觉粒子严格为 10 枚并与十个星号同步。

## 输入

- `Q`：切换爬升优先 / 低空优先。
- `E`：沿用加力。
- `G`：切换自动接敌。
- `F`：切换自动开火。
- `T`：切换武器优先，并自动跳过不存在的基础武器。

## 验证

- `bench/run.cmd player_hud 1 180 Shadow`：80/80。
- `bench/run.cmd squad_cmd_ui 1 180 Shadow`：26/26。
- `bench/run.cmd attr_gates 1 180 Shadow`：138/138。
- `bench/run.cmd player_hud_visual 1 180 Shadow Visual`：OpenGL 渲染与截图成功。
- `tools/verify_player_ref_holders.py`、`tools/verify_doc_anchors.py`、`tools/verify_docs.ps1` 通过。

## 明确排除

本次提交不包含战场气氛、地图视觉、敌机、平衡性或其他进行中的玩法改动。
