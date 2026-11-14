class_name UnitBehavior
extends RefCounted
## What each unit does every tick: walk, gather, carry resources home, build, fight.

enum Step { MOVING, ARRIVED, BLOCKED }


static func reset(u: SimEntity) -> void:
	u.path.clear()
	u.target_id = 0
	u.work_timer = 0
	u.resume_attack_move = false
	u.state = SimEntity.State.IDLE


static func update(w: SimWorld, u: SimEntity) -> void:
	if u.attack_cooldown > 0:
		u.attack_cooldown -= 1
	match u.state:
		SimEntity.State.IDLE:
			_update_idle(w, u)
		SimEntity.State.MOVE:
			_update_move(w, u)
		SimEntity.State.GATHER:
			_update_gather(w, u)
		SimEntity.State.RETURN:
			_update_return(w, u)
		SimEntity.State.BUILD:
			_update_build(w, u)
		SimEntity.State.ATTACK:
			_update_attack(w, u)
		SimEntity.State.ATTACK_MOVE:
			_update_attack_move(w, u)


## Moves one tick along the unit's path, in whole sim units.
static func step_along_path(w: SimWorld, u: SimEntity) -> Step:
	if u.path.is_empty():
		return Step.ARRIVED
	var next_cell: Vector2i = u.path[0]
	if not w.is_walkable(next_cell):
		u.path.clear()
		return Step.BLOCKED
	var target := w.tile_center(next_cell)
	var d := target - u.pos
	var dist := FixedMath.isqrt(d.x * d.x + d.y * d.y)
	var speed := int(w.unit_def(u)["speed_sub"])
	if dist <= speed:
		u.pos = target
		u.path.pop_front()
		return Step.ARRIVED if u.path.is_empty() else Step.MOVING
	u.pos += Vector2i(d.x * speed / dist, d.y * speed / dist)
	return Step.MOVING


## Walks toward the tiles next to an entity. 1 = standing next to it, 0 = on the way, -1 = can't reach.
static func _approach(w: SimWorld, u: SimEntity, e: SimEntity) -> int:
	if w.is_adjacent(u, e):
		u.path.clear()
		return 1
	if u.path.is_empty() and not w.path_to_entity(u, e):
		return -1
	if step_along_path(w, u) == Step.BLOCKED:
		u.path.clear()
	return 0


# ---------------------------------------------------------------- moving and fighting

## Idle soldiers look around now and then and engage enemies they can see.
static func _update_idle(w: SimWorld, u: SimEntity) -> void:
	if not w.is_military(u) or (w.tick + u.id) % 10 != 0:
		return
	var e := w.find_enemy(u.owner, w.tile_of(u), int(w.unit_def(u).get("los", 4)), true)
	if e != null:
		u.target_id = e.id
		u.resume_attack_move = false
		u.state = SimEntity.State.ATTACK


static func _update_move(w: SimWorld, u: SimEntity) -> void:
	match step_along_path(w, u):
		Step.ARRIVED:
			u.state = SimEntity.State.IDLE
		Step.BLOCKED:
			u.path = w.pathfinder.find_path(w.tile_of(u), u.move_goal)
			if u.path.is_empty():
				u.state = SimEntity.State.IDLE


## Walk to a spot, fighting anything met on the way, then carry on.
static func _update_attack_move(w: SimWorld, u: SimEntity) -> void:
	if (w.tick + u.id) % 10 == 0:
		var e := w.find_enemy(u.owner, w.tile_of(u), int(w.unit_def(u).get("los", 4)), true)
		if e != null:
			u.path.clear()
			u.target_id = e.id
			u.resume_attack_move = true
			u.state = SimEntity.State.ATTACK
			return
	match step_along_path(w, u):
		Step.ARRIVED:
			u.state = SimEntity.State.IDLE
		Step.BLOCKED:
			u.path = w.pathfinder.find_path(w.tile_of(u), u.move_goal)
			if u.path.is_empty():
				u.state = SimEntity.State.IDLE


static func _update_attack(w: SimWorld, u: SimEntity) -> void:
	var t: SimEntity = w.entities.get(u.target_id)
	if t == null or t.dead or t.kind == SimEntity.Kind.RESOURCE or not w.are_enemies(u.owner, t.owner):
		_target_lost(w, u)
		return
	if not w.in_attack_range(u, t):
		var stale := t.kind == SimEntity.Kind.UNIT and (w.tick + u.id) % 10 == 0
		if u.path.is_empty() or stale:
			if t.kind == SimEntity.Kind.BUILDING:
				if not w.path_to_entity(u, t):
					_target_lost(w, u)
					return
			else:
				u.path = w.pathfinder.find_path(w.tile_of(u), w.tile_of(t))
				if u.path.is_empty() and w.tile_of(u) != w.tile_of(t):
					_target_lost(w, u)
					return
		if step_along_path(w, u) == Step.BLOCKED:
			u.path.clear()
		if w.tile_of(u) == w.tile_of(t):   # same tile but not in reach yet: close the gap
			var d := t.pos - u.pos
			var dist := maxi(1, FixedMath.isqrt(d.x * d.x + d.y * d.y))
			var speed := int(w.unit_def(u)["speed_sub"])
			u.pos += d * mini(speed, dist) / dist
		return
	u.path.clear()
	if u.attack_cooldown > 0:
		return
	w.deal_damage(u, t)
	u.attack_cooldown = int(w.unit_def(u)["reload_ticks"])


static func _target_lost(w: SimWorld, u: SimEntity) -> void:
	u.target_id = 0
	u.path.clear()
	if u.resume_attack_move and u.move_goal.x >= 0:
		u.path = w.pathfinder.find_path(w.tile_of(u), u.move_goal)
		u.state = SimEntity.State.ATTACK_MOVE if not u.path.is_empty() else SimEntity.State.IDLE
	else:
		u.state = SimEntity.State.IDLE
	u.resume_attack_move = u.state == SimEntity.State.ATTACK_MOVE


# ---------------------------------------------------------------- economy

static func _update_gather(w: SimWorld, u: SimEntity) -> void:
	var r: SimEntity = w.entities.get(u.target_id)
	if r == null or not w.can_gather(u, r):
		# Used up or taken: look for the next one of the same kind nearby.
		r = null
		if u.last_res_type != "":
			r = w.find_nearest_resource(u.last_res_type, u.last_res_tile, 10, 0, u)
		if r == null:
			if u.carry_amount > 0:
				_start_return(u)
			else:
				reset(u)
			return
		u.target_id = r.id
		u.path.clear()
		if r.kind == SimEntity.Kind.BUILDING:
			r.claimed_by = u.id

	var a := _approach(w, u, r)
	if a < 0:
		reset(u)
		return
	if a == 0:
		return

	var ud := w.unit_def(u)
	var ticks: Dictionary = ud["gather_ticks"]
	if u.carry_type != r.res_type:   # switching resource drops what was carried
		u.carry_type = r.res_type
		u.carry_amount = 0
	u.last_res_id = r.id
	u.last_res_type = r.res_type
	u.last_res_tile = r.tile
	u.work_timer += 1
	if u.work_timer < int(ticks[r.res_type]):
		return
	u.work_timer = 0
	u.carry_amount += 1
	r.amount -= 1
	if r.amount <= 0:
		w.remove_entity(r)   # a node used up, or a farm field exhausted
	if u.carry_amount >= int(ud["carry"]):
		_start_return(u)


static func _start_return(u: SimEntity) -> void:
	u.path.clear()
	u.target_id = 0
	u.work_timer = 0
	u.state = SimEntity.State.RETURN


static func _update_return(w: SimWorld, u: SimEntity) -> void:
	if u.carry_amount <= 0:
		_resume_gather(w, u)
		return
	var d: SimEntity = w.buildings.get(u.target_id)
	if d == null or not d.complete or d.owner != u.owner \
			or not u.carry_type in w.building_def(d).get("dropoff", []):
		d = w.find_dropoff(u.owner, u.carry_type, w.tile_of(u))
		if d == null:
			reset(u)
			return
		u.target_id = d.id
		u.path.clear()
	var a := _approach(w, u, d)
	if a < 0:
		reset(u)
		return
	if a == 0:
		return
	var stock := w.players[u.owner].stock
	stock[u.carry_type] = int(stock.get(u.carry_type, 0)) + u.carry_amount
	u.carry_amount = 0
	_resume_gather(w, u)


static func _resume_gather(w: SimWorld, u: SimEntity) -> void:
	var r: SimEntity = w.entities.get(u.last_res_id)
	if r == null or not w.can_gather(u, r):
		r = null
		if u.last_res_type != "":
			r = w.find_nearest_resource(u.last_res_type, u.last_res_tile, 10, 0, u)
	if r == null:
		reset(u)
		return
	w.order_gather(u, r)


static func _update_build(w: SimWorld, u: SimEntity) -> void:
	var b: SimEntity = w.buildings.get(u.target_id)
	if b == null or b.owner != u.owner or b.complete:
		_after_build(w, u, b)
		return
	var a := _approach(w, u, b)
	if a < 0:
		reset(u)
		return
	if a == 0:
		return
	b.build_progress += 1
	# health rises with construction (exact integer steps, so it sums to max_hp)
	b.hp += b.max_hp * b.build_progress / b.build_needed - b.max_hp * (b.build_progress - 1) / b.build_needed
	b.hp = mini(b.hp, b.max_hp)
	if b.build_progress >= b.build_needed:
		w.complete_building(b)
		_after_build(w, u, b)


## After finishing a farm or drop-off camp, builders start working it, like AoE2.
static func _after_build(w: SimWorld, u: SimEntity, b: SimEntity) -> void:
	reset(u)
	if b == null or not b.complete:
		return
	if w.is_gatherable(b) and w.can_gather(u, b):
		w.order_gather(u, b)
		return
	if not w.building_def(b).get("trains", []).is_empty():
		return   # Town Centers and War Lodges don't send builders off gathering
	var best: SimEntity = null
	var best_d := 1 << 30
	for res_type in w.building_def(b).get("dropoff", []):
		var r := w.find_nearest_resource(res_type, b.tile, 8)
		if r != null and FixedMath.octile(b.tile, r.tile) < best_d:
			best = r
			best_d = FixedMath.octile(b.tile, r.tile)
	if best != null:
		w.order_gather(u, best)
