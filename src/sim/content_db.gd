class_name ContentDB
extends RefCounted
## Loads game content from data/*.json.
## Units, buildings, technologies, traits and eras will all live in data files,
## so adding content means adding data, not code.

const TERRAIN_PATH := "res://data/terrain.json"


static func load_terrain() -> Array:
	var text := FileAccess.get_file_as_string(TERRAIN_PATH)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("terrain"):
		push_error("ContentDB: could not read %s" % TERRAIN_PATH)
		return []
	return parsed["terrain"]
