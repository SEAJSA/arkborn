extends Label
## Developer readout, toggled with F12: seed, tick, tile under the mouse, terrain, FPS.

var game: Node


func _ready() -> void:
	visible = false


func _process(_delta: float) -> void:
	if not visible or game == null:
		return
	var sim: SimWorld = game.sim
	var t: Vector2i = game.iso_map.world_to_tile(game.iso_map.get_global_mouse_position())
	var terrain := "-"
	if sim.in_bounds(t):
		terrain = sim.terrain_id_at(t)
	text = "seed %d   tick %d   tile %d, %d %s   %d FPS" % [
		sim.world_seed, sim.tick, t.x, t.y, terrain, Engine.get_frames_per_second()]
