class_name SquadFearConeConfig
extends Resource

## 纯配置，可由任何小队装配；每个控制器复制配置，计时绝不写进 Resource。
@export var range_m := 3000.0
@export var angle_deg := 60.0
@export var warning_s := 1.0
@export var emission_s := 6.0
@export var exposure_s := 2.0
@export var fear_s := 5.0
@export var initial_wait_s := 10.0
@export var cooldown_min_s := 18.0
@export var cooldown_max_s := 24.0
@export var max_emitters := 1
@export var color := Color("b05cff")

func valid() -> bool:
	return range_m > 0.0 and angle_deg > 0.0 and angle_deg <= 180.0 \
		and warning_s > 0.0 and emission_s > 0.0 and exposure_s > 0.0 \
		and fear_s > 0.0 and initial_wait_s >= 0.0 and cooldown_min_s >= 0.0 \
		and cooldown_max_s >= cooldown_min_s and max_emitters == 1
