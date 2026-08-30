extends Label
class_name DebugHUD

@export var horde_path: NodePath
@export var flow_field_path: NodePath
@export var recent_window_seconds: float = 2.0

@onready var horde: HordeSimulation = get_node(horde_path) as HordeSimulation
@onready var flow_field: FlowField = get_node(flow_field_path) as FlowField

var update_accumulator: float = 0.0
var frame_time_accumulator_ms: float = 0.0
var sampled_frames: int = 0
var recent_window_accumulator: float = 0.0
var recent_worst_frame_ms: float = 0.0
var recent_worst_sim_ms: float = 0.0
var displayed_recent_worst_frame_ms: float = 0.0
var displayed_recent_worst_sim_ms: float = 0.0
var peak_frame_ms: float = 0.0
var peak_sim_ms: float = 0.0

func _process(delta: float) -> void:
	var frame_ms: float = delta * 1000.0
	update_accumulator += delta
	frame_time_accumulator_ms += frame_ms
	sampled_frames += 1

	recent_window_accumulator += delta
	recent_worst_frame_ms = maxf(recent_worst_frame_ms, frame_ms)
	recent_worst_sim_ms = maxf(recent_worst_sim_ms, horde.last_simulation_ms)
	peak_frame_ms = maxf(peak_frame_ms, frame_ms)
	peak_sim_ms = maxf(peak_sim_ms, horde.last_simulation_ms)

	if recent_window_accumulator >= maxf(recent_window_seconds, 0.25):
		displayed_recent_worst_frame_ms = recent_worst_frame_ms
		displayed_recent_worst_sim_ms = recent_worst_sim_ms
		recent_window_accumulator = 0.0
		recent_worst_frame_ms = 0.0
		recent_worst_sim_ms = 0.0

	if update_accumulator < 0.25:
		return

	var average_frame_ms: float = 0.0
	if sampled_frames > 0:
		average_frame_ms = frame_time_accumulator_ms / float(sampled_frames)

	var flow_state: String = "REBUILD" if flow_field.rebuild_in_progress else "READY"
	text = "FPS: %d   Avg: %.2f ms   Recent worst: %.2f ms   Peak: %.2f ms   Horde: %d   Slice: %.2f ms / %d agents   Recent slice: %.2f ms   Peak slice: %.2f ms   Agent Hz: %.1f   Flow: %s   Last rebuild: %.1f ms / %d frames" % [
		Engine.get_frames_per_second(),
		average_frame_ms,
		displayed_recent_worst_frame_ms,
		peak_frame_ms,
		horde.agent_count,
		horde.last_simulation_ms,
		horde.agents_processed_last_frame,
		displayed_recent_worst_sim_ms,
		peak_sim_ms,
		horde.effective_updates_per_second,
		flow_state,
		flow_field.last_rebuild_ms,
		flow_field.last_rebuild_frames,
	]

	update_accumulator = 0.0
	frame_time_accumulator_ms = 0.0
	sampled_frames = 0
