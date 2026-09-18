class_name BlockContainers
extends RefCounted

signal changed

const CHEST_SIZE := 27
const INPUT := 0
const FUEL := 1
const OUTPUT := 2

## Vector3i -> {block_id, inventory, progress, burn_remaining, recipe_input}.
## Inventory slots are directly accessible; furnace UI must restrict output to
## extraction and use can_insert() before inserting into its other slots.
var containers: Dictionary = {}


func ensure_chest(position: Vector3i) -> ItemInventory:
	return _ensure(position, BlockRegistry.BLOCK_CHEST, CHEST_SIZE)


func ensure_furnace(position: Vector3i) -> ItemInventory:
	return _ensure(position, BlockRegistry.BLOCK_FURNACE, 3)


func _ensure(position: Vector3i, block_id: int, size: int) -> ItemInventory:
	if containers.has(position):
		return containers[position].inventory if containers[position].block_id == block_id else null
	var inventory := ItemInventory.new(size)
	inventory.changed.connect(changed.emit)
	containers[position] = {"block_id": block_id, "inventory": inventory,
		"progress": 0.0, "burn_remaining": 0.0, "recipe_input": 0}
	changed.emit()
	return inventory


## Queries never create containers, including when chunks load or tick runs.
func get_inventory(position: Vector3i) -> ItemInventory:
	return containers[position].inventory if containers.has(position) else null


## Returns live furnace state, or {}. Progress and burn_remaining are seconds.
func get_furnace(position: Vector3i) -> Dictionary:
	if containers.has(position) and containers[position].block_id == BlockRegistry.BLOCK_FURNACE:
		return containers[position]
	return {}


func can_insert(position: Vector3i, slot: int, item_id: int) -> bool:
	var inventory := get_inventory(position)
	if inventory == null or slot < 0 or slot >= inventory.slots.size() or not ItemRegistry.is_valid(item_id):
		return false
	if containers[position].block_id == BlockRegistry.BLOCK_CHEST:
		return true
	return (slot == INPUT and CraftingRecipes.SMELTING.has(item_id)) or (slot == FUEL and ItemRegistry.fuel_seconds(item_id) > 0.0)


## Removes the model and returns its stacks for the caller to drop or retain.
func remove(position: Vector3i) -> Array:
	var inventory := get_inventory(position)
	if inventory == null:
		return []
	var contents := inventory.persistent_state()
	inventory.changed.disconnect(changed.emit)
	containers.erase(position)
	changed.emit()
	return contents


func tick(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	var dirty := false
	for position in containers:
		var furnace: Dictionary = containers[position]
		if furnace.block_id != BlockRegistry.BLOCK_FURNACE:
			continue
		var inventory: ItemInventory = furnace.inventory
		var remaining := delta
		while remaining > 0.0:
			var input_id := int(inventory.slots[INPUT].get("id", 0))
			var output_id := int(CraftingRecipes.SMELTING.get(input_id, 0))
			if furnace.recipe_input != input_id:
				furnace.progress = 0.0
				furnace.recipe_input = input_id
				dirty = true
			var output := inventory.slots[OUTPUT]
			var fits := output.is_empty() or (int(output.id) == output_id and int(output.count) < ItemRegistry.stack_limit(output_id))
			if output_id == 0 or not fits:
				if furnace.progress != 0.0 or furnace.burn_remaining > 0.0:
					dirty = true
				furnace.progress = 0.0
				furnace.burn_remaining = maxf(0.0, float(furnace.burn_remaining) - remaining)
				break
			if furnace.burn_remaining <= 0.0:
				var fuel_id := int(inventory.slots[FUEL].get("id", 0))
				var burn := ItemRegistry.fuel_seconds(fuel_id)
				if burn <= 0.0:
					break
				furnace.burn_remaining = burn
				inventory.remove_at(FUEL)
			var step := minf(remaining, minf(float(furnace.burn_remaining), CraftingRecipes.SMELT_SECONDS - float(furnace.progress)))
			furnace.burn_remaining = maxf(0.0, float(furnace.burn_remaining) - step)
			furnace.progress += step
			remaining -= step
			dirty = true
			if furnace.progress >= CraftingRecipes.SMELT_SECONDS:
				furnace.progress = 0.0
				# Commit both slots before notifying observers.
				inventory.slots[INPUT].count -= 1
				if inventory.slots[INPUT].count == 0:
					inventory.slots[INPUT] = {}
				if output.is_empty():
					inventory.slots[OUTPUT] = {"id": output_id, "count": 1, "durability": 0}
				else:
					output.count += 1
				inventory.changed.emit()
	if dirty:
		changed.emit()


## JSON-safe, versioned state. No scene nodes or live inventory references.
func persistent_state() -> Dictionary:
	var entries: Array = []
	for position: Vector3i in containers:
		var entry: Dictionary = containers[position]
		entries.append({"position": [position.x, position.y, position.z],
			"block_id": entry.block_id, "slots": entry.inventory.persistent_state(),
			"progress": entry.progress, "burn_remaining": entry.burn_remaining,
			"recipe_input": entry.recipe_input})
	return {"version": 1, "containers": entries}


func restore(state: Dictionary) -> void:
	if int(state.get("version", 0)) != 1 or not state.get("containers") is Array:
		return
	for entry in containers.values():
		entry.inventory.changed.disconnect(changed.emit)
	containers.clear()
	for value in state.containers:
		if not value is Dictionary:
			continue
		var entry: Dictionary = value
		var coords = entry.get("position")
		if not coords is Array or coords.size() != 3 or not entry.get("slots") is Array:
			continue
		var block_id := int(entry.get("block_id", 0))
		if block_id != BlockRegistry.BLOCK_CHEST and block_id != BlockRegistry.BLOCK_FURNACE:
			continue
		var position := Vector3i(int(coords[0]), int(coords[1]), int(coords[2]))
		if containers.has(position):
			continue
		var inventory := _ensure(position, block_id, CHEST_SIZE if block_id == BlockRegistry.BLOCK_CHEST else 3)
		inventory.restore(entry.slots)
		if block_id == BlockRegistry.BLOCK_FURNACE:
			var furnace: Dictionary = containers[position]
			var progress := float(entry.get("progress", 0.0))
			var burn := float(entry.get("burn_remaining", 0.0))
			furnace.progress = clampf(progress, 0.0, CraftingRecipes.SMELT_SECONDS) if is_finite(progress) else 0.0
			furnace.burn_remaining = clampf(burn, 0.0, 80.0) if is_finite(burn) else 0.0
			furnace.recipe_input = int(entry.get("recipe_input", 0))
	changed.emit()
