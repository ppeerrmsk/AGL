extends RefCounted
const Review := preload("res://scripts/diagnostics/tokyo_f5_review.gd")


class ReturnInputProbe extends "res://scripts/tests/tokyo_camera_return_audit.gd":
	func keys(wanted: Array[int]) -> void:
		held=wanted.duplicate()


class ReturnBattleProbe extends Node:
	var camera := Node2D.new()
	var _camera_ctrl := {"_wasd_velocity":Vector2.ZERO}


static func departure_resume_checks() -> bool:
	var audit := ReturnInputProbe.new()
	var battle := ReturnBattleProbe.new()
	audit.phase=0
	audit.departure.assign([KEY_D])
	audit.step(battle,1100,true)
	var okay := audit.held==[KEY_D]
	audit.step(battle,1200,false)
	okay=okay and audit.held.is_empty() and audit.departure==[KEY_D]
	audit.step(battle,1200,false)
	audit.step(battle,1200,true)
	okay=okay and audit.held==[KEY_D] and audit.departure_resumes==1
	audit.step(battle,1300,true)
	okay=okay and audit.held==[KEY_D] and audit.departure_resumes==1
	audit.keys([])
	battle.camera.free()
	battle.free()
	print("[Tokyo return modal resume] fail=",int(not okay))
	return okay


static func departure_checks() -> bool:
	var audit := preload("res://scripts/tests/tokyo_camera_return_audit.gd")
	var bounds := Rect2(-10000,-10000,20000,20000)
	var size := Vector2(1920,1080)
	var okay := true
	# 玩家与镜头均位于东边界：固定D键完全不能移开；应选真实可达的反方向。
	for scale: float in [0.2,5.0]:
		var half := size/(2.0*scale)
		var center := Vector2(bounds.end.x-half.x,0)
		okay=okay and audit.departure_key(center,center,bounds,size,scale,0)!=KEY_D
		center=Vector2(bounds.position.x+half.x,0)
		okay=okay and audit.departure_key(center,center,bounds,size,scale,2)!=KEY_A
	# 无边界时保留同距离的轮换方向；极小地图按正式镜头规则居中，不能伪造距离。
	var codes: Array[int]=[KEY_D,KEY_W,KEY_A,KEY_S]
	for preferred in 4:
		okay=okay and audit.departure_key(Vector2.ZERO,Vector2.ZERO,Rect2(),size,1.0,preferred)==codes[preferred]
	okay=okay and audit.clamped_position(Vector2(999,999),Rect2(-10,-10,20,20),size)==Vector2.ZERO
	print("[Tokyo return departure] fail=",int(not okay))
	return okay


static func continuity_checks() -> bool:
	var probe := preload("res://scripts/tests/tokyo_input_continuity.gd")
	var samples: Array[Dictionary]=[]
	# 已开始响应后镜头停500ms，战斗仍推进；旧首响应/终点判据会漏掉此例。
	for time: int in [0,20,40,140,240,340,440,540,560,580]:
		var x := float(mini(time,40)) if time<560 else float(time-500)
		samples.append({"tick_us":time*1000,"ms":time,"input_open":true,"return_case":0,
			"return_excess_px":500.0,"physics_step":time/16,"player_position":[time*0.1,0],
			"position":[x,0],"zoom":1.0,"camera_wait_started":40,"pending_pan":500.0,"reason":"waiting"})
	var stopped: Dictionary=probe.summarize(samples)
	var okay: bool=is_equal_approx(stopped.max_camera_stop_ms,520.0) and stopped.freeze_episodes==1 \
		and stopped.space_cases["0"].max_camera_stop_ms==520.0 and stopped.camera_stops[0].player_moved>0
	okay=okay and stopped.stationary_pan_frames==5 and stopped.max_stationary_pan_ms==500.0 and stopped.map_limited_samples==9
	# 模态期间暂停不算可操控卡死，但墙钟停顿仍单独记录。
	var modal := samples.duplicate(true)
	for row: Dictionary in modal: row.input_open=false
	var paused: Dictionary=probe.summarize(modal)
	okay=okay and paused.freeze_episodes==0 and paused.max_camera_stop_ms==0 and paused.modal_ms==580.0
	# 卡住尚未恢复就弹出模态，也必须保留之前已经发生的500ms冻结。
	var interrupted := samples.duplicate(true)
	for index in range(8,interrupted.size()): interrupted[index].input_open=false
	var interrupted_result: Dictionary=probe.summarize(interrupted)
	okay=okay and interrupted_result.freeze_detected and interrupted_result.max_camera_stop_ms==500.0
	# 整幅画面断更后镜头直接追上：有位移也必须记400ms卡顿。
	var gap: Array[Dictionary]=[samples[0].duplicate(true),samples[-1].duplicate(true)]
	gap[1].tick_us=400000;gap[1].ms=400
	var blocked: Dictionary=probe.summarize(gap)
	okay=okay and blocked.max_present_gap_ms==400.0 and blocked.freeze_episodes>0
	okay=okay and blocked.stationary_pan_frames==0 and blocked.max_stationary_pan_ms==0.0
	var zoom_samples := samples.duplicate(true)
	for row: Dictionary in zoom_samples:
		row.position=[row.ms,0];row.target_zoom=2.0
		row.zoom=1.1 if row.ms>=560 else 1.0
	var zoom_blocked: Dictionary=probe.summarize(zoom_samples)
	okay=okay and zoom_blocked.max_camera_stop_ms<=100.0 and zoom_blocked.max_zoom_stop_ms==560.0 and zoom_blocked.notice_detected
	print("[Tokyo input continuity] fail=",int(not okay))
	return okay


static func run() -> int:
	var good := continuity_checks() and departure_checks() and departure_resume_checks() and Review.request_path(PackedStringArray(),true).is_empty()
	good=good and Review.request_path(PackedStringArray(["--tokyo-f5-review=res://tmp/review.json"]),true)=={"path":"res://tmp/review.json"}
	for arguments: PackedStringArray in [PackedStringArray(["--tokyo-f5-review=res://tmp/../project.godot"]),
		PackedStringArray(["--tokyo-f5-review=F:/outside.json"]),PackedStringArray(["--tokyo-f5-review=res://tmp/a.json","--tokyo-f5-review=res://tmp/b.json"])]:
		good=good and Review.request_path(arguments,true).has("error")
	good=good and Review.request_path(PackedStringArray(["--tokyo-f5-review=res://tmp/review.json"]),false).has("error")
	var valid := {"schema":1,"package":{"path":"res://resources/maps/tokyo_playable/candidate/package.json","sha256":"a".repeat(64)},
		"run":"f5_round_1","seconds":45,"pose":[-3997.733,-15061.16,2.38363528251648]}
	good=good and Review.valid_request(valid)
	good=good and Review.stream_options(valid)=={"AGL_TOKYO_REUSE_TEXTURE":"0","AGL_TOKYO_BALANCED_IO":"0","AGL_TOKYO_CACHE_MIB":"96","AGL_TOKYO_WIDE_HANDOFF":"0","AGL_TOKYO_FAST_FILE_PROBE":"0","AGL_TOKYO_RESIDENT_FOUNDATION":"0","AGL_TOKYO_GUARD_PREFETCH":"0"}
	var optimized := valid.duplicate(true);optimized["stream_optimizations"]=true
	good=good and Review.valid_request(optimized) and Review.stream_options(optimized)=={"AGL_TOKYO_REUSE_TEXTURE":"1","AGL_TOKYO_BALANCED_IO":"1","AGL_TOKYO_CACHE_MIB":"96","AGL_TOKYO_WIDE_HANDOFF":"0","AGL_TOKYO_FAST_FILE_PROBE":"0","AGL_TOKYO_RESIDENT_FOUNDATION":"0","AGL_TOKYO_GUARD_PREFETCH":"0"}
	for budget: Variant in [96,192,384,192.0]:
		var configured := valid.duplicate(true);configured["cache_budget_mib"]=budget
		good=good and Review.valid_request(configured) and Review.stream_options(configured).AGL_TOKYO_CACHE_MIB==str(int(budget))
		good=good and Review.valid_request(JSON.parse_string(JSON.stringify(configured)))
	for budget: Variant in [null,true,0,97,256,768,192.5,"192"]:
		var configured := valid.duplicate(true);configured["cache_budget_mib"]=budget
		good=good and not Review.valid_request(configured)
	var wide := valid.duplicate(true);wide["wide_handoff"]=true
	good=good and Review.valid_request(wide) and Review.stream_options(wide).AGL_TOKYO_WIDE_HANDOFF=="1"
	for invalid: Variant in [1,"true",null]:
		var wrong := valid.duplicate(true);wrong["wide_handoff"]=invalid
		good=good and not Review.valid_request(wrong)
	var fast := valid.duplicate(true);fast["fast_file_probe"]=true
	var path_prefetch := valid.duplicate(true);path_prefetch["guard_prefetch"]=true
	good=good and Review.valid_request(path_prefetch) and Review.stream_options(path_prefetch).AGL_TOKYO_GUARD_PREFETCH=="1"
	for wrong_value: Variant in [1,"true",null]:
		var wrong := valid.duplicate(true);wrong["guard_prefetch"]=wrong_value
		good=good and not Review.valid_request(wrong)
	var resident := valid.duplicate(true);resident["resident_foundation"]=true
	good=good and Review.valid_request(resident) and Review.stream_options(resident).AGL_TOKYO_RESIDENT_FOUNDATION=="1"
	for invalid: Variant in [1,"true",null]:
		var wrong := valid.duplicate(true);wrong["resident_foundation"]=invalid
		good=good and not Review.valid_request(wrong)
	good=good and Review.valid_request(fast) and Review.stream_options(fast).AGL_TOKYO_FAST_FILE_PROBE=="1"
	for invalid: Variant in [1,"true",null]:
		var wrong := valid.duplicate(true);wrong["fast_file_probe"]=invalid
		good=good and not Review.valid_request(wrong)
	for setting: Variant in [1,"true",null]:
		var configured := valid.duplicate(true);configured["stream_optimizations"]=setting
		good=good and not Review.valid_request(configured)
	for mode: String in ["manual","automatic"]:
		var configured := valid.duplicate(true);configured["mode"]=mode
		good=good and Review.valid_request(configured)
	for mode: Variant in [true,1,"unknown"]:
		var configured := valid.duplicate(true);configured["mode"]=mode
		good=good and not Review.valid_request(configured)
	for field: String in ["schema","package","run","seconds","pose"]:
		var broken := valid.duplicate(true);broken.erase(field)
		good=good and not Review.valid_request(broken)
	for duration: Variant in [true,0,29,121,45.5,"45"]:
		var broken := valid.duplicate(true);broken.seconds=duration
		good=good and not Review.valid_request(broken)
	var broken := valid.duplicate(true);broken.package.path="res://resources/maps/tokyo_playable/../outside.json"
	good=good and not Review.valid_request(broken)
	broken=valid.duplicate(true);broken.pose=[0,0,INF]
	good=good and not Review.valid_request(broken)
	print("[Tokyo explicit F5 review] fail=",int(not good))
	return int(not good)
