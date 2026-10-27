extends CanvasLayer

signal retry
signal to_title

var _root: Control
var _backdrop: ColorRect
var _title_label: Label
var _msg_vbox: VBoxContainer


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_root.visible = false


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	# Full-rect backdrop via Ui.dim; keep a reference so we can retint it
	_backdrop = Ui.dim(0.78)
	_root.add_child(_backdrop)

	# Centred outer container
	var outer: VBoxContainer = VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_CENTER)
	outer.grow_horizontal = Control.GROW_DIRECTION_BOTH
	outer.grow_vertical = Control.GROW_DIRECTION_BOTH
	outer.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_theme_constant_override("separation", 16)
	_root.add_child(outer)

	# Title label — placeholder text; overwritten in show_death / show_win
	_title_label = Ui.heading("", 54)
	outer.add_child(_title_label)

	# Message / stats rows
	_msg_vbox = VBoxContainer.new()
	_msg_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_msg_vbox.add_theme_constant_override("separation", 8)
	outer.add_child(_msg_vbox)

	# Spacer
	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 24.0)
	outer.add_child(spacer)

	# Button row
	var btn_row: HBoxContainer = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 20)
	outer.add_child(btn_row)

	var btn_retry: Button = Ui.button("Try Again", _on_retry_pressed, 260)
	btn_retry.process_mode = Node.PROCESS_MODE_ALWAYS
	btn_row.add_child(btn_retry)

	var btn_title: Button = Ui.button("Quit to Title", _on_title_pressed, 260)
	btn_title.process_mode = Node.PROCESS_MODE_ALWAYS
	btn_row.add_child(btn_title)


func _clear_msg_rows() -> void:
	for child: Node in _msg_vbox.get_children():
		child.queue_free()


func show_death(cause: String) -> void:
	_clear_msg_rows()

	_backdrop.color = Color(0.12, 0.0, 0.0, 0.86)

	_title_label.text = "NATAGPUAN KA."
	_title_label.add_theme_color_override("font_color", Ui.BLOOD)
	_title_label.add_theme_font_size_override("font_size", 54)

	var sub_label: Label = Ui.label("You were found.", 20, Ui.MUTED, true)
	_msg_vbox.add_child(sub_label)

	var cause_label: Label = Ui.label(cause, 20, Ui.BONE, true)
	_msg_vbox.add_child(cause_label)

	_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func show_win(stats: Array) -> void:
	_clear_msg_rows()

	_backdrop.color = Color(0.0, 0.0, 0.0, 0.86)

	_title_label.text = "BANISHED"
	_title_label.add_theme_color_override("font_color", Ui.EMBER)
	_title_label.add_theme_font_size_override("font_size", 54)

	for entry: Variant in stats:
		var stat_label: Label = Ui.label(str(entry), 20, Ui.BONE, true)
		_msg_vbox.add_child(stat_label)

	_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func hide_screen() -> void:
	_root.visible = false


func _on_retry_pressed() -> void:
	emit_signal("retry")


func _on_title_pressed() -> void:
	emit_signal("to_title")
