extends Node3D
## A ritual candle. Hold E on it to light it. A lit candle makes a 2 m safe zone
## the Esmiringhoy will not enter.

signal lit(candle)
signal blocked(requirements)   # raised when request_light() comes in without the extras it needs

const SAFE_RADIUS := 2.0

@export var label := "A"
## Extra components this candle needs beyond the matches, e.g. ["salt"]. main.gd
## sets these per candle; `granted` is checked for each one before lighting.
var requires: Array = []
var granted: Callable = Callable()

var is_lit := false
var light: OmniLight3D
var flame: MeshInstance3D
var wick_mat: StandardMaterial3D
var area: Area3D
var _audio: AudioStreamPlayer3D
var _base_energy := 2.2


func _ready() -> void:
	add_to_group("candles")
	var wax := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.04
	cm.bottom_radius = 0.045
	cm.height = 0.24
	cm.radial_segments = 12
	wax.mesh = cm
	var wax_mat := StandardMaterial3D.new()
	wax_mat.albedo_color = Color(0.85, 0.8, 0.68)
	wax_mat.roughness = 0.5
	wax_mat.subsurf_scatter_enabled = true
	wax_mat.subsurf_scatter_strength = 0.4
	wax.material_override = wax_mat
	wax.position.y = 0.12
	add_child(wax)

	# a dish under it
	var dish := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 0.08
	dm.bottom_radius = 0.06
	dm.height = 0.02
	dish.mesh = dm
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.35, 0.27, 0.12)
	brass.metallic = 0.8
	brass.roughness = 0.4
	dish.material_override = brass
	dish.position.y = 0.01
	add_child(dish)

	# wick glints faintly so a beam can find it
	var wick := MeshInstance3D.new()
	var wm := CylinderMesh.new()
	wm.top_radius = 0.004
	wm.bottom_radius = 0.004
	wm.height = 0.03
	wick.mesh = wm
	wick_mat = StandardMaterial3D.new()
	wick_mat.albedo_color = Color(0.1, 0.05, 0.03)
	wick_mat.emission_enabled = true
	wick_mat.emission = Color("ff5a1f")
	wick_mat.emission_energy_multiplier = 0.6
	wick.material_override = wick_mat
	wick.position.y = 0.255
	add_child(wick)

	flame = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.11)
	flame.mesh = q
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.albedo_texture = _flame_texture()
	fm.albedo_color = Color(1.0, 0.75, 0.4)
	fm.emission_enabled = true
	fm.emission = Color(1.0, 0.55, 0.2)
	fm.emission_energy_multiplier = 3.0
	flame.material_override = fm
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flame.position.y = 0.32
	flame.visible = false
	add_child(flame)

	light = OmniLight3D.new()
	light.light_color = Color("ff9a4a")
	light.light_energy = 0.0
	light.omni_range = 2.5
	light.shadow_enabled = true
	light.position.y = 0.36
	add_child(light)

	# interaction target (physics layer 5 = value 16)
	area = Area3D.new()
	area.collision_layer = 16
	area.collision_mask = 0
	area.monitoring = false
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 0.28
	cs.shape = sp
	cs.position.y = 0.18
	area.add_child(cs)
	add_child(area)
	area.set_meta("candle", self)

	_audio = AudioStreamPlayer3D.new()
	_audio.stream = load("res://assets/audio/sfx_candle_light.ogg")
	_audio.volume_db = -4.0
	add_child(_audio)


func _flame_texture() -> Texture2D:
	var img := Image.create(32, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 32:
			var u := (x - 15.5) / 16.0
			var v := y / 63.0  # 0 top, 1 bottom
			var width := sin(v * PI) * (0.35 + 0.65 * v)
			var a := clampf(1.0 - absf(u) / max(width, 0.01), 0.0, 1.0)
			a *= smoothstep(0.0, 0.25, v)
			img.set_pixel(x, y, Color(1.0, 0.8 + 0.2 * (1.0 - v), 0.5, a))
	return ImageTexture.create_from_image(img)


## Called by the player. In co-op it lights on every peer (deterministic node path);
## solo it just lights locally.
func request_light() -> void:
	var missing := _missing_requirements()
	if not missing.is_empty():
		blocked.emit(missing)
		return
	if Net.active:
		_net_light.rpc()
	else:
		light_it()


## Any components from `requires` the caller hasn't earned yet.
func _missing_requirements() -> Array:
	var missing: Array = []
	for r in requires:
		if granted.is_null() or not granted.call(r):
			missing.append(r)
	return missing


@rpc("any_peer", "call_local", "reliable")
func _net_light() -> void:
	light_it()


func light_it() -> void:
	if is_lit:
		return
	is_lit = true
	flame.visible = true
	wick_mat.emission_energy_multiplier = 2.0
	_audio.play()
	var t := create_tween()
	t.tween_property(light, "light_energy", _base_energy, 0.6)
	lit.emit(self)


func is_inside_safe_zone(p: Vector3) -> bool:
	if not is_lit:
		return false
	var d := p - global_position
	d.y = 0.0
	return d.length() < SAFE_RADIUS


func _process(_delta: float) -> void:
	if is_lit:
		var f := 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.023) + randf_range(-0.06, 0.06)
		light.light_energy = _base_energy * f
		flame.scale = Vector3(1.0, 0.9 + 0.2 * f, 1.0)
