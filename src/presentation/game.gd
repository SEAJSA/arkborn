extends Node2D
## Root of the game scene. Owns the simulation, runs it at a fixed tick rate,
## and connects the drawing layers, camera, input and interface to it.

const SPEEDS: Array[float] = [1.0, 1.5, 2.0, 4.0]
const PLAYER_COLORS: Array[Color] = [
	Color("#3b6fd8"), Color("#d84a3b"), Color("#3bb04a"), Color("#d8c13b"),
	Color("#3bc0d8"), Color("#a84ad8"), Color("#e08a3b"), Color("#9a9a9a")]

@export var world_seed := 1337
@export var map_size := 0   ## 0 = use map_size from data/rules.json

var sim: SimWorld
var content: Dictionary
var local_player := 0
var paused := false
var reveal_map := false   ## debug view: ignore fog of war (F11)
var speed_index := 0
var interp := 0.0   ## 0..1 between the previous and current sim tick
var _acc := 0.0

@onready var iso_map: Node2D = $IsoMap
@onready var resource_layer: Node2D = $ResourceLayer
@onready var entity_layer: Node2D = $EntityLayer
@onready var fog_layer: Node2D = $FogLayer
@onready var controller: Node2D = $InputController
@onready var camera: Camera2D = $RtsCamera
@onready var hud: CanvasLayer = $HUD


func _ready() -> void:
	content = ContentDB.load_all()
	sim = SimWorld.new()
	var n: int = map_size if map_size > 0 else int(content["rules"].get("map_size", 160))
	sim.setup(content, world_seed, n, n)
	iso_map.setup(self)
	resource_layer.setup(self)
	entity_layer.setup(self)
	fog_layer.setup(self)
	camera.setup(iso_map.map_bounds())
	controller.setup(self)
	hud.setup(self)
	focus_home()
	var args := OS.get_cmdline_user_args()
	if "--demo" in args:
		_start_demo()
	for a in args:
		if a.begins_with("--skip-minutes="):   # testing aid: let game time pass before showing it
			for i in int(a.get_slice("=", 1)) * 60 * SimWorld.TICK_RATE:
				sim.step()
			sim.take_events()
	if "--reveal" in args:
		reveal_map = true
		fog_layer.visible = false
	if "--watch-ai" in args:   # testing aid: look at the AI's base
		camera.focus_on(sim_to_world(sim.tile_center(sim.start_tiles[1])))
		local_player = 0


func _process(delta: float) -> void:
	var tick_len := 1.0 / SimWorld.TICK_RATE
	if not paused:
		_acc += delta * SPEEDS[speed_index]
		var steps := 0
		while _acc >= tick_len and steps < 12:
			sim.step()
			_acc -= tick_len
			steps += 1
		if steps >= 12:
			_acc = 0.0   # the computer can't keep up; slow down instead of spiralling
	interp = clampf(_acc / tick_len, 0.0, 1.0)


## What the local player can see right now (or everything, in the debug reveal view).
func can_see(tile: Vector2i) -> bool:
	return reveal_map or sim.is_visible_to(local_player, tile)


func has_explored(tile: Vector2i) -> bool:
	return reveal_map or sim.is_explored_by(local_player, tile)


## Called when the simulation reports that a player has lost everything.
func on_player_defeated(player: int) -> void:
	if player == local_player:
		hud.show_banner("Defeated", "Your people have fallen. Rebirth as a successor people arrives in a later milestone.")
	elif sim.winner() == local_player:
		hud.show_banner("Victory!", "Every rival tribe has been defeated.")
	else:
		hud.toast("%s has been defeated." % sim.players[player].name)


## Every player action goes through here as a command.
func issue(cmd: Dictionary) -> void:
	cmd["p"] = local_player
	sim.queue_command(cmd)


func toggle_pause() -> void:
	paused = not paused


func change_speed(step: int) -> void:
	speed_index = clampi(speed_index + step, 0, SPEEDS.size() - 1)


func sim_to_world(p: Vector2i) -> Vector2:
	return iso_map.tile_to_world(p.x / float(SimWorld.SUB), p.y / float(SimWorld.SUB))


func entity_world_pos(e: SimEntity) -> Vector2:
	return sim_to_world(e.prev_pos).lerp(sim_to_world(e.pos), interp)


func player_color(owner: int) -> Color:
	return PLAYER_COLORS[owner % PLAYER_COLORS.size()] if owner >= 0 else Color.GRAY


func resource_color(res_type: String) -> Color:
	var rt: Dictionary = content["resource_types"].get(res_type, {})
	return Color.html(rt.get("color", "#ffffff"))


func resource_def_color(type_id: String) -> Color:
	return Color.html(content["resources"][type_id].get("color", "#ffffff"))


func home_building() -> SimEntity:
	for id in sim.buildings:
		var b: SimEntity = sim.buildings[id]
		if b.owner == local_player and not sim.building_def(b).get("trains", []).is_empty():
			return b
	return null


func focus_home() -> void:
	var tc := home_building()
	if tc != null:
		camera.focus_on(sim_to_world(tc.pos) + Vector2(0, 60))


## Scripted opening used for automated visual checks: godot --path . -- --demo
func _start_demo() -> void:
	var vills: Array = sim.units.keys()
	var home := sim.start_tiles[0]
	var berry := sim.find_nearest_resource("food", home, 20)
	var tree := sim.find_nearest_resource("wood", home, 25)
	var tc := home_building()
	issue({"t": "gather", "units": [vills[0]], "target": berry.id})
	issue({"t": "gather", "units": [vills[1]], "target": tree.id})
	for c in sim.spiral_free_cells(home + Vector2i(-5, 3), 80):
		if sim.can_place("house", c, local_player):
			issue({"t": "build", "units": [vills[2]], "building": "house", "tile": c})
			break
	issue({"t": "train", "building": tc.id, "unit": "villager"})
	issue({"t": "rally", "building": tc.id, "tile": berry.tile, "target": berry.id})
	speed_index = SPEEDS.size() - 1
	if "--demo-ui" in OS.get_cmdline_user_args():
		issue({"t": "train", "building": tc.id, "unit": "villager"})
		issue({"t": "train", "building": tc.id, "unit": "villager"})
		controller.select_ids([tc.id])
	else:
		controller.select_ids([vills[0], vills[1], vills[2]])
	if "--demo-place" in OS.get_cmdline_user_args():
		controller.select_ids([vills[2]])
		controller.start_placing("woodcutters_hut")
		Input.warp_mouse(Vector2(1040, 420))
