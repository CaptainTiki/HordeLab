extends Node
class_name FlowField

const UNREACHABLE: int = 1_000_000_000
const CARDINAL_COST: int = 10
const DIAGONAL_COST: int = 14
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
var heap_cells: Array[Vector2i] = []
var heap_costs: PackedInt32Array = PackedInt32Array()
var goal_cell: Vector2i = Vector2i(-1, -1)
var rebuild_in_progress: bool = false
var last_rebuild_ms: float = 0.0
var last_rebuild_frames: int = 0
var rebuild_frame_count: int = 0
var rebuild_start_usec: int = 0

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
		rebuild_frame_count += 1
		_process_rebuild_budget()

func _begin_rebuild() -> void:
	goal_cell = grid.world_to_cell(goal.global_position)
	pending_integration.fill(UNREACHABLE)
	heap_cells.clear()
	heap_costs = PackedInt32Array()
	rebuild_frame_count = 0
	rebuild_start_usec = Time.get_ticks_usec()

	if not grid.is_valid_cell(goal_cell) or grid.is_blocked(goal_cell):
		integration.fill(UNREACHABLE)
		rebuild_in_progress = false
		last_rebuild_ms = 0.0
		last_rebuild_frames = 0
		return

	pending_integration[_index(goal_cell)] = 0
	_heap_push(goal_cell, 0)
	rebuild_in_progress = true

func _process_rebuild_budget() -> void:
	var processed: int = 0
	var budget: int = maxi(rebuild_cells_per_frame, 1)

	while not heap_cells.is_empty() and processed < budget:
		var current: Vector2i = heap_cells[0]
		var queued_cost: int = heap_costs[0]
		_heap_pop_root()

		var current_cost: int = pending_integration[_index(current)]
		if queued_cost != current_cost:
			continue

		processed += 1
		for direction: Vector2i in NEIGHBOR_DIRS:
			var neighbor: Vector2i = current + direction
			if not can_traverse(current, neighbor):
				continue

			var move_cost: int = get_step_cost(direction)
			var candidate_cost: int = current_cost + move_cost
			var neighbor_index: int = _index(neighbor)
			if candidate_cost >= pending_integration[neighbor_index]:
				continue

			pending_integration[neighbor_index] = candidate_cost
			_heap_push(neighbor, candidate_cost)

	if heap_cells.is_empty():
		integration = pending_integration.duplicate()
		rebuild_in_progress = false
		last_rebuild_frames = rebuild_frame_count
		last_rebuild_ms = float(Time.get_ticks_usec() - rebuild_start_usec) / 1000.0

func get_cost(cell: Vector2i) -> int:
	if not grid.is_valid_cell(cell):
		return UNREACHABLE
	return integration[_index(cell)]

func get_step_cost(direction: Vector2i) -> int:
	if direction.x != 0 and direction.y != 0:
		return DIAGONAL_COST
	return CARDINAL_COST

func get_next_cell(cell: Vector2i) -> Vector2i:
	var current_cost: int = get_cost(cell)
	if current_cost == UNREACHABLE or current_cost == 0:
		return cell

	var best_cell: Vector2i = cell
	var best_total: int = current_cost
	for direction: Vector2i in NEIGHBOR_DIRS:
		var neighbor: Vector2i = cell + direction
		if not can_traverse(cell, neighbor):
			continue
		var neighbor_cost: int = get_cost(neighbor)
		if neighbor_cost == UNREACHABLE:
			continue
		var total: int = neighbor_cost + get_step_cost(direction)
		if total < best_total:
			best_total = total
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

func _heap_push(cell: Vector2i, cost: int) -> void:
	heap_cells.append(cell)
	heap_costs.append(cost)
	var index: int = heap_cells.size() - 1
	while index > 0:
		var parent: int = (index - 1) / 2
		if heap_costs[parent] <= cost:
			break
		heap_cells[index] = heap_cells[parent]
		heap_costs[index] = heap_costs[parent]
		index = parent
	heap_cells[index] = cell
	heap_costs[index] = cost

func _heap_pop_root() -> void:
	var last_index: int = heap_cells.size() - 1
	if last_index < 0:
		return
	if last_index == 0:
		heap_cells.pop_back()
		heap_costs.resize(0)
		return

	var replacement_cell: Vector2i = heap_cells[last_index]
	var replacement_cost: int = heap_costs[last_index]
	heap_cells.pop_back()
	heap_costs.resize(last_index)

	var index: int = 0
	var size: int = heap_cells.size()
	while true:
		var left: int = index * 2 + 1
		if left >= size:
			break
		var right: int = left + 1
		var child: int = left
		if right < size and heap_costs[right] < heap_costs[left]:
			child = right
		if heap_costs[child] >= replacement_cost:
			break
		heap_cells[index] = heap_cells[child]
		heap_costs[index] = heap_costs[child]
		index = child

	heap_cells[index] = replacement_cell
	heap_costs[index] = replacement_cost

func _index(cell: Vector2i) -> int:
	return cell.y * grid.cells_x + cell.x
