extends CanvasLayer

var _root: Control
var _content_vbox: VBoxContainer

var _objectives: Array = []
var _notes: Array = []
var _prev_mouse: Input.MouseMode = Input.MOUSE_MODE_CAPTURED


func _ready() -> void:
	layer = 8
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.hide()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	_root.add_child(Ui.dim(0.55))
	_root.add_child(Ui.vignette())

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	# the journal itself: a procedurally aged parchment page
	var paper: PanelContainer = PanelContainer.new()
	paper.add_theme_stylebox_override("panel", Ui.paper_panel(24))
	center.add_child(paper)

	var outer_vbox: VBoxContainer = VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 12)
	paper.add_child(outer_vbox)

	var title: Label = Ui.heading("JOURNAL")
	title.add_theme_color_override("font_color", Ui.INK)
	outer_vbox.add_child(title)
	outer_vbox.add_child(Ui.divider(200.0, 0.5))

	_content_vbox = VBoxContainer.new()
	_content_vbox.add_theme_constant_override("separation", 8)
	outer_vbox.add_child(_content_vbox)

	var close: Button = Ui.button("Close", func() -> void: toggle())
	close.add_theme_color_override("font_color", Ui.INK)
	close.add_theme_color_override("font_hover_color", Color("8a4a1e"))
	outer_vbox.add_child(close)


func _rebuild_content() -> void:
	for ch: Node in _content_vbox.get_children():
		ch.queue_free()

	_section("OBJECTIVES")

	if _objectives.is_empty():
		_content_vbox.add_child(Ui.label("No objectives yet.", 16, Ui.INK_MUTED))
	else:
		for obj: Dictionary in _objectives:
			var obj_text: String = obj.get("text", "")
			var obj_done: bool = obj.get("done", false)
			var prefix: String = "✓ " if obj_done else "• "
			var obj_color: Color = Ui.INK_MUTED if obj_done else Ui.INK
			_content_vbox.add_child(Ui.label(prefix + obj_text, 16, obj_color))

	_content_vbox.add_child(Ui.divider(160.0, 0.3))
	_section("NOTES")

	if _notes.is_empty():
		_content_vbox.add_child(Ui.label("Nothing written yet.", 16, Ui.INK_MUTED))
	else:
		for note: String in _notes:
			_content_vbox.add_child(Ui.label(note, 16, Ui.INK))

	_content_vbox.add_child(Ui.divider(160.0, 0.3))
	_section("MAP")
	_content_vbox.add_child(Ui.label("A hand-drawn map will fill in here. (coming soon)", 16, Ui.INK_MUTED))


## A small section caption on the paper, in faded ink with the inscription font.
func _section(text: String) -> void:
	var cap: Label = Ui.label(text, 14, Ui.INK_MUTED)
	cap.add_theme_constant_override("outline_size", 0)
	var f: Font = Ui.HEAD
	if f != null:
		cap.add_theme_font_override("font", f)
	_content_vbox.add_child(cap)


func set_content(objectives: Array, notes: Array) -> void:
	_objectives = objectives
	_notes = notes
	if _root.visible:
		_rebuild_content()


func toggle() -> void:
	if _root.visible:
		_root.hide()
		Input.mouse_mode = _prev_mouse   # restore (captured in-game, visible in menus)
	else:
		_prev_mouse = Input.mouse_mode
		_rebuild_content()
		_root.show()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("journal"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if _root.visible and event.is_action_pressed("ui_cancel"):
		toggle()
		get_viewport().set_input_as_handled()
