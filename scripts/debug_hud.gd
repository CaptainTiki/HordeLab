extends Label
class_name DebugHUD

@export var horde_path: NodePath
@export var flow_field_path: NodePath

@onready var horde: HordeSimulation = get_node(horde_path) as HordeSimulation
@onready var flow_field: FlowField = get_node(flow_field_path) as FlowField

var update_accumulator: float = 0.0
var frame_time_accumulator_ms: float = 0.0
var sampled_frames: int = 0

func _process(delta: float) -> void:
	update_accumulator += delta
	frame_time_accumulator_ms += delta * 1000.0
	sampled_frames += 1
	if update_accumulator < 0.25:
		return

	var average_frame_ms: float = 0.0
	if sampled_frames > 0:
		average_frame_ms = frame_time_accumulator_ms / float(sampled_frames)

	var flow_state: String = "REBUILD" if flow_field.rebuild_in_progress else "READY"
	text = "FPS: %d   Frame: %.2f ms   Horde: %d   Flow: %s" % [
		Engine.get_frames_per_second(),
		average_frame_ms,
		horde.agent_count,
		flow_state,
	]

	update_accumulator = 0.0
	frame_time_accumulator_ms = 0.0
	sampled_frames = 0
