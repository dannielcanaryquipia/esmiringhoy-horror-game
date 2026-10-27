extends Node3D
## The Esmiringhoy's body, assembled from low-poly primitives to match board 03:
## 2.4 m, stooped, long twisting neck, swept-back horns, arms to the ankles,
## backward-bent legs, ember cracks. Faces -Z. Also drives its procedural animation.

const SKIN_SHADER := preload("res://assets/shaders/sh_demon_body.gdshader")

@export var height_scale := 1.0
@export var eye_color := Color("ff2a33")

var skin: ShaderMaterial
var eye_mat: StandardMaterial3D

var hips: Node3D
var spine: Node3D
var chest: Node3D
var neck: Node3D
var head: Node3D
var jaw: Node3D
var arms: Array[Node3D] = []      # shoulder pivots
var elbows: Array[Node3D] = []
var hands: Array[Node3D] = []
var thighs: Array[Node3D] = []
var knees: Array[Node3D] = []

var _phase := 0.0
var _time := 0.0
var _catch_pose := 0.0  # 0..1 blend into the grab / roar pose
var _eat := 0.0         # 0..1 blend into the hunched "devouring from behind" pose
var _search := 0.0      # 0..1 searching hunch + slow head craning
var _give_up := 0.0     # 0..1 brief weary slump + head-shake when it loses the trail


func _ready() -> void:
	skin = ShaderMaterial.new()
	skin.shader = SKIN_SHADER
	skin.set_shader_parameter("skin_tex", load("res://assets/textures/tex_demon_skin_albedo.png"))
	skin.set_shader_parameter("crack_mask", load("res://assets/textures/tex_demon_cracks_mask.png"))
	eye_mat = StandardMaterial3D.new()
	eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye_mat.albedo_color = eye_color
	eye_mat.emission_enabled = true
	eye_mat.emission = eye_color
	eye_mat.emission_energy_multiplier = 0.0
	_build()
	scale = Vector3.ONE * height_scale


# ------------------------------------------------------------ mesh helpers
func _capsule(parent: Node3D, r: float, h: float, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = max(h, r * 2.0)
	m.radial_segments = 10
	m.rings = 4
	mi.mesh = m
	mi.material_override = skin
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


func _cone(parent: Node3D, r: float, h: float, pos: Vector3, rot: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = 0.002
	m.bottom_radius = r
	m.height = h
	m.radial_segments = 6
	m.rings = 1
	mi.mesh = m
	mi.material_override = skin
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _pivot(parent: Node3D, pos: Vector3, rot := Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation = rot
	parent.add_child(n)
	return n


# ------------------------------------------------------------ build
func _build() -> void:
	hips = _pivot(self, Vector3(0, 1.12, 0))
	_capsule(hips, 0.09, 0.3, Vector3.ZERO, Vector3(0, 0, PI / 2))

	# --- torso, leaning forward
	spine = _pivot(hips, Vector3(0, 0.04, 0), Vector3(deg_to_rad(-22), 0, 0))
	_capsule(spine, 0.11, 0.42, Vector3(0, 0.2, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.8))  # waist
	_capsule(spine, 0.17, 0.5, Vector3(0, 0.55, 0), Vector3.ZERO, Vector3(1.25, 1.0, 0.75))  # ribcage
	chest = _pivot(spine, Vector3(0, 0.8, 0))
	_capsule(chest, 0.08, 0.66, Vector3.ZERO, Vector3(0, 0, PI / 2))  # shoulder bar

	# --- long twisting neck and skull
	neck = _pivot(chest, Vector3(0, 0.04, -0.02), Vector3(deg_to_rad(-28), 0, deg_to_rad(4)))
	_capsule(neck, 0.05, 0.36, Vector3(0, 0.17, 0))
	head = _pivot(neck, Vector3(0, 0.36, 0), Vector3(deg_to_rad(40), 0, 0))
	_capsule(head, 0.12, 0.34, Vector3(0, 0.08, 0), Vector3.ZERO, Vector3(0.95, 1.0, 1.1))  # skull
	jaw = _pivot(head, Vector3(0, -0.04, -0.04))
	_capsule(jaw, 0.06, 0.2, Vector3(0, -0.04, -0.06), Vector3(deg_to_rad(70), 0, 0), Vector3(1.3, 1.0, 0.7))
	for sx in [-1.0, 1.0]:
		# hollow sockets (dark spheres) with a small burning eye inside
		var socket := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.035
		sm.height = 0.06
		socket.mesh = sm
		var black := StandardMaterial3D.new()
		black.albedo_color = Color(0.01, 0.005, 0.005)
		socket.material_override = black
		socket.position = Vector3(sx * 0.05, 0.11, -0.115)
		head.add_child(socket)
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.02
		em.height = 0.04
		eye.mesh = em
		eye.material_override = eye_mat
		eye.position = Vector3(sx * 0.05, 0.11, -0.14)
		head.add_child(eye)
		# horns sweeping back and up, in two segments
		var horn := _pivot(head, Vector3(sx * 0.07, 0.2, 0.02), Vector3(deg_to_rad(55), 0, deg_to_rad(-sx * 18)))
		_cone(horn, 0.035, 0.26, Vector3(0, 0.13, 0), Vector3.ZERO)
		var tip := _pivot(horn, Vector3(0, 0.22, 0), Vector3(deg_to_rad(-45), 0, 0))
		_cone(tip, 0.018, 0.22, Vector3(0, 0.1, 0), Vector3.ZERO)

	# --- arms that reach the ankles, claws dragging
	for sx in [-1.0, 1.0]:
		var sh := _pivot(chest, Vector3(sx * 0.33, 0, 0), Vector3(deg_to_rad(18), 0, deg_to_rad(sx * 8)))
		_capsule(sh, 0.05, 0.62, Vector3(0, -0.31, 0))
		var el := _pivot(sh, Vector3(0, -0.62, 0), Vector3(deg_to_rad(10), 0, 0))
		_capsule(el, 0.042, 0.66, Vector3(0, -0.33, 0))
		var hd := _pivot(el, Vector3(0, -0.66, 0))
		_capsule(hd, 0.045, 0.14, Vector3(0, -0.05, 0), Vector3.ZERO, Vector3(1.2, 1.0, 0.6))
		for i in 4:
			var cx := (i - 1.5) * 0.026
			var claw := _pivot(hd, Vector3(cx, -0.1, -0.01), Vector3(deg_to_rad(-12 - i * 2), 0, deg_to_rad(cx * 60)))
			_cone(claw, 0.012, 0.35, Vector3(0, -0.17, 0), Vector3(PI, 0, 0))
		arms.append(sh)
		elbows.append(el)
		hands.append(hd)

	# --- backward-bent (digitigrade) legs
	for sx in [-1.0, 1.0]:
		var th := _pivot(hips, Vector3(sx * 0.13, 0, 0), Vector3(deg_to_rad(-28), 0, 0))
		_capsule(th, 0.07, 0.52, Vector3(0, -0.26, 0))
		var kn := _pivot(th, Vector3(0, -0.5, 0), Vector3(deg_to_rad(62), 0, 0))
		_capsule(kn, 0.05, 0.48, Vector3(0, -0.24, 0))
		var an := _pivot(kn, Vector3(0, -0.47, 0), Vector3(deg_to_rad(-48), 0, 0))
		_capsule(an, 0.04, 0.3, Vector3(0, -0.15, 0))
		var ft := _pivot(an, Vector3(0, -0.3, 0), Vector3(deg_to_rad(14), 0, 0))
		_capsule(ft, 0.04, 0.22, Vector3(0, 0, -0.08), Vector3(PI / 2, 0, 0))
		thighs.append(th)
		knees.append(kn)


# ------------------------------------------------------------ look controls
func set_hunting(on: bool) -> void:
	skin.set_shader_parameter("pulse_hz", 2.0 if on else 0.6)
	var t := create_tween()
	t.tween_property(eye_mat, "emission_energy_multiplier", 6.0 if on else 0.0, 0.4)


func set_flare(v: float) -> void:
	skin.set_shader_parameter("flare", v)


func set_dissolve(v: float) -> void:
	skin.set_shader_parameter("dissolve", v)


func set_catch_pose(v: float) -> void:
	_catch_pose = v


## Blend into the devouring pose: hunched low over the victim's back, jaw working.
func set_eat(v: float) -> void:
	_eat = clampf(v, 0.0, 1.0)


## Blend into the searching stance: craned forward, head sweeping slowly.
func set_search(v: float) -> void:
	_search = clampf(v, 0.0, 1.0)


func set_give_up(v: float) -> void:
	_give_up = clampf(v, 0.0, 1.0)


## A short one-shot "lost the trail" beat: a weary head-shake and shoulder drop.
func play_give_up() -> void:
	var t := create_tween()
	t.tween_method(set_give_up, 0.0, 1.0, 0.3)
	t.tween_interval(0.35)
	t.tween_method(set_give_up, 1.0, 0.0, 0.3)


## speed: current ground speed. mode: "lurk", "hunt", "frozen", "stutter", "catch"
func animate(delta: float, speed: float, mode: String) -> void:
	if mode == "frozen":
		# perfectly still, with a tiny tremble
		hips.position.x = randf_range(-0.004, 0.004)
		return
	_time += delta
	var stride := clampf(speed / 4.6, 0.0, 1.0)
	_phase += delta * (2.0 + speed * 1.6)
	var ph := _phase
	if mode == "stutter":
		ph = floor(_phase * 4.0) / 4.0  # skipped frames
	var swing := sin(ph * 2.0)
	var breathe := sin(_time * 1.6)

	hips.position.y = 1.12 - abs(sin(ph * 2.0)) * 0.05 * stride
	hips.position.x = 0.0
	spine.rotation.x = deg_to_rad(-22 - 10 * stride) + breathe * 0.02
	chest.scale = Vector3(1.0, 1.0 + breathe * 0.025, 1.0)
	neck.rotation.z = deg_to_rad(4) + sin(_time * 0.7) * 0.12 * (1.0 - stride)  # slow, wrong twisting
	for i in 2:
		var s := 1.0 if i == 0 else -1.0
		thighs[i].rotation.x = deg_to_rad(-28) + swing * s * 0.5 * stride
		knees[i].rotation.x = deg_to_rad(62) + max(0.0, -swing * s) * 0.5 * stride
		var arm_rest := deg_to_rad(18) - swing * s * 0.25 * stride
		var arm_grab := deg_to_rad(-75)
		arms[i].rotation.x = lerpf(arm_rest, arm_grab, _catch_pose)
		elbows[i].rotation.x = lerpf(deg_to_rad(10) + breathe * 0.05, deg_to_rad(-25), _catch_pose)
	jaw.rotation.x = lerpf(0.0, deg_to_rad(55), _catch_pose)
	head.rotation.x = lerpf(deg_to_rad(40), deg_to_rad(5), _catch_pose)

	# devouring the victim from behind: crane down over the back, gnashing jaw
	if _eat > 0.0:
		var chomp: float = absf(sin(_time * 9.0))
		hips.position.y -= 0.42 * _eat
		spine.rotation.x += deg_to_rad(-34) * _eat
		neck.rotation.x = deg_to_rad(44) * _eat
		head.rotation.x = lerpf(head.rotation.x, deg_to_rad(58), _eat)
		jaw.rotation.x = lerpf(jaw.rotation.x, deg_to_rad(22) + chomp * deg_to_rad(42), _eat)
		for i in 2:
			arms[i].rotation.x = lerpf(arms[i].rotation.x, deg_to_rad(-88), _eat)   # clutch the body

	# searching: crane forward and sweep the head slowly, scanning the room
	if _search > 0.0:
		spine.rotation.x += deg_to_rad(-12) * _search
		neck.rotation.x = lerpf(deg_to_rad(-28), deg_to_rad(12), _search)
		head.rotation.x = lerpf(head.rotation.x, deg_to_rad(16), _search)
		neck.rotation.z += sin(_time * 1.1) * 0.18 * _search

	# give-up: a weary head-shake and a shoulder drop as it loses interest
	if _give_up > 0.0:
		neck.rotation.y = sin(_time * 20.0) * 0.14 * _give_up
		spine.rotation.x += deg_to_rad(10) * _give_up
		chest.scale.y *= 1.0 - 0.05 * _give_up
