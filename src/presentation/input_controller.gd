extends Node2D
## Turns mouse and keyboard input into selections and commands, AoE2-style.
## Left click or drag selects, right click gives orders, hotkeys trigger the command panel.
## Also draws the drag box, building placement preview, order markers and rally flag.

signal selection_changed

const DRAG_THRESHOLD := 6.0

var game: Node
var selected: Array[int] = []
var placing := ""   ## building type being placed, "" when not placing

var _press := false
var _dragging := false
var _drag_start_world := Vector2.ZERO
var _drag_start_screen := Vector2.ZERO
var _markers: Array = []   ## [world position, seconds left, color]
var _idle_cycle := 0


func setup(g: Node) -> void:
	game = g


func _process(delta: float) -> void:
	if game == null:
		return
	var sim: SimWorld = game.sim
	var kept: Array[int] = []
	for id in selected:
		if sim.entities.has(id):
			kept.append(id)
	if kept.size() != selected.size():
		select_ids(kept)
	# a drag released over the interface panels never reaches _unhandled_input
	if _press and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_finish_left_click(get_global_mouse_position(), false)
	for m in _markers:
		m[1] -= delta
	_markers = _markers.filter(func(m: Array) -> bool: return m[1] > 0.0)
	queue_redraw()


# ---------------------------------------------------------------- selection helpers

func select_ids(ids: Array) -> void:
	var typed: Array[int] = []
	for id in ids:
		typed.append(int(id))
	selected = typed
	selection_changed.emit()


func selected_set() -> Dictionary:
	var out := {}
	for id in selected:
		out[id] = true
	return out


func selected_entities() -> Array[SimEntity]:
	var out: Array[SimEntity] = []
	for id in selected:
		var e: SimEntity = game.sim.entities.get(id)
		if e != null:
			out.append(e)
	return out


func own_selected_units() -> Array[int]:
	var out: Array[int] = []
	for e in selected_entities():
		if e.kind == SimEntity.Kind.UNIT and e.owner == game.local_player:
			out.append(e.id)
	return out


func single_own_building() -> SimEntity:
	if selected.size() != 1:
		return null
	var e: SimEntity = game.sim.entities.get(selected[0])
	if e != null and e.kind == SimEntity.Kind.BUILDING and e.owner == game.local_player:
		return e
	return null


## What's under the mouse: units first, then buildings (whole visible shape), then resources.
func entity_under(world: Vector2) -> SimEntity:
	var sim: SimWorld = game.sim
	var best: SimEntity = null
	var best_d := 20.0
	var me: int = game.local_player
	for id in sim.units:
		var u: SimEntity = sim.units[id]
		if u.owner != me and not game.can_see(sim.tile_of(u)):
			continue
		var d: float = (game.entity_world_pos(u) + Vector2(0, -18)).distance_to(world)
		if d < best_d:
			best = u
			best_d = d
	if best != null:
		return best
	var front: SimEntity = null
	for id in sim.buildings:
		var b: SimEntity = sim.buildings[id]
		if b.owner != me and not game.has_explored(b.tile):
			continue
		var c := PlaceholderArt.building_corners(game, b)
		var hgt := float(sim.building_def(b)["height"]) + float(sim.building_def(b)["roof_height"])
		var shape := PackedVector2Array([c[3], c[3] + Vector2(0, -hgt), c[0] + Vector2(0, -hgt),
			c[1] + Vector2(0, -hgt), c[1], c[2]])
		if Geometry2D.is_point_in_polygon(world, shape):
			if front == null or b.pos.y + b.pos.x > front.pos.y + front.pos.x:
				front = b
	if front != null:
		return front
	for offset in [Vector2.ZERO, Vector2(0, 16), Vector2(0, 30)]:   # tree canopies stand above their tile
		var t: Vector2i = game.iso_map.world_to_tile(world + offset)
		if sim.in_bounds(t) and game.has_explored(t):
			var r: SimEntity = sim.resources.get(sim.occupancy[sim.idx(t)])
			if r != null:
				return r
	return null


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if game == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if placing != "":
					_try_place(mb.shift_pressed)
					return
				_press = true
				_dragging = false
				_drag_start_world = get_global_mouse_position()
				_drag_start_screen = mb.position
			elif _press:
				_finish_left_click(get_global_mouse_position(), mb.shift_pressed)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if placing != "":
				placing = ""
			else:
				_context_command(get_global_mouse_position())
	elif event is InputEventMouseMotion and _press and not _dragging:
		if (event as InputEventMouseMotion).position.distance_to(_drag_start_screen) > DRAG_THRESHOLD:
			_dragging = true
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event as InputEventKey)


func _finish_left_click(world: Vector2, shift: bool) -> void:
	if _dragging:
		_box_select(_drag_start_world, world, shift)
	else:
		_click_select(world, shift)
	_press = false
	_dragging = false


func _click_select(world: Vector2, shift: bool) -> void:
	var e := entity_under(world)
	if e == null:
		if not shift:
			select_ids([])
		return
	if shift and e.kind == SimEntity.Kind.UNIT and e.owner == game.local_player:
		var ids := own_selected_units()
		if e.id in ids:
			ids.erase(e.id)
		else:
			ids.append(e.id)
		select_ids(ids)
	else:
		select_ids([e.id])


func _box_select(a: Vector2, b: Vector2, shift: bool) -> void:
	var rect := Rect2(a, b - a).abs()
	var ids: Array[int] = []
	if shift:
		ids = own_selected_units()
	var sim: SimWorld = game.sim
	for id in sim.units:
		var u: SimEntity = sim.units[id]
		if u.owner == game.local_player and not u.id in ids \
				and rect.grow(8).has_point(game.entity_world_pos(u) + Vector2(0, -15)):
			ids.append(u.id)
	select_ids(ids)


func _context_command(world: Vector2) -> void:
	var sim: SimWorld = game.sim
	var units := own_selected_units()
	var target := entity_under(world)
	var tile: Vector2i = game.iso_map.world_to_tile(world)
	if units.is_empty():
		var b := single_own_building()
		if b != null and sim.in_bounds(tile):
			var tid := 0
			if target != null and target.kind == SimEntity.Kind.RESOURCE:
				tid = target.id
			game.issue({"t": "rally", "building": b.id, "tile": tile, "target": tid})
			_add_marker(world, Color("#ffd24a"))
		return
	if target != null and target.kind != SimEntity.Kind.RESOURCE and sim.are_enemies(game.local_player, target.owner):
		game.issue({"t": "attack", "units": units, "target": target.id})
		_add_marker(game.entity_world_pos(target), Color("#ff4a3a"))
		return
	if target != null and target.kind == SimEntity.Kind.BUILDING and target.owner == game.local_player \
			and sim.is_gatherable(target):
		game.issue({"t": "gather", "units": units, "target": target.id})
		_add_marker(game.sim_to_world(target.pos), Color("#e0b84a"))
		return
	if target != null and target.kind == SimEntity.Kind.RESOURCE:
		game.issue({"t": "gather", "units": units, "target": target.id})
		_add_marker(game.sim_to_world(target.pos), game.resource_color(target.res_type))
		return
	if target != null and target.kind == SimEntity.Kind.BUILDING and target.owner == game.local_player:
		if not target.complete:
			game.issue({"t": "assist", "units": units, "target": target.id})
			_add_marker(game.sim_to_world(target.pos), Color("#e0b84a"))
			return
		if not sim.building_def(target).get("dropoff", []).is_empty():
			game.issue({"t": "return", "units": units, "target": target.id})
	if sim.in_bounds(tile):
		game.issue({"t": "move", "units": units, "tile": tile})
		_add_marker(world, Color("#7ee07e"))


func _add_marker(pos: Vector2, col: Color) -> void:
	_markers.append([pos, 0.45, col])


func _handle_key(k: InputEventKey) -> void:
	match k.keycode:
		KEY_ESCAPE:
			if placing != "":
				placing = ""
			else:
				select_ids([])
		KEY_H:
			var tc: SimEntity = game.home_building()
			if tc != null:
				select_ids([tc.id])
				game.camera.focus_on(game.sim_to_world(tc.pos))
		KEY_PERIOD:
			_next_idle_villager()
		KEY_COMMA:
			_select_army()
		KEY_P, KEY_F3:
			game.toggle_pause()
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			game.change_speed(1)
		KEY_MINUS, KEY_KP_SUBTRACT:
			game.change_speed(-1)
		KEY_SPACE:
			var ents := selected_entities()
			if not ents.is_empty():
				game.camera.focus_on(game.entity_world_pos(ents[0]))
		KEY_F12:
			game.hud.toggle_debug()
		KEY_F11:
			game.reveal_map = not game.reveal_map
			game.fog_layer.visible = not game.reveal_map
		_:
			for cmd in available_commands():
				var hk := String(cmd["hotkey"])
				if hk != "" and OS.find_keycode_from_string(hk) == k.keycode:
					if cmd["enabled"]:
						(cmd["action"] as Callable).call()
					return


## Selects every soldier you own (AoE2 has a similar "all military" hotkey).
func _select_army() -> void:
	var ids: Array[int] = []
	for id in game.sim.units:
		var u: SimEntity = game.sim.units[id]
		if u.owner == game.local_player and game.sim.is_military(u):
			ids.append(u.id)
	if not ids.is_empty():
		select_ids(ids)
		game.camera.focus_on(game.entity_world_pos(game.sim.units[ids[0]]))


func _next_idle_villager() -> void:
	var sim: SimWorld = game.sim
	var idle: Array[SimEntity] = []
	for id in sim.units:
		var u: SimEntity = sim.units[id]
		if u.owner == game.local_player and u.state == SimEntity.State.IDLE \
				and sim.unit_def(u).get("can_build", false):
			idle.append(u)
	if idle.is_empty():
		return
	_idle_cycle = (_idle_cycle + 1) % idle.size()
	var u := idle[_idle_cycle]
	select_ids([u.id])
	game.camera.focus_on(game.entity_world_pos(u))


# ---------------------------------------------------------------- commands panel

## The buttons the bottom panel shows for the current selection. Hotkeys use the same list.
func available_commands() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var sim: SimWorld = game.sim
	var pl: SimPlayer = sim.players[game.local_player]
	var units := own_selected_units()
	var can_build := false
	for id in units:
		if sim.unit_def(sim.units[id]).get("can_build", false):
			can_build = true
	if can_build:
		for bid in game.content["buildings"]:
			var d: Dictionary = game.content["buildings"][bid]
			var type_id: String = bid
			var cost: Dictionary = d.get("cost", {})
			out.append({"label": d["name"], "hotkey": d.get("hotkey", ""), "cost": cost,
				"enabled": pl.can_afford(cost), "action": func() -> void: start_placing(type_id)})
	if not units.is_empty():
		out.append({"label": "Stop", "hotkey": "X", "cost": {}, "enabled": true,
			"action": func() -> void: game.issue({"t": "stop", "units": own_selected_units()})})
	var b := single_own_building()
	if b != null and b.complete:
		var limit := int(sim.rules.get("train_queue_limit", 5))
		var building_id := b.id
		for ut in sim.building_def(b).get("trains", []):
			var ud: Dictionary = game.content["units"][ut]
			var unit_type: String = ut
			var cost: Dictionary = ud.get("cost", {})
			out.append({"label": "Train " + String(ud["name"]), "hotkey": ud.get("hotkey", ""), "cost": cost,
				"enabled": pl.can_afford(cost) and b.queue.size() < limit,
				"action": func() -> void: game.issue({"t": "train", "building": building_id, "unit": unit_type})})
	return out


func start_placing(type_id: String) -> void:
	placing = type_id


func _ghost_tile() -> Vector2i:
	var s := int(game.content["buildings"][placing]["size"])
	var f: Vector2 = game.iso_map.world_to_tile_f(get_global_mouse_position())
	return Vector2i(floori(f.x - s * 0.5 + 0.5), floori(f.y - s * 0.5 + 0.5))


func _try_place(keep_placing: bool) -> void:
	var t := _ghost_tile()
	if game.sim.can_place(placing, t, game.local_player):
		game.issue({"t": "build", "units": own_selected_units(), "building": placing, "tile": t})
		_add_marker(game.iso_map.tile_to_world(t.x + 1, t.y + 1), Color("#e0b84a"))
		if not keep_placing:   # hold Shift to place several, like AoE2
			placing = ""


# ---------------------------------------------------------------- overlay drawing

func _draw() -> void:
	if game == null:
		return
	var px: float = 1.0 / game.camera.zoom.x   # one screen pixel in world units
	if _press and _dragging:
		var r := Rect2(_drag_start_world, get_global_mouse_position() - _drag_start_world).abs()
		draw_rect(r, Color(1, 1, 1, 0.08))
		draw_rect(r, Color(1, 1, 1, 0.85), false, px)
	if placing != "":
		var t := _ghost_tile()
		var s := float(game.content["buildings"][placing]["size"])
		var ok: bool = game.sim.can_place(placing, t, game.local_player)
		var m: Node = game.iso_map
		var pts := PackedVector2Array([m.tile_to_world(t.x, t.y), m.tile_to_world(t.x + s, t.y),
			m.tile_to_world(t.x + s, t.y + s), m.tile_to_world(t.x, t.y + s)])
		var col := Color(0.3, 0.9, 0.3) if ok else Color(0.95, 0.25, 0.2)
		draw_colored_polygon(pts, Color(col, 0.35))
		pts.append(pts[0])
		draw_polyline(pts, col, 2.0 * px)
	for mk in _markers:
		var k: float = 1.0 - mk[1] / 0.45
		PlaceholderArt.ring(self, mk[0], 6 + 10 * k, 3 + 5 * k, Color(mk[2], 1.0 - k), 2.0 * px)
	var b := single_own_building()
	if b != null and b.rally_tile.x >= 0:
		var p: Vector2 = game.iso_map.tile_to_world(b.rally_tile.x + 0.5, b.rally_tile.y + 0.5)
		draw_line(p, p + Vector2(0, -26), Color("#3b2a1a"), 2.0)
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -26), p + Vector2(14, -21), p + Vector2(0, -16)]),
			game.player_color(game.local_player))
