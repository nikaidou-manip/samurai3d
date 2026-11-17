extends Node3D
## Scene dunia ada di main.tscn (edit lewat editor). Script ini hanya mendaftarkan tombol input.


func _ready() -> void:
	_key("move_forward", KEY_W)
	_key("move_back", KEY_S)
	_key("move_left", KEY_A)
	_key("move_right", KEY_D)
	_key("run", KEY_SHIFT)
	_key("jump", KEY_SPACE)
	_key("dash", KEY_CTRL)
	_key("dash", KEY_Q)
	_key("block", KEY_F)
	_key("skill", KEY_E)
	_mouse("attack", MOUSE_BUTTON_LEFT)
	_mouse("block", MOUSE_BUTTON_RIGHT)


func _key(action: String, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var e := InputEventKey.new()
	e.physical_keycode = keycode
	InputMap.action_add_event(action, e)


func _mouse(action: String, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var e := InputEventMouseButton.new()
	e.button_index = button
	InputMap.action_add_event(action, e)
