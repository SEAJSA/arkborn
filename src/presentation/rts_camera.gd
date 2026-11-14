extends Camera2D
## Age of Empires II-style camera.
## WASD / arrow keys or screen-edge to scroll, mouse wheel or trackpad pinch to zoom,
## middle-mouse drag or two-finger trackpad swipe to pan.

@export var pan_speed := 900.0
@export var edge_margin := 12.0
@export var zoom_min := 0.35
@export var zoom_max := 2.0
@export var zoom_step := 0.1
@export var map_path: NodePath = ^"../IsoMap"

var _dragging := false
var _bounds := Rect2()


func _ready() -> void:
	var map := get_node(map_path)
	_bounds = map.map_bounds()
	position = _bounds.get_center()
	make_current()


func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		dir.y += 1.0

	var vp := get_viewport()
	var size := vp.get_visible_rect().size
	var mouse := vp.get_mouse_position()
	if not _dragging and DisplayServer.window_is_focused() and Rect2(Vector2.ZERO, size).has_point(mouse):
		if mouse.x <= edge_margin:
			dir.x -= 1.0
		elif mouse.x >= size.x - edge_margin:
			dir.x += 1.0
		if mouse.y <= edge_margin:
			dir.y -= 1.0
		elif mouse.y >= size.y - edge_margin:
			dir.y += 1.0

	if dir != Vector2.ZERO:
		position += dir.normalized() * pan_speed * delta / zoom.x
		_clamp_to_map()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_by(zoom_step)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_by(-zoom_step)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging:
		position -= (event as InputEventMouseMotion).relative / zoom.x
		_clamp_to_map()
	elif event is InputEventMagnifyGesture:  # Mac trackpad pinch
		_zoom_by((event as InputEventMagnifyGesture).factor - 1.0)
	elif event is InputEventPanGesture:  # Mac two-finger swipe
		position += (event as InputEventPanGesture).delta * 20.0 / zoom.x
		_clamp_to_map()


func _zoom_by(amount: float) -> void:
	var z := clampf(zoom.x * (1.0 + amount), zoom_min, zoom_max)
	zoom = Vector2(z, z)
	_clamp_to_map()


func _clamp_to_map() -> void:
	position.x = clampf(position.x, _bounds.position.x, _bounds.end.x)
	position.y = clampf(position.y, _bounds.position.y, _bounds.end.y)
