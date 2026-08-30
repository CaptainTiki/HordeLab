extends Node3D
class_name BuildController

@export var camera_path: NodePath
@export var grid_path: NodePath

@onready var camera: Camera3D = get_node(camera_path) as Camera3D
@onready var grid: BattlefieldGrid = get_node(grid_path) as BattlefieldGrid

var placement_active: bool = false
var ghost: MeshInstance3D
var ghost_cell: Vector2i = Vector2i(-1, -1)
var ghost_valid: bool = false

var valid_material: StandardMaterial3D
var invalid_material: StandardMaterial3D
var wall_material: StandardMaterial3D

func _ready() -> void:
	valid_material = _make_material(Color(0.20, 0.85, 0.35, 0.55), true)
	invalid_material = _make_material(Color(0.95, 0.20, 0.18, 0.55), true)
	wall_material = _make_material(Color(0.52, 0.28, 0.12, 1.0), false)

	ghost = MeshInstance3D.new()
	ghost.name = "WallGhost"
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(grid.cell_size * 0.9, 2.2, grid.cell_size * 0.9)
	ghost.mesh = mesh
	ghost.visible = false
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ghost)

func _process(_delta: float) -> void:
	if not placement_active:
		return
	_update_ghost(get_viewport().get_mouse_position())

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_B:
			placement_active = not placement_active
			ghost.visible = placement_active
			if placement_active:
				_update_ghost(get_viewport().get_mouse_position())
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_ESCAPE and placement_active:
			_cancel_placement()
			get_viewport().set_input_as_handled()
			return

	if not placement_active:
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_place_wall()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_placement()
			get_viewport().set_input_as_handled()

func _update_ghost(screen_position: Vector2) -> void:
	var world_position: Vector3 = _screen_to_ground(screen_position)
	if not world_position.is_finite():
		ghost.visible = false
		ghost_valid = false
		return

	ghost_cell = grid.world_to_cell(world_position)
	ghost_valid = grid.is_valid_cell(ghost_cell) and not grid.is_blocked(ghost_cell)
	ghost.visible = true
	var snapped: Vector3 = grid.cell_to_world(ghost_cell)
	ghost.global_position = Vector3(snapped.x, 1.1, snapped.z)
	ghost.material_override = valid_material if ghost_valid else invalid_material

func _screen_to_ground(screen_position: Vector2) -> Vector3:
	var ray_origin: Vector3 = camera.project_ray_origin(screen_position)
	var ray_direction: Vector3 = camera.project_ray_normal(screen_position)
	if absf(ray_direction.y) < 0.0001:
		return Vector3.INF
	var distance: float = -ray_origin.y / ray_direction.y
	if distance < 0.0:
		return Vector3.INF
	return ray_origin + ray_direction * distance

func _place_wall() -> void:
	if not ghost_valid:
		return

	grid.set_blocked(ghost_cell, true)

	var wall: MeshInstance3D = MeshInstance3D.new()
	wall.name = "Wall_%d_%d" % [ghost_cell.x, ghost_cell.y]
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(grid.cell_size * 0.9, 2.2, grid.cell_size * 0.9)
	wall.mesh = mesh
	wall.material_override = wall_material
	var snapped: Vector3 = grid.cell_to_world(ghost_cell)
	wall.global_position = Vector3(snapped.x, 1.1, snapped.z)
	add_child(wall)

	ghost_valid = false
	_update_ghost(get_viewport().get_mouse_position())

func _cancel_placement() -> void:
	placement_active = false
	ghost.visible = false
	ghost_valid = false

func _make_material(color: Color, transparent: bool) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material
