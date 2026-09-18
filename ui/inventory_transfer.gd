class_name InventoryTransfer
extends RefCounted

## Return the two proposed stacks without mutating either inventory. Checking
## the reverse side of a swap prevents inserting items into furnace outputs.
static func proposal(source: ItemInventory, from: int, target: ItemInventory, to: int, split: bool, accepts: Callable) -> Array:
	if source == null or target == null or from < 0 or to < 0 or from >= source.slots.size() or to >= target.slots.size():
		return []
	if source == target and from == to:
		return []
	var first: Dictionary = source.slots[from].duplicate(true)
	var second: Dictionary = target.slots[to].duplicate(true)
	if first.is_empty() or not accepts.call(target, to, int(first["id"])):
		return []
	var amount := ceili(float(first["count"]) / 2.0) if split else int(first["count"])
	if second.is_empty():
		second = first.duplicate(true)
		second["count"] = amount
	elif second["id"] == first["id"] and second.get("durability", 0) == first.get("durability", 0):
		amount = mini(amount, ItemRegistry.stack_limit(int(first["id"])) - int(second["count"]))
		if amount <= 0:
			return []
		second["count"] += amount
	else:
		if split or not accepts.call(source, from, int(second["id"])):
			return []
		return [second, first]
	first["count"] -= amount
	if int(first["count"]) == 0:
		first = {}
	return [first, second]


static func commit(source: ItemInventory, from: int, target: ItemInventory, to: int, split: bool, accepts: Callable) -> bool:
	var stacks := proposal(source, from, target, to, split, accepts)
	if stacks.is_empty():
		return false
	# Both sides are committed before any observer sees a changed signal.
	source.slots[from] = stacks[0]
	target.slots[to] = stacks[1]
	source.changed.emit()
	if target != source:
		target.changed.emit()
	return true
