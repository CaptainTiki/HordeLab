extends Node

@export var camera_path: NodePath
@export var build_controller_path: NodePath

@onready var camera: Camera3D = get_node(camera_path) as Camera3D
@onready var build_controller: BuildController = get_node(build_controller_path) as BuildController

var selected_unit: Node = null

func _unhandled_input(event: InputEvent) -> void:
	if build_controller != null and build_controller.placement_active:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_select_at_screen_position(event.position)

func _select_at_screen_position(screen_position: Vector2) -> void:
	var ray_origin: Vector3 = camera.project_ray_origin(screen_position)
	var ray_end: Vector3 = ray_origin + camera.project_ray_normal(screen_position) * 1000.0
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var result: Dictionary = camera.get_world_3d().direct_space_state.intersect_ray(query)

	if selected_unit != null and selected_unit.has_method("set_selected"):
		selected_unit.call("set_selected", false)
	selected_unit = null

	if result.is_empty():
		return

	var collider: Object = result["collider"] as Object
	if collider != null and collider.has_method("set_selected"):
		selected_unit = collider as Node
		selected_unit.call("set_selected", true)
