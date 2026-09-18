class_name InventoryOverlay
extends CanvasLayer

signal opened
signal closed
signal time_selected(hours: float)
signal weather_toggled

const TIME_BUTTONS := [
	{"node": "MorningButton", "hours": 6.0},
	{"node": "DayButton", "hours": 12.0},
	{"node": "EveningButton", "hours": 18.0},
	{"node": "NightButton", "hours": 0.0},
]

@onready var _panel: PanelContainer = $Center/Panel
@onready var _heading: Label = $Center/Panel/Box/Heading
@onready var _time_row: HBoxContainer = $Center/Panel/Box/TimeRow
@onready var _weather_row: HBoxContainer = $Center/Panel/Box/WeatherRow
@onready var _grid: GridContainer = $Center/Panel/Box/Grid
@onready var _weather_button: Button = $Center/Panel/Box/WeatherRow/WeatherButton
@onready var _hint: Label = $Center/Panel/Box/Hint
@onready var _dim: ColorRect = $Dim

var _inventory: ItemInventory
var _world: VoxelWorld
var _station_inventory: ItemInventory
var _at_table := false
var _scroll: ScrollContainer
var _station_box: VBoxContainer
var _station_grid: GridContainer
var _recipes: VBoxContainer
var _status: Label
var _slots: Array[InventorySlot] = []
var _selected: Dictionary = {}
var _session := 0
var _previous_focus: Control
var _containers: BlockContainers
var _station_position := Vector3i.ZERO
var _station_kind := 0
var _furnace_status: Label
var _recipe_buttons: Array[Button] = []
var _legacy_inventory := false
var _game_mode: int = GameMode.SURVIVAL
var _creative_controls: Array[Control] = []
var _catalog: VBoxContainer
var _catalog_grid: GridContainer
var _catalog_buttons: Dictionary = {}
const RECIPE_CATEGORIES := ["Basics", "Tools", "Storage", "Food", "Building", "Lighting"]
var _recipe_search: LineEdit
var _recipe_category: OptionButton
var _craftable_only: CheckBox
var _recipe_cards: Array[VBoxContainer] = []
var _recipe_requirements: Array[Label] = []
var _recipe_max_buttons: Array[Button] = []
var _recipe_groups: Dictionary = {}
var _recipe_empty: Label
var _recipe_availability: Array[Dictionary] = []
var _recipes_dirty := true


func _ready() -> void:
	UITheme.apply(_panel)
	_style_static()
	for entry in TIME_BUTTONS:
		var button := _time_row.get_node(entry["node"]) as Button
		button.pressed.connect(_on_time_button.bind(entry["hours"]))
	_weather_button.pressed.connect(_on_weather_button)
	_build_contents()
	set_game_mode(_game_mode)
	get_viewport().size_changed.connect(_apply_responsive_layout)
	GameConfig.interface_scale_changed.connect(_apply_responsive_layout)


func _style_static() -> void:
	_dim.color = Color(UITheme.VOID.r, UITheme.VOID.g, UITheme.VOID.b, 0.62)
	_panel.add_theme_stylebox_override("panel", UITheme.modal_style())
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	UITheme.style_heading(_heading)
	var box := _heading.get_parent() as VBoxContainer
	var eyebrow := UITheme.eyebrow("Supplies")
	box.add_child(eyebrow)
	box.move_child(eyebrow, 0)

	# Wrap the centered time row in a segmented strip and left-align it.
	var strip := PanelContainer.new()
	strip.add_theme_stylebox_override("panel", UITheme.panel_style(
		Color(UITheme.SURFACE_HI.r, UITheme.SURFACE_HI.g, UITheme.SURFACE_HI.b, 0.5), UITheme.LINE, 1, 8))
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var time_index := _time_row.get_index()
	_time_row.reparent(strip)
	box.add_child(strip)
	var time_eyebrow := UITheme.eyebrow("Set Time")
	box.add_child(time_eyebrow)
	box.move_child(time_eyebrow, time_index)
	box.move_child(strip, time_index + 1)
	_time_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	_time_row.add_theme_constant_override("separation", 4)
	for entry in TIME_BUTTONS:
		var button := _time_row.get_node(entry["node"]) as Button
		UITheme.style_button_flat(button)
		button.custom_minimum_size = Vector2(108.0, 34.0)

	var weather_eyebrow := UITheme.eyebrow("Weather")
	box.add_child(weather_eyebrow)
	box.move_child(weather_eyebrow, _weather_row.get_index())
	_creative_controls.assign([time_eyebrow, strip, weather_eyebrow, _weather_row])
	_weather_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	UITheme.style_button_ghost(_weather_button)
	_weather_button.custom_minimum_size = Vector2(240.0, 38.0)

	_grid.columns = 10
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	_hint.add_theme_color_override("font_color", UITheme.MUTED)
	UITheme.apply_font_size(_hint, 13)
	_refresh_hint()


## The close hint follows the live inventory binding.
func _refresh_hint() -> void:
	_hint.text = "Drag or click two slots to move. Shift: half stack.\nPress %s or ESC to close" % GameConfig.input_key("inventory")
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _unhandled_input(event: InputEvent) -> void:
	if visible:
		if event.is_action_pressed("inventory") or event.is_action_pressed("ui_cancel"):
			close_panel()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("inventory"):
		open_panel()
		get_viewport().set_input_as_handled()


func open_panel() -> void:
	if visible:
		return
	_previous_focus = get_viewport().gui_get_focus_owner()
	_session += 1
	_apply_responsive_layout()
	_refresh_hint()
	_refresh()
	visible = true
	Motion.dim_in(_dim)
	Motion.pop_in(_panel)
	opened.emit()
	if not visible:
		return
	if not _slots.is_empty():
		_slots[0].grab_focus()
	else:
		(_time_row.get_node("MorningButton") as Button).grab_focus()


func _apply_responsive_layout() -> void:
	if not is_node_ready():
		return
	var viewport_size := get_viewport().get_visible_rect().size
	_grid.columns = 10 if viewport_size.x >= 820.0 else 5
	if _station_grid != null:
		_station_grid.columns = _grid.columns
	if _catalog_grid != null:
		_catalog_grid.columns = 4 if viewport_size.x >= 820.0 else 2
	_panel.custom_minimum_size.x = minf(820.0, maxf(320.0, viewport_size.x - 32.0))
	if _scroll != null:
		_scroll.custom_minimum_size = Vector2(0, maxf(160.0, minf(760.0, viewport_size.y - 72.0)))


func close_panel() -> void:
	if not visible:
		return
	visible = false
	_session += 1
	_selected.clear()
	_set_station_inventory(null)
	_at_table = false
	_recipes_dirty = true
	_containers = null
	_station_kind = 0
	_heading.text = "INVENTORY"
	if is_instance_valid(_previous_focus) and _previous_focus.is_visible_in_tree():
		_previous_focus.grab_focus()
	closed.emit()


func show_inventory(inventory_data: Dictionary, world_ref: VoxelWorld) -> void:
	# Legacy callers can still present counts; configured live models stay authoritative.
	if _inventory == null or _legacy_inventory:
		var model := ItemInventory.new()
		model.migrate_counts(inventory_data)
		configure_inventory(model, world_ref)
		_legacy_inventory = true


func set_weather_state(raining: bool) -> void:
	_weather_button.text = "Weather · Rain" if raining else "Weather · Sunny"


## Session initialization only; the inventory exposes no mode selector.
func set_game_mode(mode: int) -> void:
	_game_mode = GameMode.CREATIVE if mode == GameMode.CREATIVE else GameMode.SURVIVAL
	if not is_node_ready():
		return
	var creative := _game_mode == GameMode.CREATIVE
	for control in _creative_controls:
		control.visible = creative
	_catalog.visible = creative
	if creative and _catalog_buttons.is_empty():
		_build_catalog()


func _build_catalog() -> void:
	var ids: Array[int] = []
	for definition in BlockRegistry.BLOCK_DEFS:
		var id := int(definition[0])
		if id in [BlockRegistry.BLOCK_AIR, BlockRegistry.BLOCK_WATER, BlockRegistry.BLOCK_LAVA, BlockRegistry.BLOCK_FIRE]:
			continue
		if id >= BlockRegistry.BLOCK_WATER_FLOW_7 and id <= BlockRegistry.BLOCK_WATER_FLOW_1:
			continue
		if (int(definition[5]) & BlockRegistry.FLAG_UNBREAKABLE) != 0 or not ItemRegistry.is_valid(id):
			continue
		ids.append(id)
	for offset in ItemRegistry.ITEM_NAMES.size():
		ids.append(ItemRegistry.ITEM_FLINT_AND_STEEL + offset)
	for id in ids:
		var button := Button.new()
		button.text = item_name(id)
		button.icon = item_icon(id)
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 40)
		button.custom_minimum_size = Vector2(144, 64)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.tooltip_text = "Grant %s x%d" % [item_name(id), ItemRegistry.stack_limit(id)]
		UITheme.style_button_flat(button)
		UITheme.apply_font_size(button, 12)
		button.pressed.connect(_grant_catalog_item.bind(id))
		_catalog_grid.add_child(button)
		_catalog_buttons[id] = button


func _grant_catalog_item(id: int) -> void:
	if _game_mode != GameMode.CREATIVE or _inventory == null or not _catalog_buttons.has(id):
		return
	var requested := ItemRegistry.stack_limit(id)
	var remaining := _inventory.add_item(id, requested)
	if remaining == requested:
		_status.text = "No room in backpack. No items were changed."
	else:
		_status.text = "Added %s x%d.%s" % [item_name(id), requested - remaining,
			" No room for the rest." if remaining > 0 else ""]


func _build_contents() -> void:
	var box := _heading.get_parent() as VBoxContainer
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.follow_focus = true
	_panel.add_child(_scroll)
	box.reparent(_scroll)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_station_box = VBoxContainer.new()
	box.add_child(_station_box)
	box.move_child(_station_box, _grid.get_index())
	_station_grid = GridContainer.new()
	_station_grid.columns = 10
	_station_box.add_child(UITheme.eyebrow("Station storage"))
	_station_box.add_child(_station_grid)
	_furnace_status = UITheme.muted_label("", 12)
	_furnace_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_station_box.add_child(_furnace_status)
	_station_box.hide()
	var inventory_title := UITheme.eyebrow("Backpack / first 10 slots are the hotbar")
	box.add_child(inventory_title)
	box.move_child(inventory_title, _grid.get_index())
	_catalog = VBoxContainer.new()
	_catalog.name = "CreativeCatalog"
	box.add_child(_catalog)
	box.move_child(_catalog, _hint.get_index())
	_catalog.add_child(UITheme.eyebrow("Creative catalog / select to add a stack"))
	_catalog_grid = GridContainer.new()
	_catalog_grid.columns = 4
	_catalog_grid.add_theme_constant_override("h_separation", 8)
	_catalog_grid.add_theme_constant_override("v_separation", 8)
	_catalog.add_child(_catalog_grid)
	_recipes = VBoxContainer.new()
	box.add_child(_recipes)
	box.move_child(_recipes, _hint.get_index())
	_recipes.add_child(UITheme.eyebrow("Recipe book / ingredients shown as owned / needed"))
	var guide := UITheme.muted_label("Getting started: Any logs -> planks (in inventory) -> sticks + crafting table. Place the table and right-click it -> wooden pickaxe -> mine stone for cobblestone -> stone pickaxe + furnace -> smelt iron ore. Table recipes require opening the placed table.", 13)
	guide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_recipes.add_child(guide)
	_recipe_search = LineEdit.new()
	_recipe_search.placeholder_text = "Search recipes or ingredients"
	_recipe_search.tooltip_text = "Search by recipe name, wood species, or ingredient"
	_recipe_search.text_changed.connect(func(_text: String) -> void: _refresh_recipes())
	_recipes.add_child(_recipe_search)
	_recipe_category = OptionButton.new()
	_recipe_category.add_item("All categories")
	for category in RECIPE_CATEGORIES:
		_recipe_category.add_item(category)
	_recipe_category.item_selected.connect(func(_index: int) -> void: _refresh_recipes())
	_recipes.add_child(_recipe_category)
	_craftable_only = CheckBox.new()
	_craftable_only.text = "Craftable only"
	_craftable_only.toggled.connect(func(_enabled: bool) -> void: _refresh_recipes())
	_recipes.add_child(_craftable_only)
	for category in RECIPE_CATEGORIES:
		var group := VBoxContainer.new()
		group.add_child(UITheme.eyebrow(category))
		_recipes.add_child(group)
		_recipe_groups[category] = group
	for recipe in CraftingRecipes.RECIPES:
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 6)
		_recipe_groups[str(recipe["category"]).capitalize()].add_child(card)
		_recipe_cards.append(card)
		var title := Label.new()
		title.text = "%s x%d" % [item_name(int(recipe["output"])), int(recipe["count"])]
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UITheme.apply_font_size(title, 16)
		card.add_child(title)
		var requirements := UITheme.muted_label("", 13)
		requirements.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(requirements)
		_recipe_requirements.append(requirements)
		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 40)
		UITheme.style_button_ghost(button)
		UITheme.apply_font_size(button, 13)
		button.pressed.connect(_craft.bind(str(recipe["id"])))
		card.add_child(button)
		_recipe_buttons.append(button)
		var maximum := Button.new()
		maximum.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UITheme.style_button_ghost(maximum)
		UITheme.apply_font_size(maximum, 13)
		maximum.pressed.connect(_craft_max.bind(str(recipe["id"])))
		card.add_child(maximum)
		_recipe_max_buttons.append(maximum)
	_recipe_empty = UITheme.muted_label("No matching recipes. Clear search or turn off Craftable only to see requirements.", 13)
	_recipe_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_recipes.add_child(_recipe_empty)
	_status = UITheme.muted_label("", 13)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	box.move_child(_status, _hint.get_index())
	var close_button := Button.new()
	close_button.text = "Close"
	UITheme.style_button_ghost(close_button)
	close_button.pressed.connect(close_panel)
	box.add_child(close_button)
	_rebuild_slots()
	_apply_responsive_layout()


func configure_inventory(model: ItemInventory, world_ref: VoxelWorld) -> void:
	_legacy_inventory = false
	if _inventory != null and _inventory.changed.is_connected(_on_inventory_changed):
		_inventory.changed.disconnect(_on_inventory_changed)
	_inventory = model
	_recipes_dirty = true
	_world = world_ref
	_session += 1
	_selected.clear()
	if _inventory != null:
		_inventory.changed.connect(_on_inventory_changed)
	if is_node_ready():
		_rebuild_slots()
		for id in _catalog_buttons:
			_catalog_buttons[id].icon = item_icon(int(id))


func _set_station_inventory(model: ItemInventory) -> void:
	if _station_inventory != null and _station_inventory.changed.is_connected(_refresh):
		_station_inventory.changed.disconnect(_refresh)
	_station_inventory = model
	if model != null:
		model.changed.connect(_refresh)
	_session += 1
	_selected.clear()
	_rebuild_slots()


func _rebuild_slots() -> void:
	_slots.clear()
	for grid in [_grid, _station_grid]:
		for child in grid.get_children():
			grid.remove_child(child)
			child.queue_free()
	for model in [_inventory, _station_inventory]:
		if model == null:
			continue
		var grid: GridContainer = _grid if model == _inventory else _station_grid
		for index in model.slots.size():
			var slot := InventorySlot.new()
			slot.inventory = model
			slot.slot_index = index
			slot.overlay = self
			if model == _inventory and index < ItemInventory.HOTBAR_SIZE:
				slot.caption = str((index + 1) % ItemInventory.HOTBAR_SIZE)
			elif model == _station_inventory and model.slots.size() == 3:
				slot.caption = ["Input", "Fuel", "Output"][index]
			grid.add_child(slot)
			_slots.append(slot)
	_station_box.visible = _station_inventory != null
	_refresh()


func _refresh() -> void:
	for slot in _slots:
		slot.refresh()
		slot.selected = not _selected.is_empty() and _selected.get("inventory") == slot.inventory and _selected.get("index") == slot.slot_index
	_refresh_recipes()
	if _furnace_status != null:
		_furnace_status.visible = _station_kind == BlockRegistry.BLOCK_FURNACE
		if _containers != null and _furnace_status.visible:
			var state := _containers.get_furnace(_station_position)
			_furnace_status.text = "Smelting: %d%% | Fuel: %.1fs remaining\nPut a recipe ingredient in Input and fuel in Fuel. Close inventory to resume smelting: inventory pauses the game. Reopen the furnace to collect Output (extraction only).\nOne input -> one output every %.0f seconds.\n" % [
				roundi(float(state.get("progress", 0.0)) / CraftingRecipes.SMELT_SECONDS * 100.0), float(state.get("burn_remaining", 0.0)), CraftingRecipes.SMELT_SECONDS]
			var smelting: PackedStringArray = []
			for id in CraftingRecipes.SMELTING:
				smelting.append("%s -> %s%s" % [item_name(int(id)), item_name(int(CraftingRecipes.SMELTING[id])), " (raw meat: Creative only; survival source not yet available)" if int(id) == ItemRegistry.ITEM_RAW_MEAT else ""])
			var fuels: PackedStringArray = []
			var ids: Array[int] = []
			for definition in BlockRegistry.BLOCK_DEFS:
				ids.append(int(definition[0]))
			for offset in ItemRegistry.ITEM_NAMES.size():
				ids.append(ItemRegistry.ITEM_FLINT_AND_STEEL + offset)
			for id in ids:
				var seconds := ItemRegistry.fuel_seconds(id)
				if seconds > 0.0:
					fuels.append("%s: %.0fs" % [item_name(id), seconds])
			_furnace_status.text += "Recipes:\n%s\nFuel per item:\n%s" % ["\n".join(smelting), ", ".join(fuels)]


func _on_inventory_changed() -> void:
	_recipes_dirty = true
	if visible:
		_refresh()


func item_name(item_id: int) -> String:
	if ItemRegistry.is_item(item_id):
		return ItemRegistry.get_item_name(item_id).capitalize()
	if _world != null:
		return _world.get_block_name(item_id).capitalize()
	for definition in BlockRegistry.BLOCK_DEFS:
		if int(definition[0]) == item_id:
			return str(definition[1]).capitalize()
	return "Item %d" % item_id


func item_icon(item_id: int) -> Texture2D:
	if ItemRegistry.is_item(item_id):
		return ItemRegistry.make_icon(item_id, 48)
	if _world != null and _world.get_registry() != null:
		return BlockIcon.make_icon(_world.get_registry(), item_id, 48)
	return null


func drag_data(slot: InventorySlot, split: bool = false) -> Dictionary:
	if not visible or slot.inventory.slots[slot.slot_index].is_empty():
		return {}
	var stack: Dictionary = slot.inventory.slots[slot.slot_index].duplicate(true)
	return {"overlay": self, "session": _session, "inventory": slot.inventory,
		"index": slot.slot_index, "stack": stack, "split": split,
		"amount": ceili(float(stack["count"]) / 2.0) if split else int(stack["count"])}


func activate_slot(slot: InventorySlot) -> void:
	if _selected.is_empty():
		_selected = drag_data(slot, Input.is_key_pressed(KEY_SHIFT))
		if not _selected.is_empty():
			_status.text = "Selected %s. Choose a destination slot." % item_name(int(_selected["stack"]["id"]))
	else:
		drop_stack(slot, _selected)
		_selected = {}
	_refresh()


func open_station(position: Vector3i, kind: int, containers: BlockContainers) -> void:
	if _inventory == null or containers == null:
		return
	if kind not in [BlockRegistry.BLOCK_CRAFTING_TABLE, BlockRegistry.BLOCK_CHEST, BlockRegistry.BLOCK_FURNACE]:
		return
	var model: ItemInventory
	if kind == BlockRegistry.BLOCK_CHEST:
		model = containers.ensure_chest(position)
	elif kind == BlockRegistry.BLOCK_FURNACE:
		model = containers.ensure_furnace(position)
	if kind != BlockRegistry.BLOCK_CRAFTING_TABLE and model == null:
		return
	_containers = containers
	_station_position = position
	_station_kind = kind
	_at_table = kind == BlockRegistry.BLOCK_CRAFTING_TABLE
	_recipes_dirty = true
	_set_station_inventory(model)
	_heading.text = item_name(kind).to_upper()
	open_panel()
	if visible and not _slots.is_empty():
		_slots[0].grab_focus()


func _accepts(model: ItemInventory, index: int, item_id: int) -> bool:
	if model == _inventory:
		return true
	return model == _station_inventory and _containers != null and _containers.can_insert(_station_position, index, item_id)


func can_drop(slot: InventorySlot, data: Variant) -> bool:
	if not visible or not data is Dictionary or data.get("overlay") != self or data.get("session", -1) != _session:
		return false
	var source: ItemInventory = data.get("inventory") as ItemInventory
	var index := int(data.get("index", -1))
	if source == null or source not in [_inventory, _station_inventory] or slot.inventory not in [_inventory, _station_inventory]:
		return false
	if index < 0 or index >= source.slots.size() or source.slots[index] != data.get("stack"):
		return false
	return not InventoryTransfer.proposal(source, index, slot.inventory, slot.slot_index, bool(data.get("split", false)), _accepts).is_empty()


func drop_stack(slot: InventorySlot, data: Variant) -> bool:
	if not can_drop(slot, data):
		_status.text = "That move is not allowed. No items were moved."
		return false
	var moved := InventoryTransfer.commit(data["inventory"], int(data["index"]), slot.inventory, slot.slot_index, bool(data["split"]), _accepts)
	_status.text = "Stack moved." if moved else "No items were moved."
	_selected = {}
	_refresh()
	return moved


func _refresh_recipes() -> void:
	# Capacity checks copy inventories. Filters and slot selection reuse the result;
	# only backpack mutations or a station change invalidate recipe availability.
	if _recipes_dirty:
		_recipe_availability.clear()
		for recipe in CraftingRecipes.RECIPES:
			var recipe_id := str(recipe["id"])
			_recipe_availability.append({
				"maximum": CraftingRecipes.max_craftable(_inventory, recipe_id, _at_table) if _inventory != null else 0,
				"reason": CraftingRecipes.blocking_reason(_inventory, recipe_id, _at_table) if _inventory != null else "No inventory available.",
			})
		_recipes_dirty = false
	var query := _recipe_search.text.strip_edges().to_lower()
	var shown := 0
	for group in _recipe_groups.values():
		group.hide()
	for index in _recipe_buttons.size():
		var recipe: Dictionary = CraftingRecipes.RECIPES[index]
		var button := _recipe_buttons[index]
		var requirements: PackedStringArray = []
		for id in recipe["ingredients"]:
			var needed := int(recipe["ingredients"][id])
			var owned := _inventory.count_item(int(id)) if _inventory != null else 0
			requirements.append("%s %d/%d" % [item_name(int(id)), owned, needed])
		var recipe_id := str(recipe["id"])
		var category := str(recipe["category"]).capitalize()
		var maximum := int(_recipe_availability[index]["maximum"])
		var reason := str(_recipe_availability[index]["reason"])
		var station := "Crafting table: ready" if _at_table else "Requires crafting table: place it and right-click to open"
		_recipe_requirements[index].text = "%s\n%s%s" % [", ".join(requirements), station if recipe["table"] else "Inventory crafting / no table needed", "\n1 batch: " + reason if not reason.is_empty() else ""]
		button.text = "Craft 1 batch / %s x%d" % [item_name(int(recipe["output"])), int(recipe["count"])]
		button.icon = item_icon(int(recipe["output"]))
		button.disabled = not reason.is_empty()
		button.tooltip_text = reason
		_recipe_max_buttons[index].text = "Craft Max / %d batches / %s x%d" % [maximum, item_name(int(recipe["output"])), maximum * int(recipe["count"])]
		_recipe_max_buttons[index].disabled = maximum == 0
		_recipe_max_buttons[index].tooltip_text = reason if maximum == 0 else "Craft the largest batch that fits, up to 64 batches"
		var searchable := (recipe_id + " " + item_name(int(recipe["output"])) + " " + " ".join(requirements)).to_lower()
		var matches := (query.is_empty() or searchable.contains(query)) and (_recipe_category.selected == 0 or _recipe_category.get_item_text(_recipe_category.selected) == category) and (not _craftable_only.button_pressed or maximum > 0)
		_recipe_cards[index].visible = matches
		if matches:
			_recipe_groups[category].show()
			shown += 1
	_recipe_empty.visible = shown == 0


func _craft_max(recipe_id: String) -> void:
	if _inventory != null:
		_craft(recipe_id, CraftingRecipes.max_craftable(_inventory, recipe_id, _at_table))


func _craft(recipe_id: String, batches: int = 1) -> void:
	_selected = {}
	if _inventory != null and batches > 0 and CraftingRecipes.craft(_inventory, recipe_id, _at_table, batches):
		var recipe := CraftingRecipes.get_recipe(recipe_id)
		_status.text = "Crafted %s x%d (%d batches)." % [item_name(int(recipe["output"])), int(recipe["count"]) * batches, batches]
	else:
		_status.text = CraftingRecipes.blocking_reason(_inventory, recipe_id, _at_table) if _inventory != null else "No inventory available."
	_refresh()


func _on_time_button(hours: float) -> void:
	if _game_mode == GameMode.CREATIVE:
		time_selected.emit(hours)


func _on_weather_button() -> void:
	if _game_mode == GameMode.CREATIVE:
		weather_toggled.emit()
