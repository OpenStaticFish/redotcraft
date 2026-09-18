class_name GameMode
extends RefCounted

const CREATIVE := 0
const SURVIVAL := 1


static func is_valid(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) \
		and (value == CREATIVE or value == SURVIVAL)


static func display_name(mode: int) -> String:
	match mode:
		CREATIVE:
			return "Creative"
		SURVIVAL:
			return "Survival"
	return "Unknown"
