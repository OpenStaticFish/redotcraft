extends SceneTree

var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for offset in ItemRegistry.ITEM_NAMES.size():
		var id := ItemRegistry.ITEM_FLINT_AND_STEEL + offset
		var icon := ItemRegistry.make_icon(id, 48)
		_expect(icon != null and icon.get_width() == 48, "every registered item has a hotbar icon")
	var overlay: Node = load("res://ui/inventory_overlay.tscn").instantiate()
	root.add_child(overlay)
	var inventory := ItemInventory.new()
	overlay.configure_inventory(inventory, null)
	overlay.open_panel()
	_expect(overlay._game_mode == GameMode.SURVIVAL, "standalone inventory defaults to survival")
	_expect(overlay._grid.get_child_count() == 40 and inventory.count_item(1) == 0, "empty survival model displays empty slots without starter grants")
	for slot in overlay._slots:
		_expect(slot._count.text.is_empty() and slot._icon.texture == null, "empty slots have no count or icon")
	for control in overlay._creative_controls:
		_expect(not control.visible, "survival hides cheat controls and headings")
	_expect(not overlay._catalog.visible and overlay._catalog_buttons.is_empty(), "survival has no creative catalog")
	var cheats: Array[String] = []
	overlay.time_selected.connect(func(_hours: float) -> void: cheats.append("time"))
	overlay.weather_toggled.connect(func() -> void: cheats.append("weather"))
	overlay._on_time_button(12.0)
	overlay._on_weather_button()
	overlay._grant_catalog_item(1)
	_expect(cheats.is_empty() and inventory.count_item(1) == 0, "survival guards cheat callbacks")
	overlay.close_panel()
	inventory.add_item(5, 12)
	inventory.add_item(14, 8)
	inventory.add_item(1011, 4)
	overlay.configure_inventory(inventory, null)
	overlay.open_panel()
	await process_frame
	await process_frame
	_expect(overlay._grid.get_child_count() == 40, "all forty slots are visible, including empty slots")
	var slot_rect := Rect2(Vector2.ZERO, overlay._slots[0].size)
	_expect(slot_rect.encloses(overlay._slots[0]._count.get_rect()), "stack quantity fits inside its slot")
	_expect(overlay._slots[0]._count.text == "12", "quantity label reflects live count")
	_expect(overlay._panel.size.y <= root.get_visible_rect().size.y, "scrolling bounds modal height")
	var data: Dictionary = overlay.drag_data(overlay._slots[0], true)
	_expect(inventory.slots[0].count == 12, "starting a drag does not remove items")
	_expect(overlay.drop_stack(overlay._slots[10], data), "split drag accepted")
	_expect(inventory.slots[0].count == 6 and inventory.slots[10].count == 6, "rounded split preserves counts")
	_expect(not overlay.drop_stack(overlay._slots[11], data), "stale drag cannot be replayed")
	var containers := BlockContainers.new()
	var chest_pos := Vector3i(1, 2, 3)
	overlay.open_station(chest_pos, BlockRegistry.BLOCK_CHEST, containers)
	data = overlay.drag_data(overlay._slots[10])
	_expect(overlay.drop_stack(overlay._slots[40], data), "backpack to chest transfer")
	_expect(inventory.count_item(5) == 6 and containers.get_inventory(chest_pos).count_item(5) == 6, "chest transfer conserves count")
	data = overlay.drag_data(overlay._slots[40])
	_expect(overlay.drop_stack(overlay._slots[10], data), "chest to backpack transfer")
	var furnace_pos := Vector3i(4, 2, 3)
	overlay.open_station(furnace_pos, BlockRegistry.BLOCK_FURNACE, containers)
	var furnace := containers.get_inventory(furnace_pos)
	_expect(overlay._furnace_status.text.contains("Close inventory") and overlay._furnace_status.text.contains("Creative only"), "furnace explains pause and unavailable survival meat")
	for id in CraftingRecipes.SMELTING:
		_expect(overlay._furnace_status.text.contains("%s -> %s" % [overlay.item_name(int(id)), overlay.item_name(int(CraftingRecipes.SMELTING[id]))]), "furnace lists every actual smelting recipe")
	_expect(overlay._furnace_status.text.contains("%s: %.0fs" % [overlay.item_name(ItemRegistry.ITEM_COAL), ItemRegistry.fuel_seconds(ItemRegistry.ITEM_COAL)]), "furnace lists actual fuel duration")
	data = overlay.drag_data(overlay._slots[1])
	var before := inventory.persistent_state()
	_expect(not overlay.drop_stack(overlay._slots[42], data), "output rejects insertion")
	_expect(not overlay.drop_stack(overlay._slots[41], data), "fuel rejects ore")
	_expect(inventory.persistent_state() == before, "rejected drags leave source unchanged")
	_expect(overlay.drop_stack(overlay._slots[40], data), "ore accepted in input")
	data = overlay.drag_data(overlay._slots[2])
	_expect(overlay.drop_stack(overlay._slots[41], data), "coal accepted as fuel")
	furnace.slots[2] = {"id": 1012, "count": 2, "durability": 0}
	furnace.changed.emit()
	data = overlay.drag_data(overlay._slots[42])
	_expect(not overlay.drop_stack(overlay._slots[0], data), "output cannot swap with occupied unlike stack")
	_expect(furnace.slots[2].count == 2, "rejected output swap preserves output")
	_expect(overlay.drop_stack(overlay._slots[3], data), "output can be extracted to empty slot")
	_expect(inventory.count_item(1012) == 2 and furnace.slots[2].is_empty(), "output extraction has no duplication")
	data = overlay.drag_data(overlay._slots[0])
	overlay.close_panel()
	overlay.open_panel()
	_expect(not overlay.drop_stack(overlay._slots[11], data), "closing invalidates pending drag")
	_expect(not overlay._at_table, "normal inventory has no crafting table access")
	overlay.open_station(Vector3i.ZERO, BlockRegistry.BLOCK_CRAFTING_TABLE, containers)
	_expect(overlay._at_table, "crafting table enables table recipes")
	var wood_before := inventory.count_item(5)
	overlay._recipe_buttons[_recipe_index("planks_oak")].pressed.emit()
	_expect(inventory.count_item(5) == wood_before - 1 and inventory.count_item(74) == 4, "recipe button crafts one batch")
	paused = true
	_expect(overlay.can_process(), "inventory remains interactive while paused")
	overlay.close_panel()
	paused = false
	var modal_button := Button.new()
	root.add_child(modal_button)
	modal_button.grab_focus()
	var reject_open := func() -> void: overlay.close_panel()
	overlay.opened.connect(reject_open)
	overlay.open_panel()
	_expect(not overlay.visible and modal_button.has_focus(), "rejected inventory open preserves modal focus")
	overlay.open_station(chest_pos, BlockRegistry.BLOCK_CHEST, containers)
	_expect(not overlay.visible and modal_button.has_focus(), "rejected station open preserves modal focus")
	modal_button.free()
	overlay.queue_free()
	await process_frame
	await _verify_creative()
	await _verify_recipe_book()
	# Let the real recipe button's click cue finish before tearing down audio.
	await create_timer(0.5).timeout
	print("INVENTORY UI VERIFY: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(0 if _failures == 0 else 1)


func _verify_creative() -> void:
	var overlay: Node = load("res://ui/inventory_overlay.tscn").instantiate()
	root.add_child(overlay)
	var inventory := ItemInventory.new(2)
	overlay.configure_inventory(inventory, null)
	overlay.set_game_mode(GameMode.CREATIVE)
	overlay.open_panel()
	await process_frame
	_expect(overlay._catalog.is_visible_in_tree(), "creative catalog is visible")
	for control in overlay._creative_controls:
		_expect(control.is_visible_in_tree(), "creative exposes time and weather controls")
	for definition in BlockRegistry.BLOCK_DEFS:
		var id := int(definition[0])
		var water := id == BlockRegistry.BLOCK_WATER or (id >= BlockRegistry.BLOCK_WATER_FLOW_7 and id <= BlockRegistry.BLOCK_WATER_FLOW_1)
		var excluded := id in [BlockRegistry.BLOCK_AIR, BlockRegistry.BLOCK_LAVA, BlockRegistry.BLOCK_FIRE] or water or (int(definition[5]) & BlockRegistry.FLAG_UNBREAKABLE) != 0
		_expect(overlay._catalog_buttons.has(id) == (not excluded and ItemRegistry.is_valid(id)), "catalog filters block %d" % id)
	for offset in ItemRegistry.ITEM_NAMES.size():
		_expect(overlay._catalog_buttons.has(ItemRegistry.ITEM_FLINT_AND_STEEL + offset), "catalog contains every registered item")
	_expect(overlay.find_children("*", "OptionButton", true, false).size() == 1 and overlay._recipe_category.item_count == 7, "only selector is the recipe category, not game mode")
	for button in overlay.find_children("*", "Button", true, false):
		_expect(not "survival" in button.text.to_lower() and not "creative" in button.text.to_lower(), "no mode switching button")
	overlay._catalog_buttons[1].pressed.emit()
	_expect(inventory.count_item(1) == 64, "catalog click grants exactly one block stack")
	overlay._catalog_buttons[ItemRegistry.ITEM_WOOD_PICKAXE].pressed.emit()
	_expect(inventory.count_item(ItemRegistry.ITEM_WOOD_PICKAXE) == 1 and inventory.slots[1].durability == ItemRegistry.max_durability(ItemRegistry.ITEM_WOOD_PICKAXE), "catalog tools have full durability and do not stack")
	var before := inventory.persistent_state()
	overlay._catalog_buttons[2].pressed.emit()
	overlay._catalog_buttons[1].pressed.emit()
	_expect(inventory.persistent_state() == before, "full inventory grants neither duplicate nor replace existing items")
	_expect(overlay._status.text.contains("No room"), "full inventory reports feedback")
	inventory.remove_at(0, 3)
	overlay._catalog_buttons[1].pressed.emit()
	_expect(inventory.persistent_state() == before, "partial capacity grants only the three available spaces")
	_expect(overlay._status.text.contains("x3") and overlay._status.text.contains("No room"), "partial grant reports actual count and overflow")
	overlay.close_panel()
	overlay.open_panel()
	_expect(overlay._game_mode == GameMode.CREATIVE, "opening and closing preserves fixed session mode")
	overlay.queue_free()
	await process_frame


func _recipe_index(id: String) -> int:
	for index in CraftingRecipes.RECIPES.size():
		if str(CraftingRecipes.RECIPES[index]["id"]) == id:
			return index
	return -1


func _verify_recipe_book() -> void:
	var overlay: Node = load("res://ui/inventory_overlay.tscn").instantiate()
	root.add_child(overlay)
	var inventory := ItemInventory.new()
	overlay.configure_inventory(inventory, null)
	overlay.open_panel()
	var planks := _recipe_index("planks_oak")
	var pick := _recipe_index("wood_pickaxe")
	_expect(overlay._recipe_buttons.size() == CraftingRecipes.RECIPES.size(), "recipe buttons preserve model order")
	for index in CraftingRecipes.RECIPES.size():
		_expect(overlay._recipe_cards[index].visible, "unavailable recipes remain discoverable by default")
		_expect(not overlay._recipe_requirements[index].text.is_empty(), "requirements are readable outside disabled buttons")
	_expect(overlay._recipe_requirements[pick].text.contains("Requires crafting table"), "table requirement explains opening a placed table")
	overlay._recipe_search.text = "spruce"
	overlay._recipe_search.text_changed.emit("spruce")
	_expect(overlay._recipe_cards[_recipe_index("planks_spruce")].visible and not overlay._recipe_cards[planks].visible, "search matches recipe identity and ingredients")
	overlay._recipe_search.text = "zz-no-such-recipe"
	overlay._recipe_search.text_changed.emit("zz-no-such-recipe")
	_expect(overlay._recipe_empty.visible, "empty search has recovery guidance")
	overlay._recipe_search.text = ""
	overlay._recipe_search.text_changed.emit("")
	overlay._recipe_category.select(2)
	overlay._recipe_category.item_selected.emit(2)
	for index in CraftingRecipes.RECIPES.size():
		_expect(overlay._recipe_cards[index].visible == (str(CraftingRecipes.RECIPES[index]["category"]).to_lower() == "tools"), "category filter shows only its group")
	overlay._recipe_category.select(0)
	overlay._recipe_category.item_selected.emit(0)
	overlay._craftable_only.button_pressed = true
	_expect(overlay._recipe_empty.visible, "empty inventory has no craftable recipes")
	inventory.add_item(5, 3)
	_expect(overlay._recipe_cards[planks].visible and not overlay._recipe_cards[pick].visible, "craftable filter updates with live inventory")
	_expect(overlay._recipe_requirements[planks].text.contains("3/1"), "ingredients display owned and needed counts")
	_expect(overlay._recipe_max_buttons[planks].text.contains("3 batches") and overlay._recipe_max_buttons[planks].focus_mode == Control.FOCUS_ALL, "max control reports batch count and supports keyboard focus")
	var cached: Dictionary = overlay._recipe_availability[planks]
	overlay._recipe_search.text_changed.emit("")
	overlay._refresh()
	_expect(is_same(cached, overlay._recipe_availability[planks]), "filter and selection refresh reuse capacity trials")
	var stale: Dictionary = overlay.drag_data(overlay._slots[0])
	overlay._recipe_max_buttons[planks].pressed.emit()
	_expect(inventory.count_item(5) == 0 and inventory.count_item(74) == 12, "Craft Max consumes exactly available batches")
	_expect(not overlay.can_drop(overlay._slots[10], stale), "crafting invalidates stale source stack drag")
	_expect(overlay._status.text.contains("x12") and not overlay._recipe_cards[planks].visible, "max output feedback and craftability refresh")
	_expect(not is_same(cached, overlay._recipe_availability[planks]), "craft mutation invalidates cached capacity")
	overlay._craftable_only.button_pressed = false
	var full := ItemInventory.new(1)
	full.add_item(5, 64)
	overlay.configure_inventory(full, null)
	var reason := CraftingRecipes.blocking_reason(full, "planks_oak", false)
	_expect(not reason.is_empty() and overlay._recipe_requirements[planks].text.contains(reason), "capacity reason is visible, not just a tooltip")
	_expect(overlay._recipe_buttons[planks].disabled and overlay._recipe_max_buttons[planks].disabled, "capacity disables both crafting controls")
	var before := full.persistent_state()
	overlay._craft_max("planks_oak")
	_expect(full.persistent_state() == before, "blocked max leaves inventory unchanged")
	var compact := ItemInventory.new(1)
	compact.add_item(74, 4)
	overlay.configure_inventory(compact, null)
	var sticks := _recipe_index("sticks")
	_expect(overlay._recipe_buttons[sticks].disabled and not overlay._recipe_max_buttons[sticks].disabled, "max can free ingredient space even when a single batch cannot fit")
	overlay._recipe_max_buttons[sticks].grab_focus()
	await process_frame
	var accept := InputEventAction.new()
	accept.action = "ui_accept"
	accept.pressed = true
	Input.parse_input_event(accept)
	await process_frame
	accept = InputEventAction.new()
	accept.action = "ui_accept"
	accept.pressed = false
	Input.parse_input_event(accept)
	await process_frame
	_expect(compact.count_item(74) == 0 and compact.count_item(1010) == 8, "max accounts for slots freed by consuming ingredients")
	overlay.configure_inventory(inventory, null)
	inventory.add_item(1010, 2)
	_expect(overlay._recipe_buttons[pick].disabled, "materials alone do not bypass table access")
	var containers := BlockContainers.new()
	overlay.open_station(Vector3i.ZERO, BlockRegistry.BLOCK_CRAFTING_TABLE, containers)
	_expect(not overlay._recipe_buttons[pick].disabled, "opening table updates recipe availability")
	overlay.close_panel()
	cached = overlay._recipe_availability[planks]
	inventory.add_item(5, 1)
	_expect(overlay._recipes_dirty and is_same(cached, overlay._recipe_availability[planks]), "closed inventory defers capacity trials")
	overlay.open_panel()
	_expect(not overlay._recipes_dirty and not is_same(cached, overlay._recipe_availability[planks]), "reopening refreshes deferred inventory changes")
	_expect(overlay._recipe_buttons[pick].disabled, "closing table removes table access")
	var previous_scale := root.content_scale_factor
	root.content_scale_factor = previous_scale * root.get_visible_rect().size.x / 640.0
	await process_frame
	await process_frame
	_expect(overlay._grid.columns == 5, "narrow layout reduces backpack columns")
	_expect(overlay._panel.size.x <= root.get_visible_rect().size.x and overlay._panel.size.y <= root.get_visible_rect().size.y, "recipe book stays within narrow viewport")
	_expect(overlay._scroll.follow_focus, "keyboard navigation follows focused recipes through scroll panel")
	root.content_scale_factor = previous_scale
	overlay.close_panel()
	overlay.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
