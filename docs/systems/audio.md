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
| Radio | -10 | 无线电人声（Step 2 未启用） | HighPass + LowPass + Distortion |

默认值在 `AudioManager.DEFAULT_BUS_DB`。用户通过[音频设置面板](../../scripts/audio/audio_settings_panel.gd)调整后持久化到 `user://audio.cfg`。

## API 一览

### 音乐

```gdscript
AudioManager.play_music(id, fade_in=1.5, loop=true)
AudioManager.stop_music(fade_out=2.0)
AudioManager.crossfade_music(id, duration=2.0, loop=true)
AudioManager.play_music_playlist(ids, fade_in=2.0, crossfade_between=2.0)
AudioManager.set_music_muffled(muffled, duration=0.35)
```

双播放器轮换实现 crossfade（`_music_player_a` / `_music_player_b`）。
**播放列表模式**：首曲淡入后 `loop=false`，播完触发 `finished` → 自动 crossfade 下一首，周而复始。调用 `play_music/crossfade_music/stop_music` 会自动退出 playlist 模式（BOSS 登场就是靠这个）。
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

## 音量调整速查

| 调什么 | 怎么调 |
|---|---|
| 全局类别音量 | 运行时：`set_bus_volume_linear("SFX", 0.5)`；默认：改 `DEFAULT_BUS_DB` |
| 单个音效相对其它 | 修改 `play_sfx_2d` 调用的 `volume_db` 参数 |
| 远距无线电味强弱 | `_apply_sfx_effects` 里改 `rev.wet` / HighPass cutoff |
| 引擎听到的最远缩放 | `ENGINE_ZOOM_MIN` / `ENGINE_ZOOM_MAX` |
| 菜单模糊强度 | `MUFFLE_CUTOFF_MENU`（越低越糊） |

## 格式要求

- **BGM**：`.ogg` Vorbis, 44.1kHz stereo, Quality 5（~160 kbps）
- **SFX**：`.wav` PCM, 44.1kHz **mono**（定位音效必须 mono）, 16-bit, ≤ 2s
- **UI**：`.wav`, 可 stereo（非定位）, ≤ 0.5s

## 集成点

- `survivor_mode._ready` 启动 playlist + 玩家引擎音
- `survivor_mode._unhandled_input` ESC 退主菜单 → `stop_music(1.0)`
- `_on_player_leveled_up` / `_on_upgrade_selected` → `set_music_muffled(true/false)`
- `tactical_map.open/close` → `set_music_muffled(true/false)`
- `survivor_spawner._spawn_f47_squad` → BOSS 登场 `crossfade_music("boss", 2.0)`
- `aircraft._update_gun` / `_fire_missile_at` / salvo loop → `play_sfx_2d`
- `missile_manager._physics_process` 命中分支 → `play_sfx_2d` 爆炸声
- `main_menu._on_audio_settings_pressed` → 弹出音频设置面板
