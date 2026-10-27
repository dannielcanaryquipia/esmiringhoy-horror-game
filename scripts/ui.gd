extends Node
## Shared UI theme + widget factory. Autoload name: `Ui`.
## One source of truth for the lobby, HUD, pause menu and end screens, so they stop
## each re-declaring the same palette and button/label builders.

# Palette from the design board (00 · Overview).
const VOID := Color("0e0c0c")         # background black
const BONE := Color("e9e2d8")         # main text
const MUTED := Color("a79c90")        # secondary text, labels
const SOFT := Color("c9bfb3")         # body text on dark panels
const EMBER := Color("ff5a1f")        # titles, accents (the demon's cracks)
const EMBER_SOFT := Color("ff7a45")   # hover / secondary accent
const BLOOD := Color("c8202a")        # demon eye — death, danger
const MOON := Color("7c9cc9")         # moonlight — calm meters (breath)
const FLASH := Color("f2e6c8")        # flashlight beam
const PANEL := Color("151111")        # board card fill
const PANEL_HOVER := Color("1a1210")  # board "ember" card fill
const PANEL_EDGE := Color("2e2622")   # board card border
# Ink colors for text sitting on the light paper surfaces (journal, panels).
const INK := Color(0.27, 0.19, 0.12)
const INK_MUTED := Color(0.46, 0.37, 0.28)

# Typography from the design board (bundled, SIL Open Font License — see
# assets/fonts/licenses):
#   HEAD — IM Fell English: titles, big messages, buttons (the old-print serif)
#   BODY — Inter: everything you read
#   MONO — JetBrains Mono: small tracked uppercase labels (BATTERY, CANDLES …)
const FONT_DIR := "res://assets/fonts/"
const HEAD_MIN_PX := 28                # labels this big or larger use the serif
var BODY: FontVariation
var BODY_BOLD: FontVariation
var HEAD: FontVariation
var HEAD_ITALIC: FontVariation
var MONO: FontVariation


## Build the themed fonts and register custom input actions once at startup.
func _ready() -> void:
	BODY = _font_variant("Inter-Variable.ttf", 400)
	BODY_BOLD = _font_variant("Inter-Variable.ttf", 600)
	HEAD = _font_variant("IMFellEnglish-Regular.ttf", 0)
	HEAD_ITALIC = _font_variant("IMFellEnglish-Italic.ttf", 0)
	MONO = _font_variant("JetBrainsMono-Variable.ttf", 500)
	MONO.spacing_glyph = 2               # the board's wide letter-spacing on labels
	MONO.spacing_space = 2
	HEAD.spacing_glyph = 1
	# any Control that doesn't pick a font (sliders, line edits, popups) gets Inter too
	ThemeDB.fallback_font = BODY

	if not InputMap.has_action("journal"):
		InputMap.add_action("journal")
		for k in [KEY_J, KEY_TAB]:
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event("journal", e)


## Load a bundled font as a FontVariation. `weight` sets the wght axis of a
## variable font (0 = leave as is). Falls back to Godot's built-in font if missing.
func _font_variant(file: String, weight: int) -> FontVariation:
	var fv := FontVariation.new()
	var path := FONT_DIR + file
	if ResourceLoader.exists(path):
		fv.base_font = load(path)
		if weight > 0:
			var ts := TextServerManager.get_primary_interface()
			fv.variation_opentype = {ts.name_to_tag("wght"): weight}
	else:
		push_warning("Ui: missing font " + path + ", using the default font")
		fv.base_font = ThemeDB.fallback_font
	return fv


## A text label. Big sizes (≥ HEAD_MIN_PX) get the IM Fell English serif like the
## board's titles; everything else is Inter.
func label(text: String, font_px: int, color: Color, centered := false) -> Label:
	var l := Label.new()
	l.text = text
	var f: Font = HEAD if font_px >= HEAD_MIN_PX else BODY
	if f != null:
		l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", font_px)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 5)
	l.add_theme_color_override("font_outline_color", Color(0.02, 0.01, 0.0, 0.95))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if centered:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


## A small uppercase label in JetBrains Mono with wide tracking — the board's
## "01 · DARK ROOM" / "PALETTE" caption style. Used for HUD captions.
func mono(text: String, font_px: int, color: Color, centered := false) -> Label:
	var l := label(text.to_upper(), font_px, color, centered)
	if MONO != null:
		l.add_theme_font_override("font", MONO)
	l.add_theme_constant_override("outline_size", 4)
	return l


func heading(text: String, font_px := 32) -> Label:
	var l := label(text, font_px, EMBER, true)
	if HEAD != null:
		l.add_theme_font_override("font", HEAD)
	l.add_theme_constant_override("outline_size", 8)
	return l


func button(text: String, cb: Callable, width := 260) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 46)
	b.focus_mode = Control.FOCUS_NONE
	if HEAD != null:
		b.add_theme_font_override("font", HEAD)
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", BONE)
	b.add_theme_color_override("font_hover_color", EMBER)
	b.add_theme_color_override("font_pressed_color", EMBER_SOFT)
	for s in ["normal", "hover", "pressed", "disabled"]:
		# board-style cards: dark fill, thin warm edge, ember edge on hover
		var sb := StyleBoxFlat.new()
		sb.bg_color = PANEL_HOVER if s == "hover" or s == "pressed" else PANEL
		sb.set_content_margin_all(8)
		sb.set_corner_radius_all(4)
		sb.border_color = Color(EMBER, 0.7) if s == "hover" or s == "pressed" else PANEL_EDGE
		sb.set_border_width_all(1)
		b.add_theme_stylebox_override(s, sb)
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


## A full-screen dim backdrop for modal panels.
func dim(alpha := 0.78) -> ColorRect:
	var d := ColorRect.new()
	d.set_anchors_preset(Control.PRESET_FULL_RECT)
	d.color = Color(0, 0, 0, alpha)
	return d


## A labelled key/value row (controls lists, mechanics, stats).
func row(key: String, val: String, key_w := 170) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	var k := label(key, 17, EMBER, false)
	k.custom_minimum_size = Vector2(key_w, 24)
	h.add_child(k)
	var d := label(val, 16, MUTED, false)
	d.custom_minimum_size = Vector2(400, 0)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(d)
	return h


## A labelled horizontal slider that reports changes through `on_change`.
func slider(text: String, min_v: float, max_v: float, step: float, value: float, on_change: Callable) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	var cap := label(text, 15, BONE, false)
	v.add_child(cap)
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(320, 20)
	s.value_changed.connect(func(nv: float) -> void: on_change.call(nv))
	v.add_child(s)
	return v


# ------------------------------------------------------------------ paper surfaces
# Everything here is generated in code (brief rule 6: no downloaded assets).

var _paper_tex: Texture2D


## An aged-paper texture: warm base, film grain, a few soft water stains.
func paper_texture() -> Texture2D:
	if _paper_tex != null:
		return _paper_tex
	var img := Image.create(160, 160, false, Image.FORMAT_RGBA8)
	var base := Color(0.72, 0.65, 0.52)
	for y in 160:
		for x in 160:
			var n := (randf() - 0.5) * 0.09 + 0.03 * sin(x * 0.21) * sin(y * 0.17)
			img.set_pixel(x, y, Color(base.r + n, base.g + n, base.b + n * 0.8, 1.0))
	# soft dark stains
	for i in 7:
		var cx := randf_range(10.0, 150.0)
		var cy := randf_range(10.0, 150.0)
		var rad := randf_range(9.0, 22.0)
		var stain := randf_range(0.04, 0.11)
		for y in range(maxi(int(cy - rad), 0), mini(int(cy + rad), 159)):
			for x in range(maxi(int(cx - rad), 0), mini(int(cx + rad), 159)):
				var c := img.get_pixel(x, y)
				var d := Vector2(x - cx, y - cy).length() / rad
				var fall := (1.0 - d) * (1.0 - d)
				img.set_pixel(x, y, Color(c.r - stain * fall, c.g - stain * fall, c.b - stain * fall, 1.0))
	_paper_tex = ImageTexture.create_from_image(img)
	return _paper_tex


## A parchment panel StyleBox for the journal and menu panels.
func paper_panel(pad := 16.0) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = paper_texture()
	sb.set_texture_margin_all(10.0)
	sb.set_content_margin_all(pad)
	return sb


## A soft radial vignette (transparent centre, black edges) as a full-screen rect.
## Sits under menus for depth; a CanvasLayer/Control child handles placement.
func vignette(applied_albedo := 0.5) -> TextureRect:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.55, 1.0])
	grad.colors = PackedColorArray([Color(0, 0, 0, 0.0), Color(0, 0, 0, applied_albedo)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 1.4)
	tex.width = 512
	tex.height = 512
	var rect := TextureRect.new()
	rect.texture = tex
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## A thin ember divider line, for section breaks on paper or menus.
func divider(width := 180.0, alpha := 0.45) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(EMBER, alpha)
	r.custom_minimum_size = Vector2(width, 2)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r
