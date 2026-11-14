extends Node2D
## One 16x16-tile block of resource nodes, drawn back to front.

var game: Node
var origin := Vector2i.ZERO
var size := 16


func _draw() -> void:
	if game == null:
		return
	var sim: SimWorld = game.sim
	for s in range(0, 2 * size - 1):
		for lx in range(maxi(0, s - size + 1), mini(s, size - 1) + 1):
			var c := origin + Vector2i(lx, s - lx)
			if not sim.in_bounds(c):
				continue
			var id := sim.occupancy[sim.idx(c)]
			if id == 0:
				continue
			var r: SimEntity = sim.resources.get(id)
			if r != null:
				PlaceholderArt.draw_resource(self, game, r)
