extends Node3D
## Esmiringhoy — sample build.
## One dark room, one demon, two ritual candles. Light both to banish it.
## Get caught and you become an Esmiringhoy yourself.

const PlayerScript := preload("res://scripts/player.gd")
const DemonScript := preload("res://scripts/demon.gd")
const CandleScript := preload("res://scripts/candle.gd")
const PickupScript := preload("res://scripts/pickup.gd")
const ItemScript := preload("res://scripts/item.gd")
const HudScript := preload("res://scripts/hud.gd")
const PauseScript := preload("res://scripts/pause.gd")
const OVERLAY_SHADER := preload("res://assets/shaders/sh_catch_overlay.gdshader")

const DEMON_WAKES_AFTER := 15.0

@onready var room = $Room

var player
var demon
var hud
var candles: Array = []
var overlay_mat: ShaderMaterial
var game_over := false
var won := false

var has_matches := false
var has_key := false
var has_salt := false
var chapel_open := false
var _warned_matches := false
var _warned_salt := false
var _env: Environment

var _drone: AudioStreamPlayer
var _beat_slow: AudioStreamPlayer
var _beat_fast: AudioStreamPlayer
var _sfx: AudioStreamPlayer
var _creak_3d: AudioStreamPlayer3D
var _bulb_dark := 0.0
var _bulb_cooldown := 0.0
var _chair_amt := 0.0
var _time := 0.0


func _enter_tree() -> void:
	_setup_input()


func _ready() -> void:
	randomize()
	EndScreen.hide_screen()   # make sure no end screen lingers from the previous run
	_setup_environment()

	var all_players := _spawn_players()
	player = _local_player(all_players)
	player.set_hole_area(room.hole_area)

	demon = DemonScript.new()
	demon.name = "Esmiringhoy"
	add_child(demon)
	demon.global_position = room.demon_lurk
	demon.rotation.y = deg_to_rad(-60)
	demon.setup(all_players, room)
	demon.caught_player.connect(_on_caught)
	demon.hunt_started.connect(_on_hunt_started)
	for p in all_players:
		p.set_demon(demon)
		p.breath_seconds = Game.tuning().get("breath", 6.0)
		p.camera.fov = Settings.fov

	Game.reset_stats()
	# autoloads persist across scene reloads; guard so a recreated main connects once
	if not Settings.changed.is_connected(_apply_settings):
		Settings.changed.connect(_apply_settings)
	if not EndScreen.retry.is_connected(_on_end_retry):
		EndScreen.retry.connect(_on_end_retry)
	if not EndScreen.to_title.is_connected(_on_end_title):
		EndScreen.to_title.connect(_on_end_title)

	for key in room.candle_spots:
		var c = CandleScript.new()
		c.label = key
		c.name = "Candle_" + str(key)   # deterministic path so lighting can sync in co-op
		add_child(c)
		c.global_position = room.candle_spots[key]
		c.lit.connect(_on_candle_lit)
		if key == "D":
			c.requires = ["salt"]
			c.granted = func(_r) -> bool: return has_salt
		c.blocked.connect(_on_candle_blocked)
		candles.append(c)

	for spot in room.battery_spots:
		var b = PickupScript.new()
		add_child(b)
		b.global_position = spot
		b.collected.connect(_on_battery_collected)

	_spawn_quest_items()
	_setup_switches()
	_setup_lures()

	_setup_overlay()
	hud = HudScript.new()
	add_child(hud)
	hud.set_candles(0, candles.size())
	add_child(PauseScript.new())   # Esc pause / settings, re-captures the mouse on resume
	_setup_audio()

	hud.message("ANG SILID", "The candles are hidden somewhere in the house. Find the matches, the salt and the key — light them all. Walk, don't run. Hide if you must.", 7.0)
	get_tree().create_timer(DEMON_WAKES_AFTER).timeout.connect(demon.activate)


# ============================================================ players (solo + co-op)
## One player per connected peer (just one in single-player). Authority is set
## BEFORE add_child so each player's _ready() configures its own camera correctly.
func _spawn_players() -> Array:
	var list: Array = []
	var ids: Array = Net.peer_ids()
	var base: Vector3 = room.player_spawn
	var offsets := [Vector3.ZERO, Vector3(1.3, 0, 0), Vector3(-1.3, 0, 0), Vector3(0, 0, 1.4)]
	for i in ids.size():
		var id: int = ids[i]
		var p = PlayerScript.new()
		p.name = "Player_%d" % id
		p.set_multiplayer_authority(id)
		add_child(p)
		p.global_position = base + offsets[i % offsets.size()]
		list.append(p)
	return list


func _local_player(list: Array):
	var me: int = Net.my_id()
	for p in list:
		if p.get_multiplayer_authority() == me:
			return p
	return list[0]


# ============================================================ quest items (randomized)
## Granny-style: every kind of quest item spawns at ONE spot picked from its pool
## each run, so the house reads differently every night. The host rolls so every
## co-op peer instantiates the exact same layout.
func _spawn_quest_items() -> void:
	if Net.active and not Net.is_host():
		return   # non-hosts wait for the host's picks to arrive over the wire
	var picks := {}
	for kind in room.item_pools:
		picks[kind] = room.item_pools[kind].pick_random()
	_spawn_items_at.rpc(picks)
	# the ritual candles move too: A, B and C each land in a different room every
	# night; D never leaves the oratorio altar
	var labels: Array = []
	for c in candles:
		if str(c.label) != "D":
			labels.append(str(c.label))
	_place_candles.rpc(room.roll_candle_spots(labels))


## Move each ritual candle to the spot the host rolled for it (runs on every peer).
@rpc("authority", "call_local", "reliable")
func _place_candles(spots: Dictionary) -> void:
	for c in candles:
		var key: String = str(c.label)
		if spots.has(key):
			c.global_position = spots[key]


@rpc("authority", "call_local", "reliable")
func _spawn_items_at(picks: Dictionary) -> void:
	for kind in picks:
		var it = ItemScript.new()
		it.kind = kind
		add_child(it)   # _ready builds the visual from `kind`, so set it first
		it.global_position = picks[kind]
		it.collected.connect(_on_item_collected)


# ============================================================ setup
func _setup_input() -> void:
	_bind("move_forward", [KEY_W, KEY_UP])
	_bind("move_back", [KEY_S, KEY_DOWN])
	_bind("move_left", [KEY_A, KEY_LEFT])
	_bind("move_right", [KEY_D, KEY_RIGHT])
	_bind("sprint", [KEY_SHIFT])
	_bind("flashlight", [KEY_F])
	_bind("interact", [KEY_E])
	_bind("restart", [KEY_R])
	_bind("crouch", [KEY_CTRL, KEY_C])
	_bind("jump", [KEY_SPACE])
	_bind("throw", [KEY_Q])


func _bind(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)


## Values from design board 02.
func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("06070d")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("2b3550")
	# baseline fill so every room is readable while walking (was 0.03 — pitch black).
	# still dim and moody; the flashlight and darkness-hiding mechanics still matter.
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.ssao_enabled = true
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.014   # thinner, so far rooms aren't a grey wall
	env.volumetric_fog_albedo = Color("8c96a8")
	env.volumetric_fog_length = 32.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.1
	env.adjustment_saturation = 0.85
	env.adjustment_brightness = Settings.brightness
	_env = env
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _setup_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_mat = ShaderMaterial.new()
	overlay_mat.shader = OVERLAY_SHADER
	rect.material = overlay_mat
	layer.add_child(rect)


func _setup_audio() -> void:
	_drone = _music("res://assets/audio/amb_house_drone.ogg", -16.0)
	_beat_slow = _music("res://assets/audio/sfx_heartbeat_slow.ogg", -60.0)
	_beat_fast = _music("res://assets/audio/sfx_heartbeat_fast.ogg", -60.0)
	_sfx = AudioStreamPlayer.new()
	add_child(_sfx)
	_creak_3d = AudioStreamPlayer3D.new()
	_creak_3d.unit_size = 3.0
	add_child(_creak_3d)


func _music(path: String, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	var s: AudioStreamOggVorbis = load(path).duplicate()
	s.loop = true
	p.stream = s
	p.volume_db = db
	p.autoplay = true
	add_child(p)
	return p


func _play_3d(path: String, at: Vector3, db := 0.0, pitch := 1.0) -> void:
	_creak_3d.stream = load(path)
	_creak_3d.global_position = at
	_creak_3d.volume_db = db
	_creak_3d.pitch_scale = pitch
	_creak_3d.play()


# ============================================================ per-frame
func _process(delta: float) -> void:
	_time += delta
	if not game_over:
		Game.time_survived += delta
		Game.note_close(_demon_dist())
	if Input.is_action_just_pressed("restart") and game_over:
		get_tree().reload_current_scene()
		return
	_update_hud()
	_update_heartbeat(delta)
	_update_bulb(delta)
	_update_haunting(delta)
	_update_chapel()


func _apply_settings() -> void:
	if is_instance_valid(player):
		player.camera.fov = Settings.fov
	if _env != null:
		_env.adjustment_brightness = Settings.brightness


func _on_end_retry() -> void:
	EndScreen.hide_screen()   # autoload persists across reload — clear it first
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_end_title() -> void:
	EndScreen.hide_screen()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")


## Open the oratorio door once the player reaches it holding the key.
func _update_chapel() -> void:
	if chapel_open or not has_key or game_over:
		return
	if room.chapel_door_area and room.chapel_door_area.overlaps_body(player):
		chapel_open = true
		create_tween().tween_property(room.chapel_door, "rotation:y", deg_to_rad(-100), 1.0).set_trans(Tween.TRANS_SINE)
		_play_3d("res://assets/audio/sfx_creak_door.ogg", room.chapel_door.global_position, 0.0)
		hud.message("THE ORATORIO", "The key turns. The door creaks open.", 3.0)


# ============================================================ room lights & lures
## The five south rooms (bodega, kitchen, sala, CR, kuarto) each have a switch:
## flip it and the bulb hums on for a while — any Esmiringhoy caught inside the
## lit room recoils and keeps its distance, a temporary safe window to work in.
## Then the fuse blows and needs a rest before the switch works again.
func _setup_switches() -> void:
	for sw_def in room.light_switches:
		var sw = sw_def["sw"]
		sw.repelled.connect(_on_room_lit)
		sw.drained.connect(_on_room_dark)


func _on_room_lit(sw) -> void:
	var nm: String = str(sw.label).to_upper()
	var demon_in: bool = demon.visible and demon.state != DemonScript.State.DORMANT \
		and sw.bounds.has_point(demon.global_position)
	if demon_in:
		# it flees and stays away for as long as the light burns (plus a grace)
		demon.scared_by_light(sw.global_position, sw.on_time + 6.0)
		hud.message("LIGHTS ON", "The Esmiringhoy recoils from the light in the %s." % nm, 3.0)
	else:
		hud.message("LIGHTS ON", "The %s is lit — a few minutes of safety." % nm, 2.5)


func _on_room_dark(sw) -> void:
	hud.message("", "The fuse blows — the %s goes dark and needs to cool." % str(sw.label).to_upper(), 2.5)


## Lures: pressed with E, they racket every ~1.6 s and the demon HEARS it through
## the same channel footsteps use — it walks toward the noise, away from you.
func _setup_lures() -> void:
	for lure in room.lures:
		lure.demon = demon
		lure.started.connect(_on_lure_started)
		lure.stopped.connect(_on_lure_stopped)


func _on_lure_started(lure) -> void:
	var say := {
		"radio": "The old sala radio crackles to life.",
		"pipes": "A valve turns — the pipes start to bang.",
		"musicbox": "The music box winds up and plinks its tune.",
	}
	hud.message(str(lure.kind).to_upper(), say.get(lure.kind, "It makes a racket."), 2.5)


func _on_lure_stopped(lure) -> void:
	hud.message("", "The %s winds down." % lure.kind, 2.0)


## The live task list, read by the HUD tracker and the pause-menu Objectives panel.
func get_objectives() -> Array:
	var lit := 0
	var lit_pre := 0   # candles outside the chapel (A, B, C) — they only need matches
	for c in candles:
		if c.is_lit:
			lit += 1
			if c.label != "D":
				lit_pre += 1
	return [
		{"text": "Find the matches", "done": has_matches},
		{"text": "Light the other candles  (%d/%d)" % [lit_pre, candles.size() - 1], "done": lit_pre >= candles.size() - 1},
		{"text": "Find the blessed salt", "done": has_salt},
		{"text": "Find the oratorio key", "done": has_key},
		{"text": "Open the oratorio", "done": chapel_open},
		{"text": "Light the chapel candle", "done": lit >= candles.size()},
	]


func _demon_dist() -> float:
	if not demon.visible or demon.state == DemonScript.State.DORMANT:
		return 99.0
	return demon.global_position.distance_to(player.global_position)


func _update_hud() -> void:
	hud.set_battery(player.battery / PlayerScript.BATTERY_MAX, player.flashlight.visible)
	var prompt_txt := ""
	if player.focus_candle != null:
		prompt_txt = "Hold E to light the candle"
	elif player.focus_switch != null:
		prompt_txt = ("Press E — flip the %s switch" % player.focus_switch.label) if player.focus_switch.can_flip() else "Fuse cooling down…"
	elif player.focus_lure != null:
		prompt_txt = ("Press E — start the %s" % player.focus_lure.label) if not player.focus_lure.active and player.focus_lure.cool_left <= 0.0 else "Winding down…"
	hud.set_prompt(player.focus_candle != null or player.focus_switch != null or player.focus_lure != null, player.light_progress, prompt_txt)
	hud.set_crouched(player.crouching and not player.turned)
	var near: bool = _demon_dist() < 4.0
	hud.set_hide_state(player.focus_hide != null, player.hiding, near, player.breath)
	hud.set_objectives(get_objectives())
	Journal.set_content(get_objectives(), [])
	if player.focus_candle and not player.can_light and not _warned_matches:
		_warned_matches = true
		hud.message("", "You need matches to light it.", 2.0)
	var focal = player.focus_candle
	if focal != null and focal.requires.has("salt") and not has_salt and not _warned_salt:
		_warned_salt = true
		hud.message("", "This candle asks for blessed salt.", 2.5)


func _update_heartbeat(delta: float) -> void:
	if game_over:
		return
	var d := _demon_dist()
	var hunting: bool = demon.state == DemonScript.State.HUNT or demon.state == DemonScript.State.STUTTER
	var slow_target := -60.0
	var fast_target := -60.0
	if d < 14.0:
		slow_target = lerpf(-6.0, -30.0, clampf((d - 4.0) / 10.0, 0.0, 1.0))
	if hunting and d < 8.0:
		fast_target = lerpf(-2.0, -18.0, clampf((d - 2.0) / 6.0, 0.0, 1.0))
		slow_target = -60.0
	_beat_slow.volume_db = move_toward(_beat_slow.volume_db, slow_target, delta * 30.0)
	_beat_fast.volume_db = move_toward(_beat_fast.volume_db, fast_target, delta * 30.0)


## The bulb flickers, and dies for 3 s whenever the demon comes within 8 m.
func _update_bulb(delta: float) -> void:
	var l: OmniLight3D = room.bulb_light
	_bulb_cooldown = maxf(_bulb_cooldown - delta, 0.0)
	if _bulb_dark > 0.0:
		_bulb_dark -= delta
		l.light_energy = 0.0
	else:
		var flick := 1.0
		if randf() < 0.04:
			flick = randf_range(0.05, 0.6)
		l.light_energy = 2.0 * flick
		var near: bool = demon.global_position.distance_to(l.global_position) < 8.0
		if near and _bulb_cooldown <= 0.0 and demon.state != DemonScript.State.DORMANT and demon.visible:
			_bulb_dark = 3.0
			_bulb_cooldown = 9.0
	room.bulb_material.emission_energy_multiplier = 3.0 * l.light_energy / 2.0
	if room.bulb_audio:
		room.bulb_audio.volume_db = -14.0 if l.light_energy > 0.05 else -60.0


## Rocking chair, kulambo net and the balcony door react to the demon.
func _update_haunting(delta: float) -> void:
	var active: bool = demon.visible and demon.state != DemonScript.State.DORMANT
	var chair: Node3D = room.rocking_chair
	var near_chair: bool = active and demon.global_position.distance_to(chair.global_position) < 6.0
	var prev := _chair_amt
	_chair_amt = move_toward(_chair_amt, 1.0 if near_chair else 0.0, delta * 0.6)
	chair.rotation.x = sin(_time * 2.2) * 0.16 * _chair_amt
	if _chair_amt > 0.3 and prev <= 0.3:
		_play_3d("res://assets/audio/sfx_creak_floor.ogg", chair.global_position, -2.0, 0.8)

	var net: MeshInstance3D = room.kulambo
	var near_net: bool = active and demon.global_position.distance_to(net.global_position) < 3.5
	var sway := 0.04 if near_net else 0.008
	net.rotation.z = sin(_time * 1.7) * sway
	net.rotation.x = sin(_time * 1.3 + 1.0) * sway * 0.6

	var door: Node3D = room.balcony_door
	if active and demon.state == DemonScript.State.HUNT and randf() < 0.05:
		door.rotation.y = randf_range(-0.02, 0.02)
	else:
		door.rotation.y = move_toward(door.rotation.y, 0.0, delta * 0.2)


# ============================================================ events
func _on_hunt_started() -> void:
	# the aparador doors creak open when it first starts hunting
	for d in room.aparador_doors:
		var side: float = signf(d.position.x)
		create_tween().tween_property(d, "rotation:y", deg_to_rad(side * 38.0), 1.4).set_trans(Tween.TRANS_SINE)
	_play_3d("res://assets/audio/sfx_creak_door.ogg", room.aparador_doors[0].global_position, 0.0)


func _on_battery_collected(_amount) -> void:
	hud.message("", "Spare battery — flashlight recharged.", 2.5)


func _on_item_collected(kind) -> void:
	if kind == "matches":
		has_matches = true
		player.can_light = true
		hud.message("MATCHES", "Now you can light the candles. Hold E on one.", 2.8)
	elif kind == "key":
		has_key = true
		hud.message("ORATORIO KEY", "The locked door is south of the back room.", 2.8)


	elif kind == "salt":
		has_salt = true
		hud.message("BLESSED SALT", "The last candle will burn on this.", 2.8)


func _on_candle_blocked(reqs: Array) -> void:
	if reqs.has("salt") and not has_salt:
		hud.message("", "This candle needs blessed salt.", 2.5)


func _on_candle_lit(_c) -> void:
	var lit_count := 0
	for c in candles:
		if c.is_lit:
			lit_count += 1
	Game.candles_lit = lit_count
	hud.set_candles(lit_count, candles.size())
	if lit_count >= candles.size() and not game_over:
		_win()
	else:
		var left := candles.size() - lit_count
		hud.message("", "%d candle%s left." % [left, "s" if left != 1 else ""], 2.5)


func _win() -> void:
	game_over = true
	won = true
	demon.banish()
	_beat_fast.volume_db = -60.0
	_beat_slow.volume_db = -60.0
	await get_tree().create_timer(3.0).timeout
	EndScreen.show_win(Game.stats_lines())


## Third-person death cinematic: the camera pulls out in front of you, the
## Esmiringhoy takes you from behind and devours you, you sink to your knees as it
## drags you into the dark — YOU WERE EATEN — then you wake as one of them.
func _on_caught(target) -> void:
	if game_over:
		return
	# co-op: only the caught player's own screen plays a death; the host tells them
	if Net.active:
		_mp_caught.rpc(target.get_multiplayer_authority())
		return
	game_over = true
	hud.set_prompt(false, 0.0)
	hud.set_crosshair(false)

	# 0.0 s · the view swings out to third person; the demon lunges onto your back
	var fwd: Vector3 = player.begin_death_cinematic(self, demon.global_position)
	demon.pose_for_eat(player.global_position, fwd)
	var player_start: Vector3 = player.global_position
	var demon_start: Vector3 = demon.global_position
	overlay_mat.set_shader_parameter("shake", 0.25)

	# 0.3 s · ROAR + it starts to feed; you buckle and sink to your knees
	await get_tree().create_timer(0.3).timeout
	_beat_slow.stop()
	_beat_fast.stop()
	_sfx.stream = load("res://assets/audio/sfx_catch_roar.ogg")
	_sfx.volume_db = 0.0
	_sfx.play()
	player.play_death_collapse(1.5)

	# 1.6 s · it drags you backward, away from the light, into the dark
	await get_tree().create_timer(1.3).timeout
	var drag := fwd * 3.2
	var pull := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	pull.tween_property(player, "global_position", player_start - drag, 1.8)
	pull.tween_property(demon, "global_position", demon_start - drag, 1.8)
	pull.tween_method(func(v): overlay_mat.set_shader_parameter("flood", v), 0.0, 1.0, 1.8)
	create_tween().tween_property(_drone, "volume_db", -60.0, 1.6)

	# 2.6 s · title over the dark
	await get_tree().create_timer(1.0).timeout
	hud.message("YOU WERE EATEN", "", -1.0)

	# 3.6 s · the dark becomes your dark — you wake as an Esmiringhoy
	await get_tree().create_timer(1.0).timeout
	overlay_mat.set_shader_parameter("shake", 0.0)
	player.end_death_cinematic()
	player.head.rotation.x = deg_to_rad(-55)   # look down at your new hands
	player.turn_into_demon(demon.body.skin)
	demon.visible = false
	var back := create_tween().set_parallel(true)
	back.tween_method(func(v): overlay_mat.set_shader_parameter("flood", v), 1.0, 0.0, 0.6)
	back.tween_method(func(v): overlay_mat.set_shader_parameter("vision", v), 0.0, 1.0, 0.6)

	# 4.4 s · first breath as the demon
	await get_tree().create_timer(0.8).timeout
	create_tween().tween_property(player.head, "rotation:x", 0.0, 0.8)
	_drone.pitch_scale = 0.8
	create_tween().tween_property(_drone, "volume_db", -10.0, 1.5)
	player.input_locked = false
	hud.message("YOU ARE ESMIRINGHOY NOW", "", 2.5)
	await get_tree().create_timer(2.2).timeout
	EndScreen.show_death(demon.last_cause)


## Co-op catch: runs on every peer. Mark that player out; the owner sees the message.
@rpc("any_peer", "call_local", "reliable")
func _mp_caught(peer_id: int) -> void:
	var node := get_node_or_null("Player_%d" % peer_id)
	if node != null:
		node.turned = true
		node.input_locked = true
	if peer_id == Net.my_id():
		game_over = true
		hud.set_prompt(false, 0.0)
		hud.set_crosshair(false)
		hud.message("TAKEN", "The Esmiringhoy took you.   Press R", -1.0)
