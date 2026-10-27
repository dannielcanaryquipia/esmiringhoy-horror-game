extends CharacterBody3D
## The Esmiringhoy's brain. States follow design board 04:
## DORMANT → LURK → HUNT ⇄ FROZEN → STUTTER → HUNT … → CATCH, or BANISHED when all candles are lit.

signal hunt_started
signal caught_player(target)

enum State { DORMANT, LURK, INVESTIGATE, HUNT, FROZEN, STUTTER, CATCH, BANISHED }

const LURK_SPEED := 2.0
const INVESTIGATE_SPEED := 2.8
const CHECK_RANGE := 1.9      # how close it must get to a hiding spot to look inside
const HUNT_SPEED := 4.0
const SIGHT_RANGE := 12.0
const FREEZE_RANGE := 8.0
const FREEZE_AFTER := 0.3     # seconds in the beam before it locks up
const FREEZE_MAX := 2.5
const FREEZE_IMMUNE := 6.0
const STUTTER_TIME := 1.5
const STUTTER_STEP := 0.25
const CATCH_RANGE := 1.6
const LOSE_TRACK_AFTER := 6.0

var state := State.DORMANT
var player                     # the player.gd it is currently targeting (nearest alive)
var players: Array = []        # all players (co-op); just [player] in single-player
var room                       # room.gd
var hunt_speed := HUNT_SPEED   # set from difficulty in setup()
var last_cause := "It caught you."   # why you died — shown on the death screen

# client-side (non-host) sync of the host's demon
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _net_hunt := false
var _net_hunt_prev := false
var _net_send := 0.0
var body                       # demon_body.gd
var agent: NavigationAgent3D

var _state_time := 0.0
var _beam_time := 0.0
var _immune := 0.0
var _unseen := 0.0
var _last_seen := Vector3.ZERO
var _wander_target := Vector3.ZERO
var _wander_pause := 0.0
var _stutter_tick := 0.0
var _scorch_dist := 0.0
var _has_hunted := false
var _whisper_cd := 4.0
var _stuck := 0.0
var _investigate_pos := Vector3.ZERO
var _look_time := 0.0
var _target_spot = null         # a hiding spot it is walking over to check
var _scan_yaw := 0.0            # current heading it is turning to look at while searching
var _scan_pause := 0.0          # dwell timer at each scan heading
var _scan_count := 0            # how many headings it has checked this search
var _scan_timeout := 0.0        # rolled once per search so the give-up time is stable
var _giving_up := false         # playing the "lost the trail" beat before patrol
var _give_up_t := 0.0
var _repel_left := 0.0          # >0: driven out of a lit room — it refuses to hunt or chase noise

var _growl: AudioStreamPlayer3D
var _voice: AudioStreamPlayer3D
var _presence: AudioStreamPlayer3D   # a constant low 3D rumble so you can always localize it
var _step: AudioStreamPlayer3D       # heavy 3D footsteps as it moves — track it by ear
var _steps: Array[AudioStream] = []
var _step_dist := 0.0
var _embers: GPUParticles3D
var _smoke: GPUParticles3D
var _scorch_tex: Texture2D


func setup(p_players: Array, p_room) -> void:
	players = p_players
	player = players[0] if players.size() > 0 else null
	room = p_room
	hunt_speed = Game.tuning().get("hunt", HUNT_SPEED)
	_net_pos = global_position


func _ready() -> void:
	collision_layer = 8   # layer 4: demons
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 2.0
	cs.shape = cap
	cs.position.y = 1.0
	add_child(cs)

	body = preload("res://scripts/demon_body.gd").new()
	add_child(body)

	agent = NavigationAgent3D.new()
	agent.path_desired_distance = 0.5
	agent.target_desired_distance = 0.6
	agent.radius = 0.4
	agent.height = 1.75
	add_child(agent)

	_growl = AudioStreamPlayer3D.new()
	var g: AudioStreamOggVorbis = load("res://assets/audio/sfx_demon_growl.ogg").duplicate()
	g.loop = true
	_growl.stream = g
	_growl.volume_db = -6.0
	_growl.unit_size = 5.0
	_growl.max_distance = 35.0
	_growl.panning_strength = 2.0        # strong left/right so you can point to it
	_growl.position.y = 2.0
	add_child(_growl)
	_voice = AudioStreamPlayer3D.new()
	_voice.unit_size = 5.0
	_voice.max_distance = 35.0
	_voice.panning_strength = 2.0
	_voice.position.y = 2.0
	add_child(_voice)

	# constant low rumble — the sound you home in on. Faint far away, swells as it nears.
	_presence = AudioStreamPlayer3D.new()
	var pr: AudioStreamOggVorbis = load("res://assets/audio/sfx_demon_growl.ogg").duplicate()
	pr.loop = true
	_presence.stream = pr
	_presence.volume_db = -20.0
	_presence.pitch_scale = 0.6
	_presence.unit_size = 4.0            # small → falls off quickly, so distance really reads
	_presence.max_distance = 34.0
	_presence.panning_strength = 2.5
	_presence.position.y = 1.4
	add_child(_presence)

	# heavy footsteps, positional — the clearest "it's coming from over there" cue
	_step = AudioStreamPlayer3D.new()
	_step.unit_size = 6.0
	_step.max_distance = 30.0
	_step.panning_strength = 2.2
	_step.position.y = 0.2
	add_child(_step)
	for i in range(1, 5):
		_steps.append(load("res://assets/audio/sfx_step_wood_%02d.ogg" % i))

	_add_heat_shimmer()
	_embers = _make_particles(true)
	_smoke = _make_particles(false)
	_scorch_tex = load("res://assets/textures/tex_decal_scorch.png")


# ---------------------------------------------------------------- visuals
func _add_heat_shimmer() -> void:
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.6, 2.6)
	q.mesh = qm
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://assets/shaders/sh_heat_shimmer.gdshader")
	q.material_override = sm
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	q.position = Vector3(0, 1.3, 0)
	add_child(q)


func _make_particles(embers: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 40 if embers else 24
	p.lifetime = 1.6 if embers else 2.5
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.3, 0.7, 0.2)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 35.0
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.5 if embers else 0.25
	pm.gravity = Vector3(0, 0.4 if embers else 0.15, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.2 if embers else 2.5
	var ramp := Gradient.new()
	if embers:
		ramp.set_color(0, Color(1.0, 0.6, 0.25, 1.0))
		ramp.set_color(1, Color(1.0, 0.2, 0.05, 0.0))
	else:
		ramp.set_color(0, Color(0.15, 0.15, 0.17, 0.35))
		ramp.set_color(1, Color(0.1, 0.1, 0.12, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = ramp
	pm.color_ramp = gt
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.025, 0.025) if embers else Vector2(0.35, 0.35)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if embers:
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.4, 0.1)
		mat.emission_energy_multiplier = 4.0
	else:
		mat.albedo_texture = load("res://assets/textures/tex_decal_dust.png")
	quad.material = mat
	p.draw_pass_1 = quad
	p.position = Vector3(0, 1.3, 0)
	add_child(p)
	return p


func _drop_scorch() -> void:
	var d := Decal.new()
	d.texture_albedo = _scorch_tex
	d.size = Vector3(0.7, 0.5, 0.9)
	d.emission_energy = 1.5
	d.texture_emission = _scorch_tex
	get_parent().add_child(d)
	d.global_position = global_position + Vector3(0, 0.1, 0)
	d.rotation.y = rotation.y
	var t := d.create_tween()
	t.tween_property(d, "emission_energy", 0.0, 6.0)
	t.parallel().tween_property(d, "modulate:a", 0.0, 20.0)
	t.tween_callback(d.queue_free)


func _say(path: String, db := 0.0, pitch := 1.0) -> void:
	_voice.stream = load(path)
	_voice.volume_db = db
	_voice.pitch_scale = pitch
	_voice.play()


# ---------------------------------------------------------------- state machine
func _set_state(s: State) -> void:
	state = s
	_state_time = 0.0
	match s:
		State.LURK:
			body.set_hunting(false)
			body.set_search(0.0)
			_growl.stop()
			_target_spot = null
			_giving_up = false
			if is_instance_valid(player):
				player.set_busted(false)
			_pick_wander()
		State.INVESTIGATE:
			body.set_hunting(false)
			_growl.stop()
			_look_time = 0.0
			_scan_yaw = rotation.y
			_scan_pause = 0.4
			_scan_count = 0
			_scan_timeout = randf_range(3.5, 5.5)
			_giving_up = false
			_say("res://assets/audio/sfx_whispers_rev.ogg", -4.0, 0.9)
		State.HUNT:
			body.set_hunting(true)
			body.set_search(0.0)
			if not _growl.playing:
				_growl.play()
			if not _has_hunted:
				_has_hunted = true
				_say("res://assets/audio/sfx_scream_sting.ogg", 0.0)
				hunt_started.emit()
		State.FROZEN:
			body.set_flare(1.0)
			_growl.stop()
			_say("res://assets/audio/sfx_demon_hiss.ogg", 2.0)
		State.STUTTER:
			body.set_flare(0.0)
			_stutter_tick = 0.0
			_say("res://assets/audio/sfx_whispers_rev.ogg", 0.0, 1.4)
		State.CATCH:
			_growl.stop()
			body.set_hunting(true)
	if _presence:
		if s == State.CATCH or s == State.BANISHED:
			_presence.stop()
		elif not _presence.playing:
			_presence.play()


func activate() -> void:
	if state == State.DORMANT:
		_set_state(State.LURK)


## Co-op: hunt whoever is nearest and still alive.
func _pick_target() -> void:
	var best = null
	var bd := INF
	for p in players:
		if p == null or p.turned:
			continue
		var d: float = global_position.distance_to(p.global_position)
		if d < bd:
			bd = d
			best = p
	if best != null:
		player = best


## Client-side: smoothly follow the host's demon transform and mirror its look.
func _apply_remote(delta: float) -> void:
	var step: float = clampf(delta * 12.0, 0.0, 1.0)
	var v: float = global_position.distance_to(_net_pos) / maxf(delta, 0.001)
	global_position = global_position.lerp(_net_pos, step)
	rotation.y = lerp_angle(rotation.y, _net_yaw, step)
	if _net_hunt != _net_hunt_prev:
		_net_hunt_prev = _net_hunt
		body.set_hunting(_net_hunt)
	body.animate(delta, clampf(v, 0.0, 4.0), "hunt" if _net_hunt else "lurk")
	_embers.emitting = true
	_smoke.emitting = true
	# keep the positional rumble + footsteps alive on the client so you can hear it
	if _presence and not _presence.playing:
		_presence.play()
	if v > 0.4:
		_step_dist += v * delta
		var stride := 1.3 if _net_hunt else 1.7
		if _step_dist >= stride:
			_step_dist = 0.0
			_step.stream = _steps.pick_random()
			_step.pitch_scale = randf_range(0.62, 0.74)
			_step.volume_db = -2.0 if _net_hunt else -9.0
			_step.play()


@rpc("authority", "unreliable_ordered", "call_remote")
func _net_demon(pos: Vector3, yaw: float, hunting: bool) -> void:
	_net_pos = pos
	_net_yaw = yaw
	_net_hunt = hunting


func _physics_process(delta: float) -> void:
	# clients don't run the AI — they just display the host's demon
	if Net.active and not Net.is_host():
		_apply_remote(delta)
		return
	_pick_target()
	if not player:
		return
	if Net.active:
		_net_send -= delta
		if _net_send <= 0.0:
			_net_send = 0.05
			_net_demon.rpc(global_position, rotation.y, _growl.playing)
	_state_time += delta
	_immune = maxf(_immune - delta, 0.0)
	_repel_left = maxf(_repel_left - delta, 0.0)
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	else:
		velocity.y = 0.0

	var mode := "lurk"
	var speed := 0.0
	match state:
		State.DORMANT, State.BANISHED:
			velocity.x = 0
			velocity.z = 0
		State.LURK:
			mode = "lurk"
			speed = _do_lurk(delta)
			_check_beam(delta)
		State.INVESTIGATE:
			mode = "lurk"
			speed = _do_investigate(delta)
			_check_beam(delta)
		State.HUNT:
			mode = "hunt"
			speed = _do_hunt(delta)
			_check_beam(delta)
			_check_catch()
		State.FROZEN:
			mode = "frozen"
			velocity.x = 0
			velocity.z = 0
			_do_frozen(delta)
		State.STUTTER:
			mode = "stutter"
			_do_stutter(delta)
			_check_catch()
		State.CATCH:
			mode = "catch"
			velocity.x = 0
			velocity.z = 0

	move_and_slide()
	body.animate(delta, speed, mode)
	_update_steps(delta)
	_embers.emitting = state != State.DORMANT and state != State.BANISHED
	_smoke.emitting = _embers.emitting


## Positional footsteps: heavier/louder when hunting, so you can hear it coming
## and tell which side it is on.
func _update_steps(delta: float) -> void:
	var v := get_real_velocity()
	var ground := Vector2(v.x, v.z).length()
	if ground < 0.4 or not is_on_floor():
		return
	_step_dist += ground * delta
	var stride := 1.3 if state == State.HUNT else 1.7
	if _step_dist >= stride:
		_step_dist = 0.0
		_step.stream = _steps.pick_random()
		_step.pitch_scale = randf_range(0.62, 0.74)
		_step.volume_db = -2.0 if state == State.HUNT else -9.0
		_step.play()


# ---------------------------------------------------------------- perception
func _eye_pos() -> Vector3:
	return global_position + Vector3(0, 2.1, 0)


func can_see_player() -> bool:
	if _repel_left > 0.0:
		return false   # light-driven: it keeps its distance, it does not hunt
	if player.turned or player.hiding:
		return false
	var head: Vector3 = player.camera.global_position
	var to := head - _eye_pos()
	var dist := to.length()
	var beam_visible: bool = player.flashlight.visible and dist < SIGHT_RANGE
	if dist > SIGHT_RANGE and not beam_visible:
		return false
	if dist < 2.5:
		return true  # it can hear you breathing
	var q := PhysicsRayQueryParameters3D.create(_eye_pos(), head, 1, [get_rid()])
	var clear := get_world_3d().direct_space_state.intersect_ray(q).is_empty()
	if clear:
		return true
	# it also notices a lit flashlight pointed its way, even around a corner
	return beam_visible and player.beam_hits(global_position + Vector3(0, 1.4, 0), SIGHT_RANGE, 30.0)


func _check_beam(delta: float) -> void:
	var chest := global_position + Vector3(0, 1.4, 0)
	var lit: bool = _immune <= 0.0 and player.beam_hits(chest, FREEZE_RANGE, 20.0)
	if lit:
		_beam_time += delta
		if _beam_time >= FREEZE_AFTER:
			_beam_time = 0.0
			_set_state(State.FROZEN)
	else:
		_beam_time = maxf(_beam_time - delta, 0.0)


func _in_candle_zone(p: Vector3) -> bool:
	for c in get_tree().get_nodes_in_group("candles"):
		if c.is_inside_safe_zone(p):
			return true
	return false


# ---------------------------------------------------------------- behaviours
func _move_toward(target: Vector3, speed: float, delta: float) -> float:
	agent.target_position = target
	var next := agent.get_next_path_position()
	var map_ready := NavigationServer3D.map_get_iteration_id(agent.get_navigation_map()) > 0
	if not map_ready or agent.is_navigation_finished():
		next = target
	var dir := next - global_position
	dir.y = 0.0
	if dir.length() < 0.05:
		velocity.x = 0
		velocity.z = 0
		return 0.0
	dir = dir.normalized()
	# never step into a lit candle's safe zone
	if _in_candle_zone(global_position + dir * (speed * delta + 0.5)):
		velocity.x = 0
		velocity.z = 0
		return 0.0
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	# turn to face where it's going
	var yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, yaw, minf(delta * 6.0, 1.0))
	return speed


func _pick_wander() -> void:
	var pts: Array = room.dark_points
	_wander_target = pts.pick_random()
	_wander_pause = 0.0


func _do_lurk(delta: float) -> float:
	if can_see_player():
		_last_seen = player.global_position
		_set_state(State.HUNT)
		return 0.0
	_whisper_cd -= delta
	if _whisper_cd <= 0.0:
		_whisper_cd = randf_range(7.0, 14.0)
		_say("res://assets/audio/sfx_whispers_rev.ogg", -6.0, randf_range(0.8, 1.0))
	var flat := _wander_target - global_position
	flat.y = 0
	if flat.length() < 0.8:
		velocity.x = 0
		velocity.z = 0
		_wander_pause += delta
		if _wander_pause > randf_range(2.0 if _repel_left > 0.0 else 4.0, 3.0 if _repel_left > 0.0 else 4.0):
			_pick_wander()
		return 0.0
	return _move_toward(_wander_target, LURK_SPEED * (2.2 if _repel_left > 0.0 else 1.0), delta)


## Called by the player when they make noise (footsteps). Loud noise (running)
## carries far; a walk barely carries; crouching is silent. The demon only reacts
## while idle — once it is hunting it already has you.
func hear_noise(at: Vector3, radius: float) -> void:
	if _repel_left > 0.0:
		return   # while repelled it pretends it didn't hear anything
	if state != State.LURK and state != State.INVESTIGATE:
		return
	if global_position.distance_to(at) <= radius:
		_investigate_pos = at
		if state != State.INVESTIGATE:
			_set_state(State.INVESTIGATE)


## Called the instant the player hides. If it had eyes on you (or was already
## hunting), it knows exactly where you went and comes to drag you out.
func on_player_hid(spot) -> void:
	var seen: bool = can_see_player() or state == State.HUNT or state == State.STUTTER
	if is_instance_valid(player):
		player.set_busted(seen)
	if seen:
		_target_spot = spot
		_last_seen = spot.global_position
		if state != State.HUNT:
			_set_state(State.HUNT)


func _do_investigate(delta: float) -> float:
	if can_see_player():
		_last_seen = player.global_position
		_giving_up = false
		body.set_search(0.0)
		_set_state(State.HUNT)
		return 0.0
	# "lost the trail" beat: stand, play the weary tell, then wander off
	if _giving_up:
		velocity.x = 0.0
		velocity.z = 0.0
		_give_up_t -= delta
		if _give_up_t <= 0.0:
			body.set_search(0.0)
			_set_state(State.LURK)
		return 0.0
	var flat := _investigate_pos - global_position
	flat.y = 0.0
	if flat.length() > 0.8:
		body.set_search(0.0)
		return _move_toward(_investigate_pos, INVESTIGATE_SPEED, delta)
	# arrived — SEARCH: turn to discrete headings, pausing to peer at each
	velocity.x = 0.0
	velocity.z = 0.0
	body.set_search(1.0)
	_look_time += delta
	_scan_pause -= delta
	rotation.y = lerp_angle(rotation.y, _scan_yaw, minf(delta * 3.0, 1.0))
	var aligned: bool = absf(wrapf(_scan_yaw - rotation.y, -PI, PI)) < 0.12
	if aligned and _scan_pause <= 0.0:
		_scan_count += 1
		_scan_yaw = rotation.y + randf_range(-2.2, 2.2)
		_scan_pause = randf_range(0.5, 1.0)
	# peer into any occupied spot it is now standing beside
	for s in get_tree().get_nodes_in_group("hiding_spots"):
		if s.occupied and global_position.distance_to(s.global_position) < CHECK_RANGE:
			_check_spot(s)
			return 0.0
	if _look_time > _scan_timeout or _scan_count >= 4:
		_begin_give_up()
	return 0.0


## It lost the trail: a brief weary tell (head-shake + low huff) before patrol.
func _begin_give_up() -> void:
	_giving_up = true
	_give_up_t = 1.0
	body.play_give_up()
	_say("res://assets/audio/sfx_demon_growl.ogg", -5.0, 0.7)


## Look inside an occupied spot. If the player was seen hiding, or isn't holding
## their breath, it finds them. Otherwise it lingers, then loses interest.
func _check_spot(spot) -> void:
	if _in_candle_zone(spot.global_position):
		_target_spot = null
		return
	if not player.is_hidden_safe():
		last_cause = "It saw you hide." if player.busted else "It heard you — you weren't holding your breath."
		_set_state(State.CATCH)
		caught_player.emit(player)
	else:
		_target_spot = null
		_set_state(State.LURK)


func _do_hunt(delta: float) -> float:
	# it saw you duck into a spot: march to it and haul you out
	if _target_spot != null and _target_spot.occupied:
		var sp: Vector3 = _target_spot.global_position
		if global_position.distance_to(sp) < CHECK_RANGE:
			_check_spot(_target_spot)
			return 0.0
		return _move_toward(sp, hunt_speed, delta)
	if can_see_player():
		_last_seen = player.global_position
		_unseen = 0.0
	else:
		_unseen += delta
		if _unseen > LOSE_TRACK_AFTER:
			_set_state(State.LURK)
			return 0.0
	var spd := _move_toward(_last_seen, hunt_speed, delta)
	# wedged on furniture or a door frame? lurch forward instead of standing there
	if spd > 0.0 and get_real_velocity().length() < 0.3:
		_stuck += delta
		if _stuck > 1.2:
			_stuck = 0.0
			_set_state(State.STUTTER)
			return 0.0
	else:
		_stuck = 0.0
	_scorch_dist += spd * delta
	if _scorch_dist > 1.2:
		_scorch_dist = 0.0
		_drop_scorch()
	return spd


func _do_frozen(_delta: float) -> void:
	var chest := global_position + Vector3(0, 1.4, 0)
	var still_lit: bool = player.beam_hits(chest, FREEZE_RANGE, 22.0)
	player.battery_drain_mult = 3.0 if still_lit else 1.0
	if not still_lit or _state_time >= FREEZE_MAX:
		player.battery_drain_mult = 1.0
		_immune = FREEZE_IMMUNE
		_set_state(State.STUTTER)


func _do_stutter(delta: float) -> void:
	velocity.x = 0
	velocity.z = 0
	_stutter_tick += delta
	if _stutter_tick >= STUTTER_STEP:
		_stutter_tick = 0.0
		agent.target_position = player.global_position
		var next := agent.get_next_path_position()
		var dir := next - global_position
		dir.y = 0
		if dir.length() > 0.05:
			dir = dir.normalized()
			var step := global_position + dir * 1.0
			if not _in_candle_zone(step):
				# jump a metre, but let physics stop it at walls
				var motion := dir * 1.0
				move_and_collide(motion)
				rotation.y = atan2(-dir.x, -dir.z)
	if _state_time >= STUTTER_TIME:
		_last_seen = player.global_position
		_set_state(State.HUNT)


func _check_catch() -> void:
	if player.turned or player.hiding:
		return
	var d: Vector3 = player.global_position - global_position
	d.y = 0
	if d.length() < CATCH_RANGE and not _in_candle_zone(player.global_position):
		last_cause = "It caught you in the open."
		_set_state(State.CATCH)
		caught_player.emit(player)


## The room lights drive it out: a shriek, then it recoils to the dark corner
## farthest from the light and refuses to hunt or follow noise for `seconds` —
## the player's window to work. Called by main.gd when a lit room finds it inside.
func scared_by_light(away_from: Vector3, seconds: float) -> void:
	if state == State.CATCH or state == State.BANISHED or state == State.DORMANT:
		return
	_set_state(State.LURK)
	_repel_left = seconds
	_immune = FREEZE_IMMUNE   # it staggers out — the beam can't simply re-freeze it
	_say("res://assets/audio/sfx_scream_sting.ogg", -2.0, 1.15)
	var best: Vector3 = _wander_target
	var bd := -1.0
	for p in room.dark_points:
		var d: float = p.distance_to(away_from)
		if d > bd:
			bd = d
			best = p
	_wander_target = best   # set after _set_state, which re-rolls a wander target
	_whisper_cd = 3.0


# ---------------------------------------------------------------- endings
func banish() -> void:
	if state == State.BANISHED:
		return
	_set_state(State.BANISHED)
	_growl.stop()
	_say("res://assets/audio/sfx_scream_sting.ogg", 3.0, 0.7)
	body.set_hunting(true)
	body.set_flare(1.0)
	var t := create_tween()
	t.tween_method(body.set_dissolve, 0.0, 1.0, 2.6)
	t.tween_callback(hide)


## Snap in behind the victim and start devouring them from the back.
## `fwd` is the horizontal direction the victim faces (away from the demon).
func pose_for_eat(victim_pos: Vector3, fwd: Vector3) -> void:
	_set_state(State.CATCH)
	var stand := victim_pos - fwd * 0.55
	stand.y = global_position.y
	global_position = stand
	rotation.y = atan2(-fwd.x, -fwd.z)   # face the same way as the victim, onto their back
	body.set_catch_pose(1.0)
	var t := create_tween()
	t.tween_property(self, "global_position", victim_pos - fwd * 0.35, 0.3).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.parallel().tween_method(body.set_eat, 0.0, 1.0, 0.7)


## Lean in close to the player's face for the roar.
func lunge_to(face_pos: Vector3) -> void:
	var dir := face_pos - global_position
	dir.y = 0
	var stand := face_pos - dir.normalized() * 1.25
	stand.y = global_position.y
	rotation.y = atan2(-dir.x, -dir.z)
	var t := create_tween()
	t.tween_property(self, "global_position", stand, 0.25).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.parallel().tween_method(body.set_catch_pose, 0.0, 1.0, 0.35)
