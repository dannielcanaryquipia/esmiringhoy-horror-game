extends Area3D
## A stationary lure the player can set off with E: a sala radio, the CR's
## clanking pipes, or a bedroom music box. While running, it makes a racket
## every ~1.6 s and reports it to the demon through hear_noise — the same path
## footsteps and thrown rocks use — so the demon walks TO it, away from you.
## It winds down after a while, then needs a cool-down before it can be
## started again. Layer 5 (value 16) so the crosshair ray finds it.

signal started(lure)
signal stopped(lure)

@export var label := "radio"
@export var kind := "radio"   # "radio" | "pipes" | "musicbox"

var demon                     # set by main.gd, so its clatter is heard
var active := false
var cool_left := 0.0

const RUN_TIME := 12.0
const NOISE_EVERY := 1.6
const NOISE_RADIUS := 11.0    # carries across most of a floor
const COOL_TIME := 45.0

var _run_left := 0.0
var _noise_left := 0.0
var _clatter: AudioStreamPlayer3D
var _hum: AudioStreamPlayer3D         # the steady hum while active
var _crank: MeshInstance3D            # the music-box crank spins while active


func _ready() -> void:
	collision_layer = 16   # layer 5: interactables
	collision_mask = 0
	monitoring = false
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.6, 0.6, 0.6)
	cs.shape = sh
	cs.position.y = 0.2
	add_child(cs)
	set_meta("lure", self)
	_clatter = AudioStreamPlayer3D.new()
	_clatter.stream = load("res://assets/audio/sfx_creak_floor.ogg")
	_clatter.volume_db = -4.0
	_clatter.unit_size = 5.0
	add_child(_clatter)
	_hum = AudioStreamPlayer3D.new()
	var hb: AudioStreamOggVorbis = load("res://assets/audio/sfx_bulb_buzz.ogg").duplicate()
	hb.loop = true
	_hum.stream = hb
	_hum.volume_db = -16.0
	_hum.unit_size = 3.5
	add_child(_hum)
	_build_visual()


# ---------------------------------------------------------------- controls
## Flip. Co-op syncs via rpc (deterministic node names set in main.gd).
func toggle() -> bool:
	if Net.active:
		_net_toggle.rpc()
		return true
	return _run()


@rpc("any_peer", "call_local", "reliable")
func _net_toggle() -> void:
	_run()


func _run() -> bool:
	if active or cool_left > 0.0:
		return false
	active = true
	_run_left = RUN_TIME
	_noise_left = 0.0
	_hum.play()
	started.emit(self)
	return true


func _process(delta: float) -> void:
	cool_left = maxf(cool_left - delta, 0.0)
	if _crank != null:
		_crank.rotation.x += delta * (7.0 if active else 0.0)
	if not active:
		return
	_run_left -= delta
	if _run_left <= 0.0:
		_stop()
		return
	_noise_left -= delta
	if _noise_left <= 0.0:
		_noise_left = NOISE_EVERY
		_clatter.pitch_scale = randf_range(0.8, 1.3)
		_clatter.play()
		if demon != null and demon.has_method("hear_noise"):
			demon.hear_noise(global_position, NOISE_RADIUS)


func _stop() -> void:
	active = false
	cool_left = COOL_TIME
	_hum.stop()
	stopped.emit(self)


# ---------------------------------------------------------------- visuals
func _build_visual() -> void:
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.1, 0.1, 0.11)
	iron.metallic = 0.6
	iron.roughness = 0.5
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.35, 0.27, 0.12)
	brass.metallic = 0.8
	brass.roughness = 0.4
	if kind == "pipes":
		# a wall valve: a pipe stub, a wheel — twist it, the plumbing bangs
		var pipe := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.05
		pm.bottom_radius = 0.05
		pm.height = 0.45
		pipe.mesh = pm
		pipe.material_override = iron
		pipe.position.y = 0.5
		add_child(pipe)
		_crank = MeshInstance3D.new()
		var wm := TorusMesh.new()
		wm.inner_radius = 0.06
		wm.outer_radius = 0.1
		_crank.mesh = wm
		_crank.material_override = brass
		_crank.position.y = 0.28
		_crank.rotation.y = PI / 2
		add_child(_crank)
	elif kind == "musicbox":
		# a small wooden box with a spinning crank on the side
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.22, 0.14, 0.18)
		box.mesh = bm
		var wd := StandardMaterial3D.new()
		wd.albedo_color = Color(0.3, 0.19, 0.1)
		wd.roughness = 0.6
		box.material_override = wd
		box.position.y = 0.09
		add_child(box)
		_crank = MeshInstance3D.new()
		var km := CylinderMesh.new()
		km.top_radius = 0.015
		km.bottom_radius = 0.015
		km.height = 0.12
		_crank.mesh = km
		_crank.material_override = brass
		_crank.rotation.z = PI / 2
		_crank.position = Vector3(0.13, 0.09, 0.0)
		add_child(_crank)
	else:
		# an old battery radio: case, speaker grille slats, two knobs
		var case := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(0.3, 0.2, 0.14)
		case.mesh = cm
		var shell := StandardMaterial3D.new()
		shell.albedo_color = Color(0.16, 0.13, 0.11)
		shell.roughness = 0.5
		case.material_override = shell
		case.position.y = 0.12
		add_child(case)
		for i in 4:
			var slat := MeshInstance3D.new()
			var sm := BoxMesh.new()
			sm.size = Vector3(0.18, 0.012, 0.012)
			slat.mesh = sm
			slat.material_override = brass
			slat.position = Vector3(-0.05, 0.055 + 0.028 * i, 0.075)
			add_child(slat)
		for gx in [0.09, 0.12]:
			var knob := MeshInstance3D.new()
			var nm2 := CylinderMesh.new()
			nm2.top_radius = 0.014
			nm2.bottom_radius = 0.014
			nm2.height = 0.02
			knob.mesh = nm2
			knob.material_override = brass
			knob.rotation.x = PI / 2
			knob.position = Vector3(gx, 0.15, 0.072)
			add_child(knob)
