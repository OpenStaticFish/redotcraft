class_name PlayPanel
extends Control

## Play hub. The landing offers Continue / New World / Load World; New World
## reveals the creation form (world type, seed, clipboard import, and the
## Advanced world-gen screen), Load World lists every saved world with
## metadata and supports loading, renaming, duplication, backup, and deletion.
## `ui_cancel` unwinds one layer at a time: delete confirmation -> load list
## or create form -> landing -> closed. The world-gen screen handles its own
## cancel first because it sits above this panel in the tree.

signal closed
signal advanced_requested
signal create_requested(seed: int, world_type: int)
signal load_requested(world_id: String)

enum View { LANDING, CREATE, LOAD }

const WORLD_TYPES := ["Normal", "Flat", "Amplified"]
const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
const CREATE_PANEL_WIDTH := 560.0
const LOAD_PANEL_WIDTH := 640.0
const VIEWPORT_MARGIN := 48.0
const STAGGER_LIMIT := 6
const SECONDS_PER_MINUTE := 60.0
const SECONDS_PER_HOUR := 3600.0
const SECONDS_PER_DAY := 86400.0
const SECONDS_PER_WEEK := 604800.0

@onready var _panel: PanelContainer = $Center/Panel
@onready var _heading: Label = $Center/Panel/Box/Heading
@onready var _footer: HBoxContainer = $Center/Panel/Box/Footer
@onready var _type_row: HBoxContainer = $Center/Panel/Box/TypeRow
@onready var _type_option: OptionButton = $Center/Panel/Box/TypeRow/TypeOption
@onready var _seed_row: HBoxContainer = $Center/Panel/Box/SeedRow
@onready var _seed_field: LineEdit = $Center/Panel/Box/SeedRow/SeedField
@onready var _import_button: Button = $Center/Panel/Box/SeedRow/ImportButton
@onready var _random_button: Button = $Center/Panel/Box/SeedRow/RandomSeedButton
@onready var _advanced_button: Button = $Center/Panel/Box/Footer/AdvancedButton
@onready var _back_button: Button = $Center/Panel/Box/Footer/BackButton
@onready var _create_button: Button = $Center/Panel/Box/Footer/CreateButton
@onready var _dim: ColorRect = $Dim
@onready var _landing_box: VBoxContainer = $Center/Panel/Box/LandingBox
@onready var _continue_button: Button = $Center/Panel/Box/LandingBox/ContinueButton
@onready var _new_world_button: Button = $Center/Panel/Box/LandingBox/NewWorldButton
@onready var _load_world_button: Button = $Center/Panel/Box/LandingBox/LoadWorldButton
@onready var _landing_hint: Label = $Center/Panel/Box/LandingBox/LandingHint
@onready var _landing_back_button: Button = $Center/Panel/Box/LandingBox/LandingFooter/LandingBackButton
@onready var _load_box: VBoxContainer = $Center/Panel/Box/LoadBox
@onready var _load_scroll: ScrollContainer = $Center/Panel/Box/LoadBox/LoadScroll
@onready var _world_list: VBoxContainer = $Center/Panel/Box/LoadBox/LoadScroll/WorldList
@onready var _empty_state: VBoxContainer = $Center/Panel/Box/LoadBox/LoadScroll/EmptyState
@onready var _empty_title: Label = $Center/Panel/Box/LoadBox/LoadScroll/EmptyState/EmptyTitle
@onready var _empty_body: Label = $Center/Panel/Box/LoadBox/LoadScroll/EmptyState/EmptyBody
@onready var _empty_create_button: Button = $Center/Panel/Box/LoadBox/LoadScroll/EmptyState/EmptyCreateButton
@onready var _confirm_row: HBoxContainer = $Center/Panel/Box/LoadBox/ConfirmRow
@onready var _confirm_label: Label = $Center/Panel/Box/LoadBox/ConfirmRow/ConfirmLabel
@onready var _cancel_delete_button: Button = $Center/Panel/Box/LoadBox/ConfirmRow/CancelDeleteButton
@onready var _confirm_delete_button: Button = $Center/Panel/Box/LoadBox/ConfirmRow/ConfirmDeleteButton
@onready var _load_footer: HBoxContainer = $Center/Panel/Box/LoadBox/LoadFooter
@onready var _delete_all_button: Button = $Center/Panel/Box/LoadBox/LoadFooter/DeleteAllButton
@onready var _delete_button: Button = $Center/Panel/Box/LoadBox/LoadFooter/DeleteButton
@onready var _load_back_button: Button = $Center/Panel/Box/LoadBox/LoadFooter/LoadBackButton
@onready var _load_button: Button = $Center/Panel/Box/LoadBox/LoadFooter/LoadButton

## Library root is injectable so verifiers can point the list at a scratch
## directory; the game always uses WorldStorage's default.
var _library_root: String = WorldStorage.DEFAULT_ROOT
var _view: int = View.LANDING
var _confirming_delete := false
var _confirming_delete_all := false
var _selected_world_id := ""
var _continue_world_id := ""
var _cards: Dictionary = {}
var _world_names: Dictionary = {}
var _landing_return: Control = null
var _manage_row: HBoxContainer
var _rename_button: Button
var _duplicate_button: Button
var _backup_button: Button
var _rename_row: HBoxContainer
var _rename_field: LineEdit
var _rename_cancel_button: Button
var _rename_confirm_button: Button
var _operation_status: Label
var _editing_rename := false
var _mode_row: HBoxContainer
var _mode_option: OptionButton
var _mode_hint: Label


func _ready() -> void:
	UITheme.apply(self)
	_build_mode_controls()
	_build_management_controls()
	_style_static()
	_load_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	for type_name in WORLD_TYPES:
		_type_option.add_item(type_name)
	_type_option.item_selected.connect(_update_creation_description)
	_mode_option.item_selected.connect(_update_creation_description)
	_update_creation_description()
	_random_button.pressed.connect(func() -> void:
		_seed_field.text = str(randi() % 1000000000)
	)
	_import_button.pressed.connect(_on_import)
	_advanced_button.pressed.connect(func() -> void: advanced_requested.emit())
	_back_button.pressed.connect(func() -> void: _back_to_landing(_new_world_button))
	_create_button.pressed.connect(_on_create)
	_seed_field.text_submitted.connect(func(_text: String) -> void: _on_create())
	_continue_button.pressed.connect(func() -> void:
		if not _continue_world_id.is_empty():
			load_requested.emit(_continue_world_id)
	)
	_new_world_button.pressed.connect(func() -> void: _show_view(View.CREATE))
	_load_world_button.pressed.connect(func() -> void: _show_view(View.LOAD))
	_landing_back_button.pressed.connect(close_panel)
	_empty_create_button.pressed.connect(func() -> void: _show_view(View.CREATE))
	_load_footer.move_child(_delete_all_button, _delete_button.get_index())
	_delete_all_button.pressed.connect(_begin_delete_all_confirmation)
	_delete_button.pressed.connect(_begin_delete_confirmation)
	_load_back_button.pressed.connect(func() -> void: _back_to_landing(_load_world_button))
	_load_button.pressed.connect(_load_selected)
	_cancel_delete_button.pressed.connect(_cancel_delete)
	_confirm_delete_button.pressed.connect(_confirm_delete)
	# A live interface-scale change moves the logical viewport under the open
	# modal, so re-fit the panel and list instead of clipping them.
	GameConfig.interface_scale_changed.connect(_apply_view_metrics)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _confirming_delete:
			_cancel_delete()
		elif _editing_rename:
			_cancel_rename()
		elif _view == View.LANDING:
			close_panel()
		else:
			_back_to_landing(_new_world_button if _view == View.CREATE else _load_world_button)
		return
	if _view == View.LOAD and not _confirming_delete and not _editing_rename \
			and not _selected_world_id.is_empty() \
			and event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_DELETE:
			get_viewport().set_input_as_handled()
			_begin_delete_confirmation()


func open_panel() -> void:
	_landing_return = null
	_confirming_delete = false
	_confirming_delete_all = false
	_editing_rename = false
	visible = true
	_show_view(View.LANDING)
	Motion.dim_in(_dim)
	Motion.pop_in(_panel)


func close_panel() -> void:
	if not visible:
		return
	_confirming_delete = false
	_confirming_delete_all = false
	_editing_rename = false
	visible = false
	closed.emit()


## The advanced world-gen screen is only reachable from the creation form, so
## returning to it always restores the create view (and its Advanced button).
func focus_advanced() -> void:
	if not visible:
		return
	if _view != View.CREATE:
		_show_view(View.CREATE)
	_advanced_button.grab_focus()


## Called by MainMenu when storage rejects the requested world (removed on
## disk, unreadable, or incompatible): refresh whatever view is showing.
func notify_load_failed() -> void:
	if not visible:
		return
	if _view == View.LOAD:
		_refresh_load_view()
	elif _view == View.LANDING:
		_refresh_landing()


func _show_view(view: int) -> void:
	_view = view
	_landing_box.visible = view == View.LANDING
	_type_row.visible = view == View.CREATE
	_mode_row.visible = view == View.CREATE
	_mode_hint.visible = view == View.CREATE
	_seed_row.visible = view == View.CREATE
	_footer.visible = view == View.CREATE
	_load_box.visible = view == View.LOAD
	match view:
		View.LANDING:
			_heading.text = "Worlds"
			_refresh_landing()
			var focus_target := _landing_return
			_landing_return = null
			if not _can_focus(focus_target):
				focus_target = _continue_button if _continue_button.visible else _new_world_button
			focus_target.grab_focus()
			Motion.stagger_in(_visible_landing_buttons())
		View.CREATE:
			_heading.text = "New World"
			_seed_field.text = str(GameConfig.get_world_seed())
			_type_option.selected = clampi(GameConfig.get_world_type(), 0, WORLD_TYPES.size() - 1)
			_update_creation_description()
			_seed_field.grab_focus()
		View.LOAD:
			_heading.text = "Load World"
			_refresh_load_view()
	_apply_view_metrics()


func _back_to_landing(opener: Control) -> void:
	if _confirming_delete:
		_cancel_delete()
	_landing_return = opener
	_show_view(View.LANDING)


# ------------------------------------------------------------- landing view --

func _refresh_landing() -> void:
	var saved := WorldStorage.latest_world_metadata(_library_root)
	_continue_world_id = String(saved.get("id", ""))
	_continue_button.visible = not _continue_world_id.is_empty()
	if _continue_button.visible:
		_continue_button.text = "Continue — %s" % String(saved.get("name", "Last World"))
	var total := WorldStorage.list_world_summaries(_library_root).size()
	_load_world_button.disabled = total == 0
	_load_world_button.tooltip_text = "Browse saved worlds" if total > 0 else "No saved worlds yet"
	if total == 0:
		_landing_hint.text = "No saved worlds yet — create one to get started."
	else:
		_landing_hint.text = "%d saved %s on this device." % [total, "world" if total == 1 else "worlds"]
	# Ember marks the single fastest path: resuming when possible, creating otherwise.
	if _continue_button.visible:
		UITheme.style_button_primary(_continue_button)
		UITheme.style_button_ghost(_new_world_button)
	else:
		UITheme.style_button_ghost(_continue_button)
		UITheme.style_button_primary(_new_world_button)


func _visible_landing_buttons() -> Array:
	var buttons: Array = [_continue_button, _new_world_button, _load_world_button]
	var visible_buttons: Array = []
	for button in buttons:
		if button != null and is_instance_valid(button) and (button as Button).visible:
			visible_buttons.append(button)
	return visible_buttons


# ---------------------------------------------------------- load world view --

func _refresh_load_view() -> void:
	for card in _cards.values():
		card.queue_free()
	_cards.clear()
	_world_names.clear()
	_selected_world_id = ""
	_confirming_delete = false
	_confirming_delete_all = false
	_editing_rename = false
	_confirm_row.visible = false
	_rename_row.visible = false
	_manage_row.visible = true
	_load_footer.visible = true
	_confirm_delete_button.text = "Delete"
	var worlds := WorldStorage.list_world_summaries(_library_root)
	var entrance: Array = []
	for world in worlds:
		var card := _build_card(world)
		_world_list.add_child(card)
		var id := String(world["id"])
		_cards[id] = card
		_world_names[id] = _display_name(world)
		if entrance.size() < STAGGER_LIMIT:
			entrance.append(card)
	var has_worlds := not worlds.is_empty()
	_world_list.visible = has_worlds
	_empty_state.visible = not has_worlds
	_delete_button.disabled = true
	_delete_button.tooltip_text = "Select a world first"
	_delete_all_button.disabled = not has_worlds
	_delete_all_button.tooltip_text = "Delete every saved world (with confirmation)" if has_worlds \
		else "No saved worlds to delete"
	_load_button.disabled = true
	_load_button.tooltip_text = "Select a world to load"
	_set_management_enabled(false)
	_operation_status.text = ""
	_apply_view_metrics()
	if has_worlds:
		(_cards.values()[0] as Button).grab_focus()
		Motion.stagger_in(entrance)
	else:
		_empty_create_button.grab_focus()


func _build_card(world: Dictionary) -> Button:
	var id := String(world["id"])
	var compatible := bool(world.get("compatible", true))
	var card := Button.new()
	card.name = "WorldCard_" + id
	card.text = ""
	card.toggle_mode = false
	card.focus_mode = Control.FOCUS_ALL
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0.0, 82.0)
	card.set_meta("world_id", id)
	card.set_meta("compatible", compatible)
	if compatible:
		card.tooltip_text = "Enter or double-click to load; Delete removes this world"
	else:
		card.tooltip_text = "Saved by a newer version of RedotCraft; it cannot be loaded yet."

	var bar := UITheme.accent_bar(UITheme.EMBER)
	bar.name = "AccentBar"
	bar.visible = false
	card.add_child(bar)

	var margin := MarginContainer.new()
	margin.name = "Content"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 8)
	card.add_child(margin)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 14)
	margin.add_child(row)

	var details := VBoxContainer.new()
	details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(details)

	var title := Label.new()
	title.text = _display_name(world)
	title.add_theme_font_override("font", UITheme.font_semi())
	title.add_theme_color_override("font_color", UITheme.INK)
	UITheme.apply_font_size(title, UITheme.SIZE_BODY)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details.add_child(title)

	var meta := Label.new()
	meta.text = "%s · Seed %d · Created %s" % [
		WORLD_TYPES[clampi(int(world.get("world_type", 0)), 0, WORLD_TYPES.size() - 1)],
		int(world.get("seed", 0)),
		_format_date(int(world.get("created_unix", 0))),
	]
	meta.add_theme_color_override("font_color", UITheme.MUTED)
	UITheme.apply_font_size(meta, 13)
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details.add_child(meta)
	var mode_label := Label.new()
	mode_label.name = "GameModeLabel"
	mode_label.text = GameMode.display_name(int(world.get("game_mode", GameMode.CREATIVE)))
	mode_label.add_theme_color_override("font_color", UITheme.MUTED)
	UITheme.apply_font_size(mode_label, 13)
	mode_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details.add_child(mode_label)

	var stats := VBoxContainer.new()
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats.custom_minimum_size = Vector2(112.0, 0.0)
	stats.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(stats)

	var caption := Label.new()
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	caption.add_theme_font_override("font", UITheme.font_eyebrow())
	caption.add_theme_color_override("font_color", UITheme.FAINT)
	UITheme.apply_font_size(caption, 11)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats.add_child(caption)

	var stat_value := Label.new()
	stat_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stat_value.add_theme_font_override("font", UITheme.font_semi())
	UITheme.apply_font_size(stat_value, UITheme.SIZE_VALUE)
	stat_value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats.add_child(stat_value)
	if compatible:
		caption.text = "LAST PLAYED"
		stat_value.add_theme_color_override("font_color", UITheme.CYAN)
		stat_value.text = _relative_time(int(world.get("updated_unix", 0)))
	else:
		caption.text = "VERSION"
		stat_value.add_theme_color_override("font_color", UITheme.WARN)
		stat_value.text = "INCOMPATIBLE"

	_style_card(card, false)
	# Button children do not contribute to its minimum size automatically.
	margin.minimum_size_changed.connect(func() -> void:
		card.custom_minimum_size.y = maxf(82.0, margin.get_combined_minimum_size().y))
	card.custom_minimum_size.y = maxf(82.0, margin.get_combined_minimum_size().y)
	card.pressed.connect(_on_card_activated.bind(id))
	card.gui_input.connect(_on_card_gui_input.bind(id))
	return card


func _style_card(card: Button, selected: bool) -> void:
	var fill := Color(UITheme.EMBER.r, UITheme.EMBER.g, UITheme.EMBER.b, 0.13) if selected \
		else Color(UITheme.SURFACE_HI.r, UITheme.SURFACE_HI.g, UITheme.SURFACE_HI.b, 0.4)
	var border := Color(UITheme.EMBER.r, UITheme.EMBER.g, UITheme.EMBER.b, 0.5) if selected \
		else UITheme.LINE_HI
	var normal := UITheme.panel_style(fill, border, 1, 8)
	normal.content_margin_left = 16.0
	normal.content_margin_right = 14.0
	normal.content_margin_top = 6.0
	normal.content_margin_bottom = 6.0
	var hover_fill := Color(UITheme.EMBER.r, UITheme.EMBER.g, UITheme.EMBER.b, 0.2) if selected \
		else Color(UITheme.SURFACE_HI.r, UITheme.SURFACE_HI.g, UITheme.SURFACE_HI.b, 0.85)
	var hover_border := Color(UITheme.EMBER.r, UITheme.EMBER.g, UITheme.EMBER.b, 0.65) if selected \
		else Color(UITheme.EMBER.r, UITheme.EMBER.g, UITheme.EMBER.b, 0.5)
	var hover := UITheme.panel_style(hover_fill, hover_border, 1, 8)
	hover.content_margin_left = 16.0
	hover.content_margin_right = 14.0
	hover.content_margin_top = 6.0
	hover.content_margin_bottom = 6.0
	card.add_theme_stylebox_override("normal", normal)
	card.add_theme_stylebox_override("hover", hover)
	var bar := card.get_node_or_null("AccentBar")
	if bar != null:
		bar.visible = selected


func _on_card_activated(id: String) -> void:
	if _confirming_delete or _editing_rename:
		return
	if id == _selected_world_id:
		_load_selected()
	else:
		_select_world(id)


func _on_card_gui_input(event: InputEvent, id: String) -> void:
	if _confirming_delete or _editing_rename:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).double_click:
		_select_world(id)
		_load_selected()


func _select_world(id: String) -> void:
	_selected_world_id = id
	for card_id in _cards:
		_style_card(_cards[card_id] as Button, card_id == id)
	var card := _cards.get(id) as Button
	var compatible := card != null and bool(card.get_meta("compatible", true))
	_delete_button.disabled = false
	_delete_button.tooltip_text = "Delete the selected world (with confirmation)"
	_load_button.disabled = not compatible
	_load_button.tooltip_text = "Load the selected world" if compatible \
		else "The selected world was saved by a newer version"
	_set_management_enabled(compatible)


func _load_selected() -> void:
	if _confirming_delete or _editing_rename or _selected_world_id.is_empty():
		return
	var card := _cards.get(_selected_world_id) as Button
	if card == null or not bool(card.get_meta("compatible", true)):
		return
	load_requested.emit(_selected_world_id)


func _begin_delete_confirmation() -> void:
	if _confirming_delete or _editing_rename or _selected_world_id.is_empty():
		return
	_confirming_delete = true
	_confirming_delete_all = false
	var world_name := String(_world_names.get(_selected_world_id, "this world"))
	_confirm_label.text = "Delete \"%s\"? Its blocks and progress are removed permanently." % world_name
	_load_footer.visible = false
	_manage_row.visible = false
	_confirm_row.visible = true
	# The safe choice takes focus first; the destructive one is one Tab away.
	_cancel_delete_button.grab_focus()


func _begin_delete_all_confirmation() -> void:
	if _confirming_delete or _editing_rename:
		return
	var world_count := WorldStorage.list_world_summaries(_library_root).size()
	if world_count == 0:
		return
	_confirming_delete = true
	_confirming_delete_all = true
	_confirm_label.text = "Delete all %d saved %s? Every world's blocks and progress will be removed permanently." % [
		world_count,
		"world" if world_count == 1 else "worlds",
	]
	_confirm_delete_button.text = "Delete All"
	_load_footer.visible = false
	_manage_row.visible = false
	_confirm_row.visible = true
	_cancel_delete_button.grab_focus()


func _cancel_delete() -> void:
	if not _confirming_delete:
		return
	var focus_target: Button = _delete_all_button if _confirming_delete_all else _delete_button
	_confirming_delete = false
	_confirming_delete_all = false
	_confirm_row.visible = false
	_manage_row.visible = true
	_load_footer.visible = true
	_confirm_delete_button.text = "Delete"
	focus_target.grab_focus()


func _confirm_delete() -> void:
	if not _confirming_delete:
		return
	if _confirming_delete_all:
		_confirm_delete_all()
		return
	var id := _selected_world_id
	_confirming_delete = false
	_confirming_delete_all = false
	_confirm_row.visible = false
	_manage_row.visible = true
	_load_footer.visible = true
	_confirm_delete_button.text = "Delete"
	if WorldStorage.delete_world(id, _library_root) and GameConfig.active_world_id == id:
		GameConfig.clear_active_world()
	_refresh_load_view()


func _confirm_delete_all() -> void:
	var active_world_id := GameConfig.active_world_id
	var deleted_active_world := false
	for world in WorldStorage.list_world_summaries(_library_root):
		var id := String(world.get("id", ""))
		if WorldStorage.delete_world(id, _library_root) and id == active_world_id:
			deleted_active_world = true
	if deleted_active_world:
		GameConfig.clear_active_world()
	_confirming_delete = false
	_confirming_delete_all = false
	_confirm_row.visible = false
	_manage_row.visible = true
	_load_footer.visible = true
	_confirm_delete_button.text = "Delete"
	_refresh_load_view()


func _begin_rename() -> void:
	if _confirming_delete or _editing_rename or _selected_world_id.is_empty():
		return
	_editing_rename = true
	_rename_field.text = String(_world_names.get(_selected_world_id, ""))
	_rename_field.select_all()
	_manage_row.visible = false
	_load_footer.visible = false
	_rename_row.visible = true
	_rename_field.grab_focus()


func _cancel_rename() -> void:
	if not _editing_rename:
		return
	_editing_rename = false
	_rename_row.visible = false
	_manage_row.visible = true
	_load_footer.visible = true
	_rename_button.grab_focus()


func _confirm_rename() -> void:
	if not _editing_rename:
		return
	var id := _selected_world_id
	var name := _rename_field.text.strip_edges()
	if not WorldStorage.rename_world(id, name, _library_root):
		_set_operation_status("Rename failed. Use 1-64 visible characters.", true)
		_rename_field.grab_focus()
		return
	if GameConfig.active_world_id == id:
		GameConfig.active_world_metadata["name"] = name
	_editing_rename = false
	_refresh_load_view()
	_select_world(id)
	_set_operation_status("Renamed to %s." % name)


func _duplicate_selected() -> void:
	if _confirming_delete or _editing_rename or _selected_world_id.is_empty():
		return
	var duplicated := WorldStorage.duplicate_world(_selected_world_id, _library_root)
	if duplicated.is_empty():
		_set_operation_status("Could not duplicate this world.", true)
		return
	var copy_id := String(duplicated.get("id", ""))
	_refresh_load_view()
	_select_world(copy_id)
	_set_operation_status("Created %s." % _display_name(duplicated))


func _backup_selected() -> void:
	if _confirming_delete or _editing_rename or _selected_world_id.is_empty():
		return
	var backup_path := WorldStorage.backup_world(_selected_world_id, _library_root)
	if backup_path.is_empty():
		_set_operation_status("Could not back up this world.", true)
	else:
		_set_operation_status("Backup saved to %s." % backup_path)
	_backup_button.grab_focus()


# ------------------------------------------------------------- create view --

func get_selected_game_mode() -> int:
	return _mode_option.get_selected_id()


func _build_mode_controls() -> void:
	var box := _type_row.get_parent()
	_mode_row = HBoxContainer.new()
	_mode_row.name = "GameModeRow"
	_mode_row.visible = false
	var label := Label.new()
	_style_row_label(label, "Game Mode")
	_mode_row.add_child(label)
	_mode_option = OptionButton.new()
	_mode_option.name = "GameModeOption"
	_mode_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for mode in [GameMode.CREATIVE, GameMode.SURVIVAL]:
		_mode_option.add_item(GameMode.display_name(mode), mode)
	_mode_option.select(_mode_option.get_item_index(GameMode.SURVIVAL))
	_mode_row.add_child(_mode_option)
	box.add_child(_mode_row)
	box.move_child(_mode_row, _type_row.get_index())
	_mode_hint = Label.new()
	_mode_hint.name = "GameModeHint"
	_mode_hint.visible = false
	_mode_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mode_hint.add_theme_color_override("font_color", UITheme.MUTED)
	UITheme.apply_font_size(_mode_hint, 13)
	box.add_child(_mode_hint)
	box.move_child(_mode_hint, _mode_row.get_index() + 1)


func _update_creation_description(_index: int = -1) -> void:
	_mode_hint.text = "Creative: build freely. Survival: gather and survive.\nGame mode is locked after creation."
	if _type_option.selected == WorldGenConfig.WORLD_TYPE_FLAT \
			and get_selected_game_mode() == GameMode.SURVIVAL:
		_mode_hint.text += "\nWarning: Flat Survival is resource-limited. Flat terrain generates no trees or ores."


func _on_import() -> void:
	var text := DisplayServer.clipboard_get().strip_edges()
	if not text.is_empty():
		_seed_field.text = text
		_seed_field.caret_column = text.length()


func _on_create() -> void:
	var seed_text := _seed_field.text.strip_edges()
	var seed_value := 0
	if seed_text.is_valid_int():
		seed_value = int(seed_text)
	elif not seed_text.is_empty():
		seed_value = seed_text.hash() & 0x7FFFFFFF
	else:
		seed_value = randi() % 1000000000
	create_requested.emit(seed_value, _type_option.selected)


# -------------------------------------------------------------- chrome/sizing

func _apply_view_metrics() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var width := LOAD_PANEL_WIDTH if _view == View.LOAD else CREATE_PANEL_WIDTH
	_panel.custom_minimum_size.x = minf(width, maxf(viewport_size.x - VIEWPORT_MARGIN, width * 0.6))
	if _view != View.LOAD:
		return
	# The list scrolls once it no longer fits between the header and footer.
	var content_height := maxf(_world_list.get_combined_minimum_size().y, _empty_state.get_combined_minimum_size().y)
	_load_scroll.custom_minimum_size.y = content_height
	var chrome := _panel.get_combined_minimum_size().y - _load_scroll.custom_minimum_size.y
	var max_height := maxf(viewport_size.y - chrome - VIEWPORT_MARGIN, 120.0)
	_load_scroll.custom_minimum_size.y = minf(content_height, max_height)


func _style_static() -> void:
	_dim.color = Color(UITheme.VOID.r, UITheme.VOID.g, UITheme.VOID.b, 0.68)
	_panel.add_theme_stylebox_override("panel", UITheme.modal_style())
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	UITheme.style_heading(_heading)
	var box := _heading.get_parent() as VBoxContainer
	var eyebrow := UITheme.eyebrow("Play")
	box.add_child(eyebrow)
	box.move_child(eyebrow, 0)
	_style_row_label($Center/Panel/Box/TypeRow/TypeLabel as Label, "World Type")
	_style_row_label($Center/Panel/Box/SeedRow/SeedLabel as Label, "Seed")
	_import_button.tooltip_text = "Paste a seed from the clipboard"
	UITheme.style_button_ghost(_import_button)
	UITheme.style_button_ghost(_random_button)
	UITheme.style_button_ghost(_advanced_button)
	UITheme.style_button_ghost(_back_button)
	UITheme.style_button_primary(_create_button)
	UITheme.style_button_ghost(_new_world_button)
	UITheme.style_button_ghost(_load_world_button)
	UITheme.style_button_ghost(_landing_back_button)
	UITheme.style_button_ghost(_delete_all_button)
	UITheme.style_button_ghost(_delete_button)
	UITheme.style_button_ghost(_load_back_button)
	UITheme.style_button_primary(_load_button)
	UITheme.style_button_ghost(_cancel_delete_button)
	UITheme.style_button_primary(_confirm_delete_button)
	UITheme.style_button_ghost(_empty_create_button)
	UITheme.style_button_ghost(_rename_button)
	UITheme.style_button_ghost(_duplicate_button)
	UITheme.style_button_ghost(_backup_button)
	UITheme.style_button_ghost(_rename_cancel_button)
	UITheme.style_button_primary(_rename_confirm_button)
	_landing_hint.add_theme_color_override("font_color", UITheme.MUTED)
	UITheme.apply_font_size(_landing_hint, 13)
	_confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_confirm_label.add_theme_color_override("font_color", UITheme.WARN)
	UITheme.apply_font_size(_confirm_label, 14)
	_empty_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_title.add_theme_font_override("font", UITheme.font_semi())
	_empty_title.add_theme_color_override("font_color", UITheme.INK_DIM)
	UITheme.apply_font_size(_empty_title, 18)
	_empty_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_body.add_theme_color_override("font_color", UITheme.MUTED)
	UITheme.apply_font_size(_empty_body, 13)
	_empty_state.custom_minimum_size = Vector2(0.0, 240.0)
	_operation_status.add_theme_color_override("font_color", UITheme.CYAN)
	UITheme.apply_font_size(_operation_status, 13)


func _build_management_controls() -> void:
	_manage_row = HBoxContainer.new()
	_manage_row.name = "ManageRow"
	_manage_row.alignment = BoxContainer.ALIGNMENT_END
	_manage_row.add_theme_constant_override("separation", 10)
	_rename_button = Button.new()
	_rename_button.text = "Rename..."
	_duplicate_button = Button.new()
	_duplicate_button.text = "Duplicate"
	_backup_button = Button.new()
	_backup_button.text = "Back Up"
	for button in [_rename_button, _duplicate_button, _backup_button]:
		_manage_row.add_child(button)
	_load_box.add_child(_manage_row)
	_load_box.move_child(_manage_row, _confirm_row.get_index())
	_rename_button.pressed.connect(_begin_rename)
	_duplicate_button.pressed.connect(_duplicate_selected)
	_backup_button.pressed.connect(_backup_selected)

	_rename_row = HBoxContainer.new()
	_rename_row.name = "RenameRow"
	_rename_row.visible = false
	_rename_row.add_theme_constant_override("separation", 10)
	_rename_field = LineEdit.new()
	_rename_field.max_length = 64
	_rename_field.placeholder_text = "World name"
	_rename_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rename_cancel_button = Button.new()
	_rename_cancel_button.text = "Cancel"
	_rename_confirm_button = Button.new()
	_rename_confirm_button.text = "Rename"
	_rename_row.add_child(_rename_field)
	_rename_row.add_child(_rename_cancel_button)
	_rename_row.add_child(_rename_confirm_button)
	_load_box.add_child(_rename_row)
	_load_box.move_child(_rename_row, _confirm_row.get_index())
	_rename_cancel_button.pressed.connect(_cancel_rename)
	_rename_confirm_button.pressed.connect(_confirm_rename)
	_rename_field.text_submitted.connect(func(_text: String) -> void: _confirm_rename())

	_operation_status = Label.new()
	_operation_status.name = "OperationStatus"
	_operation_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_load_box.add_child(_operation_status)
	_load_box.move_child(_operation_status, _load_footer.get_index())


func _set_management_enabled(enabled: bool) -> void:
	_rename_button.disabled = not enabled
	_duplicate_button.disabled = not enabled
	_backup_button.disabled = not enabled
	var hint := "Select a compatible world first"
	_rename_button.tooltip_text = "Rename the selected world" if enabled else hint
	_duplicate_button.tooltip_text = "Create an independent copy" if enabled else hint
	_backup_button.tooltip_text = "Copy the save to user://world_backups" if enabled else hint


func _set_operation_status(text: String, failed: bool = false) -> void:
	_operation_status.text = text
	_operation_status.add_theme_color_override("font_color", UITheme.WARN if failed else UITheme.CYAN)


func _style_row_label(label: Label, text: String) -> void:
	label.text = text
	label.custom_minimum_size = Vector2(160.0, 0.0)
	label.add_theme_font_override("font", UITheme.font_semi())


# ------------------------------------------------------------ presentation --

func _display_name(world: Dictionary) -> String:
	var name_text := String(world.get("name", ""))
	if not name_text.is_empty():
		return name_text
	return "World %d" % int(world.get("seed", 0))


func _can_focus(control: Control) -> bool:
	if control == null or not is_instance_valid(control) or not control.visible \
			or control.focus_mode == Control.FOCUS_NONE:
		return false
	return not (control is BaseButton and (control as BaseButton).disabled)


func _relative_time(unix_time: int) -> String:
	var delta := maxi(int(Time.get_unix_time_from_system()) - unix_time, 0)
	if delta < SECONDS_PER_MINUTE:
		return "just now"
	if delta < SECONDS_PER_HOUR:
		return "%d min ago" % floori(float(delta) / SECONDS_PER_MINUTE)
	if delta < SECONDS_PER_DAY:
		return "%d hr ago" % floori(float(delta) / SECONDS_PER_HOUR)
	if delta < SECONDS_PER_WEEK:
		return "%d d ago" % floori(float(delta) / SECONDS_PER_DAY)
	return _format_date(unix_time)


func _format_date(unix_time: int) -> String:
	var date := Time.get_datetime_dict_from_unix_time(unix_time)
	var now := Time.get_datetime_dict_from_system()
	var text := "%s %d" % [MONTHS[clampi(int(date["month"]) - 1, 0, MONTHS.size() - 1)], int(date["day"])]
	if int(date["year"]) != int(now["year"]):
		text += ", %d" % int(date["year"])
	return text
