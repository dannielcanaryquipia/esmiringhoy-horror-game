extends Area3D
## A spare battery lying in the dark. Walk into it to recharge the flashlight.
## Layer 0 / mask 4 (players): it never blocks movement, only senses the player.

signal collected(amount)

const AMOUNT := 60.0   # half of the flashlight's capacity

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
	# a small cell with a faint green glow so it reads in the dark
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.035
	cm.bottom_radius = 0.035
	cm.height = 0.14
	cm.radial_segments = 12
	body.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.35, 0.22)
	mat.metallic = 0.3
	mat.roughness = 0.5
	mat.emission_enabled = true
	mat.emission = Color(0.25, 1.0, 0.55)
	mat.emission_energy_multiplier = 0.6
	body.material_override = mat
	body.position.y = 0.12
	add_child(body)
	var cap := MeshInstance3D.new()
	var capm := CylinderMesh.new()
	capm.top_radius = 0.018
	capm.bottom_radius = 0.018
	capm.height = 0.02
	cap.mesh = capm
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.6, 0.5, 0.2)
	brass.metallic = 0.8
	brass.roughness = 0.3
	cap.material_override = brass
	cap.position.y = 0.2
	add_child(cap)
	# a soft glow so you can spot it from across a dark room
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.4, 1.0, 0.6)
	glow.light_energy = 0.5
	glow.omni_range = 1.8
	glow.position.y = 0.15
	add_child(glow)


func _process(delta: float) -> void:
	rotate_y(delta * 1.2)   # a slow spin to catch the eye


func _on_body_entered(body: Node) -> void:
	if _taken or not body.has_method("add_battery"):
		return
	_taken = true
	set_deferred("monitoring", false)
	body.add_battery(AMOUNT)
	collected.emit(AMOUNT)
	_audio.play()
	# pop up, shrink and vanish
	var t := create_tween().set_parallel(true)
	t.tween_property(self, "position:y", position.y + 0.4, 0.4).set_trans(Tween.TRANS_QUAD)
	t.tween_property(self, "scale", Vector3.ONE * 0.01, 0.4).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(queue_free)
