class_name PlaceholderArt
extends RefCounted
## Simple shapes standing in for real sprites until the art pass (Milestone 4).
## Everything here only draws; nothing changes the game.

const SHADOW := Color(0, 0, 0, 0.28)
const SKIN := Color("#e8c9a0")


static func ellipse(center: Vector2, rx: float, ry: float, n := 18) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


static func ring(ci: CanvasItem, center: Vector2, rx: float, ry: float, col: Color, width := 1.5) -> void:
	var pts := ellipse(center, rx, ry)
	pts.append(pts[0])
	ci.draw_polyline(pts, col, width, true)


static func shadow(ci: CanvasItem, p: Vector2, rx: float, ry: float) -> void:
	ci.draw_colored_polygon(ellipse(p, rx, ry), SHADOW)


static func bar(ci: CanvasItem, center: Vector2, width: float, frac: float, col: Color) -> void:
	var r := Rect2(center - Vector2(width * 0.5, 2.5), Vector2(width, 5))
	ci.draw_rect(r.grow(1), Color(0, 0, 0, 0.75))
	ci.draw_rect(Rect2(r.position, Vector2(width * clampf(frac, 0.0, 1.0), 5)), col)


static func hp_color(frac: float) -> Color:
	return Color("#4fc24f") if frac > 0.5 else (Color("#e0c040") if frac > 0.25 else Color("#e04a3a"))


# ---------------------------------------------------------------- units

static func draw_unit(ci: CanvasItem, game: Node, u: SimEntity, p: Vector2, selected: bool) -> void:
	const K := 1.45   # unit scale relative to the 64x32 tile
	var col: Color = game.player_color(u.owner)
	var moving := u.prev_pos != u.pos
	var t := Time.get_ticks_msec() * 0.001
	var bob := sin(t * 18.0 + u.id) * 1.5 if moving else 0.0
	var busy := u.state == SimEntity.State.GATHER or u.state == SimEntity.State.BUILD \
		or (u.state == SimEntity.State.ATTACK and u.path.is_empty())
	var swing := sin(t * 12.0 + u.id) * 0.7 if busy else 0.0
	if selected:
		ring(ci, p, 12 * K, 6 * K, Color.WHITE)
	shadow(ci, p, 7 * K, 3.5 * K)
	var b := p + Vector2(0, bob)
	var body := col
	var head := SKIN
	match u.type_id:
		"clubman":
			body = col.darkened(0.15)
		"slinger":
			body = col.lightened(0.15)
		"runner":
			body = col.lightened(0.05)
	var lean := 2.0 if u.type_id == "runner" and moving else 0.0
	ci.draw_rect(Rect2(b + Vector2(-3.5, -9) * K, Vector2(7, 9) * K), body.darkened(0.4))   # legs
	ci.draw_circle(b + Vector2(lean, -13) * K, 6.0 * K, body)                             # body
	ci.draw_circle(b + Vector2(lean * 1.4, -21.5) * K, 3.8 * K, head)                     # head
	var hand := b + Vector2(4 + lean, -13) * K
	match u.type_id:
		"villager":
			if busy:
				ci.draw_line(hand, b + (Vector2(9, -14).rotated(swing)) * K, Color("#6b4a2a"), 2.5)
		"clubman":
			var tip := hand + (Vector2(3, -12).rotated(swing * 1.6)) * K
			ci.draw_line(hand, tip, Color("#5a3b22"), 3.5)
			ci.draw_circle(tip, 3.2, Color("#4a2f1a"))
			ci.draw_rect(Rect2(b + Vector2(-9, -17) * K, Vector2(4, 9) * K), Color("#8a6a3a"))   # hide shield
		"slinger":
			var c := hand + Vector2(0, -6) * K
			var whirl := Vector2(6, 0).rotated(t * (16.0 if busy else 3.0) + u.id) * K
			ci.draw_line(hand, c + whirl, Color("#c9b47a"), 1.5)
			ci.draw_circle(c + whirl, 2.0, Color("#8d8d88"))
		"runner":
			ci.draw_line(b + Vector2(-4 + lean * 1.4, -24) * K, b + Vector2(4 + lean * 1.4, -24) * K, col.lightened(0.4), 2.5)  # headband
			ci.draw_line(hand, hand + Vector2(2, -13) * K, Color("#a08050"), 2.0)   # spear
	if u.carry_amount > 0:
		var rc: Color = game.resource_color(u.carry_type)
		var box := Rect2(b + Vector2(-11, -17) * K, Vector2(6, 6) * K)
		ci.draw_rect(box, rc)
		ci.draw_rect(box, Color(0, 0, 0, 0.6), false, 1.0)
	if selected or u.hp < u.max_hp:
		var f := float(u.hp) / maxf(1.0, u.max_hp)
		bar(ci, b + Vector2(0, -31) * K, 26, f, hp_color(f))


# ---------------------------------------------------------------- buildings

static func building_corners(game: Node, b: SimEntity) -> Array[Vector2]:
	var m: Node = game.iso_map
	var t := Vector2(b.tile)
	var s := float(b.size)
	return [
		m.tile_to_world(t.x, t.y), m.tile_to_world(t.x + s, t.y),
		m.tile_to_world(t.x + s, t.y + s), m.tile_to_world(t.x, t.y + s)]


static func draw_building(ci: CanvasItem, game: Node, b: SimEntity, selected: bool) -> void:
	var d: Dictionary = game.sim.building_def(b)
	var c := building_corners(game, b)
	var top: Vector2 = c[0]
	var right: Vector2 = c[1]
	var bottom: Vector2 = c[2]
	var left: Vector2 = c[3]
	var wall := Color.html(d["wall"])
	var roof := Color.html(d["roof"])
	var pcol: Color = game.player_color(b.owner)
	var full_h := float(d["height"])
	var frac := 1.0 if b.complete else float(b.build_progress) / maxf(1.0, b.build_needed)
	var up := Vector2(0, -full_h * frac)

	# Foundation
	var base := PackedVector2Array([top, right, bottom, left])
	ci.draw_colored_polygon(base, Color(0.32, 0.27, 0.2, 0.85))
	if selected:
		var outline := base.duplicate()
		outline.append(top)
		ci.draw_polyline(outline, Color.WHITE, 1.5, true)
	if d.has("field"):
		_draw_field(ci, b, d, c, frac)
		return

	# Walls rise as construction progresses
	if -up.y > 0.5:
		ci.draw_colored_polygon(PackedVector2Array([left, bottom, bottom + up, left + up]), wall.darkened(0.28))
		ci.draw_colored_polygon(PackedVector2Array([bottom, right, right + up, bottom + up]), wall)
		# player-colored band under the eaves
		var band := Vector2(0, 4)
		ci.draw_colored_polygon(PackedVector2Array([left + up, bottom + up, bottom + up + band, left + up + band]), pcol.darkened(0.2))
		ci.draw_colored_polygon(PackedVector2Array([bottom + up, right + up, right + up + band, bottom + up + band]), pcol)

	if b.complete:
		var apex := (top + bottom) * 0.5 + up + Vector2(0, -float(d["roof_height"]))
		ci.draw_colored_polygon(PackedVector2Array([left + up, top + up, apex]), roof.lightened(0.12))
		ci.draw_colored_polygon(PackedVector2Array([top + up, right + up, apex]), roof.lightened(0.04))
		ci.draw_colored_polygon(PackedVector2Array([left + up, bottom + up, apex]), roof.darkened(0.18))
		ci.draw_colored_polygon(PackedVector2Array([bottom + up, right + up, apex]), roof)
		# door on the right-facing wall
		var d0 := bottom.lerp(right, 0.38)
		var d1 := bottom.lerp(right, 0.52)
		var dh := Vector2(0, -minf(12.0, full_h * 0.55))
		ci.draw_colored_polygon(PackedVector2Array([d0, d1, d1 + dh, d0 + dh]), Color(0.16, 0.11, 0.07))
	else:
		# scaffold outline of the finished shape
		var sc := Color(0.85, 0.75, 0.55, 0.55)
		var fu := Vector2(0, -full_h)
		for p in [left, bottom, right]:
			ci.draw_line(p, p + fu, sc, 1.0)
		ci.draw_polyline(PackedVector2Array([left + fu, bottom + fu, right + fu, top + fu, left + fu]), sc, 1.0)
		bar(ci, (top + bottom) * 0.5 + Vector2(0, -full_h - 10), 40, frac, Color("#e0b84a"))

	if b.complete and (selected or b.hp < b.max_hp):
		var f := float(b.hp) / maxf(1.0, b.max_hp)
		bar(ci, (top + bottom) * 0.5 + Vector2(0, -full_h - float(d["roof_height"]) - 10), 44, f, hp_color(f))
	if b.complete and b.hp < b.max_hp / 2:   # smoke from a badly damaged building
		var tt := Time.get_ticks_msec() * 0.001
		for i in 3:
			var k := fmod(tt * 0.6 + i / 3.0, 1.0)
			ci.draw_circle((top + bottom) * 0.5 + Vector2(6 * sin(tt + i), -full_h - 10 - 30 * k), 5 + 6 * k, Color(0.25, 0.25, 0.25, 0.5 * (1.0 - k)))


## A farm: a flat field whose crop thins out as it is harvested.
static func _draw_field(ci: CanvasItem, b: SimEntity, d: Dictionary, c: Array[Vector2], frac: float) -> void:
	var top := c[0]
	var right := c[1]
	var left := c[3]
	var soil := Color.html(d["wall"])
	var crop := Color.html(d["roof"])
	ci.draw_colored_polygon(PackedVector2Array([c[0].lerp(c[2], 0.04), c[1].lerp(c[3], 0.04), c[2].lerp(c[0], 0.04), c[3].lerp(c[1], 0.04)]), soil)
	var ripeness := 1.0
	if b.complete:
		ripeness = clampf(float(b.amount) / float(d["field"]["amount"]), 0.0, 1.0)
	var rows := 7
	for i in rows:
		var k := (i + 0.5) / rows
		if not b.complete and k > frac:
			break
		var a0 := top.lerp(left, k)
		var a1 := right.lerp(c[2], k)
		ci.draw_line(a0.lerp(a1, 0.08), a0.lerp(a1, 0.92), crop.lerp(soil, 1.0 - ripeness * 0.9), 3.0)
	if not b.complete:
		bar(ci, (top + c[2]) * 0.5 + Vector2(0, -14), 40, frac, Color("#e0b84a"))


# ---------------------------------------------------------------- resources

static func draw_resource(ci: CanvasItem, game: Node, r: SimEntity) -> void:
	var p: Vector2 = game.sim_to_world(r.pos)
	var v := (r.id * 2654435761) >> 7 & 0xFFFF   # stable per-node variation
	var base: Color = game.resource_def_color(r.type_id)
	match r.type_id:
		"tree":
			var q := p + Vector2(float(v % 9) - 4.0, float((v >> 4) % 5) - 2.0)
			var s := 0.85 + float((v >> 8) % 4) * 0.08
			shadow(ci, q + Vector2(5, 1), 12 * s, 5 * s)
			ci.draw_rect(Rect2(q + Vector2(-2, -12 * s), Vector2(4, 12 * s)), Color("#5a3b22"))
			var c := base.lightened(float((v >> 3) % 5) * 0.035)
			if (v >> 10) % 7 == 0:
				c = c.lerp(Color("#3f8f86"), 0.45)   # the odd blue-green alien tree
			ci.draw_circle(q + Vector2(0, -22 * s), 12.5 * s, c.darkened(0.2))
			ci.draw_circle(q + Vector2(-2, -25 * s), 9.5 * s, c)
			ci.draw_circle(q + Vector2(-4.5, -28.5 * s), 4.5 * s, c.lightened(0.18))
		"berry_bush":
			shadow(ci, p + Vector2(2, 1), 11, 4.5)
			ci.draw_circle(p + Vector2(0, -6), 9.5, base.darkened(0.1))
			ci.draw_circle(p + Vector2(-2, -8), 6.5, base)
			for o in [Vector2(-5, -8), Vector2(3, -10), Vector2(4, -4), Vector2(-1, -3), Vector2(-3, -12)]:
				ci.draw_circle(p + o, 2.0, Color("#d43a4a"))
		"stone_pile", "metal_vein":
			shadow(ci, p + Vector2(2, 1), 13, 5)
			var rocks := [[Vector2(-5, -3), 8.0], [Vector2(5, -2), 7.0], [Vector2(0, -8), 7.5]]
			for i in rocks.size():
				var o: Vector2 = rocks[i][0]
				var rr: float = rocks[i][1]
				var rc := base.lightened(0.08 * i)
				ci.draw_colored_polygon(PackedVector2Array([
					p + o + Vector2(-rr, 2), p + o + Vector2(-rr * 0.5, -rr * 0.8),
					p + o + Vector2(rr * 0.6, -rr * 0.7), p + o + Vector2(rr, 2)]), rc)
			if r.type_id == "metal_vein":
				for o in [Vector2(-4, -5), Vector2(4, -4), Vector2(0, -11), Vector2(6, -1)]:
					ci.draw_circle(p + o, 1.8, Color("#f0c94a"))
		_:
			ci.draw_circle(p + Vector2(0, -6), 8, base)
