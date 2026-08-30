extends Node

@export var camera_path: NodePath

@onready var camera: Camera3D = get_node(camera_path)
var selected_unit: Node = null

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_select_at_screen_position(event.position)

func _select_at_screen_position(screen_position: Vector2) -> void:
	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_end := ray_origin + camera.project_ray_normal(screen_position) * 1000.0
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var result := camera.get_world_3d().direct_space_state.intersect_ray(query)

	if selected_unit != null and selected_unit.has_method("set_selected"):
		selected_unit.set_selected(false)
	selected_unit = null

	if result.is_empty():
		return

	var collider: Object = result["collider"]
	if collider != null and collider.has_method("set_selected"):
		selected_unit = collider
		selected_unit.set_selected(true)
