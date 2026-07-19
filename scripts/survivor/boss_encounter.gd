## BOSS 战基类 —— 所有 BOSS Encounter 的通用接口
##
## 飞机类 BOSS (AceSquad 及其子类) 和舰队类 BOSS (未来 CarrierStrikeGroup) 都继承这个。
## BossRegistry 按当前地图从池子里 pick 一个 BossEncounter 子类实例化后，
## 由 SurvivorSpawner 注入依赖 + 调 spawn()。
##
## 子类契约：
##   - 覆盖 spawn(...) —— 生成实际敌人单位（签名由子类定义，spawner 按类型调用）
##   - 覆盖 update(delta) —— 每帧推进 encounter 状态（角色分配 / 二阶段触发等）
##   - 覆盖 get_display_members() —— 返回 HUD BOSS 面板要显示的单位列表
##   - 设置 active = false 时代表 encounter 完结（胜利判定依据）
class_name BossEncounter
extends RefCounted

# ── 身份 / 音乐 ──
var boss_id: String = ""                  ## BossRegistry.BOSS_DEFS 的 key；由 instantiate 印上。
                                          ## 供按 BOSS 查表的下游系统用（无线电台词序列等）
var display_name: String = "BOSS"         ## HUD 标题（可直接塞 tr key）
var callsign_prefix: String = "BOSS"      ## 成员呼号前缀（HUD 阵亡显示 / EventLogger）
var bgm_track: String = "boss"            ## AudioManager music id；spawn 时切歌
var bgm_layers: Array[String] = []        ## 非空 = 层叠 BGM 模式（多轨同步，按音量切层），忽略 bgm_track
var bgm_playlist: Array[String] = []      ## 非空 = 顺序播放列表（首曲完接下一首，列表循环），优先级高于 layers/track
var initial_heading_deg: float = 90.0     ## 出场朝向（度，0=北）；由 ZoneData.boss_heading_deg 决定

# ── 运行时状态 ──
var active: bool = false                  ## false = encounter 结束（全灭或未激活）
## true 时 HUD BOSS 血条面板显示。预驻 / 巡逻阶段为 false，玩家真正进入战斗才亮血条
var hud_visible: bool = false

## encounter 是否已结束（胜利判定：曾 active → 变 inactive）
func is_defeated() -> bool:
	return not active

## 每帧推进（active 期间由 SurvivorSpawner.update 调用）
func update(_delta: float) -> void:
	pass

## 玩家正式与 BOSS 接战（boss_encounter_event 从 PRE_STAGE 切到 ENGAGED 时调用）
## 子类可覆盖以触发"接战瞬间"行为（例：CSG 弹射 F/A-18 / AceSquad 进 PURSUIT）
func engage() -> void:
	pass

## HUD BOSS 面板显示的成员列表
## 飞机 BOSS：返回 Aircraft 数组（含已击毁，HUD 显示 DOWN）
## 舰队 BOSS：返回 NavalUnit 数组（旗舰 + 关键护航）
func get_display_members() -> Array:
	return []

## 当前激活的飞机小队（用于呼号分配 / HUD 兼容）
## AceSquad 子类返回 self；纯舰队 BOSS 返回 null；
## CSG 这类"舰队 + 飞机阶段"的组合 BOSS 返回内部的飞机子小队
func get_active_ace_squad() -> AceSquad:
	return self as AceSquad
