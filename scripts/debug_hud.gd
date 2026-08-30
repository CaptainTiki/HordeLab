extends Label
class_name DebugHUD

@export var horde_path: NodePath

@onready var horde: HordeSimulation = get_node(horde_path) as HordeSimulation

var update_accumulator: float = 0.0

func _process(delta: float) -> void:
	update_accumulator += delta
	if update_accumulator < 0.25:
		return
	update_accumulator = 0.0
	text = "FPS: %d   Horde: %d" % [Engine.get_frames_per_second(), horde.agent_count]
