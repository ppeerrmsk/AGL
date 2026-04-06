extends CanvasLayer

@export var track_aircraft: Aircraft

@onready var info_label: Label = $InfoLabel

func _process(_delta: float) -> void:
	if not track_aircraft:
		_find_selected_aircraft()
	if track_aircraft:
		_update_display()

func _find_selected_aircraft() -> void:
	var main := get_parent()
	if not main:
		return
	for child in main.get_children():
		if child is Aircraft and child.selected:
			track_aircraft = child
			break

func _update_display() -> void:
	var speed_kmh := track_aircraft.speed * 3.6
	var heading_deg := rad_to_deg(track_aircraft.heading)
	if heading_deg < 0:
		heading_deg += 360.0

	var mach := speed_kmh / 1225.0
	var status := "  STALL" if track_aircraft.is_stalled else ""

	info_label.text = "HDG %03d  M%.2f%s" % [roundi(heading_deg), mach, status]
