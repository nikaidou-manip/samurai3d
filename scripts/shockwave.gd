extends Node3D
## Efek ledakan AoE: ring energi yang melebar, cakram cahaya, partikel, dan kilat lampu.
## Dibuat oleh player saat skill meledak; `radius` di-set sebelum ditambahkan ke scene.

@export var radius := 6.0
@export var duration := 0.55

@onready var _wall: MeshInstance3D = $Wall
@onready var _disc: MeshInstance3D = $Disc
@onready var _particles: GPUParticles3D = $Particles
@onready var _flash: OmniLight3D = $Flash


func _ready() -> void:
	var wall_mat := (_wall.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
	var disc_mat := (_disc.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
	_wall.material_override = wall_mat
	_disc.material_override = disc_mat
	_wall.scale = Vector3(0.3, 1.0, 0.3)
	_disc.scale = Vector3(0.3, 1.0, 0.3)

	var pm := (_particles.process_material as ParticleProcessMaterial).duplicate() as ParticleProcessMaterial
	pm.emission_ring_radius = radius * 0.5
	pm.emission_ring_inner_radius = radius * 0.2
	_particles.process_material = pm
	_particles.restart()
	_particles.emitting = true

	_flash.omni_range = radius * 1.5
	_flash.light_energy = 6.0

	var tw := create_tween().set_parallel(true)
	tw.tween_property(_wall, "scale", Vector3(radius, 1.0, radius), duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_disc, "scale", Vector3(radius, 1.0, radius), duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(wall_mat, "albedo_color:a", 0.0, duration * 1.2)
	tw.tween_property(disc_mat, "albedo_color:a", 0.0, duration)
	tw.tween_property(_flash, "light_energy", 0.0, 0.4)

	get_tree().create_timer(1.6).timeout.connect(queue_free)
