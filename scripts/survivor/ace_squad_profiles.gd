## 王牌中队编成 profile 注册表（spec ace-squadron-tier §2.7 / §2.9 / §4.3）
##
## **加新王牌中队 = 本表加一行**（+ 各队 spec）。包装五件套（代号 / 固定呼号 /
## 主色 / 血条段数 / 留档 id=键名）与调度时段档全部单点登记在这里，
## 禁止散写进事件类 / squad 子类。
##
## implemented=false 的行只作包装 / 生涯档案的数据源（档案页剪影等），
## 调度器 pool_at() 不会选它 —— 各队实装批翻 true 即入轮换。
##
## 呼号铁律（tier §2.7）：固定呼号开局 reserve_permanent 打标（杂鱼抽不到）、
## **永不 recycle**（名字属于角色，不属于尸体）。本表呼号均不在 CALLSIGNS 800 池内；
## extra_reserved 收池内撞名的代号词（如 "Vulture"/"Orion" 本身在池里）。
class_name AceSquadProfiles

const PROFILES: Dictionary = {
	"marathon": {
		"codename": "MARATHON",
		"name_key": "ACE_SQUAD_MARATHON_NAME",
		"lore_key": "ACE_SQUAD_MARATHON_LORE",
		"color": Color(1.0, 0.180, 0.239),   # 猩红 #FF2E3D（727 包装批：紫红系，金橙退役）
		"pool_time": 320.0,                  # 中期档（728 用户改档：Su-35 中期才出现）
		"callsigns": ["Pacer", "Miler", "Sprinter", "Kicker", "Sweeper"],
		"dodge": 0.20,                       # 机炮闪避基线档（tier §2.2）
		"xp_per_kill": 100,
		"squad_size": 5,
		"enemy_type": SurvivorSpawner.EnemyType.SU35,
		"tactics": "gladiator",              # 风格库 tier §3.7：全员 PURSUIT 死咬
		"gun": "ace",                        # ace_gun.tres 挂载（tier §2.4）
		"missile_count": -1,                 # -1 = 撤销等级加弹、回 base_res 原值
		"base_res": "res://resources/enemy_su35.tres",
		"formation": "diamond",
		"implemented": true,
	},
	"2ndwave": {
		"codename": "2NDWAVE",
		"name_key": "ACE_SQUAD_2NDWAVE_NAME",
		"lore_key": "ACE_SQUAD_2NDWAVE_LORE",
		"color": Color(0.706, 0.302, 1.0),   # 电紫 #B44DFF
		"pool_time": 240.0,                  # 早期档（唯一早期队——本局第一支王牌）
		"callsigns": ["Teacher", "Senior", "Junior", "Sophomore", "Freshman"],
		"dodge": 0.20,                       # 学员基线；Teacher 特高 0.50 在 element 覆写
		"xp_per_kill": 100,
		"ai_level": 0.92,                    # 学员王牌档；Teacher 顶格 1.0 在 element 覆写
		"squad_size": 5,
		"tactics": "gladiator",
		"formation": "diamond",
		# 混编（tier §3.7 条款首例）：Teacher 斗士长机 + F-15 学员骑士 element，静态分工
		"elements": [
			{"type": SurvivorSpawner.EnemyType.F4E, "count": 1, "style": "gladiator",
				"gun": "ace", "dodge": 0.50, "flares": 0, "evade": true, "ai_level": 1.0,
				"missile_count": -1, "base_res": "res://resources/enemy_f4e.tres"},
			{"type": SurvivorSpawner.EnemyType.F15, "count": 4, "style": "lancer",
				"gun": "none", "missile_count": 6},
		],
		"implemented": true,
	},
	"orion": {
		"codename": "ORION",
		"name_key": "ACE_SQUAD_ORION_NAME",
		"lore_key": "ACE_SQUAD_ORION_LORE",
		"color": Color(1.0, 0.541, 0.239),   # 伪装：普通敌方橙（宿敌条款 §3.8 豁免紫红）
		"pool_time": 300.0,                  # 独立轨道参考时刻（不进 pool_at 轮换）
		"callsigns": [],                     # 机号即呼号（Cre-XX 动态生成）
		"dodge": 0.0,                        # 档位表随成长走（该队 spawn 覆写）
		"xp_per_kill": 50,
		"squad_size": 1,
		"implemented": false,
		"nemesis": true,                     # 宿敌条款：不进轮换池、不占同场名额
	},
	"gimmick": {
		"codename": "GIMMICK",
		"name_key": "ACE_SQUAD_GIMMICK_NAME",
		"lore_key": "ACE_SQUAD_GIMMICK_LORE",
		"color": Color(0.886, 0.227, 0.557), # 洋红 #E23A8E
		"pool_time": 320.0,                  # 中期档
		"callsigns": ["Bluff", "Feint", "Bait", "Switch"],
		"dodge": 0.20,
		"xp_per_kill": 100,
		"ai_level": 0.92,
		"squad_size": 4,
		"tactics": "gladiator",
		"formation": "diamond",
		# 混编：F-16 狙击 element（SNIPER 站位带 4~6km，复用 Wraith 基建；长机 BLUFF 在此）
		# + Mirage 2000 斗士 element（贴脸屏障）。远近夹击 = Wraith 两难的非 BOSS 简装版
		"elements": [
			{"type": SurvivorSpawner.EnemyType.F16, "count": 2, "style": "schemer",
				"gun": "ace", "missile_count": 6},
			{"type": SurvivorSpawner.EnemyType.MIRAGE2000, "count": 2, "style": "gladiator",
				"gun": "ace"},
		],
		"implemented": true,
	},
	"goofighters": {
		"codename": "GOOFIGHTERS",
		"name_key": "ACE_SQUAD_GOOFIGHTERS_NAME",
		"lore_key": "ACE_SQUAD_GOOFIGHTERS_LORE",
		"color": Color(0.482, 0.247, 0.894), # 深紫罗兰 #7B3FE4
		"pool_time": 320.0,                  # 中期档
		"callsigns": ["Wisp", "Orb"],
		"dodge": 0.35,                       # 高档（难缠机：缠斗专家，tier §2.2）
		"xp_per_kill": 150,
		"ai_level": 0.92,
		"squad_size": 2,
		"enemy_type": SurvivorSpawner.EnemyType.SU47,
		"tactics": "gladiator",              # 斗士双机；QMAAM 副槽 + 眼镜蛇在机体/spawner 层
		"gun": "ace",
		"formation": "diamond",
		"base_res": "res://resources/enemy_su47.tres",
		"implemented": true,
	},
	"vulture": {
		"codename": "VULTURE",
		"name_key": "ACE_SQUAD_VULTURE_NAME",
		"lore_key": "ACE_SQUAD_VULTURE_LORE",
		"color": Color(0.557, 0.141, 0.314), # 酒红 #8E2450
		"pool_time": 400.0,                  # 后期档
		"callsigns": ["Carrion", "Buzzard", "Wake", "Kettle", "Pinion", "Perch", "Feast", "Famine"],
		"dodge": 0.20,
		"xp_per_kill": 100,
		"squad_size": 8,
		"enemy_type": SurvivorSpawner.EnemyType.MIG31,
		"tactics": "lancer",                 # 掠袭循环（lancer_squad_tactics）
		"gun": "none",                       # 纯导弹无机炮（tier §2.4 骑士豁免）
		"missile_count": 6,                  # 6 波齐射预算；弹尽撤离
		"base_res": "res://resources/enemy_mig31.tres",
		"formation": "line",                 # 横列冲锋
		"line_spacing": 600.0,
		"implemented": true,
	},
}

## 代号词本身撞 CALLSIGNS 800 池的情况（"Vulture"/"Orion"/"Wraith" 均在池内）：
## 一并永久保留，防止杂鱼顶着中队代号乱入叙事
const EXTRA_RESERVED: Array = ["Vulture", "Orion", "Wraith", "Marathon", "Gimmick"]

static func get_profile(id: String) -> Dictionary:
	return PROFILES.get(id, {})

static func codename(id: String) -> String:
	return String(get_profile(id).get("codename", id.to_upper()))

static func color(id: String) -> Color:
	return get_profile(id).get("color", Color(1.0, 0.3, 0.3))

## 调度池（tier §2.9 时段档）：已实装、非宿敌、game_time 已达档位时间的队 id。
## 顺序稳定（按 pool_time 升序，同时间按表序），轮换指针据此取模。
static func pool_at(game_time: float) -> Array:
	var out: Array = []
	for id in PROFILES:
		var p: Dictionary = PROFILES[id]
		if not bool(p.get("implemented", false)):
			continue
		if bool(p.get("nemesis", false)):
			continue   # 宿敌走独立轨道（tier §2.9 / §3.8）
		if game_time >= float(p.get("pool_time", 240.0)):
			out.append(id)
	out.sort_custom(func(a, b):
		var ta := float(PROFILES[a].get("pool_time", 0.0))
		var tb := float(PROFILES[b].get("pool_time", 0.0))
		return ta < tb if not is_equal_approx(ta, tb) else String(a) < String(b))
	return out

## 全部需永久保留的呼号（含未实装队——包装先行，杂鱼从第一天起就抽不到这些名字）
static func all_reserved_callsigns() -> Array:
	var out: Array = []
	for id in PROFILES:
		for cs in PROFILES[id].get("callsigns", []):
			out.append(String(cs))
	for cs in EXTRA_RESERVED:
		out.append(String(cs))
	return out

## 开局调用（survivor_mode setup）：把全部王牌呼号打进 CallsignDB 永久保留区。幂等。
static func reserve_callsigns() -> void:
	for cs in all_reserved_callsigns():
		CallsignDB.reserve_permanent(String(cs))
