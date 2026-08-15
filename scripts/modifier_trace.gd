class_name ModifierTrace
extends RefCounted

## 非热路径的运行时词条追踪器。通过逐项暂时清除状态、重读真实 accessor 做黑盒差分，
## 不复制物理公式；供 Shift+F12 和无头测试排查“词条到底有没有生效”。

const _EPS := 1e-9


static func _clear_aura(ac: Aircraft) -> void:
	ac.aura_max_g_add = 0.0
	ac.aura_g_structural_add = 0.0
	ac.aura_roll_rate_mult = 1.0
	ac.aura_speed_mult = 1.0
	ac.aura_accel_mult = 1.0
	ac.aura_stall_mult = 1.0


static func _sources(ac: Aircraft) -> Array:
	return [
		{"name": "cloud", "keys": ["cloud_state"],
			"clear": func(): ac.cloud_state = 0},
		{"name": "locked", "keys": ["is_locked"],
			"clear": func(): ac.is_locked = false},
		{"name": "BLOODLUST", "keys": ["status_bloodlust_active"],
			"clear": func(): ac.status_bloodlust_active = false},
		{"name": "OVERLOAD", "keys": ["status_overload_active"],
			"clear": func(): ac.status_overload_active = false},
		{"name": "evasion", "keys": ["evasion_mode"],
			"clear": func(): ac.evasion_mode = false},
		{"name": "executioner", "keys": ["executioner_active"],
			"clear": func(): ac.executioner_active = false},
		{"name": "afterburner", "keys": ["is_afterburner"],
			"clear": func(): ac.is_afterburner = false},
		{"name": "afterburner_window", "keys": ["afterburner_window_active"],
			"clear": func(): ac.afterburner_window_active = false},
		{"name": "command_sprint", "keys": ["command_sprint"],
			"clear": func(): ac.command_sprint = false},
		{"name": "guard_zone", "keys": ["guard_zone_buff_active"],
			"clear": func(): ac.guard_zone_buff_active = false},
		{"name": "J36_assault", "keys": ["sig_j36_assault_active"],
			"clear": func(): ac.sig_j36_assault_active = false},
		{"name": "hunter_assault", "keys": ["hunter_assault_active"],
			"clear": func(): ac.hunter_assault_active = false},
		{"name": "MiG41_dive", "keys": ["_sig_mig41_dive_timer"],
			"clear": func(): ac._sig_mig41_dive_timer = 0.0},
		{"name": "commander_aura", "keys": ["aura_max_g_add", "aura_g_structural_add",
				"aura_roll_rate_mult", "aura_speed_mult", "aura_accel_mult", "aura_stall_mult"],
			"clear": func(): _clear_aura(ac)},
		{"name": "low_hp", "keys": ["hp"],
			"clear": func(): ac.hp = ac.params.max_hp if ac.params else 100.0},
	]


static func _channels(ac: Aircraft) -> Array:
	return [
		{"stat": "max_g", "read": func() -> float: return AircraftPhysics.effective_max_g(ac)},
		{"stat": "max_g_instant", "read": func() -> float: return AircraftPhysics.effective_max_g_instant(ac)},
		{"stat": "max_speed_kmh", "read": func() -> float: return AircraftPhysics.effective_max_speed_kmh(ac)},
		{"stat": "cruise_kmh", "read": func() -> float: return AircraftPhysics.effective_cruise_speed_kmh(ac)},
		{"stat": "stall_kmh", "read": func() -> float: return AircraftPhysics.effective_stall_speed_kmh(ac)},
		{"stat": "corner_kmh", "read": func() -> float: return AircraftPhysics.effective_corner_speed_kmh(ac)},
		{"stat": "accel_mult", "read": func() -> float: return AircraftPhysics.effective_accel_mult(ac, ac.is_afterburner)},
		{"stat": "decel_mult", "read": func() -> float: return AircraftPhysics.effective_decel_mult(ac)},
		{"stat": "cd_rate.weapon", "read": func() -> float: return ac.cd_rate("weapon")},
		{"stat": "cd_rate.flare", "read": func() -> float: return ac.cd_rate("flare")},
		{"stat": "cd_rate.missile_reload", "read": func() -> float: return ac.cd_rate("missile_reload")},
	]


static func _save(ac: Aircraft, source: Dictionary) -> Dictionary:
	var saved: Dictionary = {}
	for key in source["keys"]:
		saved[key] = ac.get(key)
	return saved


static func _restore(ac: Aircraft, saved: Dictionary) -> void:
	for key in saved:
		ac.set(key, saved[key])


static func explain(ac: Aircraft) -> Array:
	var output: Array = []
	var sources := _sources(ac)
	for channel in _channels(ac):
		var read: Callable = channel["read"]
		var final_value: float = read.call()
		var entries: Array = []
		for source in sources:
			var saved := _save(ac, source)
			(source["clear"] as Callable).call()
			var without: float = read.call()
			_restore(ac, saved)
			if absf(without) > _EPS and absf(final_value - without) > absf(without) * 1e-6:
				entries.append({"source": source["name"], "mult": final_value / without})
		var all_saved: Array[Dictionary] = []
		for source in sources:
			all_saved.append(_save(ac, source))
			(source["clear"] as Callable).call()
		var base_value: float = read.call()
		for i in range(sources.size()):
			_restore(ac, all_saved[i])
		output.append({"stat": channel["stat"], "base": base_value,
			"final": final_value, "entries": entries})
	return output


static func print_report(ac: Aircraft) -> void:
	if ac == null or not is_instance_valid(ac) or ac.params == null:
		print("[ModTrace] 无有效飞机")
		return
	var unit_name := ac.callsign if ac.callsign != "" else str(ac)
	print("═══ ModifierTrace: %s ═══" % unit_name)
	for row in explain(ac):
		var entries: Array = row["entries"]
		if entries.is_empty() and is_equal_approx(float(row["base"]), float(row["final"])):
			continue
		var parts: Array[String] = []
		for entry in entries:
			parts.append("%s ×%.3f" % [entry["source"], entry["mult"]])
		var line := "%-22s base=%-9.2f final=%-9.2f ← %s" % [
			row["stat"], row["base"], row["final"],
			" · ".join(parts) if not parts.is_empty() else "(?)"]
		print("  " + line)
		EventLogger.log_event("MODTRACE", unit_name, line)
	print("═══════════════════════════")
