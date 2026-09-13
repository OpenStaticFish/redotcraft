## Compact profile table. Definition values are stored contiguously to avoid per-cell dictionaries.
class_name TerrainProfileCatalog
extends RefCounted

const PLAINS: int = 0
const HILLS: int = 1
const PLATEAU: int = 2
const MOUNTAINS: int = 3
const RIDGED_MOUNTAINS: int = 4

const FIELD_BASE_HEIGHT: int = 0
const FIELD_RELIEF: int = 1
const FIELD_DETAIL_FREQUENCY: int = 2
const FIELD_DETAIL_STRENGTH: int = 3
const FIELD_RIDGE_WEIGHT: int = 4
const FIELD_EROSION_WEIGHT: int = 5
const FIELD_LOCAL_RELIEF: int = 6
const FIELD_SURFACE_DETAIL: int = 7
const FIELD_COUNT: int = 8

var _names: PackedStringArray = PackedStringArray()
var _values: PackedFloat32Array = PackedFloat32Array()


## Custom arrays must have one name and FIELD_COUNT values per profile.
func _init(definition_names: PackedStringArray = PackedStringArray(), definition_values: PackedFloat32Array = PackedFloat32Array()) -> void:
	if definition_names.is_empty() and definition_values.is_empty():
		_set_defaults()
	elif definition_names.size() > 0 and definition_values.size() == definition_names.size() * FIELD_COUNT:
		_names = definition_names.duplicate()
		_values = definition_values.duplicate()
	else:
		push_warning("Invalid terrain profile definitions; using defaults")
		_set_defaults()


func profile_count() -> int:
	return _names.size()


func name_for(profile: int) -> String:
	if profile < 0 or profile >= _names.size():
		return "plains"
	return _names[profile]


func id_for_name(profile_name: String) -> int:
	for profile in _names.size():
		if _names[profile] == profile_name:
			return profile
	return PLAINS


func value(profile: int, field: int) -> float:
	var safe_profile: int = clampi(profile, 0, _names.size() - 1)
	var safe_field: int = clampi(field, 0, FIELD_COUNT - 1)
	return _values[safe_profile * FIELD_COUNT + safe_field]


func base_height(profile: int) -> float:
	return value(profile, FIELD_BASE_HEIGHT)


func relief(profile: int) -> float:
	return value(profile, FIELD_RELIEF)


func detail_frequency(profile: int) -> float:
	return value(profile, FIELD_DETAIL_FREQUENCY)


func detail_strength(profile: int) -> float:
	return value(profile, FIELD_DETAIL_STRENGTH)


func ridge_weight(profile: int) -> float:
	return value(profile, FIELD_RIDGE_WEIGHT)


func erosion_weight(profile: int) -> float:
	return value(profile, FIELD_EROSION_WEIGHT)


func _set_defaults() -> void:
	_names = PackedStringArray(["plains", "hills", "plateau", "mountains", "ridged_mountains"])
	_values = PackedFloat32Array([
		# base, relief, broad detail frequency/strength, ridge, erosion,
		# local (24-64 block) relief, fine (10 block) surface detail.
		54.0, 5.0, 0.012, 1.5, 0.0, 0.75, 1.9, 0.22,
		61.0, 14.0, 0.014, 3.0, 0.18, 0.60, 3.4, 0.30,
		70.0, 18.0, 0.010, 2.5, 0.12, 0.35, 2.6, 0.24,
		83.0, 32.0, 0.009, 4.0, 0.55, 0.20, 5.2, 0.44,
		96.0, 42.0, 0.008, 5.0, 0.70, 0.10, 6.5, 0.55,
	])
