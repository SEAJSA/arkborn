extends Control
## Diamond-shaped overview map, like AoE2's. Click or drag on it to move the camera.

var game: Node
var _tex: ImageTexture
var _bounds := Rect2()
var _k := 1.0
var _off := Vector2.ZERO
var _markers: Array[SimEntity] = []   ## non-tree resource nodes, refreshed now and then
var _refresh := 0.0


func setup(g: Node) -> void:
	game = g
	var sim: SimWorld = g.sim
	var img := Image.create_empty(sim.width, sim.height, false, Image.FORMAT_RGB8)
	var cols: Array[Color] = []
	for t in g.content["terrain"]:
		cols.append(Color.html(t["color"]))
	for y in sim.height:
		for x in sim.width:
			img.set_pixel(x, y, cols[sim.terrain[y * sim.width + x]])
	_tex = ImageTexture.create_from_image(img)
	_bounds = g.iso_map.map_bounds()
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func _process(delta: float) -> void:
	if game == null:
		return
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 2.0
		_markers.clear()
		for id in game.sim.resources:
			var r: SimEntity = game.sim.resources[id]
			if r.type_id != "tree":
				_markers.append(r)
	queue_redraw()


func _layout() -> void:
	_k = minf(size.x / _bounds.size.x, size.y / _bounds.size.y)
	_off = (size - _bounds.size * _k) * 0.5 - _bounds.position * _k


func _to_mini(world: Vector2) -> Vector2:
	return world * _k + _off


func _draw() -> void:
	if game == null:
		return
	_layout()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.06, 0.04))
	var tw: float = game.iso_map.TILE_W
	var th: float = game.iso_map.TILE_H
	draw_set_transform_matrix(Transform2D(Vector2(tw * 0.5, th * 0.5) * _k, Vector2(-tw * 0.5, th * 0.5) * _k, _off))
	draw_texture(_tex, Vector2.ZERO)
	var fog: ImageTexture = game.fog_layer.texture
	if fog != null and not game.reveal_map:
		draw_texture(fog, Vector2.ZERO)
	draw_set_transform_matrix(Transform2D.IDENTITY)

	var sim: SimWorld = game.sim
	var me: int = game.local_player
	for r in _markers:
		if not r.dead and game.has_explored(r.tile):
			draw_rect(Rect2(_to_mini(game.sim_to_world(r.pos)) - Vector2(1, 1), Vector2(2, 2)), game.resource_color(r.res_type))
	for id in sim.buildings:
		var b: SimEntity = sim.buildings[id]
		if b.owner != me and not game.has_explored(b.tile):
			continue
		draw_rect(Rect2(_to_mini(game.sim_to_world(b.pos)) - Vector2(2.5, 2.5), Vector2(5, 5)), game.player_color(b.owner))
	for id in sim.units:
		var u: SimEntity = sim.units[id]
		if u.owner != me and not game.can_see(sim.tile_of(u)):
			continue
		draw_rect(Rect2(_to_mini(game.sim_to_world(u.pos)) - Vector2(1, 1), Vector2(2, 2)), game.player_color(u.owner).lightened(0.3))

	var cam: Camera2D = game.camera
	var view := get_viewport_rect().size / cam.zoom
	var r := Rect2(cam.position - view * 0.5, view)
	draw_rect(Rect2(_to_mini(r.position), r.size * _k), Color.WHITE, false, 1.0)


func _gui_input(event: InputEvent) -> void:
	var press: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	var drag: bool = event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if press or drag:
		game.camera.focus_on((event.position - _off) / _k)
		accept_event()
