class_name FixedMath
extends RefCounted
## Integer-only math helpers. The simulation avoids floats so results are identical
## on every machine, which multiplayer lockstep and replayable saves depend on.


## Integer square root (floor).
static func isqrt(n: int) -> int:
	if n <= 0:
		return 0
	var x := n
	var y := (x + 1) / 2
	while y < x:
		x = y
		y = (x + n / x) / 2
	return x


## Octile distance between two tiles, scaled by 10 (straight step 10, diagonal 14).
static func octile(a: Vector2i, b: Vector2i) -> int:
	var dx := absi(a.x - b.x)
	var dy := absi(a.y - b.y)
	return 10 * maxi(dx, dy) + 4 * mini(dx, dy)


## Chebyshev (king-move) distance from a tile to a square footprint. 0 = inside, 1 = touching.
static func dist_to_rect(cell: Vector2i, rect_tile: Vector2i, size: int) -> int:
	var dx := maxi(maxi(rect_tile.x - cell.x, cell.x - (rect_tile.x + size - 1)), 0)
	var dy := maxi(maxi(rect_tile.y - cell.y, cell.y - (rect_tile.y + size - 1)), 0)
	return maxi(dx, dy)
