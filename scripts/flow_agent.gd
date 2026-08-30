extends Node3D
class_name FlowAgent

@export var grid_path: NodePath
@export var flow_field_path: NodePath
@export var move_speed: float = 6.0
@export var arrival_distance: float = 0.15

@onready var grid: BattlefieldGrid = get_node(grid_path) as BattlefieldGrid
@onready var flow_field: FlowField = get_node(flow_field_path) as FlowField

func _process(delta: float) -> void:
	var current_cell: Vector2i = grid.world_to_cell(global_position)
	if current_cell == flow_field.goal_cell:
		return

	var next_cell: Vector2i = flow_field.get_next_cell(current_cell)
	if next_cell == current_cell:
		return

	var target: Vector3 = grid.cell_to_world(next_cell)
	target.y = global_position.y
	var offset: Vector3 = target - global_position
	var distance: float = offset.length()
	if distance <= arrival_distance:
		global_position = target
		return

	var step: float = minf(move_speed * delta, distance)
	global_position += offset.normalized() * step
