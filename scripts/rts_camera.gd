extends Node3D

@export var move_speed := 35.0
@export var fast_multiplier := 2.5
@export var rotate_speed := 1.6
@export var zoom_speed := 3.0
@export var min_zoom := 12.0
@export var max_zoom := 80.0
@export var drag_pan_sensitivity := 0.11

@onready var camera: Camera3D = $Camera3D

var zoom_distance := 32.0
var middle_dragging := false

func _ready() -> void:
	_apply_zoom()

func _process(delta: float) -> void:
	var move_input := Vector2.ZERO
	if Input.is_key_pressed(KEY_W):
		move_input.y += 1.0
	if Input.is_key_pressed(KEY_S):
		move_input.y -= 1.0
	if Input.is_key_pressed(KEY_A):
		move_input.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		move_input.x += 1.0

	if move_input.length_squared() > 1.0:
		move_input = move_input.normalized()

	var speed := move_speed
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= fast_multiplier

	var forward := -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	global_position += (right * move_input.x + forward * move_input.y) * speed * delta

	var rotate_input := 0.0
	if Input.is_key_pressed(KEY_Q):
		rotate_input += 1.0
	if Input.is_key_pressed(KEY_E):
		rotate_input -= 1.0
	rotate_y(rotate_input * rotate_speed * delta)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			middle_dragging = event.pressed
			get_viewport().set_input_as_handled()
			return

		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_distance = max(min_zoom, zoom_distance - zoom_speed)
			_apply_zoom()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_distance = min(max_zoom, zoom_distance + zoom_speed)
			_apply_zoom()

	if event is InputEventMouseMotion and middle_dragging:
		var right := global_transform.basis.x
		right.y = 0.0
		right = right.normalized()
		var forward := -global_transform.basis.z
		forward.y = 0.0
		forward = forward.normalized()
		var scale := drag_pan_sensitivity * (zoom_distance / 32.0)
		global_position += (-right * event.relative.x + forward * event.relative.y) * scale
		get_viewport().set_input_as_handled()

func _apply_zoom() -> void:
	camera.position = Vector3(0.0, zoom_distance * 0.72, zoom_distance)
	camera.rotation_degrees.x = -36.0
