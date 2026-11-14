extends SceneTree
## Headless simulation tests. Run from the project folder:
##   godot --headless --path . --script res://tests/test_sim.gd
## Exits with code 0 when every check passes.

var _failures := 0


func _initialize() -> void:
	var content := ContentDB.load_all()
	_economy_tests(content)
	_combat_tests(content)
	_ai_tests(content)
	print("PASS" if _failures == 0 else "FAIL (%d)" % _failures)
	quit(0 if _failures == 0 else 1)


# ---------------------------------------------------------------- economy (one player)

func _economy_tests(content: Dictionary) -> void:
	print("Economy")
	var t0 := Time.get_ticks_msec()
	var a := _play_opening(content, 42)
	var ms := Time.get_ticks_msec() - t0
	var b := _play_opening(content, 42)
	var c := _play_opening(content, 7)
	_check("same seed + same commands = identical game", a.snapshot() == b.snapshot())
	_check("different seed = different game", a.snapshot() != c.snapshot())
	var start: Dictionary = content["rules"]["start_stock"]
	var p := a.players[0]
	_check("food was gathered", int(p.stock["food"]) > int(start["food"]) - 150)
	_check("wood was gathered", int(p.stock["wood"]) > int(start["wood"]) - 25 - 60)
	_check("house finished", _count(a, 0, "house", true) == 1)
	_check("3 villagers trained (pop 6)", a.pop_used(0) == 6)
	_check("pop cap raised by house (10)", a.pop_cap(0) == 10)
	var farm_food := _farm_food(a)
	_check("farm built and being worked (%d food left in field)" % farm_food, farm_food > 0 and farm_food < 250)
	print("    5 min simulated in %d ms; stock %s" % [ms, str(p.stock)])


## Two villagers on berries, one builds a house then a farm, three more trained to the woodline.
func _play_opening(content: Dictionary, seed_value: int) -> SimWorld:
	var w := SimWorld.new()
	w.setup(content, seed_value, 160, 160, 1)
	var vills: Array = w.units.keys()
	var tc := _first(w, 0, "town_center")
	var home := w.start_tiles[0]
	var berry := w.find_nearest_resource("food", home, 20)
	var tree := w.find_nearest_resource("wood", home, 25)
	w.queue_command({"t": "gather", "p": 0, "units": [vills[0], vills[1]], "target": berry.id})
	w.queue_command({"t": "build", "p": 0, "units": [vills[2]], "building": "house", "tile": _spot(w, "house", home + Vector2i(4, -4))})
	for i in 3:
		w.queue_command({"t": "train", "p": 0, "building": tc.id, "unit": "villager"})
	w.queue_command({"t": "rally", "p": 0, "building": tc.id, "tile": tree.tile, "target": tree.id})
	for t in 6000:
		if t == 1500:
			w.queue_command({"t": "build", "p": 0, "units": [vills[2]], "building": "farm", "tile": _spot(w, "farm", home + Vector2i(-5, 4))})
		w.step()
	return w


# ---------------------------------------------------------------- combat (two players)

func _combat_tests(content: Dictionary) -> void:
	print("Combat")
	var a := _skirmish(content)
	var b := _skirmish(content)
	_check("fight is deterministic", a.snapshot() == b.snapshot())
	var p0 := _units_of(a, 0, "clubman")
	var p1 := _units_of(a, 1, "slinger")
	_check("a side was wiped out (%d clubmen vs %d slingers left)" % [p0, p1], p0 == 0 or p1 == 0)
	_check("clubmen win 4 v 3 in melee", p0 > 0)
	# idle soldiers pick fights on their own, and the Town Center shoots back
	var c := _tc_defence(content)
	_check("Town Center arrows kill a lone raider", _units_of(c, 1, "runner") == 0)


func _two_player(content: Dictionary, seed_value: int) -> SimWorld:
	var w := SimWorld.new()
	w.setup(content, seed_value, 160, 160, 2)
	w.ais.clear()   # scripted tests: no AI brains
	return w


func _skirmish(content: Dictionary) -> SimWorld:
	var w := _two_player(content, 11)
	var mid := Vector2i(80, 80)
	var a := w.spiral_free_cells(mid, 4)
	var b := w.spiral_free_cells(mid + Vector2i(6, 0), 3)
	var reds: Array[int] = []
	for c in a:
		w.spawn_unit("clubman", 0, c)
	for c in b:
		reds.append(w.spawn_unit("slinger", 1, c).id)
	for t in 1200:   # 60 s: they find each other through idle aggression
		w.step()
	return w


func _tc_defence(content: Dictionary) -> SimWorld:
	var w := _two_player(content, 11)
	var tc := _first(w, 0, "town_center")
	var spot := w.spiral_free_cells(w.tile_of(tc) + Vector2i(0, 6), 1)
	w.spawn_unit("runner", 1, spot[0])
	for t in 1200:
		w.step()
	return w


# ---------------------------------------------------------------- AI (full game)

func _ai_tests(content: Dictionary) -> void:
	print("AI skirmish (20 game minutes, human idle)")
	var t0 := Time.get_ticks_msec()
	var a := _ai_game(content, 3)
	var ms := Time.get_ticks_msec() - t0
	var ai := a.ais[0]
	var vills := _units_of(a, 1, "villager")
	var army := _units_of(a, 1, "clubman") + _units_of(a, 1, "slinger") + _units_of(a, 1, "runner")
	print("    AI: %d villagers, %d soldiers, %d buildings, %d waves sent; stock %s" % [
		vills, army, _buildings_of(a, 1), ai.wave, str(a.players[1].stock)])
	print("    human: defeated=%s, %d units left" % [a.players[0].defeated, _all_units_of(a, 0)])
	print("    20 min simulated in %d ms" % ms)
	_check("AI grew its economy (15+ villagers)", vills >= 15)
	_check("AI built a War Lodge", _count(a, 1, "war_lodge", true) >= 1)
	_check("AI built houses", _count(a, 1, "house", true) >= 3)
	_check("AI attacked at least once", ai.wave >= 1)
	var tc := _first(a, 0, "town_center")
	_check("AI army reached and damaged the human base", a.players[0].defeated or tc == null or tc.hp < tc.max_hp or _all_units_of(a, 0) < 3)
	var b := _ai_game(content, 3)
	_check("AI game is deterministic", a.snapshot() == b.snapshot())


func _ai_game(content: Dictionary, seed_value: int) -> SimWorld:
	var w := SimWorld.new()
	w.setup(content, seed_value, 192, 192)
	for t in 24000:
		w.step()
	return w


# ---------------------------------------------------------------- helpers

func _first(w: SimWorld, owner: int, type_id: String) -> SimEntity:
	for id in w.buildings:
		if w.buildings[id].owner == owner and w.buildings[id].type_id == type_id:
			return w.buildings[id]
	return null


func _spot(w: SimWorld, type_id: String, near: Vector2i) -> Vector2i:
	for c in w.spiral_free_cells(near, 80):
		if w.can_place(type_id, c, 0):
			return c
	return near


func _count(w: SimWorld, owner: int, type_id: String, finished: bool) -> int:
	var n := 0
	for id in w.buildings:
		var b: SimEntity = w.buildings[id]
		if b.owner == owner and b.type_id == type_id and (b.complete or not finished):
			n += 1
	return n


func _buildings_of(w: SimWorld, owner: int) -> int:
	var n := 0
	for id in w.buildings:
		if w.buildings[id].owner == owner:
			n += 1
	return n


func _units_of(w: SimWorld, owner: int, type_id: String) -> int:
	var n := 0
	for id in w.units:
		if w.units[id].owner == owner and w.units[id].type_id == type_id:
			n += 1
	return n


func _all_units_of(w: SimWorld, owner: int) -> int:
	var n := 0
	for id in w.units:
		if w.units[id].owner == owner:
			n += 1
	return n


func _farm_food(w: SimWorld) -> int:
	for id in w.buildings:
		if w.buildings[id].type_id == "farm" and w.buildings[id].complete:
			return w.buildings[id].amount
	return -1


func _check(label: String, ok: bool) -> void:
	print(("  ok    " if ok else "  FAIL  ") + label)
	if not ok:
		_failures += 1
