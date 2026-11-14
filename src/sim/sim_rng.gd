class_name SimRng
extends RefCounted
## Deterministic random numbers using integer math only.
## Same seed, same sequence, on every machine.

var state: int


func _init(seed_value: int) -> void:
	state = absi(seed_value) & 0x7FFFFFFF
	if state == 0:
		state = 1


func next_int() -> int:
	state = (state * 1103515245 + 12345) & 0x7FFFFFFF
	return state >> 8


## 0 to n - 1.
func range_int(n: int) -> int:
	return next_int() % n


## True with a probability of per_mille / 1000.
func chance_pm(per_mille: int) -> bool:
	return range_int(1000) < per_mille
