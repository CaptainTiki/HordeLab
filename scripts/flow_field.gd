extends Node
class_name FlowField

const UNREACHABLE: int = 1_000_000_000
const NEIGHBOR_DIRS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
	Vector2i(1, 1),
	Vector2i(1, -1),
	Vector2i(-1, 1),
	Vector2i(-1, -1),
]

@export var grid_path: NodePath
@export var goal_path: NodePath
@export var rebuild_cells_per_frame: int = 400

@onready var grid: BattlefieldGrid = get_node(grid_path) as BattlefieldGrid
@onready var goal: Node3D = get_node(goal_path) as Node3D

var integration: PackedInt32Array = PackedInt32Array()
var pending_integration: PackedInt32Array = PackedInt32Array()
var frontier: Array[Vector2i] = []
var frontier_read_index: int = 0
var goal_cell: Vector2i = Vector2i(-1, -1)
var rebuild_in_progress: bool = false

func _ready() -> void:
	if not grid.is_node_ready():
		await grid.ready
	var cell_count: int = grid.cells_x * grid.cells_z
	integration.resize(cell_count)
	integration.fill(UNREACHABLE)
	pending_integration.resize(cell_count)
	pending_integration.fill(UNREACHABLE)
	grid.grid_changed.connect(_begin_rebuild)
	_begin_rebuild()

func _process(_delta: float) -> void:
	if rebuild_in_progress:
		_process_rebuild_budget()

func _begin_rebuild() -> void:
	goal_cell = grid.world_to_cell(goal.global_position)
	pending_integration.fill(UNREACHABLE)
	frontier.clear()
	frontier_read_index = 0

	if not grid.is_valid_cell(goal_cell) or grid.is_blocked(goal_cell):
		integration.fill(UNREACHABLE)
		rebuild_in_progress = false
		return

	frontier.append(goal_cell)
	pending_integration[_index(goal_cell)] = 0
	rebuild_in_progress = true

func _process_rebuild_budget() -> void:
	var processed: int = 0
	var budget: int = maxi(rebuild_cells_per_frame, 1)

	while frontier_read_index < frontier.size() and processed < budget:
		var current: Vector2i = frontier[frontier_read_index]
		frontier_read_index += 1
		processed += 1
		var current_cost: int = pending_integration[_index(current)]

		for direction: Vector2i in NEIGHBOR_DIRS:
			var neighbor: Vector2i = current + direction
			if not can_traverse(current, neighbor):
				continue
			var neighbor_index: int = _index(neighbor)
			if pending_integration[neighbor_index] <= current_cost + 1:
				continue
			pending_integration[neighbor_index] = current_cost + 1
			frontier.append(neighbor)

	if frontier_read_index >= frontier.size():
		integration = pending_integration.duplicate()
		rebuild_in_progress = false

func get_cost(cell: Vector2i) -> int:
	if not grid.is_valid_cell(cell):
		return UNREACHABLE
	return integration[_index(cell)]

func get_next_cell(cell: Vector2i) -> Vector2i:
	var current_cost: int = get_cost(cell)
	if current_cost == UNREACHABLE or current_cost == 0:
		return cell

	var best_cell: Vector2i = cell
	var best_cost: int = current_cost
	for direction: Vector2i in NEIGHBOR_DIRS:
		var neighbor: Vector2i = cell + direction
		if not can_traverse(cell, neighbor):
			continue
		var neighbor_cost: int = get_cost(neighbor)
		if neighbor_cost < best_cost:
			best_cost = neighbor_cost
			best_cell = neighbor
	return best_cell

func can_traverse(from_cell: Vector2i, to_cell: Vector2i) -> bool:
	if not grid.is_valid_cell(to_cell) or grid.is_blocked(to_cell):
		return false
	var delta: Vector2i = to_cell - from_cell
	if absi(delta.x) == 1 and absi(delta.y) == 1:
		var side_x: Vector2i = from_cell + Vector2i(delta.x, 0)
		var side_y: Vector2i = from_cell + Vector2i(0, delta.y)
		if grid.is_blocked(side_x) or grid.is_blocked(side_y):
			return false
	return true

func _index(cell: Vector2i) -> int:
	return cell.y * grid.cells_x + cell.x
