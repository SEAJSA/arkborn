class_name WorldGen
extends RefCounted
## Generates the world's terrain grid. Pure data: no drawing and no nodes.
## The same seed and size always produce the same world.
##
## Note: this uses floating-point noise, which is fine for map generation.
## The real-time simulation core (Milestone 2+) will use integer math so that
## results match exactly across machines, which multiplayer lockstep requires.


static func generate(world_seed: int, width: int, height: int, terrain_defs: Array) -> PackedInt32Array:
	var noise := FastNoiseLite.new()
	noise.seed = world_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.03
	noise.fractal_octaves = 4

	var grid := PackedInt32Array()
	grid.resize(width * height)
	for y in height:
		for x in width:
			var h := (noise.get_noise_2d(x, y) + 1.0) * 0.5  # 0.0 to 1.0
			grid[y * width + x] = _terrain_for_height(h, terrain_defs)
	return grid


static func _terrain_for_height(h: float, terrain_defs: Array) -> int:
	for i in terrain_defs.size():
		if h <= float(terrain_defs[i]["max_height"]):
			return i
	return terrain_defs.size() - 1
