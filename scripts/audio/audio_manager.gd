extends Node

## 音频管理器（AutoLoad）
##
## 职责：
## - BGM：全局单轨，支持淡入/淡出/交叉淡化（双播放器轮换实现 crossfade）
## - SFX：32 个 AudioStreamPlayer2D 池化，走 SFX Bus（带"远距无线电"效果链）
## - UI：非定位短音效
## - Bus 音量/静音持久化到 user://audio.cfg
##
## 调用示例见 docs/reference/audio.md（待补）。主要 API：
##   play_music(id, fade_in=1.5, loop=true)
##   stop_music(fade_out=2.0)
##   crossfade_music(id, duration=2.0, loop=true)
##   play_sfx_2d(id, world_pos, volume_db=0.0)
##   play_ui(id, volume_db=0.0)
##   set_bus_volume_linear(bus_name, 0~1)
##   save_settings() / _load_settings()

const SFX_POOL_SIZE := 32
const LAYER_COUNT := 4            ## 层叠音乐的最大层数（CSG BOSS 用 2）
const LAYER_SILENT_DB := -80.0    ## 非激活层音量
const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"
const UI_BUS := "UI"
const RADIO_BUS := "Radio"
const CONFIG_PATH := "user://audio.cfg"

# ────── 资源库（id → 路径）──────
const MUSIC_FILES := {
	"battle_coast": "res://audio/music/battlebgm1.ogg",
	"battle_coast_2": "res://audio/music/battlebgm2.ogg",
	"boss": "res://audio/music/bossbattle.ogg",
	# CarrierStrikeGroup BOSS 双阶段 BGM —— 层叠同步播放（两首等长 + Loop 导入开）
	"boss_csg": "res://audio/music/boss2phase1.ogg",
	"boss_csg_phase2": "res://audio/music/boss2phase2.ogg",
	# Mother Goose BOSS 双曲循环 —— 走 playlist 顺序播放（首播完接第二首，再循环回首）
	"boss_mothergoose_1": "res://audio/music/mothergoose1.ogg",
	"boss_mothergoose_2": "res://audio/music/mothergoose2.ogg",
}

const SFX_FILES := {
	"gun_fire": "res://audio/sfx/Mini_Gun_Burst.wav",
	"gun_long": "res://audio/sfx/Vulcan_Mini_Gun_Long_Burst_Medium_Distance.wav",
	"missile_launch": "res://audio/sfx/Missile_Launch_01.wav",
	"missile_launch_alt": "res://audio/sfx/Missile_Launch_02.wav",
	"missile_pass": "res://audio/sfx/Missile_Pass_By_01.wav",
	"missile_pass_alt": "res://audio/sfx/Missile_Pass_By_02.wav",
	"bomb_distant": "res://audio/sfx/Bomb_Distant_01.wav",
	"bomb_distant_02": "res://audio/sfx/Bomb_Distant_02.wav",
	"bomb_distant_03": "res://audio/sfx/Bomb_Distant_03.wav",
	"bomb_distant_04": "res://audio/sfx/Bomb_Distant_04.wav",
	"engine_f16": "res://audio/sfx/F-16_Fighting Falcon_ Medium_Distance_02.wav",
	"engine_f16_03": "res://audio/sfx/F-16_Fighting Falcon_ Medium_Distance_03.wav",
	"engine_f16_04": "res://audio/sfx/F-16_Fighting Falcon_ Medium_distance_04.wav",
}

const UI_FILES := {}

# ────── Bus 默认音量（dB）──────
const DEFAULT_BUS_DB := {
	"Music": -12.0,  # BGM 存在感低
	"SFX": -4.0,    # 默认响亮一些；远距无线电味由 Bus 效果链提供，不靠低音量
	"UI": -6.0,
	"Radio": -10.0,
}

# ────── 运行时状态 ──────
var _music_player_a: AudioStreamPlayer
var _music_player_b: AudioStreamPlayer
var _active_music: AudioStreamPlayer
var _layer_players: Array[AudioStreamPlayer] = []  ## 层叠 BGM 专用池，独立于 a/b crossfade
var _layer_active: bool = false                    ## 当前是否处于层叠模式
var _layer_active_index: int = 0                   ## 当前激活层索引（其他层静音但同步播放）
var _ui_player: AudioStreamPlayer
var _sfx_pool: Array[AudioStreamPlayer2D] = []
var _sfx_pool_idx := 0
var _tweens: Dictionary = {}  # player(instance_id) → Tween
var _music_muffle: AudioEffectLowPassFilter  # 菜单模糊滤镜（默认禁用）
var _muffle_tween: Tween

# ────── 播放列表（顺序轮播，每首播完自动下一首）──────
var _playlist: Array = []
var _playlist_idx: int = 0
var _playlist_active: bool = false
var _playlist_crossfade: float = 2.0
var _playlist_advance_armed: bool = false  ## 当前曲未到尾段（防重复触发预交叉淡化）
const MUFFLE_CUTOFF_OPEN := 20000.0  # 直通（听起来无效果）
const MUFFLE_CUTOFF_MENU := 600.0    # 模糊状态，像隔了层雾

# ────── 玩家引擎环境音 ──────
var _engine_player: AudioStreamPlayer2D = null
var _engine_host: Node2D = null
const ENGINE_ZOOM_MIN := 0.6    # 小于此 zoom 完全静音（镜头太远）
const ENGINE_ZOOM_MAX := 2.0    # 大于此 zoom 满音量（镜头贴近）

func _ready() -> void:
	# 树暂停（战术面板会 pause）时音乐不能断
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	_music_player_a = _make_music_player()
	_music_player_b = _make_music_player()
	_active_music = _music_player_a
	# 播放列表：当活跃播放器自然播完时推进到下一首
	_music_player_a.finished.connect(_on_music_player_finished.bind(_music_player_a))
	_music_player_b.finished.connect(_on_music_player_finished.bind(_music_player_b))
	for i in LAYER_COUNT:
		var lp := _make_music_player()
		_layer_players.append(lp)
	_ui_player = AudioStreamPlayer.new()
	_ui_player.bus = UI_BUS
	_ui_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_ui_player)
	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer2D.new()
		p.bus = SFX_BUS
		# 视距内 = 听得见，视距外 attenuation 使之自然衰减至不可闻
		p.max_distance = 4000.0
		p.attenuation = 1.8
		add_child(p)
		_sfx_pool.append(p)
	_load_settings()

# ═══════════════════════════════════════════════════
#  Bus 初始化 — 程序化创建 Music/SFX/UI/Radio 总线
#  SFX Bus 挂上 HighPass + LowPass + Reverb 模拟远距无线电效果
# ═══════════════════════════════════════════════════

func _setup_buses() -> void:
	var master_idx := AudioServer.get_bus_index("Master")
	var music_idx := _ensure_bus(MUSIC_BUS, master_idx, DEFAULT_BUS_DB[MUSIC_BUS])
	var sfx_idx := _ensure_bus(SFX_BUS, master_idx, DEFAULT_BUS_DB[SFX_BUS])
	var ui_idx := _ensure_bus(UI_BUS, master_idx, DEFAULT_BUS_DB[UI_BUS])
	var radio_idx := _ensure_bus(RADIO_BUS, master_idx, DEFAULT_BUS_DB[RADIO_BUS])
	_apply_sfx_effects(sfx_idx)
	_apply_radio_effects(radio_idx)
	_apply_music_effects(music_idx)
	# 避免未使用告警
	var _u := ui_idx

func _ensure_bus(bus_name: String, send_to_idx: int, default_db: float) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		return idx
	idx = AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, AudioServer.get_bus_name(send_to_idx))
	AudioServer.set_bus_volume_db(idx, default_db)
	return idx

## SFX 远距无线电效果链：
##   HighPassFilter 400Hz    — 砍掉低频，模拟小喇叭
##   LowPassFilter 2500Hz    — 砍掉高频，形成电话/无线电频带
##   Reverb（湿 0.25）       — 轻微空间感，模拟远距
func _apply_sfx_effects(bus_idx: int) -> void:
	if AudioServer.get_bus_effect_count(bus_idx) > 0:
		return
	var hp := AudioEffectHighPassFilter.new()
	hp.cutoff_hz = 400.0
	AudioServer.add_bus_effect(bus_idx, hp)
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 2500.0
	AudioServer.add_bus_effect(bus_idx, lp)
	var rev := AudioEffectReverb.new()
	rev.room_size = 0.35
	rev.wet = 0.25
	rev.dry = 0.8
	AudioServer.add_bus_effect(bus_idx, rev)

## Music Bus 挂一个默认禁用的 LowPassFilter，菜单打开时淡入 600Hz 形成"隔雾"感
func _apply_music_effects(bus_idx: int) -> void:
	# 重复调用 _setup_buses 时已有就跳过（热重载安全）
	if AudioServer.get_bus_effect_count(bus_idx) > 0:
		_music_muffle = AudioServer.get_bus_effect(bus_idx, 0) as AudioEffectLowPassFilter
		return
	_music_muffle = AudioEffectLowPassFilter.new()
	_music_muffle.cutoff_hz = MUFFLE_CUTOFF_OPEN
	AudioServer.add_bus_effect(bus_idx, _music_muffle)
	AudioServer.set_bus_effect_enabled(bus_idx, 0, false)

## Radio 无线电人声效果链（更强的频带切割 + 轻失真，Step 2 使用）
func _apply_radio_effects(bus_idx: int) -> void:
	if AudioServer.get_bus_effect_count(bus_idx) > 0:
		return
	var hp := AudioEffectHighPassFilter.new()
	hp.cutoff_hz = 300.0
	AudioServer.add_bus_effect(bus_idx, hp)
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 3400.0
	AudioServer.add_bus_effect(bus_idx, lp)
	var dist := AudioEffectDistortion.new()
	dist.mode = AudioEffectDistortion.MODE_CLIP
	dist.drive = 0.08
	AudioServer.add_bus_effect(bus_idx, dist)

func _make_music_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = MUSIC_BUS
	# 暂停时音乐继续播放（战术面板 get_tree().paused=true 不能切断 BGM）
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(p)
	return p

# ═══════════════════════════════════════════════════
#  音乐 API
# ═══════════════════════════════════════════════════

func play_music(id: String, fade_in: float = 1.5, loop: bool = true) -> void:
	_playlist_active = false
	_stop_layered_internal(fade_in)
	_play_music_internal(id, fade_in, loop)

func _play_music_internal(id: String, fade_in: float, loop: bool) -> void:
	var stream := _get_music(id)
	if stream == null:
		return
	_apply_loop(stream, loop)
	_kill_tween(_active_music)
	_active_music.stop()
	_active_music.stream = stream
	_active_music.volume_db = -80.0
	_active_music.play()
	_fade_to(_active_music, 0.0, fade_in)

func stop_music(fade_out: float = 2.0) -> void:
	_playlist_active = false
	_stop_layered_internal(fade_out)
	if _active_music == null or not _active_music.playing:
		return
	_kill_tween(_active_music)
	var p := _active_music
	_fade_to(p, -80.0, fade_out, func(): if is_instance_valid(p): p.stop())

## 交叉淡化：新曲从 -80 dB 淡入，旧曲同时淡出后停止
func crossfade_music(id: String, duration: float = 2.0, loop: bool = true) -> void:
	_playlist_active = false
	_stop_layered_internal(duration)
	_crossfade_music_internal(id, duration, loop)

func _crossfade_music_internal(id: String, duration: float, loop: bool) -> void:
	var stream := _get_music(id)
	if stream == null:
		return
	_apply_loop(stream, loop)
	var old_player := _active_music
	var new_player := _music_player_b if _active_music == _music_player_a else _music_player_a
	_kill_tween(old_player)
	_kill_tween(new_player)
	new_player.stop()
	new_player.stream = stream
	# 等功率曲线开始：新轨从 -∞（≈-80dB）起步
	new_player.volume_db = -80.0
	new_player.play()
	# 等功率交叉淡化：避免线性 dB 在中点产生 -6dB 凹陷（两轨听感同时变小），
	# 用 sin/cos 让两轨幅度的平方和恒为 1，听感音量平稳，节奏过渡更自然。
	if old_player.playing:
		_equal_power_crossfade(old_player, new_player, duration)
	else:
		# 旧轨已停 → 退化为单纯淡入新轨（仍走幅度曲线，更平滑）
		_fade_amplitude(new_player, 1.0, duration)
	_active_music = new_player

## 等功率交叉淡化（amplitude squared sum = 1）：
##   t ∈ [0,1]，old.gain = cos(t·π/2)，new.gain = sin(t·π/2)
##   对应 dB：linear_to_db(gain)，gain≈0 时 clamp 到 -80
## 比起 dB 线性插值，这样在中点两轨各保持 -3dB（幅度 0.707），合成感知音量持平。
func _equal_power_crossfade(out_player: AudioStreamPlayer, in_player: AudioStreamPlayer, duration: float) -> void:
	if duration <= 0.01:
		out_player.volume_db = -80.0
		out_player.stop()
		in_player.volume_db = 0.0
		return
	var tween := create_tween().set_parallel(false)
	_tweens[out_player.get_instance_id()] = tween
	_tweens[in_player.get_instance_id()] = tween
	# 用 method tween 驱动一个 0→1 的 t，每帧同步两轨音量
	tween.tween_method(func(t: float):
			if not is_instance_valid(out_player) or not is_instance_valid(in_player):
				return
			var a_gain: float = cos(t * PI * 0.5)
			var b_gain: float = sin(t * PI * 0.5)
			out_player.volume_db = (linear_to_db(a_gain) if a_gain > 0.001 else -80.0)
			in_player.volume_db = (linear_to_db(b_gain) if b_gain > 0.001 else -80.0),
			0.0, 1.0, duration)
	tween.tween_callback(func():
			if is_instance_valid(out_player):
				out_player.volume_db = -80.0
				out_player.stop())

## 单轨幅度淡入/淡出（target_amp ∈ [0,1]，0 = 静音 / -80dB，1 = 0dB）
## 内部用 method tween 走线性幅度曲线再换算 dB，听感比 dB 直接线性更自然。
func _fade_amplitude(player: AudioStreamPlayer, target_amp: float, duration: float) -> void:
	if duration <= 0.01:
		player.volume_db = (linear_to_db(target_amp) if target_amp > 0.001 else -80.0)
		return
	var start_amp: float = (db_to_linear(player.volume_db) if player.volume_db > -79.5 else 0.0)
	var tween := create_tween()
	_tweens[player.get_instance_id()] = tween
	tween.tween_method(func(a: float):
			if not is_instance_valid(player):
				return
			player.volume_db = (linear_to_db(a) if a > 0.001 else -80.0),
			start_amp, target_amp, duration)

## 顺序轮播播放列表：首曲用 fade_in 淡入，之后每首播完自动 crossfade 下一首（循环）
## 调用 play_music/crossfade_music/stop_music 会自动终止播放列表模式
func play_music_playlist(ids: Array, fade_in: float = 2.0, crossfade_between: float = 2.0) -> void:
	if ids.is_empty():
		return
	_stop_layered_internal(fade_in)
	_playlist = ids.duplicate()
	_playlist_idx = 0
	_playlist_crossfade = crossfade_between
	_playlist_active = true
	_playlist_advance_armed = true
	# 首曲禁用 loop，这样播完触发 finished → 自动切下一首
	_play_music_internal(_playlist[0], fade_in, false)

func _on_music_player_finished(player: AudioStreamPlayer) -> void:
	# 只有活跃播放器自然播完才推进（fade-out 的旧 player 被 stop() 不会触发 finished，但以防万一）
	if player != _active_music:
		return
	if not _playlist_active or _playlist.is_empty():
		return
	_playlist_idx = (_playlist_idx + 1) % _playlist.size()
	# 下一首也禁用 loop，周而复始
	_crossfade_music_internal(_playlist[_playlist_idx], _playlist_crossfade, false)
	_playlist_active = true  # _crossfade_music_internal 不会改这个，但保险

func is_music_playing() -> bool:
	return _active_music != null and _active_music.playing

# ═══════════════════════════════════════════════════
#  层叠音乐 API（多轨同步播放，通过音量切换层）
#  CSG BOSS 用：Phase 1 + Phase 2 同时 play + loop，
#  进二阶段时把 Phase 1 压成静音、Phase 2 拉起来 —— 作曲层面无缝衔接。
#  前提：各层曲子长度相等、BPM 一致、.ogg 导入 Loop ✓。
# ═══════════════════════════════════════════════════

## 同帧启动所有层，active_index 那层淡入到 0 dB，其他层保持 -80 dB 静音同步播放
func play_layered_music(ids: Array, fade_in: float = 2.0, active_index: int = 0) -> void:
	if ids.is_empty():
		return
	# 先关掉 a/b 主轨（层叠期间独占 BGM）
	_playlist_active = false
	_fade_out_main_music(fade_in)
	# 关掉上一次层叠（若有）
	_stop_layered_internal(0.0)
	var count: int = mini(ids.size(), LAYER_COUNT)
	_layer_active = true
	_layer_active_index = clampi(active_index, 0, count - 1)
	for i in count:
		var stream := _get_music(ids[i])
		if stream == null:
			continue
		_apply_loop(stream, true)
		var lp := _layer_players[i]
		_kill_tween(lp)
		lp.stop()
		lp.stream = stream
		lp.volume_db = LAYER_SILENT_DB
		lp.play()
		if i == _layer_active_index:
			_fade_to(lp, 0.0, fade_in)

## 切换激活层：
## 新层快速淡入到 0 dB（~45% 时间），旧层先保持满音量、等新层接上后再淡出
## —— 避免对称交叉时中段两轨都在 -40 dB 附近形成"空洞"。
func set_music_layer(index: int, duration: float = 2.0) -> void:
	if not _layer_active:
		return
	if index < 0 or index >= _layer_players.size():
		return
	_layer_active_index = index
	var rise_time: float = maxf(duration * 0.45, 0.1)   # 新层淡入时长（占总时长前半）
	var hold_time: float = duration * 0.5               # 旧层保持满音量的延迟
	var fall_time: float = maxf(duration * 0.5, 0.1)    # 旧层淡出时长
	for i in _layer_players.size():
		var lp := _layer_players[i]
		if not lp.playing:
			continue
		_kill_tween(lp)
		if i == index:
			_fade_to(lp, 0.0, rise_time)
		else:
			# 延迟 hold_time 后再开始淡出，期间新层已经接近满音量
			var t := create_tween()
			_tweens[lp.get_instance_id()] = t
			t.tween_interval(hold_time)
			t.tween_property(lp, "volume_db", LAYER_SILENT_DB, fall_time)

## 停止所有层叠层（BOSS 胜利 / 撤退用）
func stop_layered_music(fade_out: float = 2.0) -> void:
	_stop_layered_internal(fade_out)

func _stop_layered_internal(fade_out: float) -> void:
	if not _layer_active:
		return
	_layer_active = false
	for lp in _layer_players:
		if not lp.playing:
			continue
		_kill_tween(lp)
		var dying := lp
		_fade_to(dying, LAYER_SILENT_DB, fade_out,
			func(): if is_instance_valid(dying): dying.stop())

## 层叠模式开始时把当前活跃的 a/b 主轨也压下去
func _fade_out_main_music(duration: float) -> void:
	if _active_music == null or not _active_music.playing:
		return
	_kill_tween(_active_music)
	var dying := _active_music
	_fade_to(dying, LAYER_SILENT_DB, duration,
		func(): if is_instance_valid(dying): dying.stop())

## 菜单模糊效果（升级界面 / 战术面板打开时调 true，关闭时调 false）
## 淡入/淡出 cutoff_hz 模拟隔层雾的听感
func set_music_muffled(muffled: bool, duration: float = 0.35) -> void:
	if _music_muffle == null:
		return
	var bus_idx := AudioServer.get_bus_index(MUSIC_BUS)
	if bus_idx < 0:
		return
	if _muffle_tween and _muffle_tween.is_valid():
		_muffle_tween.kill()
	if muffled:
		AudioServer.set_bus_effect_enabled(bus_idx, 0, true)
		_muffle_tween = create_tween()
		_muffle_tween.tween_property(_music_muffle, "cutoff_hz", MUFFLE_CUTOFF_MENU, duration)
	else:
		_muffle_tween = create_tween()
		_muffle_tween.tween_property(_music_muffle, "cutoff_hz", MUFFLE_CUTOFF_OPEN, duration)
		# 结束后禁用，省一点 CPU
		_muffle_tween.tween_callback(func():
			var i := AudioServer.get_bus_index(MUSIC_BUS)
			if i >= 0:
				AudioServer.set_bus_effect_enabled(i, 0, false)
		)

# ═══════════════════════════════════════════════════
#  SFX API（2D 定位）
# ═══════════════════════════════════════════════════

## 在世界坐标播放 SFX。
## 若 world_pos 不在当前相机视口内（含 200px 容差）直接忽略，实现"指挥官只听视野里的事"。
## 视距内由 AudioStreamPlayer2D 自身的距离衰减决定音量（越远越轻，约 4000px 处不可闻）。
func play_sfx_2d(id: String, world_pos: Vector2, volume_db: float = 0.0) -> void:
	if not _is_on_screen(world_pos):
		return
	var stream := _get_sfx(id)
	if stream == null:
		return
	var p := _sfx_pool[_sfx_pool_idx]
	_sfx_pool_idx = (_sfx_pool_idx + 1) % SFX_POOL_SIZE
	p.stop()
	p.stream = stream
	p.global_position = world_pos
	p.volume_db = volume_db
	p.pitch_scale = randf_range(0.95, 1.05)
	p.play()

# ═══════════════════════════════════════════════════
#  玩家引擎环境音（单循环源，挂到玩家机身上）
#  只有镜头贴近玩家（zoom 大）且玩家在视野里时才出声
# ═══════════════════════════════════════════════════

func start_player_engine(host: Node2D) -> void:
	stop_player_engine()
	var stream := _get_sfx("engine_f16")
	if stream == null or host == null:
		return
	_apply_loop(stream, true)
	_engine_player = AudioStreamPlayer2D.new()
	_engine_player.bus = SFX_BUS
	_engine_player.stream = stream
	_engine_player.max_distance = 3500.0
	_engine_player.attenuation = 2.0
	_engine_player.volume_db = -80.0  # 从静音起步，_process 平滑爬到目标
	_engine_host = host
	host.add_child(_engine_player)
	_engine_player.play()

func stop_player_engine() -> void:
	if _engine_player and is_instance_valid(_engine_player):
		_engine_player.queue_free()
	_engine_player = null
	_engine_host = null

func _process(_delta: float) -> void:
	_update_engine_volume()
	_check_playlist_early_crossfade()

## 播放列表"预先交叉淡化"：在当前曲距结尾还有 _playlist_crossfade 秒时主动触发下一首，
## 让上一首的尾巴 (outro/最后小节) 与下一首的开头 (intro/起拍) 真实重叠播出，
## 避免老逻辑（等 finished 信号才切）出现的"上一首播完→静音 N 帧→下一首淡入"节奏断点。
## 等功率曲线再叠加这个时间重叠，过渡听起来连续。
func _check_playlist_early_crossfade() -> void:
	if not _playlist_active or _playlist.size() < 2:
		return
	if _active_music == null or not _active_music.playing:
		return
	if not _playlist_advance_armed:
		return
	var stream := _active_music.stream
	if stream == null:
		return
	var length: float = stream.get_length()
	if length <= 0.0:
		return
	var pos: float = _active_music.get_playback_position()
	# 距结尾不超过 crossfade 时长 → 启动下一首交叉淡化
	if length - pos <= _playlist_crossfade:
		_playlist_idx = (_playlist_idx + 1) % _playlist.size()
		_crossfade_music_internal(_playlist[_playlist_idx], _playlist_crossfade, false)
		_playlist_active = true
		# 新曲启动 → 立即重新 arm，下一首到尾段时再触发
		_playlist_advance_armed = true

func _update_engine_volume() -> void:
	if _engine_player == null or not is_instance_valid(_engine_player):
		return
	if _engine_host == null or not is_instance_valid(_engine_host):
		stop_player_engine()
		return
	var on_screen := _is_on_screen(_engine_host.global_position)
	var target_db: float
	if not on_screen:
		target_db = -80.0
	else:
		var cam := get_viewport().get_camera_2d()
		var zoom := 1.0 if cam == null else cam.zoom.x
		# 0.6 → 0（静音），2.0 → 1（满音量），之间线性
		var vol_linear := clampf((zoom - ENGINE_ZOOM_MIN) / (ENGINE_ZOOM_MAX - ENGINE_ZOOM_MIN), 0.0, 1.0)
		target_db = linear_to_db(maxf(vol_linear, 0.0001))
	# 平滑过渡避免 zoom 滚动时音量跳变
	_engine_player.volume_db = lerpf(_engine_player.volume_db, target_db, 0.15)

## 判定世界坐标是否在当前相机视口中（考虑缩放 + 200px 容差）
func _is_on_screen(world_pos: Vector2) -> bool:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return true
	var center := cam.get_screen_center_position()
	var vp_size := get_viewport().get_visible_rect().size
	# Godot Camera2D: zoom > 1 放大（看得近），zoom < 1 缩小（看得远）
	var zoom_x: float = maxf(cam.zoom.x, 0.0001)
	var zoom_y: float = maxf(cam.zoom.y, 0.0001)
	var half_w := (vp_size.x * 0.5) / zoom_x
	var half_h := (vp_size.y * 0.5) / zoom_y
	const MARGIN := 200.0
	return absf(world_pos.x - center.x) < half_w + MARGIN \
		and absf(world_pos.y - center.y) < half_h + MARGIN

# ═══════════════════════════════════════════════════
#  UI API
# ═══════════════════════════════════════════════════

func play_ui(id: String, volume_db: float = 0.0) -> void:
	var stream := _get_ui(id)
	if stream == null:
		return
	_ui_player.stream = stream
	_ui_player.volume_db = volume_db
	_ui_player.play()

# ═══════════════════════════════════════════════════
#  Bus 控制（供菜单滑条调用）
# ═══════════════════════════════════════════════════

func set_bus_volume_linear(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0: return
	AudioServer.set_bus_volume_db(idx, linear_to_db(clamp(linear, 0.0001, 1.0)))

func get_bus_volume_linear(bus_name: String) -> float:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0: return 0.0
	return db_to_linear(AudioServer.get_bus_volume_db(idx))

func set_bus_mute(bus_name: String, muted: bool) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0: return
	AudioServer.set_bus_mute(idx, muted)

func save_settings() -> void:
	var cfg := ConfigFile.new()
	for bus in ["Master", MUSIC_BUS, SFX_BUS, UI_BUS, RADIO_BUS]:
		var idx := AudioServer.get_bus_index(bus)
		if idx < 0: continue
		cfg.set_value("audio", bus + "_db", AudioServer.get_bus_volume_db(idx))
		cfg.set_value("audio", bus + "_mute", AudioServer.is_bus_mute(idx))
	cfg.save(CONFIG_PATH)

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	for bus in ["Master", MUSIC_BUS, SFX_BUS, UI_BUS, RADIO_BUS]:
		var idx := AudioServer.get_bus_index(bus)
		if idx < 0: continue
		if cfg.has_section_key("audio", bus + "_db"):
			AudioServer.set_bus_volume_db(idx, cfg.get_value("audio", bus + "_db"))
		if cfg.has_section_key("audio", bus + "_mute"):
			AudioServer.set_bus_mute(idx, cfg.get_value("audio", bus + "_mute"))

# ═══════════════════════════════════════════════════
#  内部工具
# ═══════════════════════════════════════════════════

func _get_music(id: String) -> AudioStream:
	var path: String = MUSIC_FILES.get(id, "")
	if path.is_empty():
		push_warning("AudioManager: unknown music id '%s'" % id)
		return null
	return load(path) as AudioStream

func _get_sfx(id: String) -> AudioStream:
	var path: String = SFX_FILES.get(id, "")
	if path.is_empty():
		push_warning("AudioManager: unknown sfx id '%s'" % id)
		return null
	return load(path) as AudioStream

func _get_ui(id: String) -> AudioStream:
	var path: String = UI_FILES.get(id, "")
	if path.is_empty():
		push_warning("AudioManager: unknown ui id '%s'" % id)
		return null
	return load(path) as AudioStream

func _apply_loop(stream: AudioStream, loop: bool) -> void:
	if stream is AudioStreamOggVorbis:
		stream.loop = loop
	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED

func _fade_to(player: AudioStreamPlayer, target_db: float, duration: float, on_done: Callable = Callable()) -> void:
	if duration <= 0.01:
		player.volume_db = target_db
		if on_done.is_valid():
			on_done.call()
		return
	var tween := create_tween()
	_tweens[player.get_instance_id()] = tween
	tween.tween_property(player, "volume_db", target_db, duration)
	if on_done.is_valid():
		tween.tween_callback(on_done)

func _kill_tween(player: AudioStreamPlayer) -> void:
	var key := player.get_instance_id()
	if _tweens.has(key):
		var t = _tweens[key]
		if t and t.is_valid():
			t.kill()
		_tweens.erase(key)
