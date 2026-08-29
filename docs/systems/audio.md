# 音频系统

AGL 的音频全部走 `AudioManager` AutoLoad（[scripts/audio/audio_manager.gd](../../scripts/audio/audio_manager.gd)），外部不要直接创建 `AudioStreamPlayer`。

## 设计主线：指挥官视角 + 远距无线电

玩家是坐在指挥室看战术图的指挥官，战场音效"从远处通过无线电传过来"。这个听觉美学通过 **SFX Bus 的效果链** 统一实现，调用方不用处理：

- HighPassFilter 400Hz — 砍低频，模拟小喇叭
- LowPassFilter 2500Hz — 砍高频，形成电话 / 无线电频带
- Reverb wet=0.25 — 轻微空间感

调用 `play_sfx_2d` 出的任何音效都会自动带这个味道。

## Bus 架构

启动时 `AudioManager._setup_buses` 程序化创建 4 条 Bus 挂到 Master，不依赖 `.tres` 文件：

| Bus | 默认 dB | 用途 | 挂的效果 |
|---|---|---|---|
| Master | 0 | 全局 | — |
| Music | -12 | BGM | LowPassFilter（默认禁用，菜单打开时用做模糊效果） |
| SFX | -4 | 世界音效 | HighPass + LowPass + Reverb（远距无线电） |
| UI | -6 | 界面反馈 | — |
| Radio | -10 | 无语义、不可辨词句的无线电人声纹理（素材待接入） | HighPass + LowPass + Distortion |

默认值在 `AudioManager.DEFAULT_BUS_DB`。用户通过[音频设置面板](../../scripts/audio/audio_settings_panel.gd)调整后持久化到 `user://audio.cfg`。

### 自动测试隔离

所有带 `--bench` 的进程由 `BenchRunner` 在识别参数后直接 mute `Master` 总线，保证 Music、SFX、UI、
Radio 以及未来新增总线均不占用用户的听觉环境。该 mute 只存在于测试进程，不调用 `save_settings()`；
播放器、播放入口、signal 与 Bus 状态仍按正式逻辑执行，所以音频行为断言不能因静音而被跳过。

## API 一览

### 音乐

```gdscript
AudioManager.play_music(id, fade_in=1.5, loop=true)
AudioManager.stop_music(fade_out=2.0)
AudioManager.crossfade_music(id, duration=2.0, loop=true)
AudioManager.play_music_playlist(ids, fade_in=2.0, crossfade_between=2.0)
AudioManager.crossfade_music_playlist(ids, duration=2.0, crossfade_between=2.0)
AudioManager.crossfade_music_interrupt(id, duration=2.0, loop=false) -> bool
AudioManager.resume_interrupted_music(duration=2.0) -> bool
AudioManager.has_music(id) -> bool
AudioManager.set_music_muffled(muffled, duration=0.35)
```

双播放器轮换实现 crossfade（`_music_player_a` / `_music_player_b`）。
**播放列表模式**：首曲淡入后 `loop=false`，播完触发 `finished` → 自动 crossfade 下一首，周而复始。调用 `play_music/crossfade_music/stop_music` 会自动退出 playlist 模式（BOSS 登场就是靠这个）。
`crossfade_music_playlist` 用于临时主题结束后从当前曲等功率切回播放列表；`has_music` 同时检查登记与资源存在，事件可在素材缺失时保持当前歌单不中断。
非 playlist 的 one-shot 曲自然结束时，`AudioManager.music_track_finished(id)` 发出完成信号。Ace 插入曲通过
`crossfade_music_interrupt` 冻结地图歌单当时的曲目与播放位置；自然结束或中队终态后，
`resume_interrupted_music` 从被打断的位置继续，而不是从普通歌单首曲重头播放。Boss / Game Over / 其它演出接管时丢弃该恢复点。
新加入的 OGG 若尚未由编辑器生成 `.import`，`_get_music` 会用 `AudioStreamOggVorbis.load_from_file`
直接读取原始文件；导入完成后自动回到标准 `ResourceLoader` 路径。
**模糊（muffle）效果**：预挂 Music Bus 上的 `AudioEffectLowPassFilter`，菜单打开时启用并 tween cutoff 20000→600Hz，关闭时反向 tween 回去并禁用效果。

### SFX（2D 定位）

```gdscript
AudioManager.play_sfx_2d(id, world_pos, volume_db=0.0)
```

**两道门禁**，源点必须通过才能出声：
1. **屏幕外静音** — `_is_on_screen(world_pos)` 算当前相机视口矩形（考虑 zoom + 200px 容差），源点在矩形外直接 `return`
2. **距离衰减** — `AudioStreamPlayer2D.max_distance=4000, attenuation=1.8`，以相机为听点，越远越轻，约 4000px 外趋于无声

32 个 `AudioStreamPlayer2D` 池化（round-robin 索引），避免每次 new/free。

### UI / Bus 控制

```gdscript
AudioManager.play_ui(id, volume_db=0.0)
AudioManager.set_bus_volume_linear(bus_name, 0.0~1.0)
AudioManager.get_bus_volume_linear(bus_name) -> float
AudioManager.set_bus_mute(bus_name, muted)
AudioManager.save_settings()  # 写 user://audio.cfg
```

## 玩家引擎环境音

`start_player_engine(host)` 往玩家飞机挂一个循环 `AudioStreamPlayer2D`，`_process` 每帧算目标音量：

| zoom | 音量 | 场景 |
|---|---|---|
| ≤ 0.6 | -80 dB（静音） | 视野最远（默认沙盒全景） |
| 1.0 | ≈ -30 dB | 默认视野 |
| ≥ 2.0 | 0 dB（满） | 贴脸看飞机 |
| 玩家出镜 | -80 dB | 任何缩放 |

`lerpf(current, target, 0.15)` 平滑过渡，避免滚轮阶跃。宿主 `queue_free` 时 `is_instance_valid` 检测清理。

## 资源库

全部 id → 路径映射在 `AudioManager` 常量：
- `MUSIC_FILES`（字典）—— BGM 轨
- `SFX_FILES`（字典）—— 世界音效
- `UI_FILES`（字典，暂空）—— UI 音效

新增音频文件 → 放到对应 `audio/{music,sfx,ui}/` → 在对应字典里加一行 id → 路径。
非 BOSS 王牌使用 `ace_battle_01`～`04` 四首随机池，正式路径为
`audio/music/ace_battle_01.ogg`～`04.ogg`；WAV 母版保留在 `audio_intake/10_music/ace_battle/`。
每次血条浮现只抽一首且不循环，曲终或中队终止后从先前被打断的位置继续普通歌单；部分文件缺失只缩小随机池。

### 包体边界

`audio_intake/` 是制作源，不是运行时资源：目录内 `.gdignore` 阻止 Godot 导入；
`export_presets.cfg` 的 `exclude_filter` 与 `patch_delta_exclude_filters` 同时显式排除
`audio_intake/*,audio_intake/**/*`。因此收件区的 WAV 母版、来源截图和许可证明均不进正式包或增量补丁。
不能全局排除 `*.wav`：`audio/sfx/` 下的正式机炮、导弹、爆炸和引擎音效仍需要随包发布。

### 主菜单音乐

`main_menu` → `audio/music/main_menu.ogg`，48kHz stereo、Vorbis Quality 5、循环播放。
`main_menu._ready` 仅在该曲尚未播放时以 2.0 秒淡入/交叉淡化取得音乐；资料库、商店与选图等
菜单链路不会重复重启。`survivor_mode._ready` 以 `crossfade_music_playlist` 平滑交给普通战斗双曲歌单。

## 音量调整速查

| 调什么 | 怎么调 |
|---|---|
| 全局类别音量 | 运行时：`set_bus_volume_linear("SFX", 0.5)`；默认：改 `DEFAULT_BUS_DB` |
| 单个音效相对其它 | 修改 `play_sfx_2d` 调用的 `volume_db` 参数 |
| 远距无线电味强弱 | `_apply_sfx_effects` 里改 `rev.wet` / HighPass cutoff |
| 引擎听到的最远缩放 | `ENGINE_ZOOM_MIN` / `ENGINE_ZOOM_MAX` |
| 菜单模糊强度 | `MUFFLE_CUTOFF_MENU`（越低越糊） |

## 格式要求

- **BGM**：`.ogg` Vorbis, 48kHz stereo, Quality 5（约 146～162 kbps；与现有正式 BGM 一致）
- **SFX**：`.wav` PCM, 44.1kHz **mono**（定位音效必须 mono）, 16-bit, ≤ 2s
- **UI**：`.wav`, 可 stereo（非定位）, ≤ 0.5s

## 集成点

- `survivor_mode._ready` 启动 playlist + 玩家引擎音
- `main_menu._ready` → 幂等播放 `main_menu` 循环曲；生存模式开局平滑交给普通战斗 playlist
- `ace_reinforcement_event` 的 Ace 中队血条浮现 → `survivor_mode.begin_ace_battle_music` 随机抽一首；
  `music_track_finished` 或中队终态 → `end_ace_battle_music`，仅当当前仍为该王牌曲且未进 Boss/Game Over 时恢复普通歌单
- `survivor_mode._unhandled_input` ESC 退主菜单 → `stop_music(1.0)`
- `_on_player_leveled_up` / `_on_upgrade_selected` → `set_music_muffled(true/false)`
- `tactical_map.open/close` → `set_music_muffled(true/false)`
- `survivor_spawner._spawn_f47_squad` → BOSS 登场 `crossfade_music("boss", 2.0)`
- `aircraft._update_gun` / `_fire_missile_at` / salvo loop → `play_sfx_2d`
- `missile_manager._physics_process` 命中分支 → `play_sfx_2d` 爆炸声
- `main_menu._on_audio_settings_pressed` → 弹出音频设置面板
