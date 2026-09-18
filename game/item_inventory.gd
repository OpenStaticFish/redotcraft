class_name ItemInventory
extends RefCounted

signal changed

const HOTBAR_SIZE := 10
const DEFAULT_SIZE := 40
var slots: Array[Dictionary] = []


func _init(size: int = DEFAULT_SIZE) -> void:
	slots.resize(maxi(0, size))
	for index in slots.size():
		slots[index] = {}


## Returns the number of items that did not fit. Tools never stack.
func add_item(id: int, count: int = 1, durability: int = -1) -> int:
	if count <= 0:
		return 0
	if not ItemRegistry.is_valid(id):
		return count
	var maximum := ItemRegistry.max_durability(id)
	var health := maximum if durability < 0 else clampi(durability, 0, maximum)
	if maximum > 0 and health == 0:
		return count
	var remaining := count
	var limit := ItemRegistry.stack_limit(id)
	for slot in slots:
		if slot.get("id", 0) == id and int(slot.get("durability", 0)) == health:
			var amount := mini(remaining, limit - int(slot.count))
			slot.count += amount
			remaining -= amount
	for index in slots.size():
		if remaining == 0:
			break
		if slots[index].is_empty():
			var amount := mini(remaining, limit)
			slots[index] = {"id": id, "count": amount, "durability": health}
			remaining -= amount
	if remaining != count:
		changed.emit()
	return remaining


func remove_at(index: int, count: int = 1) -> bool:
	if index < 0 or index >= slots.size() or count <= 0:
		return false
	if int(slots[index].get("count", 0)) < count:
		return false
	slots[index].count -= count
	if slots[index].count == 0:
		slots[index] = {}
	changed.emit()
	return true


## True when a tool was worn, including the use that breaks it.
func wear_tool(index: int) -> bool:
	if index < 0 or index >= slots.size() or slots[index].is_empty():
		return false
	if ItemRegistry.max_durability(int(slots[index].id)) == 0:
		return false
	slots[index].durability -= 1
	if slots[index].durability <= 0:
		slots[index] = {}
	changed.emit()
	return true


## Split moves the rounded-up half; full moves merge or swap unlike stacks.
func move_stack(from: int, to: int, split: bool = false) -> bool:
	if from < 0 or to < 0 or from >= slots.size() or to >= slots.size() or from == to:
		return false
	var source := slots[from]
	var target := slots[to]
	if source.is_empty():
		return false
	var amount: int = ceili(float(source.count) / 2.0) if split else int(source.count)
	if target.is_empty():
		slots[to] = source.duplicate()
		slots[to].count = amount
	elif target.id == source.id and target.durability == source.durability:
		amount = mini(amount, ItemRegistry.stack_limit(int(target.id)) - int(target.count))
		if amount <= 0:
			return false
		target.count += amount
	else:
		if split:
			return false
		slots[from] = target
		slots[to] = source
		changed.emit()
		return true
	source.count -= amount
	if source.count == 0:
		slots[from] = {}
	changed.emit()
	return true


func count_item(id: int) -> int:
	var count := 0
	for slot in slots:
		if slot.get("id", 0) == id:
			count += int(slot.count)
	return count


func persistent_state() -> Array:
	return slots.duplicate(true)


## Restores positions, rejects unknown IDs, and clamps malformed stack values.
func restore(state: Array) -> void:
	for index in slots.size():
		slots[index] = {}
		if index >= state.size() or not state[index] is Dictionary:
			continue
		var entry: Dictionary = state[index]
		var id := int(entry.get("id", 0))
		if not ItemRegistry.is_valid(id):
			continue
		var count := clampi(int(entry.get("count", 0)), 0, ItemRegistry.stack_limit(id))
		var maximum := ItemRegistry.max_durability(id)
		var health := clampi(int(entry.get("durability", maximum)), 0, maximum)
		if count > 0 and (maximum == 0 or health > 0):
			slots[index] = {"id": id, "count": count, "durability": health}
	changed.emit()


## Replaces legacy counts; returns overflow so callers can retain excess items.
func migrate_counts(counts: Dictionary) -> Dictionary:
	restore([])
	var overflow := {}
	var ids: Array[int] = []
	var totals := {}
	for key in counts:
		var id := int(key)
		if not totals.has(id):
			ids.append(id)
		totals[id] = int(totals.get(id, 0)) + maxi(0, int(counts[key]))
	ids.sort()
	for id in ids:
		var remainder := add_item(id, totals[id])
		if remainder > 0:
			overflow[id] = remainder
	return overflow
