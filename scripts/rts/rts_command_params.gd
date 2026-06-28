class_name RtsCommandParams
extends Resource

## RTS 指挥可调参数（去硬编码）。策划在 Inspector 里调，默认资源 resources/rts_command.tres。
## 仅约束"自动交战"（auto-engage）行为；玩家显式命令（commanded_target）走铁律，不受这些参数影响。
## 设计见 docs/specs/systems/rts-command.md。

## 到点/空闲时长机自动锁敌的搜索半径（像素，=750m @ PIXELS_PER_METER=0.5）。
## 刻意小：只自动打"贴脸"的敌人，远处交给玩家手动指挥。
@export var auto_engage_radius_px: float = 1500.0

## 拴绳系数：自动锁的目标飞出 radius × 此值 则放弃，回到待命再重选。
## 注意：仅作用于"自动锁的目标"（_auto_engage_target），绝不碰玩家命令目标。
@export var auto_engage_leash_mult: float = 1.5

## 自动交战决策 tick 频率（秒）。低频，遵守性能守则（≥3 分频）。
@export var auto_engage_interval_s: float = 0.3
