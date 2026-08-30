extends CharacterBody3D

@onready var selection_marker: MeshInstance3D = $SelectionMarker

func set_selected(selected: bool) -> void:
	selection_marker.visible = selected
