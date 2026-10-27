extends CanvasLayer

signal closed

var _root: Control

func _ready() -> void:
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.hide()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var backdrop: ColorRect = Ui.dim()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(backdrop)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	center.add_child(vbox)

	vbox.add_child(Ui.heading("SETTINGS"))

	vbox.add_child(Ui.slider(
		"Mouse sensitivity",
		0.0005, 0.006, 0.0001,
		Settings.mouse_sens,
		func(v: float) -> void: Settings.set_sens(v)
	))

	var invert_row: HBoxContainer = HBoxContainer.new()
	invert_row.add_theme_constant_override("separation", 10)
	vbox.add_child(invert_row)

	var invert_label: Label = Ui.label("Invert look Y", 18, Ui.BONE)
	invert_row.add_child(invert_label)

	var invert_btn: CheckButton = CheckButton.new()
	invert_btn.button_pressed = Settings.invert_y
	invert_btn.toggled.connect(func(pressed: bool) -> void: Settings.set_invert(pressed))
	invert_row.add_child(invert_btn)

	vbox.add_child(Ui.slider(
		"Field of view",
		60.0, 90.0, 1.0,
		Settings.fov,
		func(v: float) -> void: Settings.set_fov(v)
	))

	vbox.add_child(Ui.slider(
		"Master volume",
		0.0, 1.0, 0.01,
		Settings.master_volume,
		func(v: float) -> void: Settings.set_master(v)
	))

	vbox.add_child(Ui.slider(
		"Brightness",
		0.5, 1.5, 0.01,
		Settings.brightness,
		func(v: float) -> void: Settings.set_brightness(v)
	))

	vbox.add_child(Ui.button("Back", func() -> void: close()))


func open() -> void:
	_root.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	_root.hide()
	emit_signal("closed")


func _unhandled_input(event: InputEvent) -> void:
	if _root.visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
