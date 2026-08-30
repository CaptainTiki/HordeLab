extends Node3D
class_name HordeSimulation

const INVALID_CELL: Vector2i = Vector2i(-1, -1)
const MAX_AGENT_STEP_SECONDS: float = 0.15
const MAX_CELL_TRANSITIONS_PER_UPDATE: int = 4
const MAX_PRESENTATION_EXTRAPOLATION_SECONDS: float = 0.18
const PRESENTATION_RECONCILE_SECONDS: float = 0.10

@export var grid_path: NodePath
@export var flow_field_path: NodePath
@export var agent_count: int = 1000
@export var move_speed: float = 6.0
@export var simulation_hz: float = 30.0
@export var max_agents_per_frame: int = 1500
@export var spawn_center: Vector3 = Vector3(-58.0, 0.75, -30.0)
@export var spawn_extents: Vector2 = Vector2(16.0, 20.0)
@export var agent_radius: float = 0.32
@export var agent_height: float = 1.1
@export var density_weight: int = 16
@export var path_weight: int = 1
@export var lane_offset_fraction: float = 0.28
@export var target_arrival_distance: float = 0.08

@onready var grid: BattlefieldGrid = get_node(grid_path) as BattlefieldGrid
@onready var flow_field: FlowField = get_node(flow_field_path) as FlowField

var positions: Array[Vector3] = []
var lane_offsets: Array[Vector2] = []
var target_cells: Array[Vector2i] = []
var agent_cells: Array[Vector2i] = []
var last_update_usec: PackedInt64Array = PackedInt64Array()
var presentation_velocities: Array[Vector3] = []
var presentation_update_times: PackedFloat32Array = PackedFloat32Array()
var presentation_extrapolation_limits: PackedFloat32Array = PackedFloat32Array()
var density: PackedInt32Array = PackedInt32Array()
var reservations: PackedInt32Array = PackedInt32Array()
var work_accumulator: float = 0.0
var next_agent_index: int = 0
var agents_processed_last_frame: int = 0
var last_simulation_ms: float = 0.0
var effective_updates_per_second: float = 0.0
var update_rate_accumulator: float = 0.0
var updates_in_rate_window: int = 0
var presentation_time: float = 0.0
var multimesh_instance: MultiMeshInstance3D
var multimesh: MultiMesh
var presentation_material: ShaderMaterial
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	rng.seed = 1337
	if not grid.is_node_ready():
		await grid.ready
	density.resize(grid.cells_x * grid.cells_z)
	reservations.resize(grid.cells_x * grid.cells_z)
	_build_renderer()
	_spawn_agents()
	_initialize_density()
	_upload_all_transforms()

func _process(delta: float) -> void:
	presentation_time += delta
	_update_presentation_shader()

	var desired_updates: float = float(agent_count) * simulation_hz * delta
	work_accumulator += desired_updates
	work_accumulator = minf(work_accumulator, float(maxi(agent_count, 1)))

	var requested_agents: int = floori(work_accumulator)
	agents_processed_last_frame = mini(requested_agents, maxi(max_agents_per_frame, 1))
	if agents_processed_last_frame <= 0:
		last_simulation_ms = 0.0
		_update_rate_stats(delta, 0)
		return

	work_accumulator -= float(agents_processed_last_frame)
	reservations.fill(0)

	var frame_now_usec: int = Time.get_ticks_usec()
	var start_usec: int = frame_now_usec
	for processed: int in range(agents_processed_last_frame):
		var agent_index: int = next_agent_index
		next_agent_index += 1
		if next_agent_index >= positions.size():
			next_agent_index = 0

		var previous_usec: int = last_update_usec[agent_index]
		var elapsed_seconds: float = float(frame_now_usec - previous_usec) / 1_000_000.0
		elapsed_seconds = clampf(elapsed_seconds, 0.0, MAX_AGENT_STEP_SECONDS)
		last_update_usec[agent_index] = frame_now_usec
		_simulate_agent(agent_index, elapsed_seconds)

	last_simulation_ms = float(Time.get_ticks_usec() - start_usec) / 1000.0
	_update_rate_stats(delta, agents_processed_last_frame)

func _update_presentation_shader() -> void:
	if presentation_material == null:
		return
	presentation_material.set_shader_parameter("presentation_time", presentation_time)

func _update_rate_stats(delta: float, updates: int) -> void:
	update_rate_accumulator += delta
	updates_in_rate_window += updates
	if update_rate_accumulator < 0.5:
		return
	if agent_count > 0 and update_rate_accumulator > 0.0:
		effective_updates_per_second = float(updates_in_rate_window) / float(agent_count) / update_rate_accumulator
	else:
		effective_updates_per_second = 0.0
	update_rate_accumulator = 0.0
	updates_in_rate_window = 0

func _simulate_agent(index: int, step_delta: float) -> void:
	var old_position: Vector3 = positions[index]
	var position: Vector3 = old_position
	var starting_cell: Vector2i = agent_cells[index]
	var current_cell: Vector2i = starting_cell

	if current_cell == flow_field.goal_cell and target_cells[index] == INVALID_CELL:
		return

	# Capture where the GPU presentation should be right now before changing the
	# authoritative transform. This lets us reconcile to the new truth without
	# snapping backward from an extrapolated visual position.
	var previous_velocity: Vector3 = presentation_velocities[index]
	var visual_elapsed: float = presentation_time - presentation_update_times[index]
	visual_elapsed = clampf(visual_elapsed, 0.0, presentation_extrapolation_limits[index])
	var predicted_visual_position: Vector3 = old_position + previous_velocity * visual_elapsed

	var remaining_distance: float = move_speed * step_delta
	var transitions: int = 0

	while remaining_distance > 0.0001 and transitions < MAX_CELL_TRANSITIONS_PER_UPDATE:
		if current_cell == flow_field.goal_cell and target_cells[index] == INVALID_CELL:
			break

		var target_cell: Vector2i = target_cells[index]
		if target_cell == INVALID_CELL or not _target_is_still_valid(current_cell, target_cell):
			target_cell = _choose_next_cell(index, current_cell)
			target_cells[index] = target_cell

		var target: Vector3 = grid.cell_to_world(target_cell)
		var lane_offset: Vector2 = lane_offsets[index]
		target.x += lane_offset.x
		target.z += lane_offset.y
		target.y = position.y

		var offset: Vector3 = target - position
		var distance: float = offset.length()
		if distance <= target_arrival_distance:
			position = target
			target_cells[index] = INVALID_CELL
			current_cell = grid.world_to_cell(position)
			transitions += 1
			continue

		var move_step: float = minf(remaining_distance, distance)
		position += offset / distance * move_step
		remaining_distance -= move_step
		current_cell = grid.world_to_cell(position)

		if move_step >= distance - 0.0001:
			position = target
			current_cell = grid.world_to_cell(position)
			target_cells[index] = INVALID_CELL
			transitions += 1
			continue
		break

	positions[index] = position
	_update_agent_cell(index, starting_cell, current_cell)

	var velocity: Vector3 = Vector3.ZERO
	if step_delta > 0.0001:
		velocity = (position - old_position) / step_delta
	var extrapolation_seconds: float = clampf(step_delta * 1.35, 0.03, MAX_PRESENTATION_EXTRAPOLATION_SECONDS)
	var correction: Vector3 = predicted_visual_position - position

	presentation_velocities[index] = velocity
	presentation_update_times[index] = presentation_time
	presentation_extrapolation_limits[index] = extrapolation_seconds

	multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, position))
	# INSTANCE_CUSTOM: velocity.x, velocity.z, extrapolation limit, update time.
	multimesh.set_instance_custom_data(index, Color(
		velocity.x,
		velocity.z,
		extrapolation_seconds,
		presentation_time
	))
	# INSTANCE_COLOR is presentation-only correction data. The shader decays this
	# offset while continuing forward motion, preventing a visible snap backward.
	multimesh.set_instance_color(index, Color(
		correction.x,
		correction.z,
		PRESENTATION_RECONCILE_SECONDS,
		1.0
	))

func _update_agent_cell(index: int, old_cell: Vector2i, new_cell: Vector2i) -> void:
	if new_cell == old_cell:
		return
	if grid.is_valid_cell(old_cell):
		var old_index: int = _cell_index(old_cell)
		density[old_index] = maxi(density[old_index] - 1, 0)
	if grid.is_valid_cell(new_cell):
		density[_cell_index(new_cell)] += 1
	agent_cells[index] = new_cell

func _target_is_still_valid(current_cell: Vector2i, target_cell: Vector2i) -> bool:
	if not grid.is_valid_cell(target_cell) or grid.is_blocked(target_cell):
		return false
	if current_cell == target_cell:
		return true
	return flow_field.can_traverse(current_cell, target_cell)

func _choose_next_cell(agent_index: int, current_cell: Vector2i) -> Vector2i:
	var current_cost: int = flow_field.get_cost(current_cell)
	if current_cost == FlowField.UNREACHABLE or current_cost == 0:
		return current_cell

	var best_cell: Vector2i = current_cell
	var best_score: int = 2_000_000_000

	for direction: Vector2i in FlowField.NEIGHBOR_DIRS:
		var neighbor: Vector2i = current_cell + direction
		if not flow_field.can_traverse(current_cell, neighbor):
			continue
		var neighbor_cost: int = flow_field.get_cost(neighbor)
		if neighbor_cost == FlowField.UNREACHABLE:
			continue

		var step_cost: int = flow_field.get_step_cost(direction)
		var route_cost: int = neighbor_cost + step_cost
		if route_cost > current_cost + FlowField.DIAGONAL_COST:
			continue

		var neighbor_index: int = _cell_index(neighbor)
		var occupancy: int = density[neighbor_index] + reservations[neighbor_index]
		var tie_break: int = _stable_jitter(agent_index, neighbor)
		var score: int = route_cost * path_weight + occupancy * density_weight + tie_break
		if score < best_score:
			best_score = score
			best_cell = neighbor

	if best_cell != current_cell:
		reservations[_cell_index(best_cell)] += 1
	return best_cell

func _initialize_density() -> void:
	density.fill(0)
	for cell: Vector2i in agent_cells:
		if grid.is_valid_cell(cell):
			density[_cell_index(cell)] += 1

func _stable_jitter(agent_index: int, cell: Vector2i) -> int:
	var value: int = agent_index * 73856093
	value ^= cell.x * 19349663
	value ^= cell.y * 83492791
	return absi(value) % 7

func _cell_index(cell: Vector2i) -> int:
	return cell.y * grid.cells_x + cell.x

func _build_renderer() -> void:
	var shader: Shader = Shader.new()
	shader.code = """
shader_type spatial;

uniform vec4 agent_color : source_color = vec4(0.88, 0.13, 0.10, 1.0);
uniform float presentation_time = 0.0;

void vertex() {
	float elapsed = max(presentation_time - INSTANCE_CUSTOM.w, 0.0);
	float extrapolated_elapsed = min(elapsed, INSTANCE_CUSTOM.z);
	vec2 velocity = INSTANCE_CUSTOM.xy;
	float reconcile_duration = max(INSTANCE_COLOR.z, 0.001);
	float reconcile = 1.0 - clamp(elapsed / reconcile_duration, 0.0, 1.0);
	vec2 correction = INSTANCE_COLOR.xy * reconcile;
	vec2 presentation_offset = velocity * extrapolated_elapsed + correction;
	VERTEX += vec3(presentation_offset.x, 0.0, presentation_offset.y);
}

void fragment() {
	ALBEDO = agent_color.rgb;
	ROUGHNESS = 0.7;
}
"""

	presentation_material = ShaderMaterial.new()
	presentation_material.shader = shader

	var mesh: CapsuleMesh = CapsuleMesh.new()
	mesh.radius = agent_radius
	mesh.height = agent_height
	mesh.radial_segments = 8
	mesh.rings = 2
	mesh.material = presentation_material

	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.use_colors = true
	multimesh.instance_count = maxi(agent_count, 0)
	multimesh.mesh = mesh

	multimesh_instance = MultiMeshInstance3D.new()
	multimesh_instance.name = "HordeRenderer"
	multimesh_instance.multimesh = multimesh
	multimesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(multimesh_instance)

func _spawn_agents() -> void:
	positions.clear()
	lane_offsets.clear()
	target_cells.clear()
	agent_cells.clear()
	presentation_velocities.clear()
	positions.resize(maxi(agent_count, 0))
	lane_offsets.resize(maxi(agent_count, 0))
	target_cells.resize(maxi(agent_count, 0))
	agent_cells.resize(maxi(agent_count, 0))
	presentation_velocities.resize(maxi(agent_count, 0))
	last_update_usec.resize(maxi(agent_count, 0))
	presentation_update_times.resize(maxi(agent_count, 0))
	presentation_extrapolation_limits.resize(maxi(agent_count, 0))
	var lane_extent: float = grid.cell_size * lane_offset_fraction
	var initial_update_usec: int = Time.get_ticks_usec()

	for index: int in range(positions.size()):
		var offset_x: float = rng.randf_range(-spawn_extents.x, spawn_extents.x)
		var offset_z: float = rng.randf_range(-spawn_extents.y, spawn_extents.y)
		var position: Vector3 = spawn_center + Vector3(offset_x, 0.0, offset_z)
		var cell: Vector2i = grid.world_to_cell(position)
		if not grid.is_valid_cell(cell) or grid.is_blocked(cell):
			position = spawn_center
			cell = grid.world_to_cell(position)
		positions[index] = position
		agent_cells[index] = cell
		target_cells[index] = INVALID_CELL
		last_update_usec[index] = initial_update_usec
		presentation_velocities[index] = Vector3.ZERO
		presentation_update_times[index] = presentation_time
		presentation_extrapolation_limits[index] = 0.0
		lane_offsets[index] = Vector2(
			rng.randf_range(-lane_extent, lane_extent),
			rng.randf_range(-lane_extent, lane_extent)
		)

func _upload_all_transforms() -> void:
	for index: int in range(positions.size()):
		multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, positions[index]))
		multimesh.set_instance_custom_data(index, Color(0.0, 0.0, 0.0, presentation_time))
		multimesh.set_instance_color(index, Color(0.0, 0.0, PRESENTATION_RECONCILE_SECONDS, 1.0))
