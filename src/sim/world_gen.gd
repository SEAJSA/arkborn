class_name WorldGen
extends RefCounted
## Builds a new world from a seed: terrain first, then the starting town and resources.
## Same seed and size = same world.
##
## Terrain uses floating-point noise, which is fine because it runs once at setup and
## a saved game will store the resulting map. The tick-by-tick simulation is integer-only.


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


## Places every player's start, the scattered resources, and each starting resource kit.
static func populate(w: SimWorld) -> void:
	var spots: Array = w.rules.get("start_spots", [[0.5, 0.5]])
	for p in w.players.size():
		var s: Array = spots[p % spots.size()]
		var near := Vector2i(int(w.width * float(s[0])), int(w.height * float(s[1])))
		w.start_tiles.append(_find_start(w, near, w.start_tiles))

	# Scattered resources by terrain, kept clear of every starting area.
	var spawns: Array = w.rules.get("resource_spawns", [])
	for y in w.height:
		for x in w.width:
			var c := Vector2i(x, y)
			if w.occupancy[w.idx(c)] != 0 or _near_any(c, w.start_tiles, 7):
				continue
			var tid := w.terrain_id_at(c)
			for s in spawns:
				if s["terrain"] == tid and w.rng.chance_pm(int(s["per_mille"])):
					_cluster(w, s["resource"], c, int(s["cluster"]))
					break

	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
		Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]
	for p in w.players.size():
		var start := w.start_tiles[p]
		# Starting town
		w.place_building(String(w.rules["start_building"]), p, start - Vector2i(2, 2), true)
		for c in w.spiral_free_cells(start + Vector2i(0, 3), int(w.rules.get("start_villagers", 3))):
			w.spawn_unit("villager", p, c)
		# A guaranteed starting kit in different directions around the town
		var dir_index := w.rng.range_int(8)
		for kit in w.rules.get("start_kit", []):
			var dir := dirs[dir_index % 8]
			dir_index += 3
			var dist := int(kit["distance"])
			if dir.x != 0 and dir.y != 0:
				dist = dist * 7 / 10
			var spot := w.spiral_free_cells(start + dir * dist, 1, 8)
			if not spot.is_empty():
				_cluster(w, kit["resource"], spot[0], int(kit["count"]), true)


static func _near_any(c: Vector2i, points: Array[Vector2i], radius: int) -> bool:
	for p in points:
		if _cheb(c, p) <= radius:
			return true
	return false


## Nearest spot to `near` with open buildable land around it, well away from other starts.
static func _find_start(w: SimWorld, near: Vector2i, taken: Array[Vector2i]) -> Vector2i:
	for r in 70:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c := near + Vector2i(dx, dy)
				if not _near_any(c, taken, 40) and _is_open_area(w, c, 6):
					return c
	return near


static func _is_open_area(w: SimWorld, center: Vector2i, radius: int) -> bool:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var c := center + Vector2i(dx, dy)
			if not w.in_bounds(c):
				return false
			var tid := w.terrain_id_at(c)
			if tid != "grass" and tid != "sand" and tid != "hills":
				return false
	return true


## A clump of resource nodes grown outward from a center tile.
static func _cluster(w: SimWorld, type_id: String, center: Vector2i, count: int, dense := false) -> void:
	var placed := 0
	for r in 6:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c := center + Vector2i(dx, dy)
				if not w.is_walkable(c) or w.terrain_buildable[w.idx(c)] == 0:
					continue
				if r > 0 and not w.rng.chance_pm(850 if dense else 600):
					continue
				w.place_resource(type_id, c)
				placed += 1
				if placed >= count:
					return


static func _cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))
