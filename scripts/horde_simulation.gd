extends Node3D
class_name HordeSimulation

@export var grid_path: NodePath
@export var flow_field_path: NodePath
@export var agent_count: int = 1000
@export var move_speed: float = 6.0
@export var spawn_center: Vector3 = Vector3(-58.0, 0.75, -30.0)
@export var spawn_extents: Vector2 = Vector2(16.0, 20.0)
@export var agent_radius: float = 0.32
@export var agent_height: float = 1.1

@onready var grid: BattlefieldGrid = get_node(grid_path) as BattlefieldGrid
@onready var flow_field: FlowField = get_node(flow_field_path) as FlowField

var positions: Array[Vector3] = []
var multimesh_instance: MultiMeshInstance3D
var multimesh: MultiMesh
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	rng.seed = 1337
	_build_renderer()
	_spawn_agents()
	_upload_all_transforms()

func _process(delta: float) -> void:
	var max_step: float = move_speed * delta
	for index: int in range(positions.size()):
		var position: Vector3 = positions[index]
		var current_cell: Vector2i = grid.world_to_cell(position)
		if current_cell != flow_field.goal_cell:
			var next_cell: Vector2i = flow_field.get_next_cell(current_cell)
			if next_cell != current_cell:
				var target: Vector3 = grid.cell_to_world(next_cell)
				target.y = position.y
				var offset: Vector3 = target - position
				var distance: float = offset.length()
				if distance > 0.001:
					var step: float = minf(max_step, distance)
					position += offset / distance * step
					positions[index] = position
		multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, position))

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
	positions.resize(maxi(agent_count, 0))
	for index: int in range(positions.size()):
		var offset_x: float = rng.randf_range(-spawn_extents.x, spawn_extents.x)
		var offset_z: float = rng.randf_range(-spawn_extents.y, spawn_extents.y)
		var position: Vector3 = spawn_center + Vector3(offset_x, 0.0, offset_z)
		var cell: Vector2i = grid.world_to_cell(position)
		if not grid.is_valid_cell(cell) or grid.is_blocked(cell):
			position = spawn_center
		positions[index] = position

func _upload_all_transforms() -> void:
	for index: int in range(positions.size()):
		multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, positions[index]))
