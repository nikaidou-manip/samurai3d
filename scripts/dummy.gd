extends CharacterBody3D
## Musuh slime: mengejar player, windup (merah) lalu menyerang (melompat). Bisa di-stagger oleh serangan player.

@export var max_hp := 60
@export var chase_speed := 2.6
@export var detect_range := 9.0
@export var attack_range := 2.0
@export var attack_damage := 12
@export var windup_time := 0.7
@export var attack_cooldown := 2.0
@export var gravity := 20.0
@export var respawn_time := 4.0
@export var slime_width := 1.3        ## lebar slime (meter); model asli sangat kecil, jadi di-skala otomatis

const CLEAR := Color(1.0, 0.05, 0.05, 0.0)

var hp := 60
var dead := false

var _state := "idle"   # idle, windup, stun
var _timer := 0.0
var _atk_cd := 1.0
var _spawn := Vector3.ZERO
var _player: Node3D
var _overlay: StandardMaterial3D
var _tween: Tween

@onready var _label: Label3D = $Label3D
@onready var _body: Node3D = $Body
@onready var _slime: Node3D = $Body/Slime
@onready var _col: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	add_to_group("enemies")
	collision_layer = 2
	collision_mask = 3
	hp = max_hp
	_spawn = global_position

	_fit_slime()

	# overlay transparan untuk efek telegraph (merah) dan hit flash (putih)
	_overlay = StandardMaterial3D.new()
	_overlay.albedo_color = CLEAR
	_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for mi in _slime.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = _overlay

	# animasi bounce bawaan slime sebagai idle (loop, fase acak agar tidak serempak)
	var aps := _slime.find_children("*", "AnimationPlayer", true, false)
	if aps.size() > 0:
		var ap := aps[0] as AnimationPlayer
		var names := ap.get_animation_list()
		if names.size() > 0:
			var clip := ap.get_animation(names[0])
			clip.loop_mode = Animation.LOOP_LINEAR
			ap.play(names[0])
			ap.seek(randf() * clip.length, true)
	_update_label()


## Transform mesh relatif terhadap node slime (tanpa bergantung pada global transform).
func _mesh_box(mi: MeshInstance3D) -> AABB:
	var t := Transform3D.IDENTITY
	var n: Node = mi
	while n != _slime:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t * mi.get_aabb()


func _fit_slime() -> void:
	var box := AABB()
	var first := true
	for mi in _slime.find_children("*", "MeshInstance3D", true, false):
		var b := _mesh_box(mi as MeshInstance3D)
		box = b if first else box.merge(b)
		first = false
	if first:
		return
	var width := maxf(box.size.x, box.size.z)
	if width <= 0.0:
		return
	var s := slime_width / width
	var c := box.get_center()
	_slime.scale = Vector3.ONE * s
	_slime.position = Vector3(-c.x * s, -box.position.y * s, -c.z * s)  # tengah di origin, dasar di lantai


func _update_label() -> void:
	_label.text = "HP %d/%d" % [hp, max_hp]


func _face(to: Vector3) -> void:
	if to.length() > 0.01:
		rotation.y = atan2(-to.x, -to.z)


func _physics_process(delta: float) -> void:
	if dead:
		return
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")

	velocity.y -= gravity * delta
	_atk_cd = maxf(0.0, _atk_cd - delta)

	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var to_p := Vector3.ZERO
	var dist := INF
	var player_alive: bool = _player != null and not _player.is_dead()
	if player_alive:
		to_p = _player.global_position - global_position
		to_p.y = 0.0
		dist = to_p.length()

	match _state:
		"idle":
			var target := Vector3.ZERO
			if player_alive and dist < detect_range:
				_face(to_p)
				if dist > attack_range * 0.8:
					target = to_p / dist * chase_speed
				elif _atk_cd <= 0.0:
					_begin_windup()
			hv = hv.move_toward(target, 20.0 * delta)
		"windup":
			hv = hv.move_toward(Vector3.ZERO, 20.0 * delta)
			if player_alive:
				_face(to_p)
			_timer -= delta
			if _timer <= 0.0:
				_strike(to_p, dist, player_alive)
				_state = "idle"
				_atk_cd = attack_cooldown
		"stun":
			hv = hv.move_toward(Vector3.ZERO, 10.0 * delta)
			_timer -= delta
			if _timer <= 0.0:
				_state = "idle"

	velocity.x = hv.x
	velocity.z = hv.z
	move_and_slide()


func _set_color_tween(to: Color, time: float) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_overlay, "albedo_color", to, time)


func _begin_windup() -> void:
	_state = "windup"
	_timer = windup_time
	_set_color_tween(Color(1.0, 0.05, 0.05, 0.55), windup_time)
	# menekuk (squash) sebelum melompat
	var tw := create_tween()
	tw.tween_property(_body, "scale", Vector3(1.15, 0.8, 1.15), windup_time)


func _strike(to_p: Vector3, dist: float, player_alive: bool) -> void:
	_set_color_tween(CLEAR, 0.25)
	velocity.y = 3.5  # slime melompat saat menyerang
	var tw := create_tween()
	tw.tween_property(_body, "scale", Vector3(0.9, 1.25, 0.9), 0.08)
	tw.tween_property(_body, "scale", Vector3.ONE, 0.2)
	if not player_alive:
		return
	var forward := Vector3(-sin(rotation.y), 0.0, -cos(rotation.y))
	if dist <= attack_range + 0.5 and dist > 0.01 and forward.dot(to_p / dist) > 0.3:
		_player.take_damage(attack_damage, global_position, 8.0)


func take_damage(amount: int, from: Vector3, knock := 5.0) -> void:
	if dead:
		return
	hp = maxi(0, hp - amount)
	_update_label()
	var away := global_position - from
	away.y = 0.0
	if away.length() > 0.01:
		var push := away.normalized() * knock
		velocity.x += push.x
		velocity.z += push.z
	if _state == "windup":
		_body.scale = Vector3.ONE
	_state = "stun"
	_timer = 0.35
	_overlay.albedo_color = Color(1.0, 1.0, 1.0, 0.8)
	_set_color_tween(CLEAR, 0.3)
	if hp <= 0:
		_die()


func _die() -> void:
	dead = true
	_label.visible = false
	_col.set_deferred("disabled", true)
	if _tween:
		_tween.kill()
	var tw := create_tween()
	tw.tween_property(_body, "scale", Vector3(1.4, 0.05, 1.4), 0.25)  # menggepeng
	tw.tween_property(_body, "scale", Vector3(0.01, 0.01, 0.01), 0.15)
	tw.tween_interval(respawn_time)
	tw.tween_callback(_respawn)


func _respawn() -> void:
	global_position = _spawn
	velocity = Vector3.ZERO
	hp = max_hp
	dead = false
	_state = "idle"
	_atk_cd = 1.5
	_overlay.albedo_color = CLEAR
	_body.scale = Vector3.ONE
	_col.disabled = false
	_label.visible = true
	_update_label()
