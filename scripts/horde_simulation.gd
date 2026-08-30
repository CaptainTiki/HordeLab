extends Node3D
class_name HordeSimulation

const INVALID_CELL: Vector2i = Vector2i(-1, -1)

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
@export var density_weight: int = 7
@export var path_weight: int = 12
@export var lane_offset_fraction: float = 0.28
@export var target_arrival_distance: float = 0.08

@onready var grid: BattlefieldGrid = get_node(grid_path) as BattlefieldGrid
@onready var flow_field: FlowField = get_node(flow_field_path) as FlowField

var positions: Array[Vector3] = []
var lane_offsets: Array[Vector2] = []
var target_cells: Array[Vector2i] = []
var agent_cells: Array[Vector2i] = []
var density: PackedInt32Array = PackedInt32Array()
var reservations: PackedInt32Array = PackedInt32Array()
var work_accumulator: float = 0.0
var next_agent_index: int = 0
var agents_processed_last_frame: int = 0
var last_simulation_ms: float = 0.0
var multimesh_instance: MultiMeshInstance3D
var multimesh: MultiMesh
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
	var tick_interval: float = 1.0 / maxf(simulation_hz, 1.0)
	var desired_updates: float = float(agent_count) * simulation_hz * delta
	work_accumulator += desired_updates

	# Never allow an unlimited backlog to build up. If the renderer cannot keep
	# pace with the requested simulation rate, the horde simulation slows down
	# gracefully instead of creating a giant catch-up hitch.
	work_accumulator = minf(work_accumulator, float(maxi(agent_count, 1)))

	var requested_agents: int = floori(work_accumulator)
	agents_processed_last_frame = mini(requested_agents, maxi(max_agents_per_frame, 1))
	if agents_processed_last_frame <= 0:
		last_simulation_ms = 0.0
		return

	work_accumulator -= float(agents_processed_last_frame)
	reservations.fill(0)

	var start_usec: int = Time.get_ticks_usec()
	for processed: int in range(agents_processed_last_frame):
		var agent_index: int = next_agent_index
		next_agent_index += 1
		if next_agent_index >= positions.size():
			next_agent_index = 0
		_simulate_agent(agent_index, tick_interval)
	last_simulation_ms = float(Time.get_ticks_usec() - start_usec) / 1000.0

func _simulate_agent(index: int, step_delta: float) -> void:
	var position: Vector3 = positions[index]
	var current_cell: Vector2i = agent_cells[index]
	if current_cell == flow_field.goal_cell and target_cells[index] == INVALID_CELL:
		return

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
	elif distance > 0.001:
		var move_step: float = minf(move_speed * step_delta, distance)
		position += offset / distance * move_step

	positions[index] = position
	_update_agent_cell(index, current_cell, grid.world_to_cell(position))
	multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, position))

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
		if neighbor_cost >= current_cost:
			continue

		var neighbor_index: int = _cell_index(neighbor)
		var occupancy: int = density[neighbor_index] + reservations[neighbor_index]
		var tie_break: int = _stable_jitter(agent_index, neighbor)
		var score: int = neighbor_cost * path_weight + occupancy * density_weight + tie_break
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
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.88, 0.13, 0.10, 1.0)
	material.roughness = 0.7

	var mesh: CapsuleMesh = CapsuleMesh.new()
	mesh.radius = agent_radius
	mesh.height = agent_height
	mesh.radial_segments = 8
	mesh.rings = 2
	mesh.material = material

	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
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
	positions.resize(maxi(agent_count, 0))
	lane_offsets.resize(maxi(agent_count, 0))
	target_cells.resize(maxi(agent_count, 0))
	agent_cells.resize(maxi(agent_count, 0))
	var lane_extent: float = grid.cell_size * lane_offset_fraction

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
		lane_offsets[index] = Vector2(
			rng.randf_range(-lane_extent, lane_extent),
			rng.randf_range(-lane_extent, lane_extent)
		)

func _upload_all_transforms() -> void:
	for index: int in range(positions.size()):
		multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, positions[index]))
