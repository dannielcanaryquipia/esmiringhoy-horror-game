extends CharacterBody3D
## First-person survivor.
## WASD move · mouse look · Shift sprint (4 s) · F flashlight · hold E to light a candle.

const WALK := 2.6
const SPRINT := 5.0
const DEMON_SPEED := 4.9          # after being turned
const STAMINA_MAX := 5.5          # longer sprint so you can actually run room-to-room and escape
const GRAVITY := 9.8
const JUMP_VELOCITY := 4.5
const MOUSE_SENS := 0.0022
const BATTERY_MAX := 120.0
const LIGHT_TIME := 1.5           # seconds of holding E to light a candle
const REACH := 2.4
const FLASH_ENERGY := 11.0
const STAND_HEIGHT := 1.75
const CROUCH_HEIGHT := 1.0
const STAND_EYE := 1.6
const CROUCH_EYE := 0.82
const CROUCH_SPEED := 1.3         # slow and quiet while hiding

var head: Node3D
var camera: Camera3D
var hand: Node3D
var _col: CollisionShape3D
var _cap: CapsuleShape3D
var crouching := false
var _crouch := 0.0                # 0 = standing, 1 = fully crouched
var flashlight: SpotLight3D
var lens_mat: StandardMaterial3D

var flash_on := true
var battery := BATTERY_MAX
var battery_drain_mult := 1.0     # the demon sets this to 3 while the beam is on it
var stamina := STAMINA_MAX
var exhausted := false
var input_locked := false
var turned := false               # true once you have become an Esmiringhoy
var slow_factor := 1.0
var cinematic := false            # true during the third-person death cutscene
var body_model                    # the visible survivor body (player_body.gd), cinematic only

var focus_candle = null          # the candle under the crosshair, if any
var light_progress := 0.0
var focus_switch = null          # a room light switch under the crosshair, if any
var focus_lure = null            # a noisemaker (radio / pipes / music box), if any
var can_light := false           # set true once you have found the matches

var demon                        # set by main.gd, so footsteps can be heard
var hiding := false              # climbed into a hiding spot
var focus_hide = null            # a hiding spot under the crosshair, if any
var _hide_spot = null            # the spot currently occupied
var busted := false              # true if the demon saw you hide
var breath := 1.0                # 1 = full lungs, 0 = must gasp
var breath_seconds := 6.0        # how long a held breath lasts (set from difficulty)
var holding_breath := false
var _hide_yaw := 0.0             # extra head turn while hidden (within the spot's cone)
var _hide_pitch := 0.0
var _hide_limit_yaw := deg_to_rad(70.0)
var _hide_limit_pitch := deg_to_rad(28.0)

var _bob := 0.0
var _step_dist := 0.0
var _steps: Array[AudioStream] = []
var _step_player: AudioStreamPlayer
var _click_player: AudioStreamPlayer
var _battery_player: AudioStreamPlayer
var _warned_low := false
var _shake := 0.0
var _throw_cd := 0.0
var _hole_area: Area3D

# co-op: when this player is a remote teammate, we show a body and sync its transform
var _remote_body
var _net_send := 0.0
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _net_pitch := 0.0


func _ready() -> void:
	add_to_group("player")
	collision_layer = 4   # layer 3: players
	collision_mask = 1    # world only (ignores the moon-patch layer)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = STAND_HEIGHT
	cs.shape = cap
	cs.position.y = STAND_HEIGHT * 0.5
	add_child(cs)
	_col = cs
	_cap = cap

	head = Node3D.new()
	head.position.y = 1.6
	add_child(head)
	camera = Camera3D.new()
	camera.fov = 72.0
	camera.near = 0.03
	head.add_child(camera)
	camera.current = true

	_build_flashlight()

	for i in range(1, 5):
		_steps.append(load("res://assets/audio/sfx_step_wood_%02d.ogg" % i))
	_step_player = _make_player(-10.0)
	_click_player = _make_player(-8.0)
	_click_player.stream = load("res://assets/audio/sfx_flash_click.ogg")
	_battery_player = _make_player(-10.0)
	_battery_player.stream = load("res://assets/audio/sfx_battery_low.ogg")

	_net_pos = global_position
	_net_yaw = rotation.y
	if is_multiplayer_authority():
		camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		# a remote teammate: no camera / no input, just a visible body others can see
		camera.current = false
		_remote_body = PlayerBodyScript.new()
		add_child(_remote_body)


func _make_player(db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.volume_db = db
	add_child(p)
	return p


func _build_flashlight() -> void:
	hand = Node3D.new()
	hand.position = Vector3(0.2, -0.2, -0.32)
	camera.add_child(hand)
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.09, 0.09, 0.1)
	body_mat.metallic = 0.6
	body_mat.roughness = 0.45
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.022
	cm.bottom_radius = 0.02
	cm.height = 0.2
	body.mesh = cm
	body.material_override = body_mat
	body.rotation.x = PI / 2
	hand.add_child(body)
	var bezel := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.034
	bm.bottom_radius = 0.024
	bm.height = 0.05
	bezel.mesh = bm
	bezel.material_override = body_mat
	bezel.rotation.x = -PI / 2
	bezel.position.z = -0.12
	hand.add_child(bezel)
	var lens := MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = 0.03
	lm.bottom_radius = 0.03
	lm.height = 0.004
	lens.mesh = lm
	lens_mat = StandardMaterial3D.new()
	lens_mat.albedo_color = Color("f2e6c8")
	lens_mat.emission_enabled = true
	lens_mat.emission = Color("f2e6c8")
	lens_mat.emission_energy_multiplier = 2.0
	lens.material_override = lens_mat
	lens.rotation.x = PI / 2
	lens.position.z = -0.146
	hand.add_child(lens)

	flashlight = SpotLight3D.new()
	flashlight.light_color = Color("f2e6c8")
	flashlight.light_energy = FLASH_ENERGY
	flashlight.spot_range = 14.0
	flashlight.spot_angle = 26.0
	flashlight.spot_attenuation = 0.75
	flashlight.shadow_enabled = true
	flashlight.light_projector = load("res://assets/textures/tex_flashlight_cookie.png")
	flashlight.light_volumetric_fog_energy = 0.15
	flashlight.position.z = -0.16
	hand.add_child(flashlight)


# ------------------------------------------------------------------ input
## Mouse-look lives in _input (not _unhandled_input) so that a HUD control sitting
## under the captured cursor (the crosshair is dead-centre) can never eat the motion.
func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens: float = Settings.mouse_sens
		var inv: float = -1.0 if Settings.invert_y else 1.0
		if hiding:
			# you can only turn your head a little while wedged into a hiding spot
			_hide_yaw = clampf(_hide_yaw - event.relative.x * sens, -_hide_limit_yaw, _hide_limit_yaw)
			_hide_pitch = clampf(_hide_pitch - event.relative.y * sens * inv, -_hide_limit_pitch, _hide_limit_pitch)
			return
		if not input_locked:
			rotate_y(-event.relative.x * sens)
			head.rotation.x = clampf(head.rotation.x - event.relative.y * sens * inv, -1.4, 1.4)


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event is InputEventMouseButton and event.pressed:
		# mouse wheel crouches / stands so you can duck behind counters and under furniture
		match event.button_index:
			MOUSE_BUTTON_WHEEL_DOWN:
				set_crouch(true)
			MOUSE_BUTTON_WHEEL_UP:
				set_crouch(false)
			_:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("interact") and not input_locked and not turned:
		if hiding:
			exit_hide()
		elif focus_hide != null:
			enter_hide(focus_hide)
		elif focus_switch != null:
			focus_switch.try_flip()
			set_crouch(false)
		elif focus_lure != null:
			focus_lure.toggle()
			set_crouch(false)
	elif event.is_action_pressed("throw") and not input_locked and not turned and not hiding:
		throw_distraction()
	elif event.is_action_pressed("flashlight") and not input_locked and not turned and not hiding:
		toggle_flashlight()
	elif event.is_action_pressed("crouch") and not input_locked and not turned and not hiding:
		set_crouch(not crouching)


func set_crouch(v: bool) -> void:
	if input_locked or turned:
		return
	crouching = v


func toggle_flashlight() -> void:
	if battery <= 0.0:
		_click_player.play()
		return
	flash_on = not flash_on
	_click_player.play()


## Recharge the flashlight from a battery pickup.
func add_battery(amount: float) -> void:
	battery = minf(battery + amount, BATTERY_MAX)
	if battery / BATTERY_MAX >= 0.2:
		_warned_low = false


func set_hole_area(a: Area3D) -> void:
	_hole_area = a


# ------------------------------------------------------------------ update
func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		_apply_remote(delta)   # remote teammate — just follow its synced transform
		return
	if cinematic:
		return   # the camera is detached and driven by main.gd; the body stands frozen
	if hiding:
		_update_hide(delta)
		return
	_throw_cd = maxf(_throw_cd - delta, 0.0)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif Input.is_action_just_pressed("jump") and not input_locked and not crouching:
		velocity.y = JUMP_VELOCITY

	var dir := Vector3.ZERO
	var sprinting := false
	if not input_locked:
		var iv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		dir = (transform.basis * Vector3(iv.x, 0, iv.y)).normalized()
		sprinting = Input.is_action_pressed("sprint") and dir != Vector3.ZERO and not exhausted and not turned and not crouching

	# stamina: 4 s of sprint, recovers when you stop
	if sprinting:
		stamina = maxf(stamina - delta, 0.0)
		if stamina <= 0.0:
			exhausted = true
	else:
		stamina = minf(stamina + delta * 1.1, STAMINA_MAX)
		if exhausted and stamina > 1.5:
			exhausted = false

	slow_factor = 1.0
	if _hole_area and _hole_area.overlaps_body(self):
		slow_factor = 0.45

	var speed := WALK
	if turned:
		speed = DEMON_SPEED
	elif sprinting:
		speed = SPRINT
	elif exhausted:
		speed = WALK * 0.75
	if crouching and not turned:
		speed = minf(speed, CROUCH_SPEED)
	speed *= slow_factor
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	move_and_slide()

	_update_crouch(delta)
	_update_head(delta, Vector2(velocity.x, velocity.z).length())
	_update_battery(delta)
	_update_candle_focus(delta)

	if Net.active:
		_net_send -= delta
		if _net_send <= 0.0:
			_net_send = 0.05
			_net_player.rpc(global_position, rotation.y, head.rotation.x, flashlight.visible)


## Smoothly lowers the eye line and shrinks the collision capsule while crouching.
## The demon raycasts to the camera, so a low crouch behind furniture hides you.
func _update_crouch(delta: float) -> void:
	if input_locked or turned:
		return
	var target := 1.0 if crouching else 0.0
	_crouch = move_toward(_crouch, target, delta * 7.0)
	_cap.height = lerpf(STAND_HEIGHT, CROUCH_HEIGHT, _crouch)
	_col.position.y = _cap.height * 0.5
	head.position.y = lerpf(STAND_EYE, CROUCH_EYE, _crouch)


func _update_head(delta: float, ground_speed: float) -> void:
	if ground_speed > 0.1 and is_on_floor():
		_bob += delta * ground_speed * 2.6
		_step_dist += ground_speed * delta
		var stride := 0.75 if ground_speed < 3.5 else 1.0
		if _step_dist > stride:
			_step_dist = 0.0
			_step_player.stream = _steps.pick_random()
			_step_player.pitch_scale = randf_range(0.9, 1.1) * (0.8 if turned else 1.0)
			_step_player.volume_db = -12.0 if ground_speed < 3.5 else -7.0
			_step_player.play()
			_emit_footstep(ground_speed)
	var bob_amt := 0.028 if ground_speed > 0.1 else 0.0
	var shake := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * 0.04
	camera.position = Vector3(cos(_bob * 0.5) * bob_amt * 0.5, sin(_bob) * bob_amt, 0) + shake
	# the torch lags slightly behind the view
	if hand.get_parent() == camera:
		hand.rotation = hand.rotation.lerp(Vector3(-head.rotation.x * 0.04, 0, 0), delta * 6.0)


func set_shake(v: float) -> void:
	_shake = v


func _update_battery(delta: float) -> void:
	var on := flash_on and battery > 0.0 and not turned and flashlight.get_parent() == hand
	if on:
		battery = maxf(battery - delta * battery_drain_mult, 0.0)
	var pct := battery / BATTERY_MAX
	var energy := FLASH_ENERGY * clampf(pct / 0.2, 0.25, 1.0)  # dims under 20 %
	if pct < 0.1 and randf() < 0.08:
		energy *= randf_range(0.0, 0.5)  # dying flicker
	flashlight.visible = on
	flashlight.light_energy = energy
	lens_mat.emission_energy_multiplier = 2.0 if on else 0.0
	if pct < 0.2 and not _warned_low:
		_warned_low = true
		_battery_player.play()
	if battery <= 0.0:
		flash_on = false


## True when the flashlight beam is on `point` (within range/angle and nothing in between).
func beam_hits(point: Vector3, max_dist := 8.0, half_angle_deg := 20.0) -> bool:
	if not flashlight.visible or flashlight.get_parent() != hand:
		return false
	var origin := flashlight.global_position
	var to := point - origin
	if to.length() > max_dist:
		return false
	var fwd := -flashlight.global_transform.basis.z
	if rad_to_deg(fwd.angle_to(to)) > half_angle_deg:
		return false
	var q := PhysicsRayQueryParameters3D.create(origin, point, 1, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _update_candle_focus(delta: float) -> void:
	focus_candle = null
	focus_hide = null
	focus_switch = null
	focus_lure = null
	if input_locked or turned or hiding:
		light_progress = 0.0
		return
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * REACH
	var q := PhysicsRayQueryParameters3D.create(from, to, 16 | 1 | 32, [get_rid()])
	q.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and hit.collider is Area3D:
		if hit.collider.has_meta("candle"):
			var c = hit.collider.get_meta("candle")
			if not c.is_lit:
				focus_candle = c
		elif hit.collider.has_meta("hide_spot"):
			focus_hide = hit.collider.get_meta("hide_spot")
		elif hit.collider.has_meta("light_switch"):
			focus_switch = hit.collider.get_meta("light_switch")
		elif hit.collider.has_meta("noisemaker"):
			focus_lure = hit.collider.get_meta("lure")
	if focus_candle and can_light and Input.is_action_pressed("interact"):
		light_progress += delta / LIGHT_TIME
		if light_progress >= 1.0:
			focus_candle.request_light()
			light_progress = 0.0
	else:
		light_progress = maxf(light_progress - delta * 2.0, 0.0)


# ------------------------------------------------------------------ noise + hiding
func set_demon(d) -> void:
	demon = d


# ------------------------------------------------------------------ co-op sync
## Authority broadcasts its pose; remote copies lerp toward it.
@rpc("any_peer", "unreliable_ordered", "call_remote")
func _net_player(pos: Vector3, yaw: float, pitch: float, flash: bool) -> void:
	_net_pos = pos
	_net_yaw = yaw
	_net_pitch = pitch
	flashlight.visible = flash
	flashlight.light_energy = FLASH_ENERGY if flash else 0.0


func _apply_remote(delta: float) -> void:
	var step: float = clampf(delta * 14.0, 0.0, 1.0)
	global_position = global_position.lerp(_net_pos, step)
	rotation.y = lerp_angle(rotation.y, _net_yaw, step)
	head.rotation.x = lerp_angle(head.rotation.x, _net_pitch, step)


func set_busted(v: bool) -> void:
	busted = v


## Footsteps carry: a sprint is loud and brings the demon; a walk barely carries;
## crouching is practically silent. This is how it hears where you are.
func _emit_footstep(ground_speed: float) -> void:
	if demon == null or turned:
		return
	var radius := 0.0
	if crouching:
		radius = 1.0
	elif ground_speed > 3.5:
		radius = 9.0      # running — it WILL hear this
	else:
		radius = 3.0      # walking — only if it is close
	demon.hear_noise(global_position, radius)


## Climb into a hiding spot: snap to it, kill the flashlight, and swing the view to
## the spot's peep-out pose. Tell the demon in case it watched you do it.
func enter_hide(spot) -> void:
	if hiding or spot == null or spot.occupied:
		return
	spot.occupied = true
	_hide_spot = spot
	Game.times_hidden += 1
	# let the demon judge whether it saw you BEFORE we conceal you
	if demon != null and demon.has_method("on_player_hid"):
		demon.on_player_hid(spot)

	hiding = true
	flash_on = false
	flashlight.visible = false
	lens_mat.emission_energy_multiplier = 0.0
	crouching = false
	_hide_limit_yaw = spot.yaw_limit
	_hide_limit_pitch = spot.pitch_limit
	_hide_yaw = 0.0
	_hide_pitch = 0.0

	camera.get_parent().remove_child(camera)
	add_child(camera)
	camera.top_level = true
	camera.global_position = spot.cam_pos
	camera.look_at(spot.look_target, Vector3.UP)


func exit_hide() -> void:
	if not hiding:
		return
	if _hide_spot != null:
		_hide_spot.occupied = false
	hiding = false
	busted = false
	holding_breath = false
	breath = 1.0
	_hide_spot = null
	camera.top_level = false
	if camera.get_parent() != head:
		camera.get_parent().remove_child(camera)
		head.add_child(camera)
	camera.position = Vector3.ZERO
	camera.rotation = Vector3.ZERO


## Runs every physics frame while hidden: aim the peep view and manage your breath.
func _update_hide(delta: float) -> void:
	if _hide_spot == null:
		return
	# look out of the spot, limited to its cone
	camera.global_position = _hide_spot.cam_pos
	camera.look_at(_hide_spot.look_target, Vector3.UP)
	camera.rotate_object_local(Vector3.UP, _hide_yaw)
	camera.rotate_object_local(Vector3.RIGHT, _hide_pitch)

	# breath: hold it (Space) when the demon is near, or it hears you
	holding_breath = Input.is_action_pressed("jump")
	if holding_breath:
		breath = maxf(breath - delta / breath_seconds, 0.0)
	else:
		breath = minf(breath + delta / 2.0, 1.0)


## Throw a rock: it arcs out, lands with a clatter, and the demon hears the noise
## THERE instead of here — pulling it away so you can slip past when it's closing in.
func throw_distraction() -> void:
	if _throw_cd > 0.0 or demon == null:
		return
	var world := get_parent()
	if world == null:
		return
	_throw_cd = 0.7
	var from := camera.global_position
	var fwd := -camera.global_transform.basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + fwd * 14.0, 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var landing: Vector3 = hit.position if not hit.is_empty() else from + fwd * 12.0
	landing.y = maxf(landing.y, 0.06)

	var rock := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.05
	sm.height = 0.1
	sm.radial_segments = 6
	sm.rings = 3
	rock.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.17, 0.16)
	mat.roughness = 1.0
	rock.material_override = mat
	world.add_child(rock)
	var start := from + fwd * 0.4
	rock.global_position = start
	var dur := clampf(start.distance_to(landing) / 16.0, 0.3, 0.8)
	var t := create_tween()
	t.tween_method(func(p: float): rock.global_position = _throw_arc(start, landing, p), 0.0, 1.0, dur)
	t.tween_callback(func(): _land_rock(rock, landing))


func _throw_arc(a: Vector3, b: Vector3, p: float) -> Vector3:
	var pos := a.lerp(b, p)
	pos.y += sin(p * PI) * 1.2   # a little parabola
	return pos


func _land_rock(rock: Node3D, at: Vector3) -> void:
	if demon and demon.has_method("hear_noise"):
		demon.hear_noise(at, 12.0)
	var a := AudioStreamPlayer3D.new()
	a.stream = load("res://assets/audio/sfx_creak_floor.ogg")
	a.unit_size = 5.0
	a.volume_db = -4.0
	a.pitch_scale = randf_range(1.1, 1.3)
	get_parent().add_child(a)
	a.global_position = at
	a.play()
	var at_free := a.create_tween()   # free on a timer (robust even if the clip loops)
	at_free.tween_interval(2.5)
	at_free.tween_callback(a.queue_free)
	var rt := rock.create_tween()
	rt.tween_interval(3.0)
	rt.tween_callback(rock.queue_free)


## For the demon: are you safely hidden right now? No, if it saw you hide, or you
## aren't holding your breath (or have run out) when it comes to look.
func is_hidden_safe() -> bool:
	if not hiding:
		return false
	if busted:
		return false
	return holding_breath and breath > 0.0


# ------------------------------------------------------------------ catch
const PlayerBodyScript := preload("res://scripts/player_body.gd")

## Enter the third-person death view. Turns the player to face away from the demon
## (so it takes you from behind), drops the torch, spawns the visible survivor body,
## and detaches the camera into a cinematic rig looking back at the player's face.
## Returns the horizontal "forward" the body faces, so main.gd can drag it into the dark.
func begin_death_cinematic(world: Node3D, demon_pos: Vector3) -> Vector3:
	# if it dragged you out of a hiding spot, drop the hide state first
	if hiding:
		if _hide_spot != null:
			_hide_spot.occupied = false
		_hide_spot = null
		hiding = false
	camera.top_level = false
	cinematic = true
	input_locked = true
	flash_on = false
	crouching = false
	_crouch = 0.0
	_cap.height = STAND_HEIGHT
	_col.position.y = STAND_HEIGHT * 0.5

	# face away from the demon: it lunges onto your back
	var fwd := global_position - demon_pos
	fwd.y = 0.0
	if fwd.length() < 0.05:
		fwd = -global_transform.basis.z
	fwd = fwd.normalized()
	rotation.y = atan2(-fwd.x, -fwd.z)

	drop_flashlight(world)

	body_model = PlayerBodyScript.new()
	add_child(body_model)   # child of the player, so it already faces `fwd`

	# cinematic camera: a three-quarter front angle, looking back at the victim
	var cam_dir := fwd.rotated(Vector3.UP, deg_to_rad(34.0))
	var cam_pos := global_position + cam_dir * 3.0 + Vector3(0, 1.55, 0)
	var look_target := global_position + Vector3(0, 0.95, 0)
	camera.get_parent().remove_child(camera)
	world.add_child(camera)
	camera.global_position = cam_pos + cam_dir * 0.6   # start a touch further out
	camera.look_at(look_target, Vector3.UP)
	# slow push-in toward the victim
	var t := camera.create_tween()
	t.tween_property(camera, "global_position", cam_pos, 3.2).set_trans(Tween.TRANS_SINE)
	return fwd


## Collapse the survivor onto its knees over `dur` seconds.
func play_death_collapse(dur: float) -> void:
	if not is_instance_valid(body_model):
		return
	var t: Tween = body_model.create_tween()
	t.tween_method(body_model.set_death, 0.0, 1.0, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)


## Re-attach the camera to the head and clear the cinematic body, ready for the
## first-person "you are the demon now" view.
func end_death_cinematic() -> void:
	cinematic = false
	if is_instance_valid(body_model):
		body_model.queue_free()
		body_model = null
	if camera.get_parent() != head:
		camera.get_parent().remove_child(camera)
		head.add_child(camera)
		camera.position = Vector3.ZERO
		camera.rotation = Vector3.ZERO
	head.rotation.x = 0.0


## Let go of the torch: it falls and rolls away, still on.
func drop_flashlight(world: Node3D) -> void:
	var gt := hand.global_transform
	hand.get_parent().remove_child(hand)
	world.add_child(hand)
	hand.global_transform = gt
	var land := Vector3(gt.origin.x + randf_range(-0.4, 0.4), 0.03, gt.origin.z + randf_range(-0.4, 0.4))
	var t := create_tween().set_parallel(true)
	t.tween_property(hand, "global_position", land, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(hand, "rotation", Vector3(0, randf_range(-PI, PI), PI / 2), 0.45)
	t.chain().tween_property(hand, "global_position", land + Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6)), 0.9).set_ease(Tween.EASE_OUT)


## Become a lesser demon: no torch, claws in view, faster, red vision (main.gd adds the overlay).
func turn_into_demon(claw_material: Material) -> void:
	turned = true
	flash_on = false
	for i in 2:
		var arm := Node3D.new()
		arm.position = Vector3(-0.28 if i == 0 else 0.28, -0.32, -0.4)
		camera.add_child(arm)
		var fore := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.04
		cm.height = 0.45
		fore.mesh = cm
		fore.material_override = claw_material
		fore.rotation.x = deg_to_rad(-70)
		arm.add_child(fore)
		for k in 4:
			var claw := MeshInstance3D.new()
			var cy := CylinderMesh.new()
			cy.top_radius = 0.002
			cy.bottom_radius = 0.01
			cy.height = 0.22
			cy.radial_segments = 5
			claw.mesh = cy
			claw.material_override = claw_material
			claw.position = Vector3((k - 1.5) * 0.022, 0.08, -0.26)
			claw.rotation.x = deg_to_rad(-100)
			arm.add_child(claw)
