extends Aircraft

## Visual QA 专用：复用真实 AircraftRenderer，但不启动物理、武器与尾迹。


func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	queue_redraw()


func _draw() -> void:
	AircraftRenderer.draw_aircraft_icon(self)
