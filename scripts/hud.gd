extends CanvasLayer
## On-screen HUD: battery meter, crosshair dot, candle counter, interact prompt, messages.

const BONE := Color("e9e2d8")
const MUTED := Color("a79c90")
const EMBER := Color("ff5a1f")   # design-board ember (same as Ui.EMBER)
const MOON := Color("7c9cc9")    # design-board moonlight

var _bars: Array[ColorRect] = []
var _candles: Label
var _crouch: Label
var _prompt: Label
var _progress: ProgressBar
var _dot: ColorRect
var _title: Label
var _sub: Label
var _msg_tween: Tween
var _breath: ProgressBar
var _breath_label: Label
var _hide_hint: Label
var _obj_box: VBoxContainer
var _obj_sig := ""


func _ready() -> void:
	layer = 2
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# battery: five bars, bottom-left
	var batt := HBoxContainer.new()
	batt.add_theme_constant_override("separation", 4)
	batt.anchor_top = 1.0
	batt.anchor_bottom = 1.0
	batt.offset_left = 28
	batt.offset_top = -50
	batt.offset_bottom = -28
	batt.alignment = BoxContainer.ALIGNMENT_BEGIN
	root.add_child(batt)
	var icon := Ui.mono("Battery", 12, MUTED)
	batt.add_child(icon)
	for i in 5:
		var b := ColorRect.new()
		b.custom_minimum_size = Vector2(12, 18)
		b.color = BONE
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		batt.add_child(b)
		_bars.append(b)

	# candles: top-left
	_candles = Ui.mono("Candles  0 / 2", 15, BONE)
	_candles.position = Vector2(28, 24)
	root.add_child(_candles)

	# crouch indicator, just above the battery
	_crouch = Ui.mono("Crouched", 12, EMBER)
	_crouch.anchor_top = 1.0
	_crouch.anchor_bottom = 1.0
	_crouch.offset_left = 28
	_crouch.offset_top = -72
	_crouch.offset_bottom = -54
	_crouch.visible = false
	root.add_child(_crouch)

	# crosshair dot
	_dot = ColorRect.new()
	_dot.size = Vector2(4, 4)
	_dot.color = Color(BONE, 0.7)
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dot.anchor_left = 0.5
	_dot.anchor_top = 0.5
	_dot.anchor_right = 0.5
	_dot.anchor_bottom = 0.5
	_dot.offset_left = -2
	_dot.offset_top = -2
	_dot.offset_right = 2
	_dot.offset_bottom = 2
	root.add_child(_dot)

	# interact prompt + hold progress, just under the crosshair
	_prompt = _label("Hold E to light the candle", 16, BONE)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.set_anchors_preset(Control.PRESET_CENTER)
	_prompt.offset_left = -200
	_prompt.offset_right = 200
	_prompt.offset_top = 30
	_prompt.offset_bottom = 54
	_prompt.visible = false
	root.add_child(_prompt)
	_progress = ProgressBar.new()
	_progress.set_anchors_preset(Control.PRESET_CENTER)
	_progress.offset_left = -80
	_progress.offset_right = 80
	_progress.offset_top = 60
	_progress.offset_bottom = 66
	_progress.show_percentage = false
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress.max_value = 1.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = EMBER
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	_progress.add_theme_stylebox_override("fill", fill)
	_progress.add_theme_stylebox_override("background", bg)
	_progress.visible = false
	root.add_child(_progress)

	# big centred message
	_title = _label("", 54, BONE)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.set_anchors_preset(Control.PRESET_CENTER)
	_title.offset_left = -600
	_title.offset_right = 600
	_title.offset_top = -120
	_title.offset_bottom = -50
	_title.modulate.a = 0.0
	root.add_child(_title)
	_sub = _label("", 20, MUTED)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.set_anchors_preset(Control.PRESET_CENTER)
	_sub.offset_left = -600
	_sub.offset_right = 600
	_sub.offset_top = -40
	_sub.offset_bottom = -10
	_sub.modulate.a = 0.0
	root.add_child(_sub)

	# a hiding hint, centred low
	_hide_hint = _label("", 16, BONE)
	_hide_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hide_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hide_hint.offset_left = -300
	_hide_hint.offset_right = 300
	_hide_hint.offset_top = -120
	_hide_hint.offset_bottom = -96
	_hide_hint.visible = false
	root.add_child(_hide_hint)

	# breath meter, just under the hiding hint
	_breath_label = Ui.mono("Hold breath  [Space]", 12, EMBER)
	_breath_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_breath_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_breath_label.offset_left = -120
	_breath_label.offset_right = 120
	_breath_label.offset_top = -92
	_breath_label.offset_bottom = -74
	_breath_label.visible = false
	root.add_child(_breath_label)
	_breath = ProgressBar.new()
	_breath.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_breath.offset_left = -80
	_breath.offset_right = 80
	_breath.offset_top = -72
	_breath.offset_bottom = -66
	_breath.show_percentage = false
	_breath.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_breath.max_value = 1.0
	_breath.value = 1.0
	var bfill := StyleBoxFlat.new()
	bfill.bg_color = MOON
	var bbg := StyleBoxFlat.new()
	bbg.bg_color = Color(0, 0, 0, 0.5)
	_breath.add_theme_stylebox_override("fill", bfill)
	_breath.add_theme_stylebox_override("background", bbg)
	_breath.visible = false
	root.add_child(_breath)

	# objective tracker, top-right, on a translucent panel with an ember edge
	var tracker := PanelContainer.new()
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color(Ui.PANEL, 0.72)
	tsb.border_color = Color(EMBER, 0.35)
	tsb.border_width_left = 2
	tsb.set_corner_radius_all(2)
	tsb.content_margin_left = 14.0
	tsb.content_margin_right = 14.0
	tsb.content_margin_top = 8.0
	tsb.content_margin_bottom = 10.0
	tracker.add_theme_stylebox_override("panel", tsb)
	tracker.anchor_left = 1.0
	tracker.anchor_right = 1.0
	tracker.offset_left = -330
	tracker.offset_right = -20
	tracker.offset_top = 18
	tracker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tracker)
	_obj_box = VBoxContainer.new()
	_obj_box.add_theme_constant_override("separation", 2)
	_obj_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	tracker.add_child(_obj_box)
	var head := Ui.mono("Objectives", 12, MUTED)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_obj_box.add_child(head)


## Rebuild the top-right task list. `items` = [{text, done}]. Only rebuilds on change.
func set_objectives(items: Array) -> void:
	var sig := ""
	for it in items:
		sig += str(it.get("text", "")) + ("1" if it.get("done", false) else "0") + "|"
	if sig == _obj_sig:
		return
	_obj_sig = sig
	# drop the old rows (keep child 0, the "OBJECTIVES" header)
	while _obj_box.get_child_count() > 1:
		var n := _obj_box.get_child(_obj_box.get_child_count() - 1)
		_obj_box.remove_child(n)
		n.queue_free()
	for it in items:
		var done: bool = it.get("done", false)
		var mark := "✓ " if done else "• "
		var row := _label(mark + str(it.get("text", "")), 15, MUTED if done else BONE)
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_obj_box.add_child(row)


func _label(text: String, font_px: int, color: Color) -> Label:
	return Ui.label(text, font_px, color)


func set_battery(pct: float, on: bool) -> void:
	var lit_bars := ceili(pct * 5.0)
	for i in 5:
		var c := BONE if i < lit_bars else Color(BONE, 0.15)
		if pct < 0.2 and i < lit_bars:
			c = EMBER
		if not on:
			c.a *= 0.4
		_bars[i].color = c


func set_candles(lit_count: int, total: int) -> void:
	_candles.text = "CANDLES  %d / %d" % [lit_count, total]
	if lit_count > 0:
		_candles.add_theme_color_override("font_color", EMBER)


func set_crouched(crouched: bool) -> void:
	_crouch.visible = crouched


func set_prompt(visible_now: bool, progress: float, prompt_text := "") -> void:
	if prompt_text != "":
		_prompt.text = prompt_text
	_prompt.visible = visible_now
	_progress.visible = visible_now and progress > 0.0
	_progress.value = progress


func set_crosshair(visible_now: bool) -> void:
	_dot.visible = visible_now


## One call per frame for the whole hiding UI.
## can_hide: looking at a spot you can enter. is_hidden: currently tucked in.
## near: the demon is close enough that breath matters.
func set_hide_state(can_hide: bool, is_hidden: bool, near: bool, breath: float) -> void:
	if is_hidden:
		_hide_hint.visible = true
		_hide_hint.text = "IT'S HERE — [Space] hold your breath" if near else "[E] climb out"
		_hide_hint.add_theme_color_override("font_color", EMBER if near else MUTED)
	elif can_hide:
		_hide_hint.visible = true
		_hide_hint.text = "[E] Hide here"
		_hide_hint.add_theme_color_override("font_color", BONE)
	else:
		_hide_hint.visible = false
	_breath.visible = is_hidden and near
	_breath_label.visible = is_hidden and near
	_breath.value = breath
	_breath.get_theme_stylebox("fill").bg_color = EMBER if breath < 0.3 else MOON


## Show a message; hold <= 0 keeps it up until the next message.
func message(title: String, sub := "", hold := 4.0) -> void:
	if _msg_tween:
		_msg_tween.kill()
	_title.text = title
	_sub.text = sub
	_msg_tween = create_tween()
	_msg_tween.tween_property(_title, "modulate:a", 1.0, 0.8)
	_msg_tween.parallel().tween_property(_sub, "modulate:a", 1.0, 1.2)
	if hold > 0.0:
		_msg_tween.tween_interval(hold)
		_msg_tween.tween_property(_title, "modulate:a", 0.0, 1.2)
		_msg_tween.parallel().tween_property(_sub, "modulate:a", 0.0, 1.2)
