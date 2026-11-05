extends RefCounted
## 操作连续性：按墙钟量出回程中途停住与整幅画面断更，不用平均 FPS 替代。
const NOTICE_US := 50000
const FREEZE_US := 250000


static func returning(row: Dictionary) -> bool:
	return int(row.get("return_case",-1))>=0 and float(row.get("return_excess_px",0.0))>20.0


static func summarize(samples: Array) -> Dictionary:
	var result := {"max_present_gap_ms":0.0,"max_camera_stop_ms":0.0,"max_player_stop_ms":0.0,
		"map_limited_samples":0,"stationary_pan_frames":0,"max_stationary_pan_ms":0.0,
		"stationary_zoom_frames":0,"max_stationary_zoom_ms":0.0,
		"max_zoom_stop_ms":0.0,"zoom_stops":[],"present_hitches":[],"camera_stops":[],"space_cases":{},"modal_ms":0.0,
		"notice_ms":NOTICE_US/1000.0,"freeze_ms":FREEZE_US/1000.0,"freeze_episodes":0,
		"pixel_coverage_verified":false,"clock":"wall_microseconds"}
	var camera_anchor := Vector2.INF
	var player_anchor := Vector2.INF
	var camera_since := -1
	var player_since := -1
	var camera_first: Dictionary={}
	var zoom_since := -1
	var zoom_anchor := 1.0
	var zoom_first: Dictionary={}
	var stationary_pan_us := 0
	var stationary_zoom_us := 0
	for index in range(1,samples.size()):
		var before: Dictionary=samples[index-1]
		var row: Dictionary=samples[index]
		var now := int(row.tick_us)
		var interval := now-int(before.tick_us)
		if not row.input_open or not before.input_open:
			result.modal_ms+=interval/1000.0
			camera_since=-1;player_since=-1;zoom_since=-1
			stationary_pan_us=0;stationary_zoom_us=0
			continue
		result.max_present_gap_ms=maxf(result.max_present_gap_ms,interval/1000.0)
		# 零等待门不依赖50ms容忍值：部分推进、完全停住均保留，不把正常帧间隔叫停顿。
		if int(row.get("camera_wait_started",-1))>=0 or float(row.get("pending_pan",0.0))*float(row.zoom)>0.5:
			result.map_limited_samples+=1
		var slot := int(before.get("return_case",-1))
		var case_result: Dictionary={}
		if slot>=0:
			case_result=result.space_cases.get(str(slot),{"max_present_gap_ms":0.0,"max_camera_stop_ms":0.0,"max_player_stop_ms":0.0})
			case_result.max_present_gap_ms=maxf(case_result.max_present_gap_ms,interval/1000.0)
			result.space_cases[str(slot)]=case_result
		if interval>=NOTICE_US:
			result.present_hitches.append({"start_ms":before.ms,"end_ms":row.ms,"duration_ms":interval/1000.0,
				"return_case":slot,"map_reason":row.reason,"pending_pan":row.pending_pan,
				"physics_steps":int(row.physics_step)-int(before.physics_step)})
			result.freeze_episodes+=int(interval>=FREEZE_US)
		var player := Vector2(row.player_position[0],row.player_position[1])
		if player_since<0:
			player_since=int(before.tick_us);player_anchor=Vector2(before.player_position[0],before.player_position[1])
		var player_stop := (now-player_since)/1000.0
		result.max_player_stop_ms=maxf(result.max_player_stop_ms,player_stop)
		if not case_result.is_empty(): case_result.max_player_stop_ms=maxf(case_result.max_player_stop_ms,player_stop)
		if player.distance_to(player_anchor)>0.01: player_since=now;player_anchor=player
		# 平移仍在推进不能掩盖滚轮被卡住；缩放独立量到下一次实际变化。
		var zoom_demanded := absf(log(maxf(float(before.get("target_zoom",before.zoom)),0.001)/maxf(float(before.zoom),0.001)))>0.02
		if zoom_demanded and absf(float(row.zoom)-float(before.zoom))<0.000001:
			stationary_zoom_us+=interval;result.stationary_zoom_frames+=1
			result.max_stationary_zoom_ms=maxf(result.max_stationary_zoom_ms,stationary_zoom_us/1000.0)
		else: stationary_zoom_us=0
		if zoom_demanded:
			if zoom_since<0:
				zoom_since=int(before.tick_us);zoom_anchor=float(before.zoom);zoom_first=before
			var zoom_stop := (now-zoom_since)/1000.0
			result.max_zoom_stop_ms=maxf(result.max_zoom_stop_ms,zoom_stop)
			if absf(log(maxf(float(row.zoom),0.001)/maxf(zoom_anchor,0.001)))>0.0001 or index==samples.size()-1:
				if zoom_stop>=NOTICE_US/1000.0:
					result.zoom_stops.append({"start_ms":zoom_first.ms,"end_ms":row.ms,"duration_ms":zoom_stop,"reason":before.reason})
				zoom_since=now;zoom_anchor=float(row.zoom);zoom_first=row
		else: zoom_since=-1
		var demanded := returning(before) or (int(before.camera_wait_started)>=0 and float(before.pending_pan)*float(before.zoom)>0.5)
		var camera := Vector2(row.position[0],row.position[1])
		if demanded and camera.distance_to(Vector2(before.position[0],before.position[1]))*float(row.zoom)<0.01:
			stationary_pan_us+=interval;result.stationary_pan_frames+=1
			result.max_stationary_pan_ms=maxf(result.max_stationary_pan_ms,stationary_pan_us/1000.0)
		else: stationary_pan_us=0
		if demanded:
			if camera_since<0:
				camera_since=int(before.tick_us);camera_anchor=Vector2(before.position[0],before.position[1]);camera_first=before
			var stopped := (now-camera_since)/1000.0
			# 量到下一次实际推进，包含恢复的末帧；不能用先响应一下掩盖后续停顿。
			result.max_camera_stop_ms=maxf(result.max_camera_stop_ms,stopped)
			if not case_result.is_empty(): case_result.max_camera_stop_ms=maxf(case_result.max_camera_stop_ms,stopped)
			if camera.distance_to(camera_anchor)*float(row.zoom)>0.25 or index==samples.size()-1:
				if stopped>=NOTICE_US/1000.0:
					result.camera_stops.append({"start_ms":camera_first.ms,"end_ms":row.ms,"duration_ms":stopped,
						"return_case":camera_first.get("return_case",-1),"reason":before.reason,
						"player_moved":player.distance_to(Vector2(camera_first.player_position[0],camera_first.player_position[1])),
						"start_zoom":camera_first.zoom,"end_zoom":row.zoom,"pending_pan":before.pending_pan})
					result.freeze_episodes+=int(stopped>=FREEZE_US/1000.0)
				camera_since=now;camera_anchor=camera;camera_first=row
		else:
			camera_since=-1
	# 模态或下一输入可以截断尚未恢复的停顿。不能只数已闭合事件而漏掉这段冻结。
	result["freeze_detected"]=float(result.max_camera_stop_ms)>=FREEZE_US/1000.0 \
		or float(result.max_present_gap_ms)>=FREEZE_US/1000.0 or float(result.max_zoom_stop_ms)>=FREEZE_US/1000.0
	result["notice_detected"]=maxf(float(result.max_camera_stop_ms),maxf(float(result.max_zoom_stop_ms),float(result.max_present_gap_ms)))>=NOTICE_US/1000.0
	return result
