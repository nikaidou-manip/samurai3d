extends CanvasLayer
## HUD sederhana: HP, cooldown dash, jumlah hit, dan panduan kontrol.

var player  # dicari otomatis lewat group "player"

var _hp_bar: ProgressBar
var _hp_label: Label
var _dash_bar: ProgressBar
var _skill_bar: ProgressBar
var _info: Label
var _hits := 0
var _hit_timer := 0.0


func _ready() -> void:
	player = get_tree().get_first_node_in_group("player")
	var box := VBoxContainer.new()
	box.position = Vector2(20, 20)
	box.custom_minimum_size = Vector2(320, 0)
	add_child(box)

	_hp_label = Label.new()
	box.add_child(_hp_label)
	_hp_bar = _make_bar(Color(0.85, 0.2, 0.2))
	box.add_child(_hp_bar)

	var dl := Label.new()
	dl.text = "Dash"
	box.add_child(dl)
	_dash_bar = _make_bar(Color(0.3, 0.7, 1.0))
	_dash_bar.custom_minimum_size = Vector2(320, 10)
	box.add_child(_dash_bar)

	var sl := Label.new()
	sl.text = "Skill AoE (E)"
	box.add_child(sl)
	_skill_bar = _make_bar(Color(1.0, 0.75, 0.25))
	_skill_bar.custom_minimum_size = Vector2(320, 10)
	box.add_child(_skill_bar)

	_info = Label.new()
	box.add_child(_info)

	var help := Label.new()
	help.text = "WASD: gerak   Shift: sprint   Space: lompat   Ctrl / Q: dash (bisa di udara)   E: skill AoE\nKlik kiri: serang (combo 3 hit)   Klik kanan / F: block   Mouse: kamera   Esc: lepas mouse"
	add_child(help)
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 20)

	if player:
		player.hp_changed.connect(_on_hp_changed)
		player.hit_landed.connect(_on_hit)
		_on_hp_changed(player.hp, player.max_hp)


func _make_bar(color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(320, 20)
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("fill", fill)
	return bar


func _on_hp_changed(hp: int, max_hp: int) -> void:
	_hp_bar.max_value = max_hp
	_hp_bar.value = hp
	_hp_label.text = "HP %d / %d" % [hp, max_hp]


func _on_hit() -> void:
	_hits += 1
	_hit_timer = 2.0


func _process(delta: float) -> void:
	if player == null:
		return
	_dash_bar.max_value = player.dash_cooldown
	_dash_bar.value = player.dash_cooldown - player.dash_cd
	_skill_bar.max_value = player.skill_cooldown
	_skill_bar.value = player.skill_cooldown - player.skill_cd
	_hit_timer -= delta
	if _hit_timer <= 0.0:
		_hits = 0
	_info.text = ("Hit x%d" % _hits) if _hits > 0 else ""
