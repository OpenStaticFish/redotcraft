class_name FirstRunHints
extends Node

const UIThemeScript := preload("res://ui/ui_theme.gd")

## A one-at-a-time onboarding queue. Hints only advance while the player can
## act on them, and each completed cue is persisted by the host so returning
## players never receive the same tutorial toast again.

const HINT_MOVEMENT := "movement"
const HINT_TARGETING := "targeting"
const HINT_INVENTORY := "inventory"
const HINT_FLY := "fly"
const HINT_DURATION := 7.0
const HINT_GAP := 1.5

var completion_provider: Callable
var completion_recorder: Callable
var move_hint_provider: Callable
var key_label_provider: Callable
var presentation_allowed: Callable
var text_scale_provider: Callable

var _hint_label: Label
var _active_hint := ""
var _remaining := 0.0
var _gap_remaining := HINT_GAP
var _creative := false
var _was_flying := false


## Creates a HUD-owned label rather than sharing the gameplay status toast:
## actions such as mining and saving remain visible while a tutorial cue is up.
func initialize(hud_root: Control, styled: bool = true) -> void:
	_hint_label = Label.new()
	_hint_label.name = "FirstRunHint"
	_hint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint_label.offset_left = -420.0
	_hint_label.offset_right = 420.0
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if styled:
		_hint_label.add_theme_font_override("font", UIThemeScript.font_semi())
		UIThemeScript.apply_font_size(_hint_label, 14)
		_hint_label.add_theme_color_override("font_color", UIThemeScript.CYAN)
		_hint_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		_hint_label.add_theme_constant_override("shadow_offset_x", 2)
		_hint_label.add_theme_constant_override("shadow_offset_y", 2)
	_hint_label.hide()
	hud_root.add_child(_hint_label)
	apply_text_layout()


func set_creative(creative: bool) -> void:
	_creative = creative


## Called from Main's normal process loop with only the live player context the
## queue needs. The host owns pause/modal/photo decisions through the callback.
func tick(delta: float, moving: bool, has_target: bool, flying: bool) -> void:
	if not _can_present():
		if _hint_label != null:
			_hint_label.hide()
		_was_flying = flying
		return
	if moving:
		_complete(HINT_MOVEMENT)
	if flying and not _was_flying:
		_complete(HINT_FLY)
	_was_flying = flying
	if not _active_hint.is_empty():
		_refresh_active_text()
		_remaining -= delta
		if _remaining <= 0.0:
			_complete(_active_hint)
		return
	_gap_remaining = maxf(_gap_remaining - delta, 0.0)
	if _gap_remaining <= 0.0:
		_show_next(has_target)


## Completing an action before its prompt appears is still useful knowledge;
## skip that prompt rather than showing it after the player has already used it.
func observe_target_action() -> void:
	_complete(HINT_TARGETING)


func observe_inventory_opened() -> void:
	_complete(HINT_INVENTORY)


func apply_text_layout() -> void:
	if _hint_label == null:
		return
	var scale: float = float(text_scale_provider.call()) if text_scale_provider.is_valid() else UIThemeScript.text_scale()
	_hint_label.offset_top = -158.0 - 22.0 * scale
	_hint_label.offset_bottom = -158.0


func active_hint() -> String:
	return _active_hint


func hint_text() -> String:
	return _hint_label.text if _hint_label != null else ""


func is_hint_visible() -> bool:
	return _hint_label != null and _hint_label.visible


func _show_next(has_target: bool) -> void:
	var hint := _next_hint(has_target)
	if hint.is_empty():
		return
	_active_hint = hint
	_remaining = HINT_DURATION
	_refresh_active_text()
	_hint_label.show()


func _next_hint(has_target: bool) -> String:
	if not _is_complete(HINT_MOVEMENT):
		return HINT_MOVEMENT
	if not _is_complete(HINT_TARGETING) and has_target:
		return HINT_TARGETING
	if not _is_complete(HINT_INVENTORY) and _is_complete(HINT_TARGETING):
		return HINT_INVENTORY
	if _creative and not _is_complete(HINT_FLY) and _is_complete(HINT_INVENTORY):
		return HINT_FLY
	return ""


func _refresh_active_text() -> void:
	if _hint_label == null:
		return
	match _active_hint:
		HINT_MOVEMENT:
			_hint_label.text = "Move with %s" % _move_hint()
		HINT_TARGETING:
			_hint_label.text = "Target acquired · LMB mine · RMB place"
		HINT_INVENTORY:
			_hint_label.text = "%s opens your inventory" % _key_label("inventory")
		HINT_FLY:
			_hint_label.text = "Double-tap %s to toggle flight" % _key_label("jump")


func _complete(hint: String) -> void:
	if hint.is_empty() or _is_complete(hint):
		return
	if completion_recorder.is_valid():
		completion_recorder.call(hint)
	if _active_hint != hint:
		return
	_active_hint = ""
	_remaining = 0.0
	_gap_remaining = HINT_GAP
	if _hint_label != null:
		_hint_label.hide()


func _is_complete(hint: String) -> bool:
	return bool(completion_provider.call(hint)) if completion_provider.is_valid() else false


func _can_present() -> bool:
	return bool(presentation_allowed.call()) if presentation_allowed.is_valid() else true


func _move_hint() -> String:
	return String(move_hint_provider.call()) if move_hint_provider.is_valid() else "WASD"


func _key_label(action: String) -> String:
	return String(key_label_provider.call(action)) if key_label_provider.is_valid() else action.capitalize()
