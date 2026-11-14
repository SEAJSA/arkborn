class_name SimPathfinder
extends RefCounted
## Grid pathfinding on tiles, using Godot's built-in A* grid.
## Blocked tiles: impassable terrain, buildings and resource nodes.
## Paths are lists of whole tiles, so results don't depend on float rounding.

var _astar := AStarGrid2D.new()


func setup(width: int, height: int) -> void:
	_astar.region = Rect2i(0, 0, width, height)
	_astar.cell_size = Vector2.ONE
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.update()


func set_blocked(cell: Vector2i, blocked: bool) -> void:
	_astar.set_point_solid(cell, blocked)


## Path from one tile to another, not including the start tile.
## Empty when unreachable or already there.
func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if from == to or not _astar.is_in_boundsv(to) or _astar.is_point_solid(to):
		return result
	var from_blocked := _astar.is_point_solid(from)
	if from_blocked:
		_astar.set_point_solid(from, false)
	var path := _astar.get_id_path(from, to)
	if from_blocked:
		_astar.set_point_solid(from, true)
	for i in range(1, path.size()):
		result.append(path[i])
	return result
