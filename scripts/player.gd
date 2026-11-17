extends CharacterBody3D
## Player third-person: run, jump, dash, combo attack (3 hit), block.
##
## Karakter: samurai (assets/samurai). Model diambil dari idle.fbx (node Pivot/Model di player.tscn),
## animasi dari FBX lain digabung saat runtime ke satu AnimationPlayer.
## - dash_ground, dash_air, dan block hanya berisi 1-2 frame (pose), jadi pose ditahan dan gerak dash dibuat lewat kode.
## - Gerak maju (root motion) clip serangan dibaca dari tulang Hips lalu diterapkan ke CharacterBody3D.

signal hp_changed(hp: int, max_hp: int)
signal hit_landed

enum State { FREE, ATTACK, DASH, BLOCK, SKILL, DEAD }

const ANIM_FILES := {
	"run": "res://assets/samurai/run.fbx",
	"jump": "res://assets/samurai/jump.fbx",
	"dash": "res://assets/samurai/dash_ground.fbx",      # 1 frame (pose lunge rendah)
	"air_dash": "res://assets/samurai/dash_air.fbx",     # 1 frame (pose condong ke depan)
	"block": "res://assets/samurai/block.fbx",           # pose guard
	"attack1": "res://assets/samurai/attack1.fbx",
	"attack2": "res://assets/samurai/attack2.fbx",
	"attack3": "res://assets/samurai/attack3.fbx",
}
const SHOCKWAVE_PATH := "res://scenes/shockwave.tscn"
## Tidak ada clip power-up untuk samurai: skill AoE memakai clip attack3 (tebasan melompat ke bawah).
const SKILL_CLIP := "attack3"
const SKILL_HIT_FRAC := 0.60   ## ledakan AoE saat tebasan menghantam (sekitar 0.75 dtk dari 1.23 dtk)
const SAMURAI_TEX_DIR := "res://assets/samurai/textures/"
## Warna placeholder per material jika tekstur tidak ditemukan.
const FALLBACK_COLORS := {
	"Cuerpo_low_mat": Color(0.80, 0.60, 0.46),   # badan / kulit
	"Masc_mat": Color(0.80, 0.60, 0.46),         # wajah
	"Lompa_low_mat": Color(0.16, 0.22, 0.38),    # celana + ikat pinggang
	"Medias_mat1": Color(0.85, 0.80, 0.70),      # pembungkus kaki
	"Zapas_Mat1": Color(0.12, 0.09, 0.08),       # sandal
	"Frasco_Mat1": Color(0.55, 0.38, 0.20),      # labu
	"Sombrero_Mat": Color(0.78, 0.65, 0.35),     # topi caping
	"Ojo_Mat": Color(0.10, 0.07, 0.05),          # mata
	"Cristalino_Mat": Color(1.0, 1.0, 1.0, 0.12), # lensa mata (transparan)
}
const ROOT_MOTION_CLIPS := ["attack1", "attack2", "attack3"]
const ROOT_SAMPLE_RATE := 60.0

## Data combo (hasil analisis clip). "hit" = momen kena (fraksi durasi), "cancel" = mulai boleh
## lanjut combo / dash / lompat, "end" = serangan selesai.
const COMBO := [
	{"anim": "attack1", "speed": 2, "hit": 0.46, "cancel": 0.62, "end": 0.93, "damage": 10, "range": 2.6, "knockback": 4.0},
	{"anim": "attack2", "speed": 2, "hit": 0.50, "cancel": 0.70, "end": 0.92, "damage": 14, "range": 2.8, "knockback": 5.0},
	{"anim": "attack3", "speed": 2, "hit": 0.60, "cancel": 0.78, "end": 0.94, "damage": 25, "range": 3.2, "knockback": 12.0},
]

@export_group("Model")
@export var target_height := 1.8              ## tinggi karakter (meter) setelah auto-scale
@export var model_scale_override := 0.0       ## isi > 0 untuk skala manual (0 = auto dari tulang)
@export var model_yaw_offset_deg := 0.0       ## set 180 jika karakter menghadap mundur
@export var strip_root_motion := true         ## pindahkan gerak Hips animasi ke kode
@export var root_motion_scale := 1.0          ## pengali jarak maju serangan & dash
@export var jump_strip_vertical := true       ## hilangkan lonjakan Hips di clip jump (fisika yang lompat)

@export_group("Movement")
@export var walk_speed := 50
@export var sprint_speed := 15
@export var accel := 60.0
@export var turn_speed := 14.0
@export var jump_velocity := 7.0
@export var gravity := 20.0
@export var walk_anim_speed := 1.2
@export var sprint_anim_speed := 1.0

@export_group("Dash")
@export var dash_speed := 30.0                ## dash darat (gerak lewat kode, pose dari dash_ground.fbx)
@export var dash_time := 0.35
@export var dash_cooldown := 1.2
@export var dash_iframe_frac := 0.7           ## sebagian awal dash kebal damage
@export var max_air_dashes := 1               ## berapa kali boleh dash di udara per lompatan
@export var air_dash_speed := 30.0
@export var air_dash_time := 0.4

@export_group("Combat")
@export var max_hp := 100
@export var auto_aim_range := 4.0
@export var block_anim_speed := 1.5

@export_group("AoE Skill")
@export var skill_anim_speed := 0.8           ## clip attack3 1.23s -> ~1.5s (lebih lambat = ada waktu charge)
@export var skill_cooldown := 8.0
@export var skill_damage := 35
@export var skill_radius := 6.0
@export var skill_knockback := 16.0
@export var skill_guard := 0.5                ## pengali damage yang diterima saat casting

@export_group("Camera")
@export var cam_distance := 5.0
@export var cam_height := 1.6
@export var mouse_sens := 0.003

var hp := 100
var state: State = State.FREE
var state_t := 0.0
var dash_cd := 0.0
var skill_cd := 0.0
var combo_idx := 0
var invulnerable := false
var facing := Vector3.FORWARD

var _attack_buffered := false
var _hit_done := false
var _dash_dir := Vector3.FORWARD
var _dash_is_air := false
var _air_dashes_used := 0
var _skill_burst_done := false
var _cam_yaw := 0.0
var _cam_pitch := -0.35
var _shake := 0.0
var _flash_t := 0.0
var _swallow_until := 0
var _cur_anim := ""
var _anim_len := {}
var _root_z := {}
var _root_scale := 1.0
var _respawn_pos := Vector3.ZERO

@onready var _pivot: Node3D = $Pivot
@onready var _model: Node3D = $Pivot/Model
@onready var _cam_rig: Node3D = $CameraRig
@onready var _cam_pitch_node: Node3D = $CameraRig/PitchNode
@onready var _spring: SpringArm3D = $CameraRig/PitchNode/SpringArm3D
@onready var _camera: Camera3D = $CameraRig/PitchNode/SpringArm3D/Camera3D
@onready var _aura := get_node_or_null("ChargeAura") as GPUParticles3D
@onready var _charge_light := get_node_or_null("ChargeLight") as OmniLight3D
var _anim: AnimationPlayer
var _hit_overlay: StandardMaterial3D


func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 3
	hp = max_hp
	_respawn_pos = global_position
	_build_model()
	_setup_camera()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hp_changed.emit(hp, max_hp)


func is_dead() -> bool:
	return state == State.DEAD


# ---------------------------------------------------------------- setup

func _find_anim_player(root: Node) -> AnimationPlayer:
	var found := root.find_children("*", "AnimationPlayer", true, false)
	if found.size() > 0:
		return found[0] as AnimationPlayer
	return null


## Indeks clip dari namanya: "...Layer0" = 0, "...Layer0_003" = 3, "Armature_003|..." = -1
func _clip_index(clip_name: String) -> int:
	if clip_name.begins_with("Armature|Armature_003"):
		return -1
	var p := clip_name.rfind("Layer0_")
	if p == -1:
		return 0
	return int(clip_name.substr(p + 7))


## Clip milik file = clip dengan indeks tertinggi.
func _own_clip(ap: AnimationPlayer) -> Animation:
	var best: Animation = null
	var best_i := -999
	for n in ap.get_animation_list():
		if n == "RESET":
			continue
		var i := _clip_index(n)
		if i > best_i:
			best_i = i
			best = ap.get_animation(n)
	return best


func _build_model() -> void:
	_fit_model()
	_apply_materials()

	_anim = _find_anim_player(_model)
	if _anim == null:
		push_error("AnimationPlayer tidak ditemukan di node Pivot/Model (idle.fbx)")
		return
	_build_animations()

	_hit_overlay = StandardMaterial3D.new()
	_hit_overlay.albedo_color = Color(1.0, 0.1, 0.1, 0.45)
	_hit_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hit_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_pivot.rotation.y = atan2(facing.x, facing.z) + deg_to_rad(model_yaw_offset_deg)
	_play("idle")


## Skala otomatis dari tinggi tulang (ujung kepala - ujung kaki). AABB mesh tidak dipakai
## karena mesh ter-skin sehingga ukurannya menyesatkan.
func _fit_model() -> void:
	var s := model_scale_override
	if s <= 0.0:
		s = 1.0
		var skels := _model.find_children("*", "Skeleton3D", true, false)
		if skels.size() > 0:
			var sk := skels[0] as Skeleton3D
			sk.force_update_all_bone_transforms()
			var top := sk.find_bone("mixamorig_HeadTop_End")
			if top >= 0:
				var top_y := (sk.global_transform * sk.get_bone_global_pose(top).origin).y
				var bottom := INF
				for fn in ["mixamorig_LeftToe_End", "mixamorig_RightToe_End", "mixamorig_LeftToeBase", "mixamorig_RightToeBase"]:
					var fi := sk.find_bone(fn)
					if fi >= 0:
						bottom = minf(bottom, (sk.global_transform * sk.get_bone_global_pose(fi).origin).y)
				if bottom != INF and top_y - bottom > 0.1:
					s = target_height / (top_y - bottom)
	_model.scale *= s
	_root_scale = _model.scale.x


## Pasang tekstur dari assets/samurai/textures/<material>_baseColor|normal|emissive.png bila ada.
## Jika tidak ada, pakai warna placeholder (FALLBACK_COLORS).
func _apply_materials() -> void:
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for i in m.mesh.get_surface_count():
			var src := m.get_active_material(i) as StandardMaterial3D
			if src == null:
				continue
			var mat := src.duplicate() as StandardMaterial3D
			var base := String(src.resource_name)
			var tex_base := SAMURAI_TEX_DIR + base
			if mat.albedo_texture == null and ResourceLoader.exists(tex_base + "_baseColor.png"):
				mat.albedo_texture = load(tex_base + "_baseColor.png")
				mat.albedo_color = Color.WHITE
			if mat.normal_texture == null and ResourceLoader.exists(tex_base + "_normal.png"):
				mat.normal_enabled = true
				mat.normal_texture = load(tex_base + "_normal.png")
			if mat.emission_texture == null and ResourceLoader.exists(tex_base + "_emissive.png"):
				mat.emission_enabled = true
				mat.emission = Color.WHITE
				mat.emission_texture = load(tex_base + "_emissive.png")
			if mat.albedo_texture == null and FALLBACK_COLORS.has(base):
				var col: Color = FALLBACK_COLORS[base]
				mat.albedo_color = col
				if col.a < 1.0:
					mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.metallic = 0.0
			mat.roughness = 0.9
			m.set_surface_override_material(i, mat)


func _build_animations() -> void:
	var lib := AnimationLibrary.new()

	var idle_clip := _own_clip(_anim)
	if idle_clip:
		lib.add_animation("idle", idle_clip.duplicate())

	for key in ANIM_FILES:
		var ps := load(ANIM_FILES[key]) as PackedScene
		if ps == null:
			push_warning("Animasi %s gagal dimuat" % key)
			continue
		var inst := ps.instantiate()
		var ap := _find_anim_player(inst)
		var clip := _own_clip(ap) if ap else null
		if clip:
			lib.add_animation(key, clip.duplicate())
		else:
			push_warning("Tidak ada clip animasi di %s" % ANIM_FILES[key])
		inst.free()

	for n in lib.get_animation_list():
		var clip := lib.get_animation(n)
		clip.loop_mode = Animation.LOOP_LINEAR if (n == "idle" or n == "run") else Animation.LOOP_NONE
		if strip_root_motion:
			if n in ROOT_MOTION_CLIPS:
				_root_z[n] = _sample_root(clip)
			_strip_root_motion(clip, n == "jump" and jump_strip_vertical)
		_anim_len[n] = clip.length

	for lib_name in _anim.get_animation_library_list():
		_anim.remove_animation_library(lib_name)
	_anim.add_animation_library("", lib)
	_anim.playback_default_blend_time = 0.12


func _find_hips_track(clip: Animation) -> int:
	for i in clip.get_track_count():
		if clip.track_get_type(i) == Animation.TYPE_POSITION_3D and String(clip.track_get_path(i)).ends_with("Hips"):
			return i
	return -1


## Rekam progres maju (sumbu Z Hips) per 1/60 detik.
func _sample_root(clip: Animation) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var tr := _find_hips_track(clip)
	if tr < 0:
		return out
	var z0: float = clip.position_track_interpolate(tr, 0.0).z
	var steps := int(ceil(clip.length * ROOT_SAMPLE_RATE))
	for s in steps + 1:
		var t := minf(s / ROOT_SAMPLE_RATE, clip.length)
		out.append(clip.position_track_interpolate(tr, t).z - z0)
	return out


func _root_progress(clip_name: String, t: float) -> float:
	var arr: PackedFloat32Array = _root_z.get(clip_name, PackedFloat32Array())
	if arr.is_empty():
		return 0.0
	var f := clampf(t * ROOT_SAMPLE_RATE, 0.0, float(arr.size() - 1))
	var i := int(f)
	var j := mini(i + 1, arr.size() - 1)
	return lerpf(arr[i], arr[j], f - float(i))


func _strip_root_motion(clip: Animation, strip_vertical: bool) -> void:
	var tr := _find_hips_track(clip)
	if tr < 0:
		return
	var n := clip.track_get_key_count(tr)
	if n == 0:
		return
	var first: Vector3 = clip.track_get_key_value(tr, 0)
	for k in n:
		var v: Vector3 = clip.track_get_key_value(tr, k)
		clip.track_set_key_value(tr, k, Vector3(first.x, first.y if strip_vertical else v.y, first.z))


## Terapkan root motion clip ke velocity, searah `dir`.
func _apply_root_motion(delta: float, clip_name: String, speed: float, dir: Vector3) -> void:
	var t1 := state_t * speed
	var t0 := maxf(0.0, (state_t - delta) * speed)
	var dz := (_root_progress(clip_name, t1) - _root_progress(clip_name, t0)) * _root_scale * root_motion_scale
	var v := dir * (dz / maxf(delta, 0.0001))
	velocity.x = v.x
	velocity.z = v.z


func _setup_camera() -> void:
	_spring.spring_length = cam_distance
	_cam_rig.global_position = global_position + Vector3.UP * cam_height
	_camera.current = true


# ---------------------------------------------------------------- input / camera

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_cam_yaw -= event.relative.x * mouse_sens
		_cam_pitch = clampf(_cam_pitch - event.relative.y * mouse_sens, -1.2, 0.6)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_swallow_until = Time.get_ticks_msec() + 150  # klik untuk menangkap mouse tidak dihitung serangan


func _input_dir() -> Vector3:
	var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	return Vector3(v.x, 0.0, v.y).rotated(Vector3.UP, _cam_yaw)


func _process(delta: float) -> void:
	if _cam_rig == null:
		return
	var target := global_position + Vector3.UP * cam_height
	_cam_rig.global_position = _cam_rig.global_position.lerp(target, 1.0 - exp(-18.0 * delta))
	_cam_rig.rotation.y = _cam_yaw
	_cam_pitch_node.rotation.x = _cam_pitch

	_shake = maxf(0.0, _shake - delta * 1.5)
	_camera.h_offset = randf_range(-1.0, 1.0) * _shake * 0.25
	_camera.v_offset = randf_range(-1.0, 1.0) * _shake * 0.25

	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			_set_overlay(null)


func _set_overlay(mat: Material) -> void:
	if _model == null:
		return
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = mat


# ---------------------------------------------------------------- animation helper

func _play(anim_name: String, speed := 1.0, blend := 0.12, force := false) -> void:
	if _anim == null or not _anim.has_animation(anim_name):
		return
	if anim_name == _cur_anim and not force:
		_anim.speed_scale = speed
		return
	if force and anim_name == _cur_anim:
		_anim.stop()
	_cur_anim = anim_name
	_anim.speed_scale = speed
	_anim.play(anim_name, blend)


func _jump_anim_speed() -> float:
	var air_time := 2.0 * jump_velocity / gravity
	return clampf(float(_anim_len.get("jump", air_time)) / (air_time + 0.15), 0.5, 3.0)


# ---------------------------------------------------------------- main loop

func _physics_process(delta: float) -> void:
	dash_cd = maxf(0.0, dash_cd - delta)
	skill_cd = maxf(0.0, skill_cd - delta)
	state_t += delta
	if is_on_floor():
		_air_dashes_used = 0

	var want_attack := Input.is_action_just_pressed("attack") and Time.get_ticks_msec() >= _swallow_until
	var want_jump := Input.is_action_just_pressed("jump")
	var want_dash := Input.is_action_just_pressed("dash")
	var want_skill := Input.is_action_just_pressed("skill")
	var dir := _input_dir()

	if state != State.DASH:
		velocity.y -= gravity * delta

	match state:
		State.FREE:
			_state_free(delta, dir, want_attack, want_jump, want_dash, want_skill)
		State.ATTACK:
			_state_attack(delta, dir, want_attack, want_jump, want_dash, want_skill)
		State.DASH:
			_state_dash(delta)
		State.BLOCK:
			_state_block(delta, dir, want_dash)
		State.SKILL:
			_state_skill(delta, dir, want_dash)
		State.DEAD:
			_decel(delta, 20.0)

	move_and_slide()

	if _pivot:
		var target_yaw := atan2(facing.x, facing.z) + deg_to_rad(model_yaw_offset_deg)
		_pivot.rotation.y = lerp_angle(_pivot.rotation.y, target_yaw, 1.0 - exp(-turn_speed * delta))


func _decel(delta: float, rate: float) -> void:
	var hv := Vector3(velocity.x, 0.0, velocity.z).move_toward(Vector3.ZERO, rate * delta)
	velocity.x = hv.x
	velocity.z = hv.z


func _enter_state(s: State) -> void:
	state = s
	state_t = 0.0


# ---------------------------------------------------------------- FREE (idle / run / jump)

func _state_free(delta: float, dir: Vector3, atk: bool, jmp: bool, dsh: bool, skl: bool) -> void:
	var sprint := Input.is_action_pressed("run")
	var speed := sprint_speed if sprint else walk_speed
	var hv := Vector3(velocity.x, 0.0, velocity.z).move_toward(dir * speed, accel * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	if dir.length() > 0.1:
		facing = dir.normalized()

	if dsh and dash_cd <= 0.0:
		if is_on_floor():
			_start_dash(dir, false)
			return
		elif _air_dashes_used < max_air_dashes:
			_air_dashes_used += 1
			_start_dash(dir, true)  # dash di udara
			return

	if is_on_floor():
		if skl and skill_cd <= 0.0:
			_start_skill()
		elif atk:
			_start_attack(0)
		elif Input.is_action_pressed("block"):
			_start_block()
		elif jmp:
			_do_jump()
		elif dir.length() > 0.1:
			_play("run", sprint_anim_speed if sprint else walk_anim_speed)
		else:
			_play("idle")
	elif _cur_anim != "jump":
		# jatuh / selesai dash udara: lanjut dari pose melayang (bukan dari awal lompatan)
		_play("jump", _jump_anim_speed(), 0.1)
		if _anim:
			_anim.seek(float(_anim_len.get("jump", 1.0)) * 0.45, true)


func _do_jump() -> void:
	velocity.y = jump_velocity
	_play("jump", _jump_anim_speed(), 0.08, true)


# ---------------------------------------------------------------- DASH

func _dash_duration() -> float:
	return air_dash_time if _dash_is_air else dash_time


func _start_dash(dir: Vector3, air := false) -> void:
	_dash_dir = dir.normalized() if dir.length() > 0.1 else facing
	facing = _dash_dir
	dash_cd = dash_cooldown
	_dash_is_air = air
	invulnerable = true
	velocity.y = 0.0
	_enter_state(State.DASH)
	# kedua clip dash berupa pose 1 frame: pose ditahan, gerak dibuat lewat kode
	_play("air_dash" if air else "dash", 1.0, 0.06, true)
	_shake = maxf(_shake, 0.15)


func _state_dash(_delta: float) -> void:
	var dur := _dash_duration()
	var f := clampf(state_t / dur, 0.0, 1.0)
	var top := air_dash_speed if _dash_is_air else dash_speed
	var sp := top * (1.0 - 0.6 * f * f)  # melambat di ujung dash
	velocity.x = _dash_dir.x * sp
	velocity.z = _dash_dir.z * sp
	velocity.y = 0.0
	invulnerable = state_t < dur * dash_iframe_frac
	if state_t >= dur:
		invulnerable = false
		velocity.x = _dash_dir.x * walk_speed
		velocity.z = _dash_dir.z * walk_speed
		_enter_state(State.FREE)


# ---------------------------------------------------------------- ATTACK

func _start_attack(idx: int) -> void:
	combo_idx = idx
	var c: Dictionary = COMBO[idx]
	_enter_state(State.ATTACK)
	_hit_done = false
	_attack_buffered = false
	_auto_face()
	_play(c["anim"], c["speed"], 0.08, true)


func _attack_duration(c: Dictionary) -> float:
	return float(_anim_len.get(c["anim"], 0.8)) / float(c["speed"])


func _state_attack(delta: float, dir: Vector3, atk: bool, jmp: bool, dsh: bool, skl: bool) -> void:
	var c: Dictionary = COMBO[combo_idx]
	var frac := state_t / _attack_duration(c)
	if atk:
		_attack_buffered = true

	_apply_root_motion(delta, c["anim"], c["speed"], facing)

	if not _hit_done and frac >= c["hit"]:
		_hit_done = true
		_do_hit(c)

	if frac >= c["cancel"]:
		if dsh and dash_cd <= 0.0:
			_start_dash(dir, false)
			return
		if skl and skill_cd <= 0.0:
			_start_skill()
			return
		if jmp:
			_enter_state(State.FREE)
			combo_idx = 0
			_do_jump()
			return
		if _attack_buffered:
			_start_attack((combo_idx + 1) % COMBO.size())
			return

	if frac >= c["end"]:
		_enter_state(State.FREE)
		combo_idx = 0


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _auto_face() -> void:
	var dir := _input_dir()
	if dir.length() > 0.1:
		facing = dir.normalized()
		return
	var best_d := auto_aim_range
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		var to := _flat(e.global_position - global_position)
		var d := to.length()
		if d < best_d and d > 0.01:
			best_d = d
			facing = to / d


func _do_hit(c: Dictionary) -> void:
	var landed := false
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		var to := _flat(e.global_position - global_position)
		var d := to.length()
		if d > float(c["range"]):
			continue
		if d > 0.4 and facing.dot(to / d) < cos(deg_to_rad(70.0)):
			continue
		e.take_damage(c["damage"], global_position, c["knockback"])
		landed = true
	if landed:
		_shake = maxf(_shake, 0.35)
		hit_landed.emit()


# ---------------------------------------------------------------- BLOCK

func _start_block() -> void:
	_enter_state(State.BLOCK)
	_auto_face()
	_play("block", block_anim_speed, 0.08, true)  # clip non-loop: pose guard ditahan di frame terakhir


func _state_block(delta: float, dir: Vector3, dsh: bool) -> void:
	_decel(delta, 30.0)
	if dsh and dash_cd <= 0.0:
		_start_dash(dir, false)
		return
	if not Input.is_action_pressed("block") and state_t > 0.15:
		_enter_state(State.FREE)


# ---------------------------------------------------------------- SKILL (AoE, animasi attack3)

func _skill_duration() -> float:
	return float(_anim_len.get(SKILL_CLIP, 1.2)) / skill_anim_speed


func _start_skill() -> void:
	skill_cd = skill_cooldown
	_skill_burst_done = false
	_enter_state(State.SKILL)
	_play(SKILL_CLIP, skill_anim_speed, 0.1, true)
	_set_charge(true)


func _set_charge(on: bool) -> void:
	if _aura:
		_aura.emitting = on
	if _charge_light:
		_charge_light.visible = on
		_charge_light.light_energy = 0.0


func _state_skill(delta: float, dir: Vector3, dsh: bool) -> void:
	_decel(delta, 40.0)
	var frac := state_t / _skill_duration()
	if _charge_light and not _skill_burst_done:
		_charge_light.light_energy = clampf(frac / SKILL_HIT_FRAC, 0.0, 1.0) * 3.0  # aura makin terang

	if not _skill_burst_done and frac >= SKILL_HIT_FRAC:
		_skill_burst_done = true
		_set_charge(false)
		_skill_burst()

	if _skill_burst_done and dsh and dash_cd <= 0.0 and frac >= SKILL_HIT_FRAC + 0.05:
		_start_dash(dir, false)
		return
	if frac >= 0.97:
		_set_charge(false)
		_enter_state(State.FREE)


func _skill_burst() -> void:
	var sw_scene := load(SHOCKWAVE_PATH) as PackedScene
	if sw_scene:
		var sw := sw_scene.instantiate()
		sw.set("radius", skill_radius)
		get_parent().add_child(sw)
		(sw as Node3D).global_position = global_position + Vector3(0.0, 0.05, 0.0)

	var landed := false
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		var to := _flat(e.global_position - global_position)
		if to.length() <= skill_radius:
			e.take_damage(skill_damage, global_position, skill_knockback)
			landed = true
	_shake = 1.0
	if landed:
		hit_landed.emit()


# ---------------------------------------------------------------- damage / death

func take_damage(amount: int, from: Vector3, knock := 6.0) -> void:
	if state == State.DEAD or invulnerable:
		return
	var to := _flat(from - global_position)
	var blocked := false
	if state == State.BLOCK and to.length() > 0.01 and facing.dot(to.normalized()) > 0.2:
		blocked = true
	if blocked:
		amount = maxi(1, int(amount * 0.15))
		knock *= 0.3
	elif state == State.SKILL:
		amount = maxi(1, int(amount * skill_guard))
		knock *= 0.3
		_set_overlay(_hit_overlay)
		_flash_t = 0.12
	else:
		_set_overlay(_hit_overlay)
		_flash_t = 0.12
	if to.length() > 0.01:
		var push := -to.normalized() * knock
		velocity.x += push.x
		velocity.z += push.z
	hp = maxi(0, hp - amount)
	_shake = maxf(_shake, 0.5)
	hp_changed.emit(hp, max_hp)
	if hp <= 0:
		_die()


func _die() -> void:
	_set_charge(false)
	_enter_state(State.DEAD)
	invulnerable = false
	_play("idle")
	var tw := create_tween()
	tw.tween_property(_pivot, "rotation:x", -PI / 2.0, 0.4)
	tw.tween_interval(1.5)
	tw.tween_callback(_respawn)


func _respawn() -> void:
	_pivot.rotation.x = 0.0
	hp = max_hp
	global_position = _respawn_pos
	velocity = Vector3.ZERO
	_enter_state(State.FREE)
	hp_changed.emit(hp, max_hp)
