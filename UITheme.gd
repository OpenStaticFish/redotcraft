class_name UITheme

const INK := Color("#f4f0df")
const MUTED := Color("#b8c7c1")
const TEAL := Color("#8bd3c7")
const PANEL := Color(0.035, 0.07, 0.085, 0.92)
const PANEL_LIGHT := Color(0.08, 0.14, 0.16, 0.94)
const BORDER := Color(0.45, 0.75, 0.7, 0.35)
const FOCUS := Color(0.55, 0.83, 0.78, 0.9)


static func panel_style(color: Color, border_color: Color = BORDER, border_width: int = 1, radius: int = 8) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 9.0
	style.content_margin_bottom = 9.0
	return style


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 17

	var button_normal := panel_style(PANEL_LIGHT)
	button_normal.content_margin_top = 10.0
	button_normal.content_margin_bottom = 10.0
	var button_hover := panel_style(Color(0.12, 0.24, 0.26, 0.96), FOCUS)
	button_hover.content_margin_top = 10.0
	button_hover.content_margin_bottom = 10.0
	var button_pressed := panel_style(Color(0.05, 0.11, 0.13, 0.98), TEAL)
	button_pressed.content_margin_top = 10.0
	button_pressed.content_margin_bottom = 10.0
	var button_disabled := panel_style(Color(0.06, 0.09, 0.1, 0.7), Color(0.3, 0.35, 0.35, 0.3))
	var button_focus := panel_style(Color(0, 0, 0, 0), FOCUS, 2)
	button_focus.draw_center = false

	theme.set_stylebox("normal", "Button", button_normal)
	theme.set_stylebox("hover", "Button", button_hover)
	theme.set_stylebox("pressed", "Button", button_pressed)
	theme.set_stylebox("disabled", "Button", button_disabled)
	theme.set_stylebox("focus", "Button", button_focus)
	theme.set_color("font_color", "Button", INK)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", TEAL)
	theme.set_color("font_disabled_color", "Button", Color(0.5, 0.55, 0.55, 0.6))
	theme.set_font_size("font_size", "Button", 18)

	theme.set_stylebox("panel", "PanelContainer", panel_style(PANEL))
	theme.set_stylebox("panel", "Panel", panel_style(PANEL))

	theme.set_color("font_color", "Label", INK)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.6))
	theme.set_constant("shadow_offset_x", "Label", 1)
	theme.set_constant("shadow_offset_y", "Label", 2)

	theme.set_stylebox("normal", "LineEdit", panel_style(Color(0.02, 0.05, 0.06, 0.92), BORDER, 1, 6))
	theme.set_stylebox("focus", "LineEdit", panel_style(Color(0.03, 0.07, 0.08, 0.95), FOCUS, 2, 6))
	theme.set_stylebox("read_only", "LineEdit", panel_style(Color(0.04, 0.06, 0.07, 0.7), BORDER, 1, 6))
	theme.set_color("font_color", "LineEdit", INK)
	theme.set_color("font_placeholder_color", "LineEdit", Color(0.7, 0.76, 0.74, 0.5))
	theme.set_color("caret_color", "LineEdit", TEAL)
	theme.set_color("selection_color", "LineEdit", Color(0.55, 0.83, 0.78, 0.35))
	theme.set_constant("minimum_character_width", "LineEdit", 8)

	theme.set_stylebox("normal", "OptionButton", button_normal)
	theme.set_stylebox("hover", "OptionButton", button_hover)
	theme.set_stylebox("pressed", "OptionButton", button_pressed)
	theme.set_stylebox("disabled", "OptionButton", button_disabled)
	theme.set_stylebox("focus", "OptionButton", button_focus)
	theme.set_color("font_color", "OptionButton", INK)
	theme.set_color("font_hover_color", "OptionButton", Color.WHITE)
	theme.set_color("font_pressed_color", "OptionButton", TEAL)
	theme.set_font_size("font_size", "OptionButton", 17)

	theme.set_stylebox("panel", "PopupMenu", panel_style(PANEL))
	theme.set_stylebox("hover", "PopupMenu", panel_style(Color(0.12, 0.24, 0.26, 0.96), FOCUS, 1, 4))
	theme.set_color("font_color", "PopupMenu", INK)
	theme.set_color("font_hover_color", "PopupMenu", Color.WHITE)

	var slider_bg := StyleBoxFlat.new()
	slider_bg.bg_color = Color(0.02, 0.05, 0.06, 0.92)
	slider_bg.set_corner_radius_all(3)
	slider_bg.content_margin_top = 5.0
	slider_bg.content_margin_bottom = 5.0
	theme.set_stylebox("slider", "HSlider", slider_bg)
	var slider_grabber := StyleBoxFlat.new()
	slider_grabber.bg_color = TEAL
	slider_grabber.set_corner_radius_all(3)
	theme.set_stylebox("grabber_area", "HSlider", slider_grabber)
	theme.set_stylebox("grabber_area_highlight", "HSlider", slider_grabber)

	theme.set_color("font_color", "CheckBox", INK)
	theme.set_color("font_hover_color", "CheckBox", Color.WHITE)
	theme.set_font_size("font_size", "CheckBox", 17)

	return theme


static func heading(text: String, size: int = 34) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", TEAL)
	return label


static func muted_label(text: String, size: int = 15) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", MUTED)
	return label
