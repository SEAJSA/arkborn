extends Node2D
## Draws resource nodes (trees, bushes, stone, metal) in 16x16-tile chunks.
## When a node is used up, only its chunk is redrawn.

const CHUNK := 16
const ChunkScript := preload("res://src/presentation/resource_chunk.gd")

var game: Node
var _chunks := {}


func setup(g: Node) -> void:
	game = g
	var sim: SimWorld = g.sim
	var order: Array[Vector2i] = []
	for cy in ceili(sim.height / float(CHUNK)):
		for cx in ceili(sim.width / float(CHUNK)):
			order.append(Vector2i(cx, cy))
	# back-to-front so overlapping trees at chunk edges layer correctly
	order.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x + a.y < b.x + b.y or (a.x + a.y == b.x + b.y and a.x < b.x))
	for k in order:
		var c := Node2D.new()
		c.set_script(ChunkScript)
		c.set("game", g)
		c.set("origin", k * CHUNK)
		c.set("size", CHUNK)
		add_child(c)
		_chunks[k] = c
	sim.take_changed_tiles()


func _process(_delta: float) -> void:
	if game == null:
		return
	var sim: SimWorld = game.sim
	if sim.changed_tiles.is_empty():
		return
	for t in sim.take_changed_tiles():
		var ch: Node2D = _chunks.get(Vector2i(t.x / CHUNK, t.y / CHUNK))
		if ch != null:
			ch.queue_redraw()
