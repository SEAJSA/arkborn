class_name SimEntity
extends RefCounted
## Anything on the map: a unit, a building or a resource node.
## Positions are integers in sim units: 1 tile = SimWorld.SUB units.

enum Kind { UNIT, BUILDING, RESOURCE }
enum State { IDLE, MOVE, GATHER, RETURN, BUILD, ATTACK, ATTACK_MOVE }

var id := 0
var kind := Kind.UNIT
var type_id := ""
var owner := -1
var pos := Vector2i.ZERO        ## current position (sim units)
var prev_pos := Vector2i.ZERO   ## position last tick, for smooth drawing
var hp := 0
var max_hp := 0
var dead := false
var attack_cooldown := 0        ## ticks until it can strike again (units and armed buildings)

# Units
var state := State.IDLE
var path: Array[Vector2i] = []
var move_goal := Vector2i(-1, -1)
var target_id := 0
var resume_attack_move := false ## after this fight, carry on to move_goal
var work_timer := 0
var carry_type := ""
var carry_amount := 0
var last_res_id := 0
var last_res_type := ""
var last_res_tile := Vector2i(-1, -1)

# Buildings and resources (footprint)
var tile := Vector2i.ZERO       ## top corner tile of the footprint
var size := 1

# Buildings
var complete := true
var build_progress := 0
var build_needed := 0
var queue: Array[String] = []
var train_progress := 0
var rally_tile := Vector2i(-1, -1)
var rally_target := 0
var claimed_by := 0             ## farms: the villager working it

# Resources and farm fields
var res_type := ""
var amount := 0
