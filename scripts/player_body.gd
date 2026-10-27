extends Node3D
## The survivor's body, built from low-poly primitives and shown ONLY during the
## third-person death cinematic. Faces -Z like the demon. ~1.72 m standing.
## set_death(t): collapses from standing (0) to bowed on its knees (1).

var skin: StandardMaterial3D
var cloth: StandardMaterial3D
var hair: StandardMaterial3D

var hips: Node3D
var spine: Node3D
var neck: Node3D
var head: Node3D
var arms: Array[Node3D] = []     # shoulder pivots
var thighs: Array[Node3D] = []   # hip pivots
var knees: Array[Node3D] = []    # knee pivots

var _death := 0.0
var _time := 0.0


func _ready() -> void:
	_make_mats()
	_build()


func _make_mats() -> void:
	skin = StandardMaterial3D.new()
	skin.albedo_color = Color("c99c78")
	skin.roughness = 0.85
	cloth = StandardMaterial3D.new()
	cloth.albedo_color = Color("343a46")   # dark shirt / trousers
	cloth.roughness = 0.95
	hair = StandardMaterial3D.new()
	hair.albedo_color = Color("130f0d")
	hair.roughness = 1.0


func _cap(parent: Node3D, mat: StandardMaterial3D, r: float, h: float, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = max(h, r * 2.0)
	m.radial_segments = 8
	m.rings = 3
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


func _pivot(parent: Node3D, pos: Vector3, rot := Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation = rot
	parent.add_child(n)
	return n


func _build() -> void:
	hips = _pivot(self, Vector3(0, 0.95, 0))
	_cap(hips, cloth, 0.13, 0.26, Vector3.ZERO, Vector3(0, 0, PI / 2))

	spine = _pivot(hips, Vector3(0, 0.1, 0))
	_cap(spine, cloth, 0.15, 0.46, Vector3(0, 0.24, 0), Vector3.ZERO, Vector3(1.05, 1.0, 0.72))   # torso
	var chest := _pivot(spine, Vector3(0, 0.5, 0))
	_cap(chest, cloth, 0.06, 0.4, Vector3.ZERO, Vector3(0, 0, PI / 2))   # shoulder bar

	neck = _pivot(chest, Vector3(0, 0.05, 0))
	_cap(neck, skin, 0.045, 0.1, Vector3(0, 0.06, 0))
	head = _pivot(neck, Vector3(0, 0.14, 0))
	_cap(head, skin, 0.11, 0.24, Vector3(0, 0.08, 0), Vector3.ZERO, Vector3(0.95, 1.0, 1.0))
	var cap := MeshInstance3D.new()                              # hair cap
	var hm := SphereMesh.new()
	hm.radius = 0.115
	hm.height = 0.16
	cap.mesh = hm
	cap.material_override = hair
	cap.position = Vector3(0, 0.14, 0.01)
	head.add_child(cap)

	# arms
	for sx in [-1.0, 1.0]:
		var sh := _pivot(chest, Vector3(sx * 0.21, 0.0, 0), Vector3(deg_to_rad(6), 0, deg_to_rad(sx * 6)))
		_cap(sh, cloth, 0.05, 0.3, Vector3(0, -0.15, 0))
		var el := _pivot(sh, Vector3(0, -0.3, 0), Vector3(deg_to_rad(12), 0, 0))
		_cap(el, skin, 0.045, 0.28, Vector3(0, -0.14, 0))
		var hand := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.05
		sm.height = 0.1
		hand.mesh = sm
		hand.material_override = skin
		hand.position = Vector3(0, -0.3, 0)
		el.add_child(hand)
		arms.append(sh)

	# legs
	for sx in [-1.0, 1.0]:
		var th := _pivot(hips, Vector3(sx * 0.1, -0.02, 0))
		_cap(th, cloth, 0.08, 0.42, Vector3(0, -0.21, 0))
		var kn := _pivot(th, Vector3(0, -0.42, 0))
		_cap(kn, cloth, 0.06, 0.4, Vector3(0, -0.2, 0))
		var foot := _cap(kn, cloth, 0.06, 0.2, Vector3(0, -0.4, -0.06), Vector3(PI / 2, 0, 0))
		foot.scale = Vector3(1.0, 1.0, 0.7)
		thighs.append(th)
		knees.append(kn)


## 0 = standing, 1 = bowed down on the knees, head hanging (death collapse).
func set_death(v: float) -> void:
	_death = clampf(v, 0.0, 1.0)


func _process(delta: float) -> void:
	_time += delta
	var t := _death
	# a faint, failing tremble that fades as the body goes limp
	var tremble: float = sin(_time * 22.0) * 0.006 * (1.0 - t)

	hips.position.y = lerpf(0.95, 0.42, t)
	hips.rotation.x = lerpf(0.0, deg_to_rad(-6), t)
	spine.rotation.x = lerpf(tremble, deg_to_rad(-54), t)       # bow forward
	neck.rotation.x = lerpf(0.0, deg_to_rad(-20), t)
	head.rotation.x = lerpf(tremble * 2.0, deg_to_rad(-46), t)  # head hangs

	for i in 2:
		arms[i].rotation.x = lerpf(deg_to_rad(6), deg_to_rad(42), t)   # arms slump forward
		arms[i].rotation.z = lerpf(deg_to_rad((-1.0 if i == 0 else 1.0) * 6.0), 0.0, t)
		thighs[i].rotation.x = lerpf(0.0, deg_to_rad(86), t)           # drop to knees
		knees[i].rotation.x = lerpf(0.0, deg_to_rad(-104), t)          # shins fold under
