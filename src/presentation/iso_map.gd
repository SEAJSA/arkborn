extends Node2D
## Draws the terrain grid as isometric diamond tiles.
## Presentation only: it reads world data and never changes it.

const TILE_W := 64.0
const TILE_H := 32.0

@export var map_width := 160
@export var map_height := 160
@export var world_seed := 1337

var terrain_defs: Array = []
var grid := PackedInt32Array()
var _colors: Array[Color] = []


func _ready() -> void:
	terrain_defs = ContentDB.load_terrain()
	for t in terrain_defs:
		_colors.append(Color.html(t["color"]))
	grid = WorldGen.generate(world_seed, map_width, map_height, terrain_defs)
	queue_redraw()


## Tile coordinates -> world position of the tile's top corner.
func tile_to_world(tx: float, ty: float) -> Vector2:
	return Vector2((tx - ty) * TILE_W * 0.5, (tx + ty) * TILE_H * 0.5)


## World position -> the tile that contains it.
func world_to_tile(p: Vector2) -> Vector2i:
	var tx := (p.x / (TILE_W * 0.5) + p.y / (TILE_H * 0.5)) * 0.5
	var ty := (p.y / (TILE_H * 0.5) - p.x / (TILE_W * 0.5)) * 0.5
	return Vector2i(floori(tx), floori(ty))


func in_bounds(t: Vector2i) -> bool:
	return t.x >= 0 and t.y >= 0 and t.x < map_width and t.y < map_height


func terrain_name_at(t: Vector2i) -> String:
	return terrain_defs[grid[t.y * map_width + t.x]]["name"]


## The rectangle that contains the whole diamond-shaped map, for camera limits.
func map_bounds() -> Rect2:
	var left := tile_to_world(0, map_height).x
	var right := tile_to_world(map_width, 0).x
	var bottom := tile_to_world(map_width, map_height).y
	return Rect2(left, 0.0, right - left, bottom)


func _draw() -> void:
	if _colors.is_empty():
		return
	for y in map_height:
		for x in map_width:
			var c := _colors[grid[y * map_width + x]]
			if (x + y) % 2 == 0:
				c = c.darkened(0.05)  # light checkering so individual tiles read
			draw_colored_polygon(PackedVector2Array([
				tile_to_world(x, y),
				tile_to_world(x + 1, y),
				tile_to_world(x + 1, y + 1),
				tile_to_world(x, y + 1),
			]), c)
