extends Control
## Front lobby. Enter Ang Silid to play, or open Controls to see the key map.

const BONE := Color("e9e2d8")
const MUTED := Color("a79c90")
const EMBER := Color("ff5a1f")   # design-board ember (same as Ui.EMBER)

## Shared with the in-game pause menu (pause.gd). Keep the two in sync.
const CONTROLS := [
	["W A S D", "Move"],
	["Mouse", "Look around (the view follows the mouse)"],
	["Mouse wheel", "Scroll down to crouch, up to stand"],
	["Space", "Jump"],
	["Shift", "Sprint (a few seconds, then you tire)"],
	["F", "Flashlight on / off"],
	["E (hold)", "Light a candle"],
	["E (tap)", "Flip a room's light switch · start a lure (radio / pipes / music box)"],
	["Esc", "Pause / this menu"],
	["R", "Restart after the round ends"],
]

var _panel: Control
var _mp_panel: Control
var _mp_box: VBoxContainer
var _mp_mode := ""          # "host" | "join"
var _mp_status := ""
var _ip_edit: LineEdit


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Ui.VOID   # design-board background
	add_child(bg)
	add_child(Ui.vignette(0.45))   # depth behind the title

	var title := _label("ESMIRINGHOY", 72, EMBER, true)   # the board wordmark: IM Fell, ember
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 62
	title.offset_bottom = 150
	add_child(title)
	var sub := _label("Light the ritual candles before the Esmiringhoy finds you.", 20, MUTED, true)
	sub.set_anchors_preset(Control.PRESET_TOP_WIDE)
	sub.offset_top = 150
	sub.offset_bottom = 180
	add_child(sub)

	# an ember rule under the tagline, like a ritual inscription
	var rule := Ui.divider(220.0, 0.5)
	rule.position = Vector2(530, 194)
	add_child(rule)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.offset_left = -130
	box.offset_right = 130
	box.offset_top = -136   # starts below the tagline + rule
	box.offset_bottom = 230
	add_child(box)
	box.add_child(_button("Enter Ang Silid (solo)", _on_play))
	box.add_child(_button("Host Co-op (LAN)", _on_host))
	box.add_child(_button("Join Co-op (LAN)", _on_join_menu))
	box.add_child(_button("Controls", func(): _panel.visible = true))
	box.add_child(_button("Settings", func(): SettingsPanel.open()))
	box.add_child(_button("Quit", get_tree().quit))

	_build_panel()
	_build_mp_panel()
	Net.start_game.connect(_on_start_game)
	Net.peers_changed.connect(_refresh_mp)
	Net.joined.connect(func() -> void: _mp_status = "Connected. Waiting for the host to start…"; _refresh_mp())
	Net.join_failed.connect(func() -> void: _mp_status = "Could not reach that host. Check the IP and Wi-Fi."; _refresh_mp())
	Net.disconnected.connect(func() -> void: _mp_mode = ""; _close_mp())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _panel.visible:
		_panel.visible = false
	elif event.is_action_pressed("ui_accept") and not _panel.visible:
		_on_play()


func _on_play() -> void:
	_open_difficulty()


func _open_difficulty() -> void:
	var ov := Control.new()
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(ov)
	ov.add_child(Ui.dim(0.82))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.offset_left = -130
	v.offset_right = 130
	v.offset_top = -140
	v.offset_bottom = 160
	ov.add_child(v)
	v.add_child(Ui.heading("DIFFICULTY"))
	v.add_child(Ui.button("Easy", func() -> void: _start_solo(Game.Diff.EASY)))
	v.add_child(Ui.button("Normal", func() -> void: _start_solo(Game.Diff.NORMAL)))
	v.add_child(Ui.button("Nightmare", func() -> void: _start_solo(Game.Diff.NIGHTMARE)))
	v.add_child(Ui.button("Back", func() -> void: ov.queue_free()))


func _start_solo(d: int) -> void:
	Game.set_difficulty(d)
	get_tree().change_scene_to_file("res://scenes/main.tscn")


# ---------------------------------------------------------------- multiplayer (LAN)
func _build_mp_panel() -> void:
	_mp_panel = Control.new()
	_mp_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mp_panel.visible = false
	add_child(_mp_panel)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.82)
	_mp_panel.add_child(dim)
	_mp_box = VBoxContainer.new()
	_mp_box.add_theme_constant_override("separation", 12)
	_mp_box.set_anchors_preset(Control.PRESET_CENTER)
	_mp_box.offset_left = -260
	_mp_box.offset_right = 260
	_mp_box.offset_top = -170
	_mp_box.offset_bottom = 190
	_mp_panel.add_child(_mp_box)


func _on_host() -> void:
	if not Net.host():
		_mp_mode = "host"
		_mp_status = "Could not start a host (port in use?)."
		_open_mp()
		return
	_mp_mode = "host"
	_mp_status = ""
	_open_mp()


func _on_join_menu() -> void:
	_mp_mode = "join"
	_mp_status = ""
	_open_mp()


func _refresh_mp() -> void:
	if _mp_panel == null or not _mp_panel.visible:
		return
	for c in _mp_box.get_children():
		c.queue_free()
	if _mp_mode == "host":
		_mp_box.add_child(_label("HOST — CO-OP (LAN)", 30, EMBER, true))
		_mp_box.add_child(_label("On the other device, choose Join and enter:", 16, MUTED, true))
		_mp_box.add_child(_label("%s : %d" % [Net.local_ip(), Net.PORT], 24, BONE, true))
		_mp_box.add_child(_label("Players connected: %d" % Net.peer_ids().size(), 18, MUTED, true))
		if _mp_status != "":
			_mp_box.add_child(_label(_mp_status, 15, EMBER, true))
		_mp_box.add_child(_button("Start", func() -> void: Net.start()))
		_mp_box.add_child(_button("Cancel", _cancel_mp))
	else:
		_mp_box.add_child(_label("JOIN — CO-OP (LAN)", 30, EMBER, true))
		_mp_box.add_child(_label("Enter the host's IP (shown on the host screen):", 16, MUTED, true))
		if _ip_edit == null:
			_ip_edit = LineEdit.new()
			_ip_edit.placeholder_text = "192.168.1.xxx"
		_ip_edit.custom_minimum_size = Vector2(260, 40)
		_ip_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
		_mp_box.add_child(_ip_edit)
		if _mp_status != "":
			_mp_box.add_child(_label(_mp_status, 15, EMBER, true))
		_mp_box.add_child(_button("Connect", _do_join))
		_mp_box.add_child(_button("Cancel", _cancel_mp))


func _do_join() -> void:
	var ip := _ip_edit.text.strip_edges() if _ip_edit else ""
	if ip == "":
		_mp_status = "Type the host's IP first."
		_refresh_mp()
		return
	_mp_status = "Connecting to %s…" % ip
	_refresh_mp()
	if not Net.join(ip):
		_mp_status = "Invalid address."
		_refresh_mp()


func _open_mp() -> void:
	_mp_panel.visible = true
	_refresh_mp()


func _close_mp() -> void:
	if _mp_panel:
		_mp_panel.visible = false


func _cancel_mp() -> void:
	Net.leave()
	_mp_mode = ""
	_close_mp()


func _on_start_game() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")


# ---------------------------------------------------------------- controls view
func _build_panel() -> void:
	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.visible = false
	add_child(_panel)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.78)
	_panel.add_child(dim)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.offset_left = -240
	v.offset_right = 240
	v.offset_top = -180
	v.offset_bottom = 200
	_panel.add_child(v)
	v.add_child(_label("CONTROLS", 32, EMBER, true))
	for row in CONTROLS:
		v.add_child(_control_row(row[0], row[1]))
	var back := _button("Back", func(): _panel.visible = false)
	back.custom_minimum_size = Vector2(0, 42)
	v.add_child(back)


func _control_row(key: String, action: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	var k := _label(key, 18, BONE, false)
	k.custom_minimum_size = Vector2(150, 24)
	h.add_child(k)
	h.add_child(_label(action, 18, MUTED, false))
	return h


# ---------------------------------------------------------------- widgets (themed via Ui)
func _label(text: String, font_px: int, color: Color, centered: bool) -> Label:
	return Ui.label(text, font_px, color, centered)


func _button(text: String, cb: Callable) -> Button:
	return Ui.button(text, cb)
