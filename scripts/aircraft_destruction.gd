class_name AircraftDestruction
extends RefCounted

## 飞机坠毁动画系统（静态工具类）
## 从 aircraft.gd 提取：支持三种坠落风格（fighter / bomber / heli）
## 状态变量 (_destroy_timer/_destroy_spin/_destroy_bank_rate) 保留在 Aircraft，
## 因为外部代码（commander_overlay, survivor_mode）会读取 _destroy_timer 做淡出等。
##
## 用法（在 aircraft.gd 中）：
##   AircraftDestruction.start(self)     # 开始坠毁
##   AircraftDestruction.update(self, delta)  # 每帧推进

## 开始坠毁：根据 crash_style meta 选择动画参数
static func start(ac: Aircraft) -> void:
	EventLogger.log_event("DESTROY", ac._log_name(),
		"destroyed (alt=%.0fm, spd=%.0fm/s)" % [ac.altitude, ac.speed])
	# 注：不在这里画爆炸闪光。爆炸特效只属于"被爆炸物（导弹/火箭/AOE）击杀"的情况，
	# 由伤害源在 take_damage 前自行 ExplosionVFX.emit；机炮致命/坠地/燃油耗尽等非爆炸死亡不画。
	# 回收 callsign
	CallsignDB.recycle(ac.callsign)
	ac.is_destroyed = true
	ac.is_firing = false
	ac.combat_target = null
	# 坠落风格：不同机种有不同的坠毁动画参数
	# "bomber" = 重型轰炸机，小幅旋转 + 持续侧翻，下坠更久
	# "heli"   = 直升机，尾桨失效快速自旋 + 中速下坠
	# 默认      = 战斗机，失控旋转下坠
	var style: String = ac.get_meta("crash_style", "default") if ac.has_meta("crash_style") else "default"
	if style == "bomber":
		ac._destroy_timer = Aircraft.BOMBER_CRASH_DURATION
		# 轰炸机重量大：偏航旋转慢；但用 bank_angle 模拟持续侧翻
		ac._destroy_spin = randf_range(-Aircraft.BOMBER_YAW_SPIN_RANGE, Aircraft.BOMBER_YAW_SPIN_RANGE)
		# 初始随机方向的侧翻（左/右），一边倒的滚动
		ac._destroy_bank_rate = randf_range(Aircraft.BOMBER_ROLL_RATE_MIN, Aircraft.BOMBER_ROLL_RATE_MAX) * (1.0 if randf() < 0.5 else -1.0)
	elif style == "heli":
		# 直升机坠落：尾桨失效导致快速自旋（helicopter "autorotation fail"）
		# 比战斗机更剧烈的 yaw，但下坠速度接近战斗机
		ac._destroy_timer = Aircraft.HELI_CRASH_DURATION
		ac._destroy_spin = randf_range(-Aircraft.HELI_YAW_SPIN_RANGE, Aircraft.HELI_YAW_SPIN_RANGE) * (1.0 if randf() < 0.5 else -1.0)
		# 轻微随机侧翻
		ac._destroy_bank_rate = randf_range(-Aircraft.HELI_ROLL_RATE_RANGE, Aircraft.HELI_ROLL_RATE_RANGE)
	else:
		ac._destroy_timer = Aircraft.FIGHTER_CRASH_DURATION
		ac._destroy_spin = randf_range(-Aircraft.FIGHTER_YAW_SPIN_RANGE, Aircraft.FIGHTER_YAW_SPIN_RANGE)
		ac._destroy_bank_rate = 0.0

## 每帧推进坠落动画
static func update(ac: Aircraft, delta: float) -> void:
	var style: String = ac.get_meta("crash_style", "default") if ac.has_meta("crash_style") else "default"

	if style == "bomber":
		# 轰炸机坠落：偏航慢、下坠慢、持续侧翻
		ac.heading += ac._destroy_spin * delta
		ac.altitude -= Aircraft.BOMBER_DESCENT_MPS * delta
		ac.speed = maxf(ac.speed - Aircraft.BOMBER_SPEED_DECAY * delta, Aircraft.BOMBER_MIN_SPEED)
		# 持续侧翻：bank_angle 一直累加（会越过 ±PI 进入倒飞视觉）
		ac.bank_angle += ac._destroy_bank_rate * delta
		var velocity := Vector2(sin(ac.heading), -cos(ac.heading)) * ac.speed * Aircraft.BOMBER_MOVE_SCALE * GameConstants.PIXELS_PER_METER
		ac.global_position += velocity * delta
		ac.rotation = ac.heading
	elif style == "heli":
		# 直升机坠落：尾桨失效 → 极快自旋 + 中等下坠（约 220 m/s），几乎原地打转下坠
		ac.heading += ac._destroy_spin * delta
		ac.altitude -= Aircraft.HELI_DESCENT_MPS * delta
		ac.speed = maxf(ac.speed - Aircraft.HELI_SPEED_DECAY * delta, Aircraft.HELI_MIN_SPEED)  # 很快减速
		ac.bank_angle += ac._destroy_bank_rate * delta
		var velocity := Vector2(sin(ac.heading), -cos(ac.heading)) * ac.speed * Aircraft.HELI_MOVE_SCALE * GameConstants.PIXELS_PER_METER
		ac.global_position += velocity * delta
		ac.rotation = ac.heading
	else:
		# 战斗机失控旋转下坠
		ac.heading += ac._destroy_spin * delta
		ac.altitude -= Aircraft.FIGHTER_DESCENT_MPS * delta
		ac.speed = maxf(ac.speed - Aircraft.FIGHTER_SPEED_DECAY * delta, Aircraft.FIGHTER_MIN_SPEED)
		var velocity := Vector2(sin(ac.heading), -cos(ac.heading)) * ac.speed * GameConstants.PIXELS_PER_METER
		ac.global_position += velocity * delta
		ac.rotation = ac.heading

	ac._destroy_timer -= delta
	if ac._destroy_timer <= 0.0 or ac.altitude <= 0.0:
		ac.queue_free()
