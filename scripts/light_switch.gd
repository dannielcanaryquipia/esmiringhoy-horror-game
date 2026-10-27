extends Area3D
## A wall light switch. Flip it (tap E) and the room light hums on for a while —
## any Esmiringhoy caught inside the lit room recoils and keeps its distance.
## When the light dies, the fuse needs a rest before it can be flipped again.
## Physics layer 5 (value 16), same as candles, so the crosshair ray finds it.

signal repelled(sw)   # the light just came on — main.gd checks whether the demon is inside
signal drained(sw)    # the light just died

@export var label := "sala"      # room name, used in messages

var light: OmniLight3D           # the room's bulb; room.gd wires this
var bounds: AABB                 # the room the light protects
var lit_energy := 2.2
var on_time := 30.0              # seconds the room light stays on
var cool_time := 90.0            # fuse rest before the switch works again
var lit_left := 0.0              # >0 while the room is lit
var cool_left := 0.0

var _audio: AudioStreamPlayer3D
var _base_tween: Tween


func _ready() -> void:
	collision_layer = 16    # layer 5: interactables
	collision_mask = 0
	monitoring = false
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.45, 0.7, 0.5)
	cs.shape = sh
	add_child(cs)
	set_meta("light_switch", self)
	_audio = AudioStreamPlayer3D.new()
	_audio.stream = load("res://assets/audio/sfx_flash_click.ogg")
	_audio.volume_db = -2.0
	_audio.unit_size = 3.0
	add_child(_audio)


func can_flip() -> bool:
	return lit_left <= 0.0 and cool_left <= 0.0


## Flip it. Returns false when the fuse is still resting; co-op syncs via rpc.
func try_flip() -> bool:
	if Net.active:
		if not can_flip():
			return false
		_net_flip.rpc()
		return true
	return flip()


@rpc("any_peer", "call_local", "reliable")
func _net_flip() -> void:
	flip()


func flip() -> bool:
	if not can_flip():
		return false
	lit_left = on_time
	_audio.play()
	if _base_tween:
		_base_tween.kill()
	_base_tween = create_tween()
	_base_tween.tween_property(light, "light_energy", lit_energy, 0.25)
	repelled.emit(self)
	return true


func _process(delta: float) -> void:
	cool_left = maxf(cool_left - delta, 0.0)
	if lit_left > 0.0:
		lit_left -= delta
		# an old wire: the bulb sways and stutters
		if light != null:
			var f := 0.88 + 0.12 * sin(Time.get_ticks_msec() * 0.011) + randf_range(-0.04, 0.04)
			light.light_energy = lit_energy * f
		if lit_left <= 0.0:
			lit_left = 0.0
			cool_left = cool_time
			_audio.play()
			if _base_tween:
				_base_tween.kill()
			_base_tween = create_tween()
			_base_tween.tween_property(light, "light_energy", 0.0, 0.5)
			drained.emit(self)
