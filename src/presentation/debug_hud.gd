extends Label
## Temporary on-screen readout: seed, tile under the mouse, terrain, FPS.
## Replaced by the AoE2-style top bar in Milestone 2.

@export var map_path: NodePath = ^"../../IsoMap"

var _map: Node2D


func _ready() -> void:
	_map = get_node(map_path)


func _process(_delta: float) -> void:
	var t: Vector2i = _map.world_to_tile(_map.get_global_mouse_position())
	var terrain := "-"
	if _map.in_bounds(t):
		terrain = _map.terrain_name_at(t)
	text = "Arkborn prototype   |   seed %d   |   tile %d, %d   %s   |   %d FPS" % [
		_map.world_seed, t.x, t.y, terrain, Engine.get_frames_per_second()]
