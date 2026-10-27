extends CanvasLayer
## In-game pause / settings menu, toggled with Esc. Pauses the game, frees the
## mouse for the buttons, and re-captures it on Resume so looking works again.
## Runs with PROCESS_MODE_ALWAYS so it keeps working while the tree is paused.

const BONE := Color("e9e2d8")
const MUTED := Color("a79c90")
const EMBER := Color("ff5a1f")   # design-board ember (same as Ui.EMBER)

## Kept in sync with lobby.gd.
const CONTROLS := [
	["W A S D", "Move"],
	["Mouse", "Look around"],
	["Shift", "Run (loud — a few seconds, then you tire)"],
	["Ctrl / C", "Crouch (slow and quiet)"],
	["F", "Flashlight on / off"],
	["Q", "Throw a rock to distract it"],
	["E", "Light a candle (hold) · enter / leave a hiding spot"],
	["E", "Flip a light switch · start a lure (radio / pipes / music box)"],
	["Space", "Hold your breath (while hidden)"],
	["Space", "Jump (while moving)"],
	["Esc", "Pause / this menu"],
	["R", "Restart after the round ends"],
]

## The "how to play" guide — each mechanic, one line.
const MECHANICS := [
	["It hears you", "Running is loud and brings it. Walk to stay quiet; crouch is near-silent."],
	["Listen for it", "Its rumble and footsteps are positional — faint when far, and off to your left or right. Use a headset to point to it."],
	["Hiding", "Press E at a bed, aparador, table, cabinet, jar or curtain to climb in. It can still find you."],
	["Don't be seen hiding", "If it saw you duck in — or you ran in while it hunted — it drags you out."],
	["Hold your breath", "When it comes close to your spot, hold Space. Let go too early or run out → it hears you."],
	["Distract it", "Throw a rock (Q). It clatters where it lands and draws the demon there so you can slip past."],
	["The flashlight", "The beam freezes it for a few seconds but drains the battery fast and marks your spot."],
	["Candles", "A lit candle makes a safe zone it won't enter. The matches light all but the last — that one needs blessed salt."],
	["The goal", "Find the matches, the blessed salt and the oratorio key; open the chapel, light every candle, banish it."],
	["Room lights", "Five rooms have a switch (E). Flip it and the room stays lit a while — if it's inside, it recoils and keeps out. Then the fuse cools down before reuse."],
	["Lures", "The sala radio, CR pipes and the music box (E) make noise it walks toward — set one off, then slip away."],
]

var is_open := false
var _root: Control
var _menu: VBoxContainer
var _panel: Control
var _panel_body: VBoxContainer


func _ready() -> void:
	layer = 3
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.visible = false


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.66)
	_root.add_child(dim)

	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 14)
	_menu.set_anchors_preset(Control.PRESET_CENTER)
	_menu.offset_left = -130
	_menu.offset_right = 130
	_menu.offset_top = -210
	_menu.offset_bottom = 210
	_root.add_child(_menu)
	_menu.add_child(_label("PAUSED", 44, BONE, true))
	_menu.add_child(_button("Resume", func(): set_open(false)))
	_menu.add_child(_button("Objectives", _show_objectives))
	_menu.add_child(_button("How to Play", _show_howto))
	_menu.add_child(_button("Settings", func(): SettingsPanel.open()))
	_menu.add_child(_button("Restart", _on_restart))
	_menu.add_child(_button("Quit to Lobby", _on_quit_lobby))

	_build_panel()


## One reusable scrollable panel; the content is rebuilt per topic.
func _build_panel() -> void:
	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.visible = false
	_root.add_child(_panel)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_CENTER)
	scroll.offset_left = -300
	scroll.offset_right = 300
	scroll.offset_top = -210
	scroll.offset_bottom = 210
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	_panel_body = VBoxContainer.new()
	_panel_body.add_theme_constant_override("separation", 10)
	_panel_body.custom_minimum_size = Vector2(600, 0)
	scroll.add_child(_panel_body)


func _clear_panel() -> void:
	for c in _panel_body.get_children():
		c.queue_free()


func _row(key: String, val: String) -> HBoxContainer:
	return Ui.row(key, val)


func _show_objectives() -> void:
	_clear_panel()
	_panel_body.add_child(_label("OBJECTIVES", 30, EMBER, true))
	var list: Array = []
	var m := get_parent()
	if m and m.has_method("get_objectives"):
		list = m.get_objectives()
	if list.is_empty():
		_panel_body.add_child(_label("Survive the night.", 18, MUTED, true))
	for it in list:
		var done: bool = it.get("done", false)
		var mark := "✓  " if done else "•  "
		_panel_body.add_child(_label(mark + str(it.get("text", "")), 20, MUTED if done else BONE, false))
	_panel_body.add_child(_button("Back", func(): _show_panel(false)))
	_show_panel(true)


func _show_howto() -> void:
	_clear_panel()
	_panel_body.add_child(_label("HOW TO PLAY", 30, EMBER, true))
	for row in MECHANICS:
		_panel_body.add_child(_row(row[0], row[1]))
	_panel_body.add_child(_label("CONTROLS", 24, EMBER, true))
	for row in CONTROLS:
		_panel_body.add_child(_row(row[0], row[1]))
	_panel_body.add_child(_button("Back", func(): _show_panel(false)))
	_show_panel(true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if is_open and _panel.visible:
			_show_panel(false)
		else:
			set_open(not is_open)
		get_viewport().set_input_as_handled()


func set_open(v: bool) -> void:
	is_open = v
	_root.visible = v
	get_tree().paused = v
	if v:
		_show_panel(false)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _show_panel(v: bool) -> void:
	_panel.visible = v
	_menu.visible = not v


func _on_restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_quit_lobby() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")


# ---------------------------------------------------------------- widgets (themed via Ui)
func _label(text: String, font_px: int, color: Color, centered: bool) -> Label:
	return Ui.label(text, font_px, color, centered)


func _button(text: String, cb: Callable) -> Button:
	return Ui.button(text, cb)
