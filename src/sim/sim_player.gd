class_name SimPlayer
extends RefCounted
## One civilization's stockpile, identity and knowledge of the map.

var id := 0
var name := ""
var color_index := 0
var is_ai := false
var defeated := false
var stock := {"food": 0, "wood": 0, "stone": 0, "metal": 0}
var visible := PackedByteArray()    ## 1 where this player currently sees, per tile
var explored := PackedByteArray()   ## 1 where this player has ever seen


func can_afford(cost: Dictionary) -> bool:
	for k in cost:
		if int(stock.get(k, 0)) < int(cost[k]):
			return false
	return true


func pay(cost: Dictionary) -> void:
	for k in cost:
		stock[k] = int(stock.get(k, 0)) - int(cost[k])
