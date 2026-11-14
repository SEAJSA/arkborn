extends CanvasLayer
## AoE2-style interface: resource bar along the top; selection details,
## command buttons and minimap along the bottom. Built in code so the layout
## lives in one readable place.

const TOP_H := 34
const BOTTOM_H := 178
const MinimapScript := preload("res://src/presentation/hud/minimap.gd")

const INK := Color("#f1e3c2")
const INK_DIM := Color("#b8a888")
const PANEL := Color("#2a2119")
const TRIM := Color("#8c6b3a")

var game: Node
var _res_labels := {}
var _pop_label: Label
var _era_label: Label
var _time_label: Label
var _speed_label: Label
var _info_title: Label
var _info_body: Label
var _info_bar: ProgressBar
var _grid: GridContainer
var _buttons: Array[Button] = []
var _cmd_sig := ""
var _banner: PanelContainer
var _banner_title: Label
var _banner_body: Label
var _toast: Label
var _toast_time := 0.0

@onready var _debug: Label = $DebugLabel


func setup(g: Node) -> void:
	game = g
	_build()
	_debug.game = g
	_debug.position = Vector2(12, TOP_H + 8)


func toggle_debug() -> void:
	_debug.visible = not _debug.visible


# ---------------------------------------------------------------- layout

func _build() -> void:
	var root := Control.new()
	root.theme = _make_theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	move_child(root, 0)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Top bar: stockpile, population, era, clock, speed
	var top := PanelContainer.new()
	root.add_child(top)
	top.anchor_right = 1.0
	top.offset_bottom = TOP_H
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 22)
	top.add_child(bar)
	for rt in game.content["resource_types"]:
		var d: Dictionary = game.content["resource_types"][rt]
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 6)
		var swatch := ColorRect.new()
		swatch.color = Color.html(d["color"])
		swatch.custom_minimum_size = Vector2(14, 14)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.tooltip_text = d["name"]
		swatch.mouse_filter = Control.MOUSE_FILTER_PASS
		item.add_child(swatch)
		var lbl := _label("0", 16)
		lbl.custom_minimum_size.x = 44
		item.add_child(lbl)
		bar.add_child(item)
		_res_labels[rt] = lbl
	_pop_label = _label("", 16)
	bar.add_child(_pop_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(spacer)
	_era_label = _label("Wanderers", 16)
	bar.add_child(_era_label)
	_time_label = _label("", 16)
	bar.add_child(_time_label)
	_speed_label = _label("", 14)
	_speed_label.custom_minimum_size.x = 86
	bar.add_child(_speed_label)

	# Bottom panel: info | commands | minimap
	var bottom := PanelContainer.new()
	root.add_child(bottom)
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.anchor_right = 1.0
	bottom.offset_top = -BOTTOM_H
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	bottom.add_child(row)

	var info := VBoxContainer.new()
	info.custom_minimum_size = Vector2(330, 0)
	info.add_theme_constant_override("separation", 6)
	row.add_child(info)
	_info_title = _label("", 20)
	info.add_child(_info_title)
	_info_bar = ProgressBar.new()
	_info_bar.show_percentage = false
	_info_bar.custom_minimum_size = Vector2(300, 10)
	_info_bar.max_value = 1.0
	_info_bar.visible = false
	info.add_child(_info_bar)
	_info_body = _label("", 14)
	_info_body.add_theme_color_override("font_color", INK_DIM)
	_info_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_body.custom_minimum_size.x = 320
	info.add_child(_info_body)

	row.add_child(VSeparator.new())
	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	row.add_child(_grid)
	row.add_child(VSeparator.new())

	# Victory / defeat banner and short notices
	_banner = PanelContainer.new()
	_banner.visible = false
	root.add_child(_banner)
	_banner.anchor_left = 0.5
	_banner.anchor_right = 0.5
	_banner.anchor_top = 0.3
	_banner.anchor_bottom = 0.3
	_banner.offset_left = -260
	_banner.offset_right = 260
	var bv := VBoxContainer.new()
	_banner.add_child(bv)
	_banner_title = _label("", 40)
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(_banner_title)
	_banner_body = _label("", 15)
	_banner_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner_body.custom_minimum_size.x = 500
	bv.add_child(_banner_body)
	var close := Button.new()
	close.text = "Keep watching"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: _banner.visible = false)
	bv.add_child(close)
	_toast = _label("", 16)
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 4)
	root.add_child(_toast)
	_toast.position = Vector2(12, TOP_H + 34)

	var mini := Control.new()
	mini.set_script(MinimapScript)
	mini.custom_minimum_size = Vector2(300, 150)
	row.add_child(mini)
	mini.call("setup", game)


func show_banner(title: String, body: String) -> void:
	_banner_title.text = title
	_banner_body.text = body
	_banner.visible = true


func toast(text: String) -> void:
	_toast.text = text
	_toast_time = 6.0


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


func _make_theme() -> Theme:
	var t := Theme.new()
	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL
	panel.border_color = TRIM
	panel.set_border_width_all(2)
	panel.set_content_margin_all(8)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_color("font_color", "Label", INK)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(3)
		sb.set_border_width_all(1)
		sb.set_content_margin_all(4)
		match state:
			"normal":
				sb.bg_color = Color("#4a3a28")
				sb.border_color = Color("#a8844a")
			"hover":
				sb.bg_color = Color("#5f4b33")
				sb.border_color = Color("#e0b84a")
			"pressed":
				sb.bg_color = Color("#36291c")
				sb.border_color = Color("#e0b84a")
			"disabled":
				sb.bg_color = Color("#2f271e")
				sb.border_color = Color("#5b4a33")
		t.set_stylebox(state, "Button", sb)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", INK)
	t.set_color("font_disabled_color", "Button", Color("#7d6f58"))
	t.set_font_size("font_size", "Button", 13)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("#15100b")
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#e0b84a")
	t.set_stylebox("background", "ProgressBar", bg)
	t.set_stylebox("fill", "ProgressBar", fill)
	return t


# ---------------------------------------------------------------- per-frame updates

func _process(_delta: float) -> void:
	if game == null:
		return
	var sim: SimWorld = game.sim
	var pl: SimPlayer = sim.players[game.local_player]
	for k in _res_labels:
		_res_labels[k].text = str(pl.stock.get(k, 0))
	var used := sim.pop_used(game.local_player)
	var cap := sim.pop_cap(game.local_player)
	_pop_label.text = "Pop %d / %d" % [used, cap]
	_pop_label.add_theme_color_override("font_color", Color("#ff7a5a") if used >= cap else INK)
	var secs := sim.tick / SimWorld.TICK_RATE
	_time_label.text = "%d:%02d:%02d" % [secs / 3600, (secs / 60) % 60, secs % 60]
	_speed_label.text = "PAUSED" if game.paused else "Speed %sx" % str(game.SPEEDS[game.speed_index])
	_update_info()
	_update_commands()
	if _toast_time > 0.0:
		_toast_time -= _delta
		_toast.visible = _toast_time > 0.0


func _update_info() -> void:
	var sim: SimWorld = game.sim
	var ents: Array[SimEntity] = game.controller.selected_entities()
	_info_bar.visible = false
	if ents.is_empty():
		_info_title.text = ""
		_info_body.text = "Click a villager or building.\nH: Town Center   .: idle villager   ,: army\nP: pause   + / -: speed   F12: debug"
		return
	if ents.size() > 1:
		var counts := {}
		var carried := 0
		for e in ents:
			var n := String(sim.unit_def(e)["name"]) if e.kind == SimEntity.Kind.UNIT else e.type_id
			counts[n] = int(counts.get(n, 0)) + 1
			carried += e.carry_amount
		_info_title.text = "%d selected" % ents.size()
		var parts: Array[String] = []
		for n in counts:
			parts.append("%d %s" % [counts[n], n])
		_info_body.text = ", ".join(parts) + ("\nCarrying %d" % carried if carried > 0 else "")
		return

	var e := ents[0]
	match e.kind:
		SimEntity.Kind.UNIT:
			var ud := sim.unit_def(e)
			_info_title.text = String(ud["name"]) + _owner_tag(e)
			var lines: Array[String] = ["HP %d / %d" % [e.hp, e.max_hp], _unit_status(e)]
			var stats := "Attack %d   Armor %d" % [int(ud.get("attack", 0)), int(ud.get("armor", 0))]
			if int(ud.get("range", 0)) > 0:
				stats += "   Range %d" % int(ud["range"])
			lines.append(stats)
			if e.carry_amount > 0:
				lines.append("Carrying %d %s" % [e.carry_amount, e.carry_type])
			_info_body.text = "\n".join(lines)
		SimEntity.Kind.BUILDING:
			var d := sim.building_def(e)
			_info_title.text = String(d["name"]) + _owner_tag(e)
			var lines: Array[String] = ["HP %d / %d" % [e.hp, e.max_hp]]
			if not e.complete:
				lines.append("Under construction: %d%%" % (100 * e.build_progress / maxi(1, e.build_needed)))
				_show_bar(float(e.build_progress) / maxi(1, e.build_needed))
			elif not e.queue.is_empty():
				var ut: String = e.queue[0]
				var need := int(game.content["units"][ut]["train_ticks"])
				var housed := sim.pop_used(e.owner) >= sim.pop_cap(e.owner)
				lines.append("Training %s%s" % [game.content["units"][ut]["name"], "  (need houses!)" if housed else ""])
				if e.queue.size() > 1:
					lines.append("%d more queued" % (e.queue.size() - 1))
				_show_bar(float(e.train_progress) / need)
			if d.has("field") and e.complete:
				lines.append("%d food left in the field" % e.amount)
			if d.has("attack"):
				lines.append("Shoots arrows: attack %d, range %d" % [int(d["attack"]), int(d["range"])])
			if int(d.get("pop", 0)) > 0:
				lines.append("Houses %d people" % int(d["pop"]))
			var drop: Array = d.get("dropoff", [])
			if not drop.is_empty():
				lines.append("Accepts: " + ", ".join(PackedStringArray(drop)))
			_info_body.text = "\n".join(lines)
		SimEntity.Kind.RESOURCE:
			_info_title.text = String(game.content["resources"][e.type_id]["name"])
			_info_body.text = "%d %s remaining" % [e.amount, e.res_type]


func _owner_tag(e: SimEntity) -> String:
	if e.owner == game.local_player or e.owner < 0:
		return ""
	return "  (%s)" % game.sim.players[e.owner].name


func _show_bar(v: float) -> void:
	_info_bar.visible = true
	_info_bar.value = clampf(v, 0.0, 1.0)


func _unit_status(u: SimEntity) -> String:
	match u.state:
		SimEntity.State.MOVE:
			return "Moving"
		SimEntity.State.GATHER:
			return "Gathering %s" % u.last_res_type
		SimEntity.State.RETURN:
			return "Taking %s home" % u.carry_type
		SimEntity.State.BUILD:
			return "Building"
		SimEntity.State.ATTACK:
			return "Fighting"
		SimEntity.State.ATTACK_MOVE:
			return "Advancing"
	return "Idle"


func _update_commands() -> void:
	var cmds: Array[Dictionary] = game.controller.available_commands()
	var sig := str(game.controller.selected)
	for c in cmds:
		sig += "|" + String(c["label"])
	if sig != _cmd_sig:
		_cmd_sig = sig
		for b in _buttons:
			b.queue_free()
		_buttons.clear()
		for c in cmds:
			var b := Button.new()
			b.focus_mode = Control.FOCUS_NONE
			b.custom_minimum_size = Vector2(118, 60)
			var hk := String(c["hotkey"])
			b.text = ("[%s] " % hk if hk != "" else "") + String(c["label"]) + "\n" + _cost_text(c["cost"])
			b.pressed.connect(c["action"])
			_grid.add_child(b)
			_buttons.append(b)
	for i in mini(cmds.size(), _buttons.size()):
		_buttons[i].disabled = not cmds[i]["enabled"]


func _cost_text(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for k in cost:
		parts.append("%d %s" % [int(cost[k]), k])
	return "  ".join(parts)
