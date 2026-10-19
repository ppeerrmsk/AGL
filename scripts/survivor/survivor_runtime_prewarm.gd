extends Node
##
## SurvivorRuntimePrewarm — 正式局 Loading 阶段的运行时预热（BuildingPreloader 子节点）
##
## 把正式局里由事件首次触发、在主线程同步完成的一次性工作提前到 Loading：
##   audio     常规歌单 / 王牌 / 全部 BOSS 曲 / 引擎循环音：交给 AudioManager 每帧发起一个线程预载并常驻
##   zone_land 常量战区陆地可用性：原多边形判定提前算好（UGC/沙漠图走自身地理，跳过）
##   templates 王牌支援编成参数模板常驻
##   silhouettes 机型顶视轮廓 PNG 解码（按帧预算推进）
##   upgrade   升级弹窗：真实卡片控件在当前视口缩放下透明绘制全部升级文本——
##             项目无中文字体，中文走系统回退字体，查找 / 栅格化 / 字形纹理上传都在首次绘制时发生
## 结果只影响"何时做"，不改变任何数值与画面。
## 时序：BuildingPreloader 自身的建筑/矢量/东京地图预载全部就绪后才 begin()——不与地图预载争
## 主线程和 ResourceLoader 线程（地图预载有 15s 超时，超时会释放后在进场帧同步重建）；
## is_done() 后 BuildingPreloader 才 arm 地图会话并切场景。

const AircraftSilhouetteCatalog := preload("res://scripts/aircraft_silhouette_catalog.gd")

## 曲目按 AudioManager.MUSIC_FILES 的 id 前缀选取，不为读 SurvivorMode 常量而在 Loading 编译
## 整个 survivor_mode.gd（实测主线程 2.3~6.4s）。前缀覆盖 SurvivorMode.DEFAULT_BATTLE_MUSIC_IDS
## 与 ACE_BATTLE_MUSIC_IDS 由 test_event_hitch_prewarm 断言。
const BATTLE_MUSIC_PREFIX := "battle_"
const ACE_MUSIC_PREFIX := "ace_battle_"
## 与 SurvivorMode.begin_ace_battle_music 的沙漠专用追加曲保持一致
const DESERT_MAP_ID := "desert_railway_preview"
const DESERT_ACE_MUSIC_ID := "ace_desert"
const BOSS_MUSIC_PREFIX := "boss"
const ENGINE_SFX_IDS := ["engine_f16"]
const SILHOUETTE_BUDGET_USEC := 6000
const UPGRADE_UI_INSTANCES := 4
const UPGRADE_CARDS_PER_UI := 4
## 最后一批文本排入后再留两帧：一帧完成容器排版与绘制，一帧兜底延迟重绘
const UPGRADE_SETTLE_FRAMES := 2
## 离屏偏移只改画布变换，不改字形本地坐标与视口过采样；玩家看不到也点不到
const UPGRADE_LAYER_OFFSET := Vector2(-20000.0, -20000.0)

## 音频只排队、不等待完成：AudioManager 每帧最多发起一个线程请求，加载跨场景切换继续；
## 局内首次取用若仍在途，load_threaded_get 只等剩余部分，不会重复解析。
enum Stage { AUDIO_REQUEST, ZONE_LAND, TEMPLATES, SILHOUETTES, UPGRADE, DONE }

var _started := false
var _begin_msec := 0
var _stage := Stage.AUDIO_REQUEST
var _upgrade_uis: Array[SurvivorUpgradeUI] = []
var _upgrade_cursor := 0
var _upgrade_settle := 0
var _stage_usec: Dictionary = {}


## BuildingPreloader 自身预载全部就绪后调用；重复调用无副作用。
func begin() -> void:
	if _started:
		return
	_started = true
	_begin_msec = Time.get_ticks_msec()


func is_done() -> bool:
	return _stage == Stage.DONE


func progress() -> float:
	return float(_stage) / float(Stage.DONE)


## 当前地图会用到的曲目 id（Loading 预载清单）。
static func music_ids_for_map(map_id: String) -> Array[String]:
	var ids: Array[String] = []
	for id: String in AudioManager.MUSIC_FILES:
		if id.begins_with(BATTLE_MUSIC_PREFIX) or id.begins_with(ACE_MUSIC_PREFIX):
			ids.append(id)
	if map_id == DESERT_MAP_ID:
		ids.append(DESERT_ACE_MUSIC_ID)
	# BOSS 登场演出第一帧就切 BOSS 曲（PresentationDirector audio 通道），选定 BOSS 时再预载
	# 没有提前量；各 encounter 还会在 _init 自定层叠/歌单曲目，故按前缀预载全部 BOSS 曲
	# （约 30MB 压缩 OGG 常驻，后台线程读取）。
	for id: String in AudioManager.MUSIC_FILES:
		if id.begins_with(BOSS_MUSIC_PREFIX):
			ids.append(id)
	return ids


func _process(_delta: float) -> void:
	if _stage == Stage.DONE or not _started:
		return
	var t0 := Time.get_ticks_usec()
	var stage_before := _stage
	match _stage:
		Stage.AUDIO_REQUEST:
			_request_audio()
			_stage = Stage.ZONE_LAND
		Stage.ZONE_LAND:
			# 沙漠等 UGC 地图在 SurvivorMode 里才注入自身地理；按官方地理提前算的结果
			# 会随地理数组替换自动作废，提前算无意义，跳过。
			if not get_tree().has_meta("ugc_map_path"):
				ZoneData.prewarm_zone_land()
			_stage = Stage.TEMPLATES
		Stage.TEMPLATES:
			AceSupportSquad.prewarm_templates()
			_stage = Stage.SILHOUETTES
		Stage.SILHOUETTES:
			if AircraftSilhouetteCatalog.prewarm_textures(SILHOUETTE_BUDGET_USEC):
				_stage = Stage.UPGRADE
		Stage.UPGRADE:
			if _step_upgrade_text():
				_stage = Stage.DONE
	_stage_usec[stage_before] = int(_stage_usec.get(stage_before, 0)) + Time.get_ticks_usec() - t0
	if _stage == Stage.DONE:
		print("[RuntimePrewarm] done in %dms wall — main-thread ms: audio_request=%.1f zone_land=%.1f templates=%.1f silhouettes=%.1f upgrade=%.1f" % [
			Time.get_ticks_msec() - _begin_msec,
			_stage_ms(Stage.AUDIO_REQUEST), _stage_ms(Stage.ZONE_LAND), _stage_ms(Stage.TEMPLATES),
			_stage_ms(Stage.SILHOUETTES), _stage_ms(Stage.UPGRADE),
		])


func _stage_ms(stage: int) -> float:
	return float(_stage_usec.get(stage, 0)) / 1000.0


func _request_audio() -> void:
	AudioManager.prefetch_music(music_ids_for_map(String(get_tree().get_meta("survivor_map_id", ""))))
	AudioManager.prefetch_sfx(ENGINE_SFX_IDS)


## 每帧给每个离屏透明弹窗排入下一批升级卡；全部排完并沉淀两帧后释放。返回 true 表示完成。
func _step_upgrade_text() -> bool:
	if _upgrade_uis.is_empty() and _upgrade_cursor == 0:
		for i in UPGRADE_UI_INSTANCES:
			var ui := SurvivorUpgradeUI.new()
			ui.name = "UpgradeGlyphPrewarm%d" % i
			add_child(ui)
			ui.offset = UPGRADE_LAYER_OFFSET
			for child in ui.get_children():
				if child is CanvasItem:
					(child as CanvasItem).modulate.a = 0.0
			ui.visible = true
			_upgrade_uis.append(ui)
	var upgrades := SurvivorData.UPGRADES
	if _upgrade_cursor < upgrades.size():
		for ui in _upgrade_uis:
			var batch: Array[Dictionary] = []
			while batch.size() < UPGRADE_CARDS_PER_UI and _upgrade_cursor < upgrades.size():
				batch.append(upgrades[_upgrade_cursor])
				_upgrade_cursor += 1
			if not batch.is_empty():
				ui.prewarm_render_batch(batch)
		return false
	if _upgrade_settle < UPGRADE_SETTLE_FRAMES:
		_upgrade_settle += 1
		return false
	for ui in _upgrade_uis:
		ui.queue_free()
	_upgrade_uis.clear()
	return true
