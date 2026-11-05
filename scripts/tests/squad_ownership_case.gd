extends RefCounted
## 真实致命伤害与队级终态后，观察者不得把 RefCounted 宿主反向保活。

static func run(parent: Node) -> int:
	var failures := 0
	for kind in ["wraith", "poltergeist", "theme"]:
		var owner: AceSquad
		if kind == "wraith":
			owner = F47AceSquad.new()
		elif kind == "poltergeist":
			owner = PoltergeistSquad.new()
		else:
			owner = AceSupportSquad.new("marathon")
		var member := Aircraft.new()
		member.params = AircraftParams.new()
		member.set_physics_process(false)
		parent.add_child(member)
		owner.members.assign([member])
		owner.all_members.assign([member])
		var extras: Array[Aircraft] = []
		if kind == "wraith":
			for i in range(5):
				var extra := Aircraft.new()
				extra.params = AircraftParams.new()
				extra.set_physics_process(false)
				parent.add_child(extra)
				owner.members.append(extra)
				owner.all_members.append(extra)
				extras.append(extra)
		owner.active = true
		owner.combat_phase_active = true
		var controller: RefCounted
		if kind == "theme":
			controller = AceSquadThemeController.new(owner, "altitude_chain", null)
			(owner as AceSupportSquad)._theme_controller = controller
			(owner as AceSupportSquad).update_theme(0.6, false)
		else:
			owner._tactics_enter()
			controller = owner.get("tactics")
		var owner_probe: WeakRef = weakref(owner)
		var controller_probe: WeakRef = weakref(controller)
		if kind == "wraith":
			for i in range(extras.size()):
				extras[i].take_damage(1000000.0)
				owner.update(0.6)
				await parent.get_tree().process_frame
				owner.update(0.6)
				var still_active := owner.active and owner.members.size() == 5 - i
				print("[SquadOwnership] Wraith 击毁 %d 架仍未胜利=%s" % [i + 1, still_active])
				failures += int(not still_active)
		member.take_damage(1000000.0)
		owner.update(0.6)
		var terminal := member.is_destroyed and not owner.active
		owner._tactics_exit()
		owner = null
		await parent.get_tree().process_frame
		var released := owner_probe.get_ref() == null
		# 外部暂留控制器，跨过其下一次决策调用；宿主已释放时必须安全返回。
		controller.update(0.6)
		if kind != "theme":
			controller.start()
			controller.stop()
		var detached: bool = controller.get("_squad") == null
		controller = null
		member.queue_free()
		for extra in extras:
			if is_instance_valid(extra):
				extra.queue_free()
		await parent.get_tree().process_frame
		var clean := controller_probe.get_ref() == null
		var ok := terminal and released and detached and clean
		print("[SquadOwnership] %s terminal=%s owner_released=%s detached=%s controller_released=%s" % [kind, terminal, released, detached, clean])
		failures += int(not ok)
	return failures
