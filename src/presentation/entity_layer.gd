extends Node2D
## Draws units and buildings every frame, sorted back to front, plus combat effects.
## Unit positions are blended between the last two sim ticks so movement looks smooth.
## Enemies are drawn only where the local player can see them (buildings: once explored).

var game: Node
var _effects: Array[Dictionary] = []


func setup(g: Node) -> void:
	game = g


func _process(delta: float) -> void:
	if game == null:
		return
	for ev in game.sim.take_events():
		_add_effect(ev)
	for fx in _effects:
		fx["t"] = float(fx["t"]) + delta
	_effects = _effects.filter(func(fx: Dictionary) -> bool: return float(fx["t"]) < float(fx["dur"]))
	queue_redraw()


func _add_effect(ev: Dictionary) -> void:
	var sim: SimWorld = game.sim
	match String(ev["k"]):
		"hit":
			if not _visible_at(ev["to"]) and not _visible_at(ev["from"]):
				return
			if ev["ranged"]:
				_effects.append({"k": "shot", "a": game.sim_to_world(ev["from"]), "b": game.sim_to_world(ev["to"]), "t": 0.0, "dur": 0.35})
			else:
				_effects.append({"k": "spark", "a": game.sim_to_world(ev["to"]), "t": 0.0, "dur": 0.2})
		"death":
			if _visible_at(ev["at"]):
				_effects.append({"k": "ruin" if ev["building"] else "fallen", "a": game.sim_to_world(ev["at"]),
					"size": int(ev["size"]), "col": game.player_color(int(ev["owner"])), "t": 0.0,
					"dur": 8.0 if ev["building"] else 5.0})
		"defeated":
			game.on_player_defeated(int(ev["player"]))


func _visible_at(p: Vector2i) -> bool:
	return game.can_see(Vector2i(p.x / SimWorld.SUB, p.y / SimWorld.SUB))


func _draw() -> void:
	if game == null:
		return
	var sim: SimWorld = game.sim
	var me: int = game.local_player
	var sel: Dictionary = game.controller.selected_set()
	for fx in _effects:   # things on the ground first
		if fx["k"] == "fallen" or fx["k"] == "ruin":
			_draw_remains(fx)
	var items: Array = []
	for id in sim.buildings:
		var b: SimEntity = sim.buildings[id]
		if b.owner == me or game.has_explored(b.tile):
			items.append([game.sim_to_world(b.pos).y, b, Vector2.ZERO])
	for id in sim.units:
		var u: SimEntity = sim.units[id]
		if u.owner == me or game.can_see(sim.tile_of(u)):
			var p: Vector2 = game.entity_world_pos(u)
			items.append([p.y, u, p])
	items.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for it in items:
		var e: SimEntity = it[1]
		if e.kind == SimEntity.Kind.BUILDING:
			PlaceholderArt.draw_building(self, game, e, sel.has(e.id))
		else:
			PlaceholderArt.draw_unit(self, game, e, it[2], sel.has(e.id))
	for fx in _effects:
		var k: float = float(fx["t"]) / float(fx["dur"])
		match String(fx["k"]):
			"shot":
				var a: Vector2 = fx["a"] + Vector2(0, -22)
				var b: Vector2 = fx["b"] + Vector2(0, -18)
				var p := a.lerp(b, k) + Vector2(0, -sin(k * PI) * 26)   # lobbed stone or arrow
				draw_circle(p, 2.6, Color("#d8d4c4"))
			"spark":
				var p: Vector2 = fx["a"] + Vector2(0, -18)
				for i in 4:
					var dir := Vector2.RIGHT.rotated(i * TAU / 4 + 0.6)
					draw_line(p + dir * 3, p + dir * (5 + 8 * k), Color(1, 0.9, 0.6, 1.0 - k), 1.5)


func _draw_remains(fx: Dictionary) -> void:
	var k: float = float(fx["t"]) / float(fx["dur"])
	var p: Vector2 = fx["a"]
	var fade := 1.0 - k * k
	if fx["k"] == "fallen":
		var col: Color = fx["col"]
		draw_colored_polygon(PlaceholderArt.ellipse(p, 11, 4.5), Color(col.darkened(0.45), 0.8 * fade))
		draw_circle(p + Vector2(10, -1), 3.5, Color(PlaceholderArt.SKIN.darkened(0.3), 0.8 * fade))
	else:
		var r := 22.0 * float(fx["size"])
		draw_colored_polygon(PlaceholderArt.ellipse(p, r, r * 0.5), Color(0.2, 0.16, 0.12, 0.85 * fade))
		for i in 7:
			var o := Vector2(cos(i * 2.3) * r * 0.6, sin(i * 2.3) * r * 0.28)
			draw_rect(Rect2(p + o - Vector2(4, 3), Vector2(8, 5)), Color(0.42, 0.36, 0.28, fade))
		if k < 0.4:
			var dk := k / 0.4
			draw_circle(p + Vector2(0, -20 - 30 * dk), r * 0.4 * (0.5 + dk), Color(0.5, 0.45, 0.4, 0.55 * (1.0 - dk)))
