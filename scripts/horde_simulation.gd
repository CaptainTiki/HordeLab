extends Node3D
class_name HordeSimulation

const INVALID_CELL: Vector2i = Vector2i(-1, -1)

@export var grid_path: NodePath
@export var flow_field_path: NodePath
@export var agent_count: int = 1000
@export var move_speed: float = 6.0
@export var simulation_hz: float = 30.0
@export var spawn_center: Vector3 = Vector3(-58.0, 0.75, -30.0)
@export var spawn_extents: Vector2 = Vector2(16.0, 20.0)
@export var agent_radius: float = 0.32
@export var agent_height: float = 1.1
@export var density_weight: int = 7
@export var path_weight: int = 12
@export var lane_offset_fraction: float = 0.28
@export var density_update_interval: float = 0.10
@export var target_arrival_distance: float = 0.08

@onready var grid: BattlefieldGrid = get_node(grid_path) as BattlefieldGrid
@onready var flow_field: FlowField = get_node(flow_field_path) as FlowField

var positions: Array[Vector3] = []
var lane_offsets: Array[Vector2] = []
var target_cells: Array[Vector2i] = []
var density: PackedInt32Array = PackedInt32Array()
var reservations: PackedInt32Array = PackedInt32Array()
var density_timer: float = 0.0
var simulation_accumulator: float = 0.0
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
	_rebuild_density()
	_upload_all_transforms()

func _process(delta: float) -> void:
	var tick_interval: float = 1.0 / maxf(simulation_hz, 1.0)
	simulation_accumulator += delta
	if simulation_accumulator < tick_interval:
		return

	# Never run an unbounded catch-up loop after a slow frame. One horde tick per
	# rendered frame is the maximum; excess accumulated time is discarded.
	simulation_accumulator = fmod(simulation_accumulator, tick_interval)
	var start_usec: int = Time.get_ticks_usec()
	_simulate_tick(tick_interval)
	last_simulation_ms = float(Time.get_ticks_usec() - start_usec) / 1000.0

func _simulate_tick(step_delta: float) -> void:
	density_timer += step_delta
	if density_timer >= density_update_interval:
		density_timer = fmod(density_timer, density_update_interval)
		_rebuild_density()

	var max_step: float = move_speed * step_delta
	for index: int in range(positions.size()):
		var position: Vector3 = positions[index]
		var current_cell: Vector2i = grid.world_to_cell(position)
		if current_cell == flow_field.goal_cell and target_cells[index] == INVALID_CELL:
			multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, position))
			continue

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
			positions[index] = position
			target_cells[index] = INVALID_CELL
		elif distance > 0.001:
			var move_step: float = minf(max_step, distance)
			position += offset / distance * move_step
			positions[index] = position

		multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, position))

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

func _rebuild_density() -> void:
	density.fill(0)
	reservations.fill(0)
	for position: Vector3 in positions:
		var cell: Vector2i = grid.world_to_cell(position)
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
	positions.resize(maxi(agent_count, 0))
	lane_offsets.resize(maxi(agent_count, 0))
	target_cells.resize(maxi(agent_count, 0))
	var lane_extent: float = grid.cell_size * lane_offset_fraction

	for index: int in range(positions.size()):
		var offset_x: float = rng.randf_range(-spawn_extents.x, spawn_extents.x)
		var offset_z: float = rng.randf_range(-spawn_extents.y, spawn_extents.y)
		var position: Vector3 = spawn_center + Vector3(offset_x, 0.0, offset_z)
		var cell: Vector2i = grid.world_to_cell(position)
		if not grid.is_valid_cell(cell) or grid.is_blocked(cell):
			position = spawn_center
		positions[index] = position
		target_cells[index] = INVALID_CELL
		lane_offsets[index] = Vector2(
			rng.randf_range(-lane_extent, lane_extent),
			rng.randf_range(-lane_extent, lane_extent)
		)

func _upload_all_transforms() -> void:
	for index: int in range(positions.size()):
		multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, positions[index]))
