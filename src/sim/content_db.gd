class_name ContentDB
extends RefCounted
## Loads game content from data/*.json.
## Units, buildings, resources, terrain and rules live in data files,
## so adding content means adding data, not code.

const DATA_DIR := "res://data/"


static func load_json(file_name: String) -> Dictionary:
	var path := DATA_DIR + file_name
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("ContentDB: could not read %s" % path)
		return {}
	return parsed


static func load_terrain() -> Array:
	return load_json("terrain.json").get("terrain", [])


## Everything the simulation needs, with each list turned into an id -> definition
## dictionary. Dictionaries keep file order, which the UI uses for button order.
static func load_all() -> Dictionary:
	var res := load_json("resources.json")
	return {
		"terrain": load_terrain(),
		"units": _by_id(load_json("units.json").get("units", [])),
		"buildings": _by_id(load_json("buildings.json").get("buildings", [])),
		"resources": _by_id(res.get("resources", [])),
		"resource_types": _by_id(res.get("resource_types", [])),
		"rules": load_json("rules.json"),
	}


static func _by_id(list: Array) -> Dictionary:
	var out := {}
	for item in list:
		out[item["id"]] = item
	return out
