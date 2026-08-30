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

@onready var grid: BattlefieldGrid = get_node(grid_path) as BattlefieldGrid
@onready var goal: Node3D = get_node(goal_path) as Node3D

var integration: PackedInt32Array = PackedInt32Array()
var goal_cell: Vector2i = Vector2i(-1, -1)

func _ready() -> void:
	if not grid.is_node_ready():
		await grid.ready
	integration.resize(grid.cells_x * grid.cells_z)
	grid.grid_changed.connect(_rebuild)
	_rebuild()

func _rebuild() -> void:
	goal_cell = grid.world_to_cell(goal.global_position)
	integration.fill(UNREACHABLE)
	if not grid.is_valid_cell(goal_cell) or grid.is_blocked(goal_cell):
		return

	var frontier: Array[Vector2i] = []
	frontier.append(goal_cell)
	integration[_index(goal_cell)] = 0
	var read_index: int = 0

	while read_index < frontier.size():
		var current: Vector2i = frontier[read_index]
		read_index += 1
		var current_cost: int = integration[_index(current)]

		for direction: Vector2i in NEIGHBOR_DIRS:
			var neighbor: Vector2i = current + direction
			if not can_traverse(current, neighbor):
				continue
			var neighbor_index: int = _index(neighbor)
			if integration[neighbor_index] <= current_cost + 1:
				continue
			integration[neighbor_index] = current_cost + 1
			frontier.append(neighbor)

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
