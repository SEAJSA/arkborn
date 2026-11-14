extends Node2D
## Draws the terrain as isometric diamond tiles, and converts between
## tile coordinates and screen-world positions. Presentation only.

const TILE_W := 64.0
const TILE_H := 32.0

var game: Node
var _colors: Array[Color] = []


func setup(g: Node) -> void:
	game = g
	for t in g.content["terrain"]:
		_colors.append(Color.html(t["color"]))
	queue_redraw()


## Tile coordinates (fractions allowed) -> world position. (0,0) is the map's top corner.
func tile_to_world(tx: float, ty: float) -> Vector2:
	return Vector2((tx - ty) * TILE_W * 0.5, (tx + ty) * TILE_H * 0.5)


## World position -> fractional tile coordinates.
func world_to_tile_f(p: Vector2) -> Vector2:
	return Vector2(
		(p.x / (TILE_W * 0.5) + p.y / (TILE_H * 0.5)) * 0.5,
		(p.y / (TILE_H * 0.5) - p.x / (TILE_W * 0.5)) * 0.5)


## World position -> the tile that contains it.
func world_to_tile(p: Vector2) -> Vector2i:
	var f := world_to_tile_f(p)
	return Vector2i(floori(f.x), floori(f.y))


## The rectangle that contains the whole diamond-shaped map.
func map_bounds() -> Rect2:
	var w: int = game.sim.width
	var h: int = game.sim.height
	var left := tile_to_world(0, h).x
	var right := tile_to_world(w, 0).x
	return Rect2(left, 0.0, right - left, tile_to_world(w, h).y)


func _draw() -> void:
	if game == null:
		return
	var sim: SimWorld = game.sim
	for y in sim.height:
		for x in sim.width:
			var c := _colors[sim.terrain[y * sim.width + x]]
			if (x + y) % 2 == 0:
				c = c.darkened(0.05)  # light checkering so individual tiles read
			draw_colored_polygon(PackedVector2Array([
				tile_to_world(x, y),
				tile_to_world(x + 1, y),
				tile_to_world(x + 1, y + 1),
				tile_to_world(x, y + 1),
			]), c)
