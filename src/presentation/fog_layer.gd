extends Node2D
## Fog of war for the local player: black where never explored, dimmed where
## explored but not currently in sight. One pixel per tile, smoothed by the GPU.

var game: Node
var texture: ImageTexture
var _bytes := PackedByteArray()
var _seen_version := -1
var _xf := Transform2D.IDENTITY


func setup(g: Node) -> void:
	game = g
	visible = not g.reveal_map
	var sim: SimWorld = g.sim
	_bytes.resize(sim.width * sim.height * 2)
	var img := Image.create_from_data(sim.width, sim.height, false, Image.FORMAT_LA8, _fill())
	texture = ImageTexture.create_from_image(img)
	var tw: float = g.iso_map.TILE_W
	var th: float = g.iso_map.TILE_H
	_xf = Transform2D(Vector2(tw * 0.5, th * 0.5), Vector2(-tw * 0.5, th * 0.5), Vector2.ZERO)
	_seen_version = sim.vis_version


func _process(_delta: float) -> void:
	if game == null or game.sim.vis_version == _seen_version:
		return
	_seen_version = game.sim.vis_version
	var sim: SimWorld = game.sim
	texture.update(Image.create_from_data(sim.width, sim.height, false, Image.FORMAT_LA8, _fill()))
	queue_redraw()


func _fill() -> PackedByteArray:
	var pl: SimPlayer = game.sim.players[game.local_player]
	var vis := pl.visible
	var seen := pl.explored
	for i in vis.size():
		_bytes[i * 2 + 1] = 0 if vis[i] == 1 else (150 if seen[i] == 1 else 255)
	return _bytes


func _draw() -> void:
	if texture == null:
		return
	draw_set_transform_matrix(_xf)
	draw_texture(texture, Vector2.ZERO)
	draw_set_transform_matrix(Transform2D.IDENTITY)
