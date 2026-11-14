class_name AiPlayer
extends RefCounted
## A computer opponent. It looks at the world about once a second and sends commands
## through the same path as the human player, so it obeys every rule.
## For now it knows the whole map; later it should rely on its own fog of war.
##
## Its plan, in priority order: keep training villagers, never get housed, spread
## villagers across resources, build farms when berries run out, add drop-off camps,
## build a War Lodge, train an army, defend home, and attack in growing waves.

var pid := 0
var cfg: Dictionary
var rng: SimRng
var wave := 0
var next_attack_tick := 0

# Census, refreshed each think
var _tc: SimEntity
var _lodges: Array[SimEntity] = []
var _villagers: Array[SimEntity] = []
var _army: Array[SimEntity] = []
var _types_owned := {}      ## building type -> count (finished or not)
var _building_now := false  ## something is under construction
var _busy := {}             ## villagers given a job this think (their orders land next tick)


func _init(player_id: int, w: SimWorld) -> void:
	pid = player_id
	cfg = w.rules.get("ai", {})
	rng = SimRng.new(w.world_seed * 31 + player_id * 977 + 1)
	next_attack_tick = roundi(float(cfg.get("first_attack_minute", 9)) * 60.0 * SimWorld.TICK_RATE)


func think(w: SimWorld) -> void:
	if w.players[pid].defeated:
		return
	_census(w)
	if _tc == null:
		_rebuild_town_center(w)
		_assign_idle(w)
		return
	_train_villagers(w)
	_avoid_housing(w)
	_economy_buildings(w)
	_assign_idle(w)
	_military(w)
	_defend_or_attack(w)


func _cmd(w: SimWorld, cmd: Dictionary) -> void:
	cmd["p"] = pid
	w.queue_command(cmd)


func _census(w: SimWorld) -> void:
	_tc = null
	_lodges.clear()
	_villagers.clear()
	_army.clear()
	_types_owned.clear()
	_building_now = false
	_busy.clear()
	for id in w.buildings:
		var b: SimEntity = w.buildings[id]
		if b.owner != pid:
			continue
		_types_owned[b.type_id] = int(_types_owned.get(b.type_id, 0)) + 1
		if not b.complete:
			_building_now = true
		elif b.type_id == "town_center" and _tc == null:
			_tc = b
		elif b.type_id == "war_lodge":
			_lodges.append(b)
	for id in w.units:
		var u: SimEntity = w.units[id]
		if u.owner != pid:
			continue
		if w.is_military(u):
			_army.append(u)
		else:
			_villagers.append(u)


# ---------------------------------------------------------------- economy

func _train_villagers(w: SimWorld) -> void:
	var target := int(cfg.get("villager_target", 20))
	if _villagers.size() + _tc.queue.size() < target and _tc.queue.size() < 2:
		_cmd(w, {"t": "train", "building": _tc.id, "unit": "villager"})


func _avoid_housing(w: SimWorld) -> void:
	var cap := w.pop_cap(pid)
	if cap >= int(w.rules.get("max_pop", 200)) or int(_types_owned.get("house", 0)) * 5 + 5 > cap:
		return   # a house is already going up
	if cap - w.pop_used(pid) <= 3:
		_build(w, "house", w.tile_of(_tc), 4, 12)


func _economy_buildings(w: SimWorld) -> void:
	_finish_abandoned_sites(w)
	if _building_now:
		return
	var home := w.tile_of(_tc)
	if _villagers.size() >= 6 and not _types_owned.has("woodcutters_hut"):
		var tree := w.find_nearest_resource("wood", home, 30)
		if tree != null and FixedMath.dist_to_rect(tree.tile, _tc.tile, _tc.size) > 6:
			_build(w, "woodcutters_hut", tree.tile, 1, 5)
			return
	if _villagers.size() >= int(cfg.get("lodge_at_villagers", 10)) and not _types_owned.has("war_lodge"):
		_build(w, "war_lodge", home, 6, 16)
		return
	var pl := w.players[pid]
	if not _lodges.is_empty() and int(_types_owned.get("war_lodge", 0)) < 3 \
			and int(pl.stock.get("food", 0)) > 400 and int(pl.stock.get("wood", 0)) > 350:
		_build(w, "war_lodge", home, 6, 18)   # rich: more production
		return
	if _villagers.size() >= 12 and not _types_owned.has("quarry_camp"):
		var rock := w.find_nearest_resource("metal", home, 30)
		if rock != null and FixedMath.dist_to_rect(rock.tile, _tc.tile, _tc.size) > 6:
			_build(w, "quarry_camp", rock.tile, 1, 5)


## A construction site with nobody working on it gets a builder.
func _finish_abandoned_sites(w: SimWorld) -> void:
	var worked := {}
	for u in _villagers:
		if u.state == SimEntity.State.BUILD:
			worked[u.target_id] = true
	for id in w.buildings:
		var b: SimEntity = w.buildings[id]
		if b.owner == pid and not b.complete and not worked.has(b.id):
			var builder := _pick_builder()
			if builder != null:
				_busy[builder.id] = true
				_cmd(w, {"t": "assist", "units": [builder.id], "target": b.id})


## Puts idle villagers to work on whichever resource is furthest below its share.
func _assign_idle(w: SimWorld) -> void:
	var mix: Dictionary = cfg.get("gather_mix", {"food": 50, "wood": 50})
	var counts := {}
	var idle: Array[SimEntity] = []
	for u in _villagers:
		if _busy.has(u.id):
			continue
		if u.state == SimEntity.State.IDLE:
			idle.append(u)
		elif u.state == SimEntity.State.GATHER or u.state == SimEntity.State.RETURN:
			counts[u.last_res_type] = int(counts.get(u.last_res_type, 0)) + 1
	if idle.is_empty():
		return
	var home := w.tile_of(_tc) if _tc != null else w.tile_of(idle[0])
	var farms_taken := {}   # farms handed out this think (the orders land next tick)
	for u in idle:
		var order: Array[String] = []
		for k in mix:
			order.append(k)
		# biggest shortfall first; ties keep the order in rules.json
		order.sort_custom(func(a: String, b: String) -> bool:
			return int(mix[a]) * _villagers.size() - 100 * int(counts.get(a, 0)) > int(mix[b]) * _villagers.size() - 100 * int(counts.get(b, 0)))
		for res_type in order:
			var r := w.find_nearest_resource(res_type, home, 30, 0, u)
			if r != null and farms_taken.has(r.id):
				r = null
			# Food far from town means long walks: a farm by the Town Center is better.
			var far := r == null or (r.kind == SimEntity.Kind.RESOURCE and _tc != null \
				and FixedMath.dist_to_rect(r.tile, _tc.tile, _tc.size) > 8)
			if res_type == "food" and far and _tc != null:
				if _build(w, "farm", home, 3, 10, u):
					counts["food"] = int(counts.get("food", 0)) + 1
					break
				if r == null:
					continue
			if r != null:
				_cmd(w, {"t": "gather", "units": [u.id], "target": r.id})
				counts[res_type] = int(counts.get(res_type, 0)) + 1
				if r.kind == SimEntity.Kind.BUILDING:
					farms_taken[r.id] = true
				break


func _rebuild_town_center(w: SimWorld) -> void:
	if _villagers.is_empty() or _building_now:
		return
	_build(w, "town_center", w.tile_of(_villagers[0]), 3, 14)


# ---------------------------------------------------------------- building helper

## Finds a spot ringed by open ground (so the town never walls itself in) and sends a builder.
func _build(w: SimWorld, type_id: String, near: Vector2i, min_r: int, max_r: int, builder: SimEntity = null) -> bool:
	var d: Dictionary = w.content["buildings"][type_id]
	if not w.players[pid].can_afford(d.get("cost", {})):
		return false
	if builder == null:
		builder = _pick_builder()
	if builder == null:
		return false
	var s := int(d["size"])
	for r in range(min_r, max_r + 1):
		var start := rng.range_int(8 * r) if r > 0 else 0   # vary where along the ring it looks
		var ring := _ring(near - Vector2i(s / 2, s / 2), r)
		for i in ring.size():
			var c: Vector2i = ring[(i + start) % ring.size()]
			if w.can_place(type_id, c, pid) and _has_clearance(w, c, s):
				_busy[builder.id] = true
				_cmd(w, {"t": "build", "units": [builder.id], "building": type_id, "tile": c})
				_building_now = true
				_types_owned[type_id] = int(_types_owned.get(type_id, 0)) + 1
				return true
	return false


func _pick_builder() -> SimEntity:
	var best: SimEntity = null
	for u in _villagers:
		if u.state == SimEntity.State.BUILD or _busy.has(u.id):
			continue
		if u.state == SimEntity.State.IDLE:
			return u
		if best == null or (u.last_res_type == "wood" and best.last_res_type != "wood"):
			best = u
	return best


func _has_clearance(w: SimWorld, c: Vector2i, s: int) -> bool:
	for t in w.ring_cells(c, s):
		if not w.in_bounds(t):
			return false
		var e: SimEntity = w.entities.get(w.occupancy[w.idx(t)])
		if e != null and e.kind == SimEntity.Kind.BUILDING:
			return false
	return true


func _ring(center: Vector2i, r: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if r == 0:
		out.append(center)
		return out
	for dx in range(-r, r + 1):
		out.append(center + Vector2i(dx, -r))
	for dy in range(-r + 1, r + 1):
		out.append(center + Vector2i(r, dy))
	for dx in range(r - 1, -r - 1, -1):
		out.append(center + Vector2i(dx, r))
	for dy in range(r - 1, -r, -1):
		out.append(center + Vector2i(-r, dy))
	return out


# ---------------------------------------------------------------- army

func _military(w: SimWorld) -> void:
	if _villagers.size() < 8:
		return
	var mix: Array = cfg.get("military_mix", ["clubman"])
	var food := int(w.players[pid].stock.get("food", 0))
	var wood := int(w.players[pid].stock.get("wood", 0))
	for lodge in _lodges:
		if lodge.queue.size() >= 2:
			continue
		var unit_type: String = mix[rng.range_int(mix.size())]
		var cost: Dictionary = w.content["units"][unit_type].get("cost", {})
		food -= int(cost.get("food", 0))
		wood -= int(cost.get("wood", 0))
		# keep food back for the next villager while the economy is still growing
		var reserve := 50 if _villagers.size() < int(cfg.get("villager_target", 20)) else 0
		if food < reserve or wood < 0:
			return
		_cmd(w, {"t": "train", "building": lodge.id, "unit": unit_type})


func _defend_or_attack(w: SimWorld) -> void:
	if _army.is_empty():
		return
	var threat := w.find_enemy(pid, w.tile_of(_tc), int(cfg.get("defend_radius", 14)), false)
	if threat != null:
		var ids: Array[int] = []
		for u in _army:
			if u.state != SimEntity.State.ATTACK:
				ids.append(u.id)
		if not ids.is_empty():
			_cmd(w, {"t": "attack_move", "units": ids, "tile": w.tile_of(threat)})
		return

	if w.tick < next_attack_tick:
		return
	var sizes: Array = cfg.get("wave_sizes", [5])
	var need := int(sizes[mini(wave, sizes.size() - 1)])
	var ready: Array[int] = []
	for u in _army:
		if u.state == SimEntity.State.IDLE:
			ready.append(u.id)
	if ready.size() < need:
		return
	var target := _pick_target(w)
	if target == null:
		return
	_cmd(w, {"t": "attack_move", "units": ready, "tile": w.tile_of(target)})
	wave += 1
	next_attack_tick = w.tick + roundi(float(cfg.get("attack_interval_minutes", 4)) * 60.0 * SimWorld.TICK_RATE)


## The closest enemy Town Center, or failing that any enemy building.
func _pick_target(w: SimWorld) -> SimEntity:
	var home := w.tile_of(_tc)
	var best: SimEntity = null
	var best_d := 1 << 30
	for id in w.buildings:
		var b: SimEntity = w.buildings[id]
		if not w.are_enemies(pid, b.owner):
			continue
		var d := FixedMath.octile(home, b.tile) - (100000 if b.type_id == "town_center" else 0)
		if d < best_d:
			best = b
			best_d = d
	return best
