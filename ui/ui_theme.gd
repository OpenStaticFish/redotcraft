class_name UITheme
extends RefCounted

## "Deepslate & Ember" shared UI theme.
##
## Dark mineral/slate surfaces, one warm ember accent for actions and
## selection, a restrained cyan for readouts, and a subsetted Iosevka family
## (monospace, so every value column stays tabular). Everything is built
## procedurally so no binary theme resources need to ship.

# ---------------------------------------------------------------- palette --
const INK := Color("#ece7da")        # warm parchment — primary text
const INK_DIM := Color("#c7c1b2")    # secondary text
const MUTED := Color("#8b9aa0")      # slate — hints, eyebrows
const FAINT := Color("#5c6a70")      # disabled, key badges
const EMBER := Color("#e8a25c")      # warm amber — actions / selection
const EMBER_HI := Color("#f6c084")   # amber highlight (hover text)
const EMBER_DEEP := Color("#b97a3a") # amber pressed
const EMBER_INK := Color("#241507")  # text on amber fills
const CYAN := Color("#72c6bc")       # restrained status accent
const CYAN_DIM := Color("#4e8b84")
const SURFACE := Color("#0e1519")    # modal panels
const SURFACE_HI := Color("#16212a") # raised controls
const SURFACE_LOW := Color("#0a1014") # wells, inputs
const LINE := Color("#263540")       # hairlines
const LINE_HI := Color("#3b515c")
const VOID := Color("#05080a")       # dim backdrops
const WARN := Color("#e8b46a")

# Legacy aliases (worldgen overlay, HUD) keep compiling against the old names.
const TEAL := CYAN
const PANEL := SURFACE
const PANEL_LIGHT := SURFACE_HI
const BORDER := LINE
const FOCUS := CYAN

const FONT_REGULAR_PATH := "res://assets/fonts/iosevka-regular.ttf"
const FONT_SEMI_PATH := "res://assets/fonts/iosevka-semi-bold.ttf"
const FONT_DISPLAY_PATH := "res://assets/fonts/iosevka-extra-bold.ttf"
const FONT_WORDMARK_PATH := "res://assets/fonts/iosevka-extended-extra-bold.ttf"

const SIZE_BODY := 16
const SIZE_VALUE := 15
const SIZE_EYEBROW := 12
const SIZE_DISPLAY := 26
const SIZE_WORDMARK := 56

const TEXT_SCALE_DEFAULT := 1.0
const TEXT_SCALE_MIN := 0.5
const TEXT_SCALE_MAX := 2.0

static var _cached_theme: Theme
static var _cached_theme_scale := -1.0
static var _cached_body: Font
static var _cached_semi: Font
static var _cached_display: Font
static var _cached_wordmark: Font
static var _cached_eyebrow_font: FontVariation
static var _cached_check_off: ImageTexture
static var _cached_check_on: ImageTexture
static var _cached_switch_off: ImageTexture
static var _cached_switch_on: ImageTexture
static var _cached_grabber: ImageTexture
static var _cached_grabber_hi: ImageTexture
static var _theme_hosts: Array[WeakRef] = []
static var _game_config: Node


# ------------------------------------------------------------------ fonts --
static func font_body() -> Font:
	if _cached_body == null:
		_cached_body = load(FONT_REGULAR_PATH) as Font
	return _cached_body


static func font_semi() -> Font:
	if _cached_semi == null:
		_cached_semi = load(FONT_SEMI_PATH) as Font
	return _cached_semi


static func font_display() -> Font:
	if _cached_display == null:
		_cached_display = load(FONT_DISPLAY_PATH) as Font
	return _cached_display


static func font_wordmark() -> Font:
	if _cached_wordmark == null:
		_cached_wordmark = load(FONT_WORDMARK_PATH) as Font
	return _cached_wordmark


## SemiBold with positive glyph spacing — tracked-out small caps.
static func font_eyebrow(spacing: int = 2) -> FontVariation:
	if _cached_eyebrow_font == null:
		var variation := FontVariation.new()
		variation.base_font = font_semi()
		variation.spacing_glyph = spacing
		_cached_eyebrow_font = variation
	return _cached_eyebrow_font


# -------------------------------------------------------------- text scale --
## Text size is a multiplier on every font size in the UI, independent of the
## window content scale that sizes the whole interface. GameConfig is resolved
## through the scene tree (and cached; the node reads live settings) so the
## theme keeps no autoload compile dependency.
static func _game_config_node() -> Node:
	if _game_config != null and is_instance_valid(_game_config):
		return _game_config
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	_game_config = tree.root.get_node_or_null("GameConfig")
	return _game_config


static func text_scale() -> float:
	var config := _game_config_node()
	if config == null or not config.has_method("get_text_scale"):
		return TEXT_SCALE_DEFAULT
	return clampf(float(config.get_text_scale()), TEXT_SCALE_MIN, TEXT_SCALE_MAX)


## Base font size -> logical size. Every font-size override goes through this
## so a text-size change is one multiplier.
static func font_size(base: int) -> int:
	return maxi(1, roundi(float(base) * text_scale()))


## Applies a scaled font size and tags the control so `refresh_font_sizes()`
## can re-scale it when the text size changes.
static func apply_font_size(control: Control, base: int) -> void:
	control.set_meta("ui_base_font_size", base)
	control.add_theme_font_size_override("font_size", font_size(base))


static func refresh_font_sizes(root: Node) -> void:
	if root is Control and root.has_meta("ui_base_font_size"):
		(root as Control).add_theme_font_size_override("font_size", font_size(int(root.get_meta("ui_base_font_size"))))
	for child in root.get_children():
		refresh_font_sizes(child)


# ------------------------------------------------------------- theme hosts --
## Applies the shared theme to a screen host and remembers it, so a later
## text-size change can rebuild every live screen in one pass.
static func apply(host: Node) -> void:
	_ensure_scale_signal()
	if host.has_meta("ui_theme_host"):
		return
	host.set_meta("ui_theme_host", true)
	_theme_hosts.append(weakref(host))
	if host is Control:
		(host as Control).theme = build()


## Rebuilds the shared theme for every live host and re-scales tagged font
## sizes. Called when the UI or text scale changes.
static func refresh_all() -> void:
	var rebuilt := build()
	var live: Array[WeakRef] = []
	for ref in _theme_hosts:
		var host := ref.get_ref() as Node
		if host == null:
			continue
		live.append(ref)
		if host is Control:
			(host as Control).theme = rebuilt
		refresh_font_sizes(host)
	_theme_hosts = live


## One connection for the whole UI: any screen that applies the theme makes
## the text scale live. `build()` runs again on the same signal.
static func _ensure_scale_signal() -> void:
	var config := _game_config_node()
	if config == null or config.has_meta("ui_theme_signal"):
		return
	config.set_meta("ui_theme_signal", true)
	config.interface_scale_changed.connect(func() -> void: refresh_all())


# -------------------------------------------------------------- styleboxes --
static func panel_style(color: Color, border_color: Color = LINE, border_width: int = 1, radius: int = 10) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style


## The standard modal chrome: dark slate slab with hairline, drop shadow.
static func modal_style() -> StyleBoxFlat:
	var style := panel_style(Color(SURFACE.r, SURFACE.g, SURFACE.b, 0.97), LINE, 1, 12)
	style.content_margin_left = 22.0
	style.content_margin_right = 22.0
	style.content_margin_top = 18.0
	style.content_margin_bottom = 18.0
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.42)
	style.shadow_size = 18
	style.shadow_offset = Vector2(0, 8)
	return style


## Small HUD chip surface (instrument-cluster look); pair with accent_bar().
## Compact instrument chip used by the HUD readouts; padding stays tight so
## coords/stats occupy as little screen space as possible.
static func chip_style() -> StyleBoxFlat:
	var style := panel_style(Color(SURFACE.r, SURFACE.g, SURFACE.b, 0.88), LINE, 1, 7)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 5.0
	style.content_margin_bottom = 5.0
	return style


## Colored side bar overlaid on a chip (StyleBoxFlat has no per-side border
## colors, so the accent is a real ColorRect pinned to an edge).
static func accent_bar(accent: Color, side: int = 0) -> ColorRect:
	var bar := ColorRect.new()
	bar.color = accent
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if side == 1:
		bar.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
		bar.offset_left = -3.0
		bar.offset_right = 0.0
		bar.offset_top = 6.0
		bar.offset_bottom = -6.0
	else:
		bar.set_anchors_preset(Control.PRESET_LEFT_WIDE)
		bar.offset_left = 0.0
		bar.offset_right = 3.0
		bar.offset_top = 6.0
		bar.offset_bottom = -6.0
	return bar


static func divider(height: int = 1) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = Color(LINE.r, LINE.g, LINE.b, 0.9)
	rect.custom_minimum_size = Vector2(0, height)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


# ------------------------------------------------------------------ theme --
static func build() -> Theme:
	var scale := text_scale()
	if _cached_theme != null and is_equal_approx(scale, _cached_theme_scale):
		return _cached_theme
	_cached_theme_scale = scale
	var theme := Theme.new()
	theme.default_font = font_body()
	theme.default_font_size = font_size(SIZE_BODY)

	_button_styles(theme)
	_panel_styles(theme)
	_label_styles(theme)
	_line_edit_styles(theme)
	_popup_styles(theme)
	_slider_styles(theme)
	_check_styles(theme)
	_scroll_styles(theme)
	_tooltip_styles(theme)

	_cached_theme = theme
	return theme


static func _button_styles(theme: Theme) -> void:
	var normal := panel_style(Color(SURFACE_HI.r, SURFACE_HI.g, SURFACE_HI.b, 0.96), LINE_HI, 1, 8)
	normal.content_margin_left = 18.0
	normal.content_margin_right = 18.0
	normal.content_margin_top = 10.0
	normal.content_margin_bottom = 10.0
	var hover := panel_style(Color(0.128, 0.176, 0.208, 0.98), Color(EMBER.r, EMBER.g, EMBER.b, 0.55), 1, 8)
	hover.content_margin_left = 18.0
	hover.content_margin_right = 18.0
	hover.content_margin_top = 10.0
	hover.content_margin_bottom = 10.0
	var pressed := panel_style(Color(SURFACE_LOW.r, SURFACE_LOW.g, SURFACE_LOW.b, 0.98), Color(EMBER.r, EMBER.g, EMBER.b, 0.8), 1, 8)
	pressed.content_margin_left = 18.0
	pressed.content_margin_right = 18.0
	pressed.content_margin_top = 10.0
	pressed.content_margin_bottom = 10.0
	var disabled := panel_style(Color(SURFACE_HI.r, SURFACE_HI.g, SURFACE_HI.b, 0.4), Color(LINE.r, LINE.g, LINE.b, 0.4), 1, 8)
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color(0, 0, 0, 0)
	focus.border_color = Color(EMBER.r, EMBER.g, EMBER.b, 0.9)
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(10)
	focus.set_expand_margin_all(2.0)

	for type in ["Button", "OptionButton"]:
		theme.set_stylebox("normal", type, normal)
		theme.set_stylebox("hover", type, hover)
		theme.set_stylebox("pressed", type, pressed)
		theme.set_stylebox("disabled", type, disabled)
		theme.set_stylebox("focus", type, focus)
		theme.set_color("font_color", type, INK)
		theme.set_color("font_hover_color", type, Color("#fff7e8"))
		theme.set_color("font_pressed_color", type, EMBER_HI)
		theme.set_color("font_focus_color", type, INK)
		theme.set_color("font_disabled_color", type, Color(FAINT.r, FAINT.g, FAINT.b, 0.7))
		theme.set_font_size("font_size", type, font_size(SIZE_BODY))
	theme.set_font("font", "OptionButton", font_semi())
	theme.set_color("icon_modulate", "OptionButton", MUTED)


static func _panel_styles(theme: Theme) -> void:
	theme.set_stylebox("panel", "PanelContainer", modal_style())
	theme.set_stylebox("panel", "Panel", modal_style())


static func _label_styles(theme: Theme) -> void:
	theme.set_color("font_color", "Label", INK)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.55))
	theme.set_constant("shadow_offset_x", "Label", 0)
	theme.set_constant("shadow_offset_y", "Label", 1)


static func _line_edit_styles(theme: Theme) -> void:
	var normal := panel_style(Color(SURFACE_LOW.r, SURFACE_LOW.g, SURFACE_LOW.b, 0.95), LINE_HI, 1, 8)
	normal.content_margin_left = 12.0
	normal.content_margin_right = 12.0
	normal.content_margin_top = 8.0
	normal.content_margin_bottom = 8.0
	var focus := panel_style(Color("#0d1418"), Color(EMBER.r, EMBER.g, EMBER.b, 0.9), 2, 8)
	focus.content_margin_left = 12.0
	focus.content_margin_right = 12.0
	focus.content_margin_top = 8.0
	focus.content_margin_bottom = 8.0
	var read_only := panel_style(Color(SURFACE_LOW.r, SURFACE_LOW.g, SURFACE_LOW.b, 0.6), LINE, 1, 8)
	theme.set_stylebox("normal", "LineEdit", normal)
	theme.set_stylebox("focus", "LineEdit", focus)
	theme.set_stylebox("read_only", "LineEdit", read_only)
	theme.set_color("font_color", "LineEdit", INK)
	theme.set_color("font_placeholder_color", "LineEdit", Color(MUTED.r, MUTED.g, MUTED.b, 0.55))
	theme.set_color("caret_color", "LineEdit", EMBER)
	theme.set_color("selection_color", "LineEdit", Color(EMBER.r, EMBER.g, EMBER.b, 0.3))
	theme.set_font("font", "LineEdit", font_semi())
	theme.set_constant("minimum_character_width", "LineEdit", 6)


static func _popup_styles(theme: Theme) -> void:
	var panel := panel_style(Color(SURFACE.r, SURFACE.g, SURFACE.b, 0.99), LINE_HI, 1, 10)
	panel.content_margin_left = 6.0
	panel.content_margin_right = 6.0
	panel.content_margin_top = 6.0
	panel.content_margin_bottom = 6.0
	var item_hover := panel_style(Color(EMBER.r, EMBER.g, EMBER.b, 0.14), Color(EMBER.r, EMBER.g, EMBER.b, 0.45), 1, 6)
	item_hover.content_margin_left = 8.0
	item_hover.content_margin_right = 8.0
	item_hover.content_margin_top = 4.0
	item_hover.content_margin_bottom = 4.0
	var separator := StyleBoxFlat.new()
	separator.bg_color = Color(LINE.r, LINE.g, LINE.b, 0.9)
	separator.content_margin_top = 4.0
	separator.content_margin_bottom = 4.0
	theme.set_stylebox("panel", "PopupMenu", panel)
	theme.set_stylebox("hover", "PopupMenu", item_hover)
	theme.set_stylebox("separator", "PopupMenu", separator)
	theme.set_color("font_color", "PopupMenu", INK)
	theme.set_color("font_hover_color", "PopupMenu", EMBER_HI)
	theme.set_color("font_accelerator_color", "PopupMenu", MUTED)
	theme.set_font_size("font_size", "PopupMenu", font_size(SIZE_BODY))


static func _slider_styles(theme: Theme) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(SURFACE_LOW.r, SURFACE_LOW.g, SURFACE_LOW.b, 0.95)
	track.set_corner_radius_all(3)
	track.content_margin_top = 4.0
	track.content_margin_bottom = 4.0
	track.border_color = Color(LINE.r, LINE.g, LINE.b, 0.8)
	track.set_border_width_all(1)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(EMBER.r, EMBER.g, EMBER.b, 0.85)
	fill.set_corner_radius_all(3)
	theme.set_stylebox("slider", "HSlider", track)
	theme.set_stylebox("grabber_area", "HSlider", fill)
	theme.set_stylebox("grabber_area_highlight", "HSlider", fill)
	theme.set_icon("grabber_icon", "HSlider", _grabber_texture(false))
	theme.set_icon("grabber_icon_highlight", "HSlider", _grabber_texture(true))
	theme.set_constant("grabber_offset", "HSlider", 0)


static func _check_styles(theme: Theme) -> void:
	for type in ["CheckBox", "CheckButton"]:
		theme.set_color("font_color", type, INK)
		theme.set_color("font_hover_color", type, Color("#fff7e8"))
		theme.set_color("font_pressed_color", type, EMBER_HI)
		theme.set_color("font_focus_color", type, INK)
		theme.set_color("font_disabled_color", type, FAINT)
		theme.set_font("font", type, font_semi())
		theme.set_font_size("font_size", type, font_size(SIZE_BODY))
	theme.set_icon("checked", "CheckBox", _check_texture(true))
	theme.set_icon("unchecked", "CheckBox", _check_texture(false))
	theme.set_icon("checked_disabled", "CheckBox", _check_texture(true))
	theme.set_icon("unchecked_disabled", "CheckBox", _check_texture(false))
	theme.set_icon("checked", "CheckButton", _switch_texture(true))
	theme.set_icon("unchecked", "CheckButton", _switch_texture(false))


static func _scroll_styles(theme: Theme) -> void:
	for type in ["VScrollBar", "HScrollBar"]:
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0, 0, 0, 0)
		var thumb := StyleBoxFlat.new()
		thumb.bg_color = Color(LINE_HI.r, LINE_HI.g, LINE_HI.b, 0.9)
		thumb.set_corner_radius_all(3)
		var thumb_hi := StyleBoxFlat.new()
		thumb_hi.bg_color = Color(EMBER.r, EMBER.g, EMBER.b, 0.7)
		thumb_hi.set_corner_radius_all(3)
		theme.set_stylebox("scroll", type, bg)
		theme.set_stylebox("grabber_area", type, thumb)
		theme.set_stylebox("grabber_area_highlight", type, thumb_hi)
	theme.set_constant("separation", "HBoxContainer", 10)
	theme.set_constant("separation", "VBoxContainer", 10)


static func _tooltip_styles(theme: Theme) -> void:
	var tip := panel_style(Color("#0b1116"), LINE_HI, 1, 6)
	tip.content_margin_left = 10.0
	tip.content_margin_right = 10.0
	tip.content_margin_top = 6.0
	tip.content_margin_bottom = 6.0
	theme.set_stylebox("panel", "TooltipPanel", tip)
	theme.set_color("font_color", "TooltipLabel", INK_DIM)
	theme.set_font_size("font_size", "TooltipLabel", font_size(14))


# ------------------------------------------------ button flavor overrides --
## Filled ember call-to-action.
static func style_button_primary(button: Button) -> void:
	var normal := panel_style(EMBER_DEEP, Color(EMBER_HI.r, EMBER_HI.g, EMBER_HI.b, 0.65), 1, 8)
	normal.content_margin_left = 20.0
	normal.content_margin_right = 20.0
	normal.content_margin_top = 10.0
	normal.content_margin_bottom = 10.0
	var hover := panel_style(EMBER, EMBER_HI, 1, 8)
	hover.content_margin_left = 20.0
	hover.content_margin_right = 20.0
	hover.content_margin_top = 10.0
	hover.content_margin_bottom = 10.0
	var pressed := panel_style(Color("#9c6427"), EMBER_HI, 1, 8)
	pressed.content_margin_left = 20.0
	pressed.content_margin_right = 20.0
	pressed.content_margin_top = 10.0
	pressed.content_margin_bottom = 10.0
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color(0, 0, 0, 0)
	focus.border_color = EMBER_HI
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(10)
	focus.set_expand_margin_all(2.0)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_color_override("font_color", EMBER_INK)
	button.add_theme_color_override("font_hover_color", Color("#1a0e02"))
	button.add_theme_color_override("font_pressed_color", Color("#1a0e02"))
	button.add_theme_color_override("font_focus_color", EMBER_INK)
	button.add_theme_font_override("font", font_semi())
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_connect_click(button)


## Quiet outline button for secondary actions.
static func style_button_ghost(button: Button) -> void:
	var normal := panel_style(Color(SURFACE_HI.r, SURFACE_HI.g, SURFACE_HI.b, 0.35), LINE_HI, 1, 8)
	normal.content_margin_left = 18.0
	normal.content_margin_right = 18.0
	normal.content_margin_top = 10.0
	normal.content_margin_bottom = 10.0
	var hover := panel_style(Color(SURFACE_HI.r, SURFACE_HI.g, SURFACE_HI.b, 0.85), Color(EMBER.r, EMBER.g, EMBER.b, 0.5), 1, 8)
	hover.content_margin_left = 18.0
	hover.content_margin_right = 18.0
	hover.content_margin_top = 10.0
	hover.content_margin_bottom = 10.0
	var pressed := panel_style(Color(SURFACE_LOW.r, SURFACE_LOW.g, SURFACE_LOW.b, 0.9), Color(EMBER.r, EMBER.g, EMBER.b, 0.7), 1, 8)
	pressed.content_margin_left = 18.0
	pressed.content_margin_right = 18.0
	pressed.content_margin_top = 10.0
	pressed.content_margin_bottom = 10.0
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_font_override("font", font_semi())
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_connect_click(button)


## Flat inline button for segmented rows.
static func style_button_flat(button: Button) -> void:
	var normal := panel_style(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 6)
	normal.content_margin_left = 14.0
	normal.content_margin_right = 14.0
	normal.content_margin_top = 7.0
	normal.content_margin_bottom = 7.0
	var hover := panel_style(Color(EMBER.r, EMBER.g, EMBER.b, 0.12), Color(EMBER.r, EMBER.g, EMBER.b, 0.35), 1, 6)
	hover.content_margin_left = 14.0
	hover.content_margin_right = 14.0
	hover.content_margin_top = 7.0
	hover.content_margin_bottom = 7.0
	var pressed := panel_style(Color(EMBER.r, EMBER.g, EMBER.b, 0.2), Color(EMBER.r, EMBER.g, EMBER.b, 0.6), 1, 6)
	pressed.content_margin_left = 14.0
	pressed.content_margin_right = 14.0
	pressed.content_margin_top = 7.0
	pressed.content_margin_bottom = 7.0
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_font_override("font", font_semi())
	button.add_theme_color_override("font_color", INK_DIM)
	button.add_theme_color_override("font_hover_color", EMBER_HI)
	button.add_theme_color_override("font_pressed_color", EMBER_HI)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_connect_click(button)


## Every styled button gets one UI click. AudioManager is resolved through the
## scene tree so the theme keeps no autoload compile dependency.
static func _connect_click(button: Button) -> void:
	if button.has_meta("ui_click_connected"):
		return
	button.set_meta("ui_click_connected", true)
	button.pressed.connect(func() -> void:
		var tree := Engine.get_main_loop() as SceneTree
		if tree == null:
			return
		var audio := tree.root.get_node_or_null("AudioManager")
		if audio != null:
			audio.play_ui("click")
	)


# ----------------------------------------------------------- label factory --
static func style_heading(label: Label, size: int = SIZE_DISPLAY) -> void:
	label.add_theme_font_override("font", font_display())
	label.add_theme_color_override("font_color", INK)
	apply_font_size(label, size)


static func heading(text: String, size: int = SIZE_DISPLAY) -> Label:
	var label := Label.new()
	label.text = text
	style_heading(label, size)
	return label


## Tracked-out amber tick + caps label used as a section marker.
static func eyebrow(text: String, color: Color = MUTED) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tick := ColorRect.new()
	tick.color = EMBER
	tick.custom_minimum_size = Vector2(3, 12)
	tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tick)
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_override("font", font_eyebrow())
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	apply_font_size(label, SIZE_EYEBROW)
	row.add_child(label)
	return row


static func muted_label(text: String, size: int = 14) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", MUTED)
	apply_font_size(label, size)
	return label


static func value_label() -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", font_semi())
	label.add_theme_color_override("font_color", CYAN)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	apply_font_size(label, SIZE_VALUE)
	return label


# ------------------------------------------------------------------ rows ----
static func slider_row(box: VBoxContainer, label_text: String, minimum: float, maximum: float, step: float, value: float, format: String, display_scale: float = 1.0) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)

	var name_label := Label.new()
	name_label.text = label_text
	name_label.custom_minimum_size = Vector2(160.0, 0.0)
	name_label.add_theme_font_override("font", font_semi())
	row.add_child(name_label)

	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(120.0, 0.0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)

	var value_label := value_label()
	value_label.custom_minimum_size = Vector2(72.0, 0.0)
	value_label.text = format_value(format, value, display_scale)
	row.add_child(value_label)

	slider.value_changed.connect(func(new_value: float) -> void:
		value_label.text = UITheme.format_value(format, new_value, display_scale)
	)
	return slider


static func format_value(format: String, value: float, display_scale: float = 1.0) -> String:
	if format.contains("%d"):
		return format % roundi(value * display_scale)
	return format % (value * display_scale)


# ------------------------------------------------------ generated textures --
static func _check_texture(checked: bool) -> ImageTexture:
	if checked and _cached_check_on != null:
		return _cached_check_on
	if not checked and _cached_check_off != null:
		return _cached_check_off
	var size := 16
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var fill := Color(SURFACE_LOW.r, SURFACE_LOW.g, SURFACE_LOW.b, 0.95) if not checked else Color(EMBER_DEEP.r, EMBER_DEEP.g, EMBER_DEEP.b, 0.95)
	var border := LINE_HI if not checked else EMBER
	for y in size:
		for x in size:
			var edge := x == 0 or y == 0 or x == size - 1 or y == size - 1
			var corner := (x < 3 and y < 3) or (x < 3 and y > size - 4) or (x > size - 4 and y < 3) or (x > size - 4 and y > size - 4)
			var on := not corner
			if not on:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			image.set_pixel(x, y, border if edge else fill)
	if checked:
		for point in [
			Vector2i(4, 8), Vector2i(5, 9), Vector2i(6, 10), Vector2i(7, 11),
			Vector2i(8, 10), Vector2i(9, 9), Vector2i(10, 8), Vector2i(11, 7),
			Vector2i(12, 6),
		]:
			image.set_pixel(point.x, point.y, EMBER_HI)
			image.set_pixel(point.x, point.y - 2, EMBER_HI)
	var texture := ImageTexture.create_from_image(image)
	if checked:
		_cached_check_on = texture
	else:
		_cached_check_off = texture
	return texture


static func _switch_texture(on: bool) -> ImageTexture:
	if on and _cached_switch_on != null:
		return _cached_switch_on
	if not on and _cached_switch_off != null:
		return _cached_switch_off
	var width := 26
	var height := 15
	var radius := 6
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var track := Color(EMBER.r, EMBER.g, EMBER.b, 0.9) if on else Color(SURFACE_LOW.r, SURFACE_LOW.g, SURFACE_LOW.b, 0.95)
	var knob := EMBER_INK if on else Color(MUTED.r, MUTED.g, MUTED.b, 0.9)
	var knob_center := Vector2(width - 7, height / 2.0) if on else Vector2(7, height / 2.0)
	for y in height:
		for x in width:
			var edge := x == 0 or y == 0 or x == width - 1 or y == height - 1
			var border := EMBER_DEEP if on else LINE_HI
			image.set_pixel(x, y, border if edge else track)
	for y in height:
		for x in width:
			if Vector2(x + 0.5, y + 0.5).distance_to(knob_center) <= float(radius):
				image.set_pixel(x, y, knob)
	var texture := ImageTexture.create_from_image(image)
	if on:
		_cached_switch_on = texture
	else:
		_cached_switch_off = texture
	return texture


static func _grabber_texture(highlight: bool) -> ImageTexture:
	if highlight and _cached_grabber_hi != null:
		return _cached_grabber_hi
	if not highlight and _cached_grabber != null:
		return _cached_grabber
	var size := 15
	var center := Vector2(size, size) * 0.5
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var core := EMBER_HI if highlight else EMBER
	var ring := Color(EMBER_DEEP.r, EMBER_DEEP.g, EMBER_DEEP.b, 0.9)
	for y in size:
		for x in size:
			var distance := Vector2(x + 0.5, y + 0.5).distance_to(center)
			if distance <= 4.0:
				image.set_pixel(x, y, core)
			elif distance <= 6.2:
				image.set_pixel(x, y, ring)
			else:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
	var texture := ImageTexture.create_from_image(image)
	if highlight:
		_cached_grabber_hi = texture
	else:
		_cached_grabber = texture
	return texture
