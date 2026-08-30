extends Node3D
class_name BattlefieldGrid

@export var world_size := Vector2i(200, 200)
@export var cell_size := 2.0
@export var show_debug_grid := true

var cells_x: int
var cells_z: int
var blocked := PackedByteArray()

func _ready() -> void:
	cells_x = int(world_size.x / cell_size)
	cells_z = int(world_size.y / cell_size)
	blocked.resize(cells_x * cells_z)
	if show_debug_grid:
		_build_debug_grid()

func world_to_cell(world_position: Vector3) -> Vector2i:
	var half_x := world_size.x * 0.5
	var half_z := world_size.y * 0.5
	return Vector2i(
		floori((world_position.x + half_x) / cell_size),
		floori((world_position.z + half_z) / cell_size)
	)

func cell_to_world(cell: Vector2i) -> Vector3:
	var half_x := world_size.x * 0.5
	var half_z := world_size.y * 0.5
	return Vector3(
		-half_x + (cell.x + 0.5) * cell_size,
		0.02,
		-half_z + (cell.y + 0.5) * cell_size
	)

func is_valid_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < cells_x and cell.y < cells_z

func is_blocked(cell: Vector2i) -> bool:
	if not is_valid_cell(cell):
		return true
	return blocked[cell.y * cells_x + cell.x] != 0

func set_blocked(cell: Vector2i, value: bool) -> void:
	if not is_valid_cell(cell):
		return
	blocked[cell.y * cells_x + cell.x] = 1 if value else 0

func _build_debug_grid() -> void:
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.34, 0.38, 0.42, 0.42)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	var half_x := world_size.x * 0.5
	var half_z := world_size.y * 0.5
	var y := 0.025

	for x in range(cells_x + 1):
		var world_x := -half_x + x * cell_size
		mesh.surface_add_vertex(Vector3(world_x, y, -half_z))
		mesh.surface_add_vertex(Vector3(world_x, y, half_z))

	for z in range(cells_z + 1):
		var world_z := -half_z + z * cell_size
		mesh.surface_add_vertex(Vector3(-half_x, y, world_z))
		mesh.surface_add_vertex(Vector3(half_x, y, world_z))

	mesh.surface_end()
	var instance := MeshInstance3D.new()
	instance.name = "DebugGrid"
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
