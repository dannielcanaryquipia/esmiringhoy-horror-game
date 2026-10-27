extends Node
## Scripted trailer for Esmiringhoy. Drives a cinematic camera through the house,
## puppets the demon, plays the real death cinematic, and overlays title cards.
## Not part of the game: exclude "trailer/*" from exports.
##
## Record it with Godot's Movie Maker (fixed 30 fps, frames are never dropped):
##   godot --path . --write-movie trailer_out/frame.png --fixed-fps 30 --resolution 1280x720 res://trailer/trailer.tscn
## then encode with ffmpeg (see trailer/README.txt).

const MAIN_SCENE := preload("res://scenes/main.tscn")
const LENGTH := 61.0

var main
var player
var demon
var cam: Camera3D
var torch: SpotLight3D
var t := 0.0

var _overlay: CanvasLayer
var _black: ColorRect
var _card: Label
var _sub: Label
var _title: Label
var _tag: Label
var _credit: Label
var _fired := {}
var _demon_speed := 0.0
var _demon_mode := "lurk"
var _lunge_from := Vector3.ZERO
var _lunge_to := Vector3.ZERO
var _walk_from := Vector3.ZERO
var _walk_to := Vector3.ZERO
var _floor_torch: SpotLight3D


# ------------------------------------------------------------------ setup
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	main = MAIN_SCENE.instantiate()
	add_child(main)
	player = main.player
	demon = main.demon

	# freeze gameplay; the trailer moves everything itself
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	player.hand.visible = false
	player.flashlight.visible = false
	demon.set_physics_process(false)
	demon.state = demon.State.LURK  # awake, so the house reacts, but puppeted
	demon.visible = false
	main.hud.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	cam = Camera3D.new()
	cam.fov = 66.0
	cam.near = 0.03
	add_child(cam)
	cam.make_current()

	torch = SpotLight3D.new()
	torch.light_color = Color("f2e6c8")
	torch.light_energy = 11.0
	torch.spot_range = 14.0
	torch.spot_angle = 24.0
	torch.spot_attenuation = 0.75
	torch.shadow_enabled = true
	torch.light_projector = load("res://assets/textures/tex_flashlight_cookie.png")
	torch.light_volumetric_fog_energy = 0.25
	torch.position = Vector3(0.18, -0.15, 0.0)
	cam.add_child(torch)

	_build_overlay()
	# debug: start mid-timeline, e.g. TRAILER_START=36 (not used for the real recording)
	var start := OS.get_environment("TRAILER_START")
	if start != "":
		t = float(start)


## The game's own bundled fonts (same as the design board): IM Fell English for
## titles and cards, Inter for the small credit line.
func _font(serif: bool, _bold := false) -> Font:
	var path := "res://assets/fonts/IMFellEnglish-Regular.ttf" if serif else "res://assets/fonts/Inter-Variable.ttf"
	if ResourceLoader.exists(path):
		return load(path)
	return ThemeDB.fallback_font


func _mk_label(size: int, color: Color, serif: bool, bold := false) -> Label:
	var l := Label.new()
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_override("font", _font(serif, bold))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.modulate.a = 0.0
	return l


func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 20
	add_child(_overlay)
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(_black)

	_card = _mk_label(44, Color("e9e2d8"), true)
	_card.offset_left = 160
	_card.offset_right = -160
	_overlay.add_child(_card)

	_sub = _mk_label(30, Color("e9e2d8"), true)
	_sub.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_sub.offset_bottom = -64
	_sub.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_sub.add_theme_constant_override("shadow_offset_x", 2)
	_sub.add_theme_constant_override("shadow_offset_y", 2)
	_overlay.add_child(_sub)

	_title = _mk_label(124, Color("ff5a1f"), true, true)
	_title.offset_top = -70
	_title.offset_bottom = -70
	_title.add_theme_color_override("font_outline_color", Color(0.55, 0.06, 0.02, 0.6))
	_title.add_theme_constant_override("outline_size", 14)
	_overlay.add_child(_title)
	_title.text = "ESMIRINGHOY"

	_tag = _mk_label(26, Color("e9e2d8"), true)
	_tag.offset_top = 70
	_tag.offset_bottom = 70
	_overlay.add_child(_tag)
	_tag.text = "Light the candles.  Say the prayer.  Survive until dawn."

	_credit = _mk_label(17, Color("a79c90"), false)
	_credit.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_credit.offset_bottom = -40
	_overlay.add_child(_credit)
	_credit.text = "Co-op horror   ·   Made with Godot Engine & GDScript   ·   Coming soon to itch.io"


# ------------------------------------------------------------------ helpers
func _fade(node: CanvasItem, to: float, dur: float) -> void:
	create_tween().tween_property(node, "modulate:a", to, dur)


func _black_to(a: float, dur: float) -> void:
	create_tween().tween_property(_black, "color:a", a, dur)


func _show_card(text: String, hold: float) -> void:
	_card.text = text
	var tw := create_tween()
	tw.tween_property(_card, "modulate:a", 1.0, 0.7)
	tw.tween_interval(hold)
	tw.tween_property(_card, "modulate:a", 0.0, 0.6)


func _show_sub(text: String, hold: float) -> void:
	_sub.text = text
	var tw := create_tween()
	tw.tween_property(_sub, "modulate:a", 1.0, 0.5)
	tw.tween_interval(hold)
	tw.tween_property(_sub, "modulate:a", 0.0, 0.5)


func _play(path: String, db := 0.0, pitch := 1.0) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = load(path)
	p.volume_db = db
	p.pitch_scale = pitch
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


## True exactly once, on the first frame the timeline passes `at`.
func _at(at: float, key: String) -> bool:
	if t >= at and not _fired.has(key):
		_fired[key] = true
		return true
	return false


func _place_cam(from: Vector3, look: Vector3) -> void:
	cam.global_position = from
	cam.look_at(look, Vector3.UP)
	# keep the "player" under the camera so heartbeat / tells react to it
	player.global_position = Vector3(from.x, 0.0, from.z)


func _ease(a: float, b: float) -> float:
	return smoothstep(a, b, t)


func _candle(label: String) -> Node3D:
	for c in main.candles:
		if str(c.label) == label:
			return c
	return main.candles[0]


func _place_demon(pos: Vector3, face: Vector3) -> void:
	demon.global_position = pos
	var d := face - pos
	demon.rotation.y = atan2(-d.x, -d.z)


# ------------------------------------------------------------------ timeline
func _process(delta: float) -> void:
	t += delta
	demon.body.animate(delta, _demon_speed, _demon_mode)

	# 0–4  black + card 1
	if _at(0.3, "c1"):
		_show_card("Every generation, the Villareal family keeps a bargain.", 2.4)

	# 4–9  Shot A: down the hallway toward the bedroom door
	if t < 9.0:
		var k := _ease(4.0, 9.0)
		_place_cam(Vector3(0.0, 1.55, 11.2).lerp(Vector3(0.0, 1.55, 6.2), k), Vector3(-0.3, 1.25, -2.0))
		torch.visible = true
	if _at(4.0, "a_in"):
		_black_to(0.0, 1.2)
	if _at(5.5, "a_step"):
		_play("res://assets/audio/sfx_creak_floor.ogg", -6.0, 0.9)
	if _at(8.4, "a_out"):
		_black_to(1.0, 0.6)

	# 9–12 card 2
	if _at(9.1, "c2"):
		_show_card("Lola kept it asleep for sixty years.", 1.8)

	# 12–17 Shot B: moonlight through the capiz windows (no torch)
	if t >= 12.0 and t < 17.0:
		var k := _ease(12.0, 17.0)
		var yaw := lerpf(-0.55, 0.45, k)
		var from := Vector3(0.0, 1.45, 1.2)
		_place_cam(from, from + Vector3(sin(yaw), 0.12, -cos(yaw)))
		torch.visible = false
	if _at(12.0, "b_in"):
		_black_to(0.0, 1.0)
	if _at(16.4, "b_out"):
		_black_to(1.0, 0.6)

	# 17–20 card 3
	if _at(17.1, "c3"):
		_show_card("Tonight, at her lamay, the candles went out.", 1.8)

	# 20–25 Shot C: the tumba-tumba starts to rock; the bulb dies
	if t >= 20.0 and t < 25.0:
		var k := _ease(20.0, 25.0)
		_place_cam(Vector3(-1.4, 1.35, 3.2).lerp(Vector3(-2.1, 1.25, 2.75), k), Vector3(-3.64, 0.55, 1.75))
		torch.visible = true
	if _at(20.0, "c_in"):
		demon.visible = true
		_place_demon(Vector3(-0.9, 0.0, 3.7), Vector3(-3.6, 0, 1.7))  # behind the camera
		_black_to(0.0, 0.8)
		_play("res://assets/audio/sfx_whispers_rev.ogg", -4.0, 0.85)
	if _at(24.6, "c_out"):
		_black_to(1.0, 0.25)
		demon.visible = false

	# 25–27.5 card 4 + sting
	if _at(25.0, "c4"):
		_play("res://assets/audio/sfx_scream_sting.ogg", -2.0, 0.8)
		_card.add_theme_color_override("font_color", Color("ff5a1f"))
		_card.add_theme_font_size_override("font_size", 72)
		_card.remove_theme_font_override("font")
		_card.add_theme_font_override("font", _font(true, true))
		_show_card("IT IS AWAKE.", 1.2)

	# 27.5–33 Shot D: torch sweep reveals it beside the aparador
	if t >= 27.5 and t < 33.0:
		var k := _ease(27.7, 31.0)
		var yaw := lerpf(0.75, -0.55, k)
		var from := Vector3(0.2, 1.6, 3.4)
		_place_cam(from, from + Vector3(sin(yaw), -0.08, -cos(yaw)))
		torch.visible = true
	if _at(27.5, "d_in"):
		_card.add_theme_color_override("font_color", Color("e9e2d8"))
		_card.add_theme_font_override("font", _font(true))
		_card.add_theme_font_size_override("font_size", 44)
		demon.visible = true
		demon.body.set_hunting(false)
		_demon_mode = "lurk"
		_demon_speed = 0.0
		_place_demon(Vector3(-3.4, 0.0, -2.4), Vector3(0.2, 0, 3.4))
		_black_to(0.0, 0.5)
	if _at(30.6, "d_eyes"):
		demon.body.set_hunting(true)
		demon._growl.play()
	if _at(32.6, "d_out"):
		_black_to(1.0, 0.25)

	# 33–36 Shot E: frozen in the beam, low angle
	if t >= 33.0 and t < 36.0:
		var k := _ease(33.0, 36.0)
		_place_cam(Vector3(-1.2, 1.05, -0.4).lerp(Vector3(-1.6, 1.0, -0.8), k), Vector3(-3.4, 1.85, -2.4))
	if _at(33.0, "e_in"):
		demon._growl.stop()
		_demon_mode = "frozen"
		demon.body.set_flare(1.0)
		_play("res://assets/audio/sfx_demon_hiss.ogg", 0.0)
		_black_to(0.0, 0.15)
		_show_sub("Your light can stop it.  For a moment.", 1.8)
	if _at(35.75, "e_out"):
		_black_to(1.0, 0.2)
		demon.body.set_flare(0.0)

	# 36–41 Shot F: hiding under the bed while it walks past
	if t >= 36.0 and t < 41.0:
		_place_cam(Vector3(4.68, 0.33, -2.3), Vector3(2.0, 0.2, 0.4))
		torch.visible = false
		var w := clampf((t - 36.4) / 1.6, 0.0, 1.0) if t < 39.0 else clampf((t - 39.0) / 1.6, 0.0, 1.0) + 1.0
		var walk_pos := _walk_from.lerp(_walk_to, w * 0.5)
		_place_demon(walk_pos, _walk_to if t < 38.0 or t > 39.0 else Vector3(4.68, 0, -2.3))
		_demon_speed = 0.0 if (t > 38.0 and t < 39.0) else 2.0
	if _at(36.0, "f_in"):
		demon.visible = true
		demon.state = demon.State.LURK
		demon.body.set_hunting(true)
		demon.body.set_flare(0.0)
		_demon_mode = "lurk"
		_walk_from = Vector3(1.5, 0.0, -1.7)
		_walk_to = Vector3(4.1, 0.0, 0.9)
		# a dropped torch on the floor back-lights its legs as it passes the bed
		_floor_torch = SpotLight3D.new()
		_floor_torch.light_color = Color("f2e6c8")
		_floor_torch.light_energy = 3.5
		_floor_torch.spot_range = 9.0
		_floor_torch.spot_angle = 22.0
		_floor_torch.shadow_enabled = true
		add_child(_floor_torch)
		var from := Vector3(1.2, 0.12, 1.8)
		_floor_torch.global_transform = Transform3D(Basis.looking_at(Vector3(4.4, 0.25, -2.2) - from, Vector3.UP), from)
		_black_to(0.0, 0.3)
		_show_sub("Hide.  Hold your breath.", 2.6)
	if _at(38.0, "f_look"):
		demon.body.set_search(1.0)
		_play("res://assets/audio/sfx_whispers_rev.ogg", -2.0, 0.8)
	if _at(39.0, "f_go"):
		demon.body.set_search(0.0)
	if _at(40.7, "f_out"):
		_black_to(1.0, 0.25)
	if _at(41.0, "f_clean") and _floor_torch != null:
		_floor_torch.queue_free()

	# 41–45 Shot G: the oratorio candle
	if t >= 41.0 and t < 45.0:
		var k := _ease(41.0, 45.0)
		var c: Vector3 = _candle("D").global_position + Vector3(0, 0.25, 0)
		_place_cam(c + Vector3(1.9, 0.45, -1.6).lerp(Vector3(1.0, 0.25, -0.9), k), c)
		torch.visible = false
	if _at(41.0, "g_in"):
		demon.visible = false
		demon.state = demon.State.DORMANT  # calm the house for this shot
		_black_to(0.0, 0.4)
	if _at(41.9, "g_lit"):
		_candle("D").light_it()
	if _at(42.4, "g_sub"):
		_show_sub("Light the candles.  Say the prayer.", 1.9)
	if _at(44.7, "g_out"):
		_black_to(1.0, 0.25)

	# 45–53 Shot H: the real death cinematic — eaten from behind, then you turn
	if _at(45.0, "h_in"):
		demon.visible = true
		demon.state = demon.State.HUNT
		demon.body.set_hunting(true)
		_demon_mode = "catch"
		_demon_speed = 0.0
		player.global_position = Vector3(0.6, 0.0, 1.0)
		player.rotation.y = 0.0
		demon.global_position = Vector3(0.6, 0.0, 2.6)
		player.hand.visible = true          # the torch drops and rolls, still on
		player.flashlight.visible = true
		cam.current = false
		player.camera.make_current()
		main._on_caught(player)
		_black_to(0.0, 0.15)
	if _at(47.6, "h_eaten"):
		_card.add_theme_color_override("font_color", Color("c21a1a"))
		_card.add_theme_font_size_override("font_size", 64)
		_card.add_theme_font_override("font", _font(true, true))
		_show_card("YOU WERE EATEN", 0.8)
	if _at(49.4, "h_sub"):
		_show_sub("If it catches you… you become one of them.", 1.8)
	if _at(53.0, "h_out"):
		_black_to(1.0, 0.4)
	if _at(53.6, "h_clean"):
		EndScreen.hide_screen()
		main.overlay_mat.set_shader_parameter("vision", 0.0)

	# 53.5–61 Title
	if _at(53.8, "title"):
		main.overlay_mat.set_shader_parameter("vision", 0.0)
		_play("res://assets/audio/sfx_catch_roar.ogg", -3.0, 0.55)
		_fade(_title, 1.0, 1.6)
	if _at(55.6, "tag"):
		_fade(_tag, 1.0, 1.2)
	if _at(56.8, "credit"):
		_fade(_credit, 1.0, 1.2)
	if _at(LENGTH - 1.2, "end_fade"):
		_fade(_title, 0.0, 1.0)
		_fade(_tag, 0.0, 1.0)
		_fade(_credit, 0.0, 1.0)
	if t >= LENGTH:
		get_tree().quit()
