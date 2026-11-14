class_name SimWorld
extends RefCounted
## The whole game state and its rules.
## Advances in fixed ticks and changes only through commands, so the same
## starting seed plus the same commands always produce the same game.

const SUB := 256        ## sim units per tile
const TICK_RATE := 20   ## ticks per second of game time
const SEPARATION := 90  ## units closer than this (sim units) push apart when standing

var content: Dictionary
var rules: Dictionary
var world_seed := 0
var width := 0
var height := 0
var tick := 0

var terrain := PackedInt32Array()
var terrain_passable := PackedByteArray()
var terrain_buildable := PackedByteArray()
var occupancy := PackedInt32Array()   ## entity id of the building/resource on each tile, 0 = free

var entities := {}    ## id -> SimEntity (all)
var units := {}       ## id -> SimEntity
var buildings := {}   ## id -> SimEntity
var resources := {}   ## id -> SimEntity
var players: Array[SimPlayer] = []
var ais: Array[AiPlayer] = []
var start_tiles: Array[Vector2i] = []

var pathfinder := SimPathfinder.new()
var rng: SimRng
var vis_version := 0  ## goes up whenever visibility is recalculated
## Tiles whose resource node appeared or disappeared since take_changed_tiles() was last called.
var changed_tiles: Array[Vector2i] = []
## Things worth showing (shots, hits, deaths) since take_events() was last called.
var events: Array[Dictionary] = []

var _pending: Array[Dictionary] = []
var _next_id := 1
var _sort_origin := Vector2i.ZERO
var _unit_grid := {}      ## tile index -> Array of units on that tile, rebuilt each tick
var _circles := {}        ## radius -> tile offsets inside that circle


# ---------------------------------------------------------------- setup

## player_count limits how many of the players in rules.json take part (-1 = all).
func setup(p_content: Dictionary, seed_value: int, w: int, h: int, player_count := -1) -> void:
	content = p_content
	rules = content["rules"]
	_prepare_content()
	world_seed = seed_value
	width = w
	height = h
	rng = SimRng.new(seed_value)

	var tdefs: Array = content["terrain"]
	terrain = WorldGen.generate(seed_value, w, h, tdefs)
	terrain_passable.resize(w * h)
	terrain_buildable.resize(w * h)
	occupancy.resize(w * h)
	occupancy.fill(0)
	pathfinder.setup(w, h)
	for i in w * h:
		var td: Dictionary = tdefs[terrain[i]]
		terrain_passable[i] = 1 if td.get("passable", true) else 0
		terrain_buildable[i] = 1 if td.get("buildable", true) else 0
		if terrain_passable[i] == 0:
			pathfinder.set_blocked(Vector2i(i % w, i / w), true)

	var pdefs: Array = rules.get("players", [{"name": "Player 1", "ai": false}])
	var n := pdefs.size() if player_count < 0 else mini(player_count, pdefs.size())
	var start_stock: Dictionary = rules.get("start_stock", {})
	for p in n:
		var pl := SimPlayer.new()
		pl.id = p
		pl.name = String(pdefs[p].get("name", "Player %d" % (p + 1)))
		pl.color_index = p
		pl.is_ai = bool(pdefs[p].get("ai", false))
		for k in start_stock:
			pl.stock[k] = int(start_stock[k])
		pl.visible.resize(w * h)
		pl.explored.resize(w * h)
		pl.visible.fill(0)
		pl.explored.fill(0)
		players.append(pl)
		if pl.is_ai:
			ais.append(AiPlayer.new(p, self))

	WorldGen.populate(self)
	_rebuild_unit_grid()
	_update_visibility()


## Converts human-friendly numbers in the data files (seconds, tiles per second)
## into whole ticks and sim units once, at load.
func _prepare_content() -> void:
	for id in content["units"]:
		var d: Dictionary = content["units"][id]
		d["speed_sub"] = maxi(1, roundi(float(d["speed"]) * SUB / TICK_RATE))
		var ticks := {}
		var rates: Dictionary = d.get("gather_rate", {})
		for r in rates:
			ticks[r] = maxi(1, roundi(TICK_RATE / float(rates[r])))
		d["gather_ticks"] = ticks
		d["train_ticks"] = roundi(float(d.get("train_time", 10)) * TICK_RATE)
		d["reload_ticks"] = maxi(1, roundi(float(d.get("reload", 2.0)) * TICK_RATE))
	for id in content["buildings"]:
		var b: Dictionary = content["buildings"][id]
		b["build_ticks"] = roundi(float(b.get("build_time", 10)) * TICK_RATE)
		b["reload_ticks"] = maxi(1, roundi(float(b.get("reload", 2.0)) * TICK_RATE))


# ---------------------------------------------------------------- tiles

func idx(c: Vector2i) -> int:
	return c.y * width + c.x


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height


func is_walkable(c: Vector2i) -> bool:
	return in_bounds(c) and terrain_passable[idx(c)] == 1 and occupancy[idx(c)] == 0


func tile_of(e: SimEntity) -> Vector2i:
	if e.kind != SimEntity.Kind.UNIT:
		return e.tile + Vector2i(e.size / 2, e.size / 2)
	return Vector2i(e.pos.x / SUB, e.pos.y / SUB)


func tile_center(c: Vector2i) -> Vector2i:
	return Vector2i(c.x * SUB + SUB / 2, c.y * SUB + SUB / 2)


func terrain_id_at(c: Vector2i) -> String:
	return content["terrain"][terrain[idx(c)]]["id"]


## Free walkable tiles nearest to center first, in a fixed spiral order.
func spiral_free_cells(center: Vector2i, count: int, max_radius := 12) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for r in max_radius + 1:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c := center + Vector2i(dx, dy)
				if is_walkable(c):
					out.append(c)
					if out.size() >= count:
						return out
	return out


## Tiles touching a footprint on any side or corner.
func ring_cells(rect_tile: Vector2i, size: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(rect_tile.y - 1, rect_tile.y + size + 1):
		for x in range(rect_tile.x - 1, rect_tile.x + size + 1):
			var c := Vector2i(x, y)
			if FixedMath.dist_to_rect(c, rect_tile, size) == 1:
				out.append(c)
	return out


func has_walkable_ring(e: SimEntity) -> bool:
	for c in ring_cells(e.tile, e.size):
		if is_walkable(c):
			return true
	return false


func is_visible_to(player: int, c: Vector2i) -> bool:
	return in_bounds(c) and players[player].visible[idx(c)] == 1


func is_explored_by(player: int, c: Vector2i) -> bool:
	return in_bounds(c) and players[player].explored[idx(c)] == 1


# ---------------------------------------------------------------- entities

func unit_def(u: SimEntity) -> Dictionary:
	return content["units"][u.type_id]


func building_def(b: SimEntity) -> Dictionary:
	return content["buildings"][b.type_id]


func def_of(e: SimEntity) -> Dictionary:
	match e.kind:
		SimEntity.Kind.UNIT:
			return content["units"][e.type_id]
		SimEntity.Kind.BUILDING:
			return content["buildings"][e.type_id]
	return content["resources"][e.type_id]


func is_military(u: SimEntity) -> bool:
	return bool(unit_def(u).get("military", false))


func are_enemies(a: int, b: int) -> bool:
	return a >= 0 and b >= 0 and a != b


func _new_entity(kind: SimEntity.Kind, type_id: String, owner: int) -> SimEntity:
	var e := SimEntity.new()
	e.id = _next_id
	_next_id += 1
	e.kind = kind
	e.type_id = type_id
	e.owner = owner
	entities[e.id] = e
	return e


func spawn_unit(type_id: String, owner: int, cell: Vector2i) -> SimEntity:
	var d: Dictionary = content["units"][type_id]
	var u := _new_entity(SimEntity.Kind.UNIT, type_id, owner)
	u.pos = tile_center(cell)
	u.prev_pos = u.pos
	u.hp = int(d["hp"])
	u.max_hp = u.hp
	units[u.id] = u
	return u


func place_building(type_id: String, owner: int, cell: Vector2i, is_complete: bool) -> SimEntity:
	var d: Dictionary = content["buildings"][type_id]
	var b := _new_entity(SimEntity.Kind.BUILDING, type_id, owner)
	b.tile = cell
	b.size = int(d["size"])
	b.pos = Vector2i(cell.x * SUB + b.size * SUB / 2, cell.y * SUB + b.size * SUB / 2)
	b.prev_pos = b.pos
	b.max_hp = int(d["hp"])
	b.build_needed = int(d["build_ticks"])
	b.hp = b.max_hp if is_complete else maxi(1, b.max_hp / 10)
	b.complete = false
	b.build_progress = 0
	buildings[b.id] = b
	_occupy(b, true)
	if is_complete:
		complete_building(b)
	return b


func place_resource(type_id: String, cell: Vector2i) -> SimEntity:
	var d: Dictionary = content["resources"][type_id]
	var r := _new_entity(SimEntity.Kind.RESOURCE, type_id, -1)
	r.tile = cell
	r.size = 1
	r.pos = tile_center(cell)
	r.prev_pos = r.pos
	r.res_type = d["res_type"]
	r.amount = int(d["amount"])
	resources[r.id] = r
	_occupy(r, true)
	changed_tiles.append(cell)
	return r


func remove_entity(e: SimEntity) -> void:
	if e.dead:
		return
	e.dead = true
	entities.erase(e.id)
	units.erase(e.id)
	buildings.erase(e.id)
	resources.erase(e.id)
	if e.kind != SimEntity.Kind.UNIT:
		_occupy(e, false)
	if e.kind == SimEntity.Kind.RESOURCE:
		changed_tiles.append(e.tile)


func _occupy(e: SimEntity, on: bool) -> void:
	for y in e.size:
		for x in e.size:
			var c := e.tile + Vector2i(x, y)
			var i := idx(c)
			occupancy[i] = e.id if on else 0
			pathfinder.set_blocked(c, on or terrain_passable[i] == 0)


func complete_building(b: SimEntity) -> void:
	b.complete = true
	b.build_progress = b.build_needed
	var field: Dictionary = building_def(b).get("field", {})
	if not field.is_empty():
		b.res_type = field["res_type"]
		b.amount = int(field["amount"])


## Hands the drawing code the tiles whose resource nodes changed since it last asked.
func take_changed_tiles() -> Array[Vector2i]:
	var out := changed_tiles
	changed_tiles = []
	return out


## Hands the drawing code the shots, hits and deaths since it last asked.
func take_events() -> Array[Dictionary]:
	var out := events
	events = []
	return out


# ---------------------------------------------------------------- gathering

## Resource nodes, plus finished farm fields that still hold food.
func is_gatherable(e: SimEntity) -> bool:
	if e == null or e.dead:
		return false
	if e.kind == SimEntity.Kind.RESOURCE:
		return true
	return e.kind == SimEntity.Kind.BUILDING and e.complete and e.res_type != "" and e.amount > 0


## A farm can be worked by one villager at a time.
func farm_free_for(f: SimEntity, unit_id: int) -> bool:
	if f.claimed_by == 0 or f.claimed_by == unit_id:
		return true
	var c: SimEntity = units.get(f.claimed_by)
	return c == null or c.target_id != f.id


func can_gather(u: SimEntity, target: SimEntity) -> bool:
	if not is_gatherable(target) or not unit_def(u).get("gather_rate", {}).has(target.res_type):
		return false
	if target.kind == SimEntity.Kind.BUILDING:
		return target.owner == u.owner and farm_free_for(target, u.id)
	return true


## Nearest place to gather a resource type: a node someone can stand next to,
## or one of this unit's own free farms.
func find_nearest_resource(res_type: String, from: Vector2i, radius := 10, exclude_id := 0, for_unit: SimEntity = null) -> SimEntity:
	var best: SimEntity = null
	var best_d := radius * 10 + 1
	for id in resources:
		var r: SimEntity = resources[id]
		if r.res_type != res_type or r.id == exclude_id:
			continue
		var d := FixedMath.octile(from, r.tile)
		if d < best_d and has_walkable_ring(r):
			best = r
			best_d = d
	if for_unit != null:
		for id in buildings:
			var f: SimEntity = buildings[id]
			if f.owner != for_unit.owner or f.res_type != res_type or f.id == exclude_id or not is_gatherable(f):
				continue
			var d := FixedMath.octile(from, f.tile)
			if d < best_d and farm_free_for(f, for_unit.id):
				best = f
				best_d = d
	return best


## Nearest finished building of this player that accepts this resource.
func find_dropoff(owner: int, res_type: String, from: Vector2i) -> SimEntity:
	var best: SimEntity = null
	var best_d := 1 << 30
	for id in buildings:
		var b: SimEntity = buildings[id]
		if b.owner != owner or not b.complete:
			continue
		var accepts: Array = building_def(b).get("dropoff", [])
		if not res_type in accepts:
			continue
		var d := FixedMath.dist_to_rect(from, b.tile, b.size)
		if d < best_d:
			best = b
			best_d = d
	return best


# ---------------------------------------------------------------- queries

func is_adjacent(u: SimEntity, e: SimEntity) -> bool:
	return FixedMath.dist_to_rect(tile_of(u), e.tile, e.size) <= 1


## Gives a unit a path to the nearest free tile next to an entity. False if unreachable.
func path_to_entity(u: SimEntity, e: SimEntity) -> bool:
	var from := tile_of(u)
	var cands: Array[Vector2i] = []
	for c in ring_cells(e.tile, e.size):
		if is_walkable(c):
			cands.append(c)
	_sort_origin = from
	cands.sort_custom(_closer_to_origin)
	for i in mini(3, cands.size()):
		var p := pathfinder.find_path(from, cands[i])
		if not p.is_empty():
			u.path = p
			return true
	return false


func _closer_to_origin(a: Vector2i, b: Vector2i) -> bool:
	var da := FixedMath.octile(_sort_origin, a)
	var db := FixedMath.octile(_sort_origin, b)
	if da != db:
		return da < db
	if a.y != b.y:
		return a.y < b.y
	return a.x < b.x


## Nearest enemy of `owner` within `radius` tiles: units first, then (optionally) buildings.
func find_enemy(owner: int, center: Vector2i, radius: int, include_buildings: bool) -> SimEntity:
	var best: SimEntity = null
	var best_d := 1 << 30
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var c := center + Vector2i(dx, dy)
			if not in_bounds(c):
				continue
			var bucket: Array = _unit_grid.get(idx(c), [])
			for e in bucket:
				if e.dead or not are_enemies(owner, e.owner):
					continue
				var d := FixedMath.octile(center, c)
				if d < best_d:
					best = e
					best_d = d
	if best != null or not include_buildings:
		return best
	for id in buildings:
		var b: SimEntity = buildings[id]
		if not are_enemies(owner, b.owner):
			continue
		var d := FixedMath.dist_to_rect(center, b.tile, b.size)
		if d <= radius and d < best_d:
			best = b
			best_d = d
	return best


func in_attack_range(attacker: SimEntity, target: SimEntity) -> bool:
	var reach := int(def_of(attacker).get("range", 0))
	if target.kind == SimEntity.Kind.BUILDING:
		return FixedMath.dist_to_rect(tile_of(attacker), target.tile, target.size) <= maxi(1, reach)
	var d := target.pos - attacker.pos
	var r := reach * SUB + 230
	return d.x * d.x + d.y * d.y <= r * r


func pop_used(owner: int) -> int:
	var n := 0
	for id in units:
		if units[id].owner == owner:
			n += int(unit_def(units[id]).get("pop", 1))
	return n


func pop_cap(owner: int) -> int:
	var n := 0
	for id in buildings:
		var b: SimEntity = buildings[id]
		if b.owner == owner and b.complete:
			n += int(building_def(b).get("pop", 0))
	return mini(n, int(rules.get("max_pop", 200)))


func can_place(type_id: String, cell: Vector2i, owner: int, check_cost := true) -> bool:
	var d: Dictionary = content["buildings"].get(type_id, {})
	if d.is_empty():
		return false
	var s := int(d["size"])
	for y in s:
		for x in s:
			var c := cell + Vector2i(x, y)
			if not in_bounds(c):
				return false
			var i := idx(c)
			if terrain_buildable[i] == 0 or occupancy[i] != 0:
				return false
	for id in units:
		if FixedMath.dist_to_rect(tile_of(units[id]), cell, s) == 0:
			return false
	if check_cost and not players[owner].can_afford(d.get("cost", {})):
		return false
	return true


# ---------------------------------------------------------------- combat

func deal_damage(attacker: SimEntity, target: SimEntity) -> void:
	var ad := def_of(attacker)
	var atk := int(ad.get("attack", 0))
	if target.kind == SimEntity.Kind.BUILDING:
		atk = int(ad.get("building_attack", atk))
	var dmg := maxi(1, atk - int(def_of(target).get("armor", 0)))
	target.hp -= dmg
	events.append({"k": "hit", "from": attacker.pos, "to": target.pos,
		"ranged": int(ad.get("range", 0)) > 0, "owner": attacker.owner})
	if target.hp <= 0:
		events.append({"k": "death", "at": target.pos, "owner": target.owner,
			"building": target.kind == SimEntity.Kind.BUILDING, "size": target.size})
		remove_entity(target)


# ---------------------------------------------------------------- commands

## Commands are the only way to change the game. The player's clicks, the AI,
## and (later) other players over the network all arrive here.
func queue_command(cmd: Dictionary) -> void:
	_pending.append(cmd)


func _apply(cmd: Dictionary) -> void:
	var p := int(cmd.get("p", 0))
	if p < 0 or p >= players.size() or players[p].defeated:
		return
	match String(cmd.get("t", "")):
		"move":
			_cmd_move(p, cmd["units"], cmd["tile"], false)
		"attack_move":
			_cmd_move(p, cmd["units"], cmd["tile"], true)
		"attack":
			_cmd_attack(p, cmd["units"], int(cmd["target"]))
		"gather":
			_cmd_gather(p, cmd["units"], int(cmd["target"]))
		"build":
			_cmd_build(p, cmd["units"], String(cmd["building"]), cmd["tile"])
		"assist":
			_cmd_assist(p, cmd["units"], int(cmd["target"]))
		"return":
			_cmd_return(p, cmd["units"], int(cmd["target"]))
		"train":
			_cmd_train(p, int(cmd["building"]), String(cmd["unit"]))
		"rally":
			_cmd_rally(p, int(cmd["building"]), cmd["tile"], int(cmd.get("target", 0)))
		"stop":
			for u in _own_units(p, cmd["units"]):
				UnitBehavior.reset(u)


func _own_units(p: int, ids: Array) -> Array[SimEntity]:
	var out: Array[SimEntity] = []
	for id in ids:
		var u: SimEntity = units.get(int(id))
		if u != null and u.owner == p:
			out.append(u)
	return out


func _cmd_move(p: int, ids: Array, goal: Vector2i, attack_move: bool) -> void:
	var list := _own_units(p, ids)
	var cells := spiral_free_cells(goal, list.size())
	for i in list.size():
		if i < cells.size():
			order_move(list[i], cells[i])
			if attack_move:
				list[i].state = SimEntity.State.ATTACK_MOVE


func order_move(u: SimEntity, cell: Vector2i) -> void:
	UnitBehavior.reset(u)
	u.move_goal = cell
	u.path = pathfinder.find_path(tile_of(u), cell)
	u.state = SimEntity.State.MOVE


func _cmd_attack(p: int, ids: Array, target_id: int) -> void:
	var t: SimEntity = entities.get(target_id)
	if t == null or t.kind == SimEntity.Kind.RESOURCE or not are_enemies(p, t.owner):
		return
	for u in _own_units(p, ids):
		UnitBehavior.reset(u)
		u.target_id = t.id
		u.state = SimEntity.State.ATTACK


func _cmd_gather(p: int, ids: Array, target_id: int) -> void:
	var r: SimEntity = entities.get(target_id)
	if not is_gatherable(r):
		return
	for u in _own_units(p, ids):
		order_gather(u, r)


func order_gather(u: SimEntity, r: SimEntity) -> void:
	if r.kind == SimEntity.Kind.RESOURCE and not has_walkable_ring(r):
		var alt := find_nearest_resource(r.res_type, r.tile, 6)   # deep in a forest: nearest reachable
		if alt == null:
			return
		r = alt
	if not can_gather(u, r):
		return
	UnitBehavior.reset(u)
	u.target_id = r.id
	u.last_res_id = r.id
	u.last_res_type = r.res_type
	u.last_res_tile = r.tile
	u.state = SimEntity.State.GATHER
	if r.kind == SimEntity.Kind.BUILDING:
		r.claimed_by = u.id


func _cmd_build(p: int, ids: Array, type_id: String, cell: Vector2i) -> void:
	var builders := _builders(p, ids)
	if builders.is_empty() or not can_place(type_id, cell, p):
		return
	players[p].pay(content["buildings"][type_id].get("cost", {}))
	var b := place_building(type_id, p, cell, false)
	for u in builders:
		_order_build(u, b)


func _cmd_assist(p: int, ids: Array, target_id: int) -> void:
	var b: SimEntity = buildings.get(target_id)
	if b == null or b.owner != p or b.complete:
		return
	for u in _builders(p, ids):
		_order_build(u, b)


func _builders(p: int, ids: Array) -> Array[SimEntity]:
	var out: Array[SimEntity] = []
	for u in _own_units(p, ids):
		if unit_def(u).get("can_build", false):
			out.append(u)
	return out


func _order_build(u: SimEntity, b: SimEntity) -> void:
	UnitBehavior.reset(u)
	u.target_id = b.id
	u.state = SimEntity.State.BUILD


func _cmd_return(p: int, ids: Array, target_id: int) -> void:
	var b: SimEntity = buildings.get(target_id)
	if b == null or b.owner != p:
		return
	for u in _own_units(p, ids):
		if u.carry_amount > 0:
			UnitBehavior.reset(u)
			u.target_id = b.id
			u.state = SimEntity.State.RETURN


func _cmd_train(p: int, building_id: int, unit_type: String) -> void:
	var b: SimEntity = buildings.get(building_id)
	if b == null or b.owner != p or not b.complete:
		return
	if not unit_type in building_def(b).get("trains", []):
		return
	if b.queue.size() >= int(rules.get("train_queue_limit", 5)):
		return
	var cost: Dictionary = content["units"][unit_type].get("cost", {})
	if not players[p].can_afford(cost):
		return
	players[p].pay(cost)
	b.queue.append(unit_type)


func _cmd_rally(p: int, building_id: int, cell: Vector2i, target_id: int) -> void:
	var b: SimEntity = buildings.get(building_id)
	if b == null or b.owner != p:
		return
	b.rally_tile = cell
	b.rally_target = target_id


# ---------------------------------------------------------------- tick

func step() -> void:
	tick += 1
	if events.size() > 4000:   # nobody is reading them (tests, headless runs)
		events.clear()
	for cmd in _pending:
		_apply(cmd)
	_pending.clear()
	_rebuild_unit_grid()

	var think_every := maxi(1, roundi(float(rules.get("ai", {}).get("think_interval", 1.0)) * TICK_RATE))
	for ai in ais:
		if (tick + ai.pid * 7) % think_every == 0:
			ai.think(self)

	for id in units.keys():
		var u: SimEntity = units.get(id)
		if u == null:
			continue
		u.prev_pos = u.pos
		UnitBehavior.update(self, u)
	_separate_units()
	for id in buildings.keys():
		var b: SimEntity = buildings.get(id)
		if b != null:
			_update_building(b)
	if tick % 10 == 0:
		_update_visibility()
	if tick % 20 == 0:
		_check_defeat()


func _rebuild_unit_grid() -> void:
	_unit_grid.clear()
	for id in units:
		var u: SimEntity = units[id]
		var k := idx(tile_of(u))
		if not _unit_grid.has(k):
			_unit_grid[k] = []
		_unit_grid[k].append(u)


## Standing units that overlap drift apart so groups spread out instead of stacking.
func _separate_units() -> void:
	for id in units:
		var u: SimEntity = units[id]
		if not _can_drift(u):
			continue
		var t := tile_of(u)
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var c := t + Vector2i(dx, dy)
				if not in_bounds(c):
					continue
				for o in _unit_grid.get(idx(c), []):
					if o.id <= u.id or o.dead or not _can_drift(o):
						continue
					var d: Vector2i = o.pos - u.pos
					var d2 := d.x * d.x + d.y * d.y
					if d2 >= SEPARATION * SEPARATION:
						continue
					var push := Vector2i(6, 0) if (u.id + o.id) % 2 == 0 else Vector2i(0, 6)
					if d2 > 0:
						var dist := FixedMath.isqrt(d2)
						push = d * 6 / maxi(dist, 1)
					_nudge(o, push)
					_nudge(u, -push)


func _can_drift(u: SimEntity) -> bool:
	return u.state == SimEntity.State.IDLE or (u.state == SimEntity.State.ATTACK and u.path.is_empty())


func _nudge(u: SimEntity, v: Vector2i) -> void:
	var p := u.pos + v
	if is_walkable(Vector2i(p.x / SUB, p.y / SUB)):
		u.pos = p


func _update_building(b: SimEntity) -> void:
	if not b.complete:
		return
	var d := building_def(b)
	if d.has("attack"):
		if b.attack_cooldown > 0:
			b.attack_cooldown -= 1
		elif (tick + b.id) % 5 == 0:
			var e := find_enemy(b.owner, tile_of(b), int(d.get("range", 0)) + b.size / 2, false)
			if e != null:
				deal_damage(b, e)
				b.attack_cooldown = int(d["reload_ticks"])
	if b.queue.is_empty():
		return
	if pop_used(b.owner) >= pop_cap(b.owner):
		return   # housed: training waits, like AoE2
	b.train_progress += 1
	var unit_type: String = b.queue[0]
	if b.train_progress < int(content["units"][unit_type]["train_ticks"]):
		return
	var cells := spiral_free_cells(b.tile + Vector2i(b.size / 2, b.size / 2), 1)
	if cells.is_empty():
		return
	b.train_progress = 0
	b.queue.pop_front()
	var u := spawn_unit(unit_type, b.owner, cells[0])
	var target: SimEntity = entities.get(b.rally_target)
	if target != null and is_gatherable(target) and can_gather(u, target):
		order_gather(u, target)
	elif b.rally_tile.x >= 0:
		var spot := spiral_free_cells(b.rally_tile, 1)
		if not spot.is_empty():
			order_move(u, spot[0])


func _circle(radius: int) -> Array[Vector2i]:
	if _circles.has(radius):
		return _circles[radius]
	var out: Array[Vector2i] = []
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy <= radius * radius + radius:
				out.append(Vector2i(dx, dy))
	_circles[radius] = out
	return out


## Recomputes what each player can see: line of sight around their units and buildings.
func _update_visibility() -> void:
	for pl in players:
		pl.visible.fill(0)
	for id in units:
		var u: SimEntity = units[id]
		_stamp_sight(u.owner, tile_of(u), int(unit_def(u).get("los", 4)))
	for id in buildings:
		var b: SimEntity = buildings[id]
		_stamp_sight(b.owner, tile_of(b), int(building_def(b).get("los", 3)) + b.size / 2)
	vis_version += 1


func _stamp_sight(owner: int, center: Vector2i, radius: int) -> void:
	if owner < 0 or owner >= players.size():
		return
	var pl := players[owner]
	for off in _circle(radius):
		var c := center + off
		if c.x >= 0 and c.y >= 0 and c.x < width and c.y < height:
			var i := c.y * width + c.x
			pl.visible[i] = 1
			pl.explored[i] = 1


## A player is defeated when they have no units and no buildings other than farms.
func _check_defeat() -> void:
	var alive := {}
	for id in units:
		alive[units[id].owner] = true
	for id in buildings:
		var b: SimEntity = buildings[id]
		if not building_def(b).has("field"):
			alive[b.owner] = true
	for pl in players:
		if not pl.defeated and not alive.has(pl.id):
			pl.defeated = true
			events.append({"k": "defeated", "player": pl.id})


## The surviving player, or -1 while more than one remains.
func winner() -> int:
	var left: Array[int] = []
	for pl in players:
		if not pl.defeated:
			left.append(pl.id)
	return left[0] if left.size() == 1 and players.size() > 1 else -1


# ---------------------------------------------------------------- tests

## A compact picture of the whole state, for comparing two runs.
func snapshot() -> Array:
	var out: Array = [tick, _next_id]
	for pl in players:
		out.append([pl.stock["food"], pl.stock["wood"], pl.stock["stone"], pl.stock["metal"], pl.defeated])
	for id in units:
		var u: SimEntity = units[id]
		out.append([u.id, u.pos.x, u.pos.y, u.state, u.hp, u.carry_amount, u.target_id])
	for id in buildings:
		var b: SimEntity = buildings[id]
		out.append([b.id, b.hp, b.build_progress, b.queue.size(), b.train_progress, b.amount])
	var total := 0
	for id in resources:
		total += resources[id].amount
	out.append([resources.size(), total])
	return out
