extends Area3D
## A quest item lying in the dark (matches, a key). Walk into it to pick it up.
## Layer 0 / mask 4 (players): never blocks movement, only senses the player.
## main.gd listens to `collected(kind)` and updates objectives.

signal collected(kind)

@export var kind := "matches"   # "matches", "key" or "salt"

var _taken := false
var _audio: AudioStreamPlayer3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 4   # layer 3: players
	monitoring = true
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 0.6
	cs.shape = sp
	cs.position.y = 0.2
	add_child(cs)
	_build_visual()
	_audio = AudioStreamPlayer3D.new()
	_audio.stream = load("res://assets/audio/sfx_flash_click.ogg")
	_audio.volume_db = -3.0
	add_child(_audio)
	body_entered.connect(_on_body_entered)


func _build_visual() -> void:
	var tint := Color(1.0, 0.62, 0.3)
	if kind == "key":
		tint = Color(0.95, 0.85, 0.4)
	elif kind == "salt":
		tint = Color(0.82, 0.9, 1.0)   # a blessed, faintly blue-white shimmer
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint * 0.6
	mat.metallic = 0.85 if kind == "key" else 0.3
	mat.roughness = 0.5
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = 0.7
	if kind == "matches":
		# a small matchbox
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.1, 0.04, 0.16)
		box.mesh = bm
		box.material_override = mat
		box.position.y = 0.12
		add_child(box)
	elif kind == "key":
		# a key: a shaft with a bow ring on top
		var shaft := MeshInstance3D.new()
		var sm := CylinderMesh.new()
		sm.top_radius = 0.012
		sm.bottom_radius = 0.012
		sm.height = 0.18
		shaft.mesh = sm
		shaft.material_override = mat
		shaft.position.y = 0.12
		add_child(shaft)
		var bow := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.03
		tm.outer_radius = 0.055
		bow.mesh = tm
		bow.material_override = mat
		bow.position.y = 0.22
		bow.rotation.x = PI / 2
		add_child(bow)
	else:
		# blessed salt: a low clay bowl with a small mound of white grains
		var clay := _clay_mat()
		var bowl := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.05
		cm.bottom_radius = 0.035
		cm.height = 0.05
		bowl.mesh = cm
		bowl.material_override = clay
		bowl.position.y = 0.1
		add_child(bowl)
		var grain_mat := StandardMaterial3D.new()
		grain_mat.albedo_color = Color(0.95, 0.94, 0.88)
		grain_mat.roughness = 1.0
		grain_mat.emission_enabled = true
		grain_mat.emission = tint
		grain_mat.emission_energy_multiplier = 0.5
		var grains := MeshInstance3D.new()
		var gm := SphereMesh.new()
		gm.radius = 0.036
		gm.height = 0.05
		grains.mesh = gm
		grains.material_override = grain_mat
		grains.position.y = 0.13
		add_child(grains)
	var glow := OmniLight3D.new()
	glow.light_color = tint
	glow.light_energy = 0.55
	glow.omni_range = 1.8
	glow.position.y = 0.15
	add_child(glow)


## Local cached clay look for the salt bowl.
func _clay_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.36, 0.25, 0.16)
	m.roughness = 0.8
	return m


func _process(delta: float) -> void:
	rotate_y(delta * 1.2)


func _on_body_entered(body: Node) -> void:
	if _taken or not body.is_in_group("player"):
		return
	_taken = true
	set_deferred("monitoring", false)
	collected.emit(kind)
	_audio.play()
	var t := create_tween().set_parallel(true)
	t.tween_property(self, "position:y", position.y + 0.4, 0.4).set_trans(Tween.TRANS_QUAD)
	t.tween_property(self, "scale", Vector3.ONE * 0.01, 0.4).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(queue_free)
