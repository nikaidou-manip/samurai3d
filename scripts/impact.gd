extends Node3D
## VFX impact pukulan tangan kosong: hembusan angin vertikal di titik kena.
## Garis-garis angin tipis (quad vertikal + shader additive) disusun melingkari
## titik pukulan, lalu pita cahayanya menyapu dari bawah ke atas lewat uniform
## `progress` -- seperti udara yang terdorong keluar sekejap saat tinju mendarat.
## Dibuat oleh player tepat di momen hit; parameter di-set sebelum masuk scene
## (pola yang sama dengan scenes/shockwave.tscn). Animasi digerakkan manual di
## _process (bukan tween) supaya tidak bergantung pada properti shader yang
## ter-parse oleh renderer.

@export var streaks := 7                ## jumlah garis angin di sekeliling titik kena
@export var burst_radius := 0.26        ## sebaran garis dari pusat (meter)
@export var streak_height := 0.8        ## tinggi garis angin (meter)
@export var streak_width := 0.05        ## lebar garis angin (meter)
@export var duration := 0.26            ## lama semburan (detik)
@export var band := 0.62                ## panjang sapuan yang menyala (fraksi tinggi)
@export var tilt_deg := 13.0            ## kemiringan garis ke luar (angin menyebar)
@export var color := Color(0.85, 0.95, 1.0, 0.85)  ## putih pucat kebiruan (angin)
@export var scale_all := 1.0            ## pengali ukuran (pukulan berat lebih besar)
@export var yaw_deg := 0.0              ## arah hadap (diisi dari player.facing)

const CORE_STREAKS := 2                 ## garis pusat: lebih tinggi & lebih terang
const FADE_START := 0.45                ## fraksi durasi saat mulai memudar
const LIFE_MARGIN := 0.2                ## detik ekstra sebelum node dibebaskan

const GUST_SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;

uniform vec4 tint : source_color = vec4(0.85, 0.95, 1.0, 0.9);
uniform float progress : hint_range(0.0, 2.0) = 0.0;
uniform float band : hint_range(0.1, 1.0) = 0.62;
uniform float fade = 1.0;

void fragment() {
	float along = UV.y;                  // 0 = bawah, 1 = ujung atas
	float head = progress;
	float tail = progress - band;
	float sweep = smoothstep(0.0, 0.18, head - along) * smoothstep(0.0, band * 0.55, along - tail);
	float across = UV.x;
	float soft = smoothstep(0.0, 0.4, across) * (1.0 - smoothstep(0.6, 1.0, across));
	float a = sweep * soft * fade;
	ALBEDO = tint.rgb;
	EMISSION = tint.rgb * a;
	ALPHA = tint.a * a;
}
"""

var _shader: Shader
var _lines: Array[Dictionary] = []  ## [{mat, dur, delay}]
var _t := 0.0
var _life := 0.0


func _ready() -> void:
	_shader = Shader.new()
	_shader.code = GUST_SHADER
	rotation.y = deg_to_rad(yaw_deg)

	var s := scale_all
	# garis pusat: napas angin utama tepat di titik kena
	for i in CORE_STREAKS:
		_spawn_line(color * Color(1.0, 1.0, 1.0, 0.95),
			burst_radius * s * randf_range(0.05, 0.12),
			streak_height * s * randf_range(1.15, 1.3),
			streak_width * s * randf_range(1.1, 1.4),
			randf_range(-6.0, 6.0), 0.0)
	# garis sekeliling: angin menyebar keluar dari titik kena
	for i in streaks:
		var ang := TAU * float(i) / float(streaks) + randf_range(-0.25, 0.25)
		var dim := color * Color(1.0, 1.0, 1.0, randf_range(0.3, 0.55))
		_spawn_line(dim,
			burst_radius * s * randf_range(0.85, 1.15),
			streak_height * s * randf_range(0.8, 1.05),
			streak_width * s * randf_range(0.7, 1.1),
			tilt_deg * randf_range(0.7, 1.3), ang)

	_life = duration + LIFE_MARGIN
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	for l in _lines:
		var local_t: float = _t - float(l["delay"])
		if local_t <= 0.0:
			continue
		var f := clampf(local_t / float(l["dur"]), 0.0, 1.0)
		# ease-out: semburan kencang di awal lalu melembut (angin terlepas)
		var eased := 1.0 - pow(1.0 - f, 2.4)
		var mat: ShaderMaterial = l["mat"]
		mat.set_shader_parameter("progress", (1.0 + band) * eased)
		var fade := 1.0 if f < FADE_START else clampf(1.0 - (f - FADE_START) / (1.0 - FADE_START), 0.0, 1.0)
		mat.set_shader_parameter("fade", fade)
	if _t >= _life:
		queue_free()


## Satu garis angin: quad vertikal + material yang sapuannya dianimasikan di _process.
## Garis diposisikan di ring sejauh `ring_r`, menghadap keluar, lalu dimiringkan
## keluar sebesar `tilt_d` derajat supaya terlihat seperti angin yang menyebar.
func _spawn_line(col: Color, ring_r: float, h: float, w: float, tilt_d: float, ang: float) -> void:
	var mi := MeshInstance3D.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(sin(ang), 0.0, cos(ang)) * ring_r
	mi.rotation = Vector3(deg_to_rad(tilt_d), ang, 0.0)
	mi.mesh = _line_mesh(h, w)

	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("tint", col)
	mat.set_shader_parameter("band", band)
	mat.set_shader_parameter("progress", 0.0)
	mat.set_shader_parameter("fade", 1.0)
	mi.material_override = mat
	add_child(mi)

	var delay := randf_range(0.0, 0.05)
	var dur := duration * randf_range(0.85, 1.05)
	_lines.append({"mat": mat, "dur": dur, "delay": delay})
	_life = maxf(_life, delay + dur + LIFE_MARGIN)


## Quad vertikal (bidang XY) setinggi h selebar w, terpusat di titik kena.
## UV.y = 0 di bawah -> 1 di atas (arah sapuan angin).
func _line_mesh(h: float, w: float) -> ArrayMesh:
	var verts := PackedVector3Array([
		Vector3(-w * 0.5, -h * 0.5, 0.0),
		Vector3(w * 0.5, -h * 0.5, 0.0),
		Vector3(-w * 0.5, h * 0.5, 0.0),
		Vector3(w * 0.5, h * 0.5, 0.0),
	])
	var uvs := PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(1.0, 0.0),
		Vector2(0.0, 1.0),
		Vector2(1.0, 1.0),
	])
	var idx := PackedInt32Array([0, 1, 2, 2, 1, 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
