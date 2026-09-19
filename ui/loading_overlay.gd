class_name LoadingOverlay
extends Control

## Transitional world-entry presentation. It is deliberately read-only: the
## player remains locked until VoxelWorld has committed collision for the local
## spawn ring, while the rest of the requested horizon keeps streaming.

var _panel: PanelContainer
var _phase: Label
var _detail: Label
var _progress_text: Label
var _activity: Label
var _bar: Panel
var _fill: ColorRect
var _progress := 0.0
var _pending_progress: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	UITheme.apply(self)
	_build()
	set_progress(_pending_progress)
	call_deferred("grab_focus")


func _build() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(UITheme.VOID.r, UITheme.VOID.g, UITheme.VOID.b, 0.86)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.custom_minimum_size = Vector2(460.0, 0.0)
	_panel.add_theme_stylebox_override("panel", UITheme.modal_style())
	center.add_child(_panel)

	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 10)
	_panel.add_child(box)

	var eyebrow := Label.new()
	eyebrow.name = "Eyebrow"
	eyebrow.text = "WORLD PREPARATION"
	eyebrow.add_theme_font_override("font", UITheme.font_eyebrow())
	UITheme.apply_font_size(eyebrow, UITheme.SIZE_EYEBROW)
	eyebrow.add_theme_color_override("font_color", UITheme.CYAN)
	box.add_child(eyebrow)

	_phase = Label.new()
	_phase.name = "Phase"
	_phase.add_theme_font_override("font", UITheme.font_display())
	UITheme.apply_font_size(_phase, 24)
	_phase.add_theme_color_override("font_color", UITheme.INK)
	box.add_child(_phase)

	_detail = Label.new()
	_detail.name = "Detail"
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.apply_font_size(_detail, UITheme.SIZE_BODY)
	_detail.add_theme_color_override("font_color", UITheme.INK_DIM)
	box.add_child(_detail)

	_bar = Panel.new()
	_bar.name = "ProgressTrack"
	_bar.custom_minimum_size = Vector2(0.0, 10.0)
	_bar.add_theme_stylebox_override("panel", UITheme.panel_style(UITheme.SURFACE_LOW, UITheme.LINE, 1, 5))
	box.add_child(_bar)
	_fill = ColorRect.new()
	_fill.name = "ProgressFill"
	_fill.color = UITheme.EMBER
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(_fill)
	_bar.resized.connect(_layout_progress)

	_progress_text = Label.new()
	_progress_text.name = "ProgressText"
	UITheme.apply_font_size(_progress_text, UITheme.SIZE_VALUE)
	_progress_text.add_theme_color_override("font_color", UITheme.CYAN)
	box.add_child(_progress_text)

	_activity = Label.new()
	_activity.name = "Activity"
	UITheme.apply_font_size(_activity, UITheme.SIZE_EYEBROW)
	_activity.add_theme_color_override("font_color", UITheme.MUTED)
	box.add_child(_activity)


## Accepts VoxelWorld.get_streaming_progress() snapshots before or after the
## control enters the tree, so scene startup cannot miss the first update.
func set_progress(progress: Dictionary) -> void:
	_pending_progress = progress.duplicate()
	if _phase == null:
		return
	var total := maxi(int(progress.get("total", 0)), 1)
	var loaded := clampi(int(progress.get("loaded", 0)), 0, total)
	var percent := clampi(roundi(float(loaded) / float(total) * 100.0), 0, 100)
	_progress = float(loaded) / float(total)
	var spawn_total := maxi(int(progress.get("spawn_total", 0)), 1)
	var spawn_collision := clampi(int(progress.get("spawn_collision", 0)), 0, spawn_total)
	var initial_ready := bool(progress.get("initial_ready", false))
	var streaming := bool(progress.get("streaming", false))
	if not initial_ready:
		_phase.text = "Preparing a safe spawn"
		_detail.text = "Generating nearby terrain and its collision before you enter the world."
		_progress_text.text = "Spawn area  %d / %d chunks secure" % [spawn_collision, spawn_total]
	elif streaming:
		_phase.text = "Spawn ready"
		_detail.text = "The horizon is still streaming in the background."
		_progress_text.text = "Horizon  %d / %d chunks · %d%%" % [loaded, total, percent]
	else:
		_phase.text = "World ready"
		_detail.text = "Terrain and collision are ready."
		_progress_text.text = "Horizon  %d / %d chunks · 100%%" % [loaded, total]
	var active := int(progress.get("pending", 0))
	var queued := int(progress.get("queued", 0))
	var staged := int(progress.get("generated", 0))
	_activity.text = "%d active · %d queued · %d awaiting mesh" % [active, queued, staged]
	_layout_progress()


## Unlocking gameplay never waits for this cosmetic fade. It also drops focus
## and mouse interception immediately, preserving normal HUD input behavior.
func complete() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	set_process_unhandled_input(false)
	var config := get_tree().root.get_node_or_null("GameConfig")
	if config != null and config.has_method("is_reduced_motion") \
			and bool(config.is_reduced_motion()):
		queue_free()
		return
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "modulate:a", 0.0, 0.18)
	tween.tween_callback(queue_free)


func _layout_progress() -> void:
	if _bar == null or _fill == null:
		return
	_fill.position = Vector2.ZERO
	_fill.size = Vector2(_bar.size.x * _progress, _bar.size.y)


## A loading overlay is not cancellable because abandoning the scene while
## worker jobs are in flight would turn Escape into a long synchronous wait.
## Consume input until Main releases the player after the safe spawn boundary.
func _unhandled_input(_event: InputEvent) -> void:
	if visible:
		get_viewport().set_input_as_handled()
