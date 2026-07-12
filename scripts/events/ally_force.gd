class_name AllyForce
extends RefCounted

## ALLY 第三方友军通用转换（spec global-awareness-roe §2.6）
##
## 用法：先经既有生成管线（spawner._create_enemy / _spawn_ground 同款）拿到接线完整的
## 单位，再调 convert_* 翻阵营。通用规则由此单点保证：
##   team = ALLY(2)（IFF：与玩家互不敌对互不误伤；击杀 0 XP —— _detect_kills 只认 HOSTILE）
##   不占 token / 不计敌实例（token 账本只扫 HOSTILE）
##   不被 hunter / 磁吸航点 / 边界纪律 / 远距清理 / LOD 冻结接管（director 循环只扫 HOSTILE）
##   不可操控（RTS 选择 / 攻击目标池只认 TEAM_HOSTILE）
##   色板：机体转 FactionPalette 海绿（强调色三分支由 GameConstants 按 team 自动走）


## 飞机版：翻阵营 + 打 meta + 机体换 ALLY 色
static func convert_aircraft(ac: Aircraft) -> void:
	if ac == null or not is_instance_valid(ac):
		return
	ac.team = CombatUnit.TEAM_ALLY
	ac.set_meta("category", "ally")
	ac.set_meta("token_cost", 0)
	ac.set_meta("skip_far_cleanup", true)
	if ac.params:
		ac.params.icon_color = GameConstants.COL_FRIEND_ALLY
		ac.params.wing_color = Color(0.20, 0.50, 0.42)


## 地面版（SAM / AA 等）：翻阵营 + 打 meta（本体绘制/标签色经 FactionPalette 按 team 三分支）
static func convert_ground(gu: Node) -> void:
	if gu == null or not is_instance_valid(gu):
		return
	if "team" in gu:
		gu.team = CombatUnit.TEAM_ALLY
	gu.set_meta("category", "ally")
	gu.set_meta("token_cost", 0)
	gu.set_meta("skip_far_cleanup", true)
