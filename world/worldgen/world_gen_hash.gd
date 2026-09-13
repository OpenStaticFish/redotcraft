## Integer-only coordinate hashing for worker-safe, reproducible world generation.
class_name WorldGenHash
extends RefCounted

const MODULUS: int = 2147483647
const UNIT_DENOMINATOR: float = 2147483646.0


static func positive_mod(value: int, modulus: int) -> int:
	assert(modulus > 0, "modulus must be positive")
	var result: int = value % modulus
	if result < 0:
		result += modulus
	return result


## Division rounded toward negative infinity, unlike truncating integer division.
static func floor_div(value: int, divisor: int) -> int:
	assert(divisor > 0, "divisor must be positive")
	var quotient: int = value / divisor
	var remainder: int = value % divisor
	if remainder < 0:
		quotient -= 1
	return quotient


static func floor_mod(value: int, divisor: int) -> int:
	return value - floor_div(value, divisor) * divisor


static func hash_1d(seed: int, x: int) -> int:
	return _finalize(_combine(_reduce(seed), _coordinate_mix(x)))


static func hash_2d(seed: int, x: int, z: int) -> int:
	var value: int = _combine(_reduce(seed), _coordinate_mix(x))
	value = _combine(value, _coordinate_mix(z + 104729))
	return _finalize(value)


static func hash_3d(seed: int, x: int, y: int, z: int) -> int:
	var value: int = _combine(_reduce(seed), _coordinate_mix(x))
	value = _combine(value, _coordinate_mix(y + 104729))
	value = _combine(value, _coordinate_mix(z + 209759))
	return _finalize(value)


## Returns a deterministic value in the inclusive-exclusive interval [0.0, 1.0).
static func float_01_2d(seed: int, x: int, z: int) -> float:
	return float(hash_2d(seed, x, z) - 1) / UNIT_DENOMINATOR


static func float_01_3d(seed: int, x: int, y: int, z: int) -> float:
	return float(hash_3d(seed, x, y, z) - 1) / UNIT_DENOMINATOR


static func signed_float_2d(seed: int, x: int, z: int) -> float:
	return float_01_2d(seed, x, z) * 2.0 - 1.0


static func int_range_2d(seed: int, x: int, z: int, minimum: int, maximum: int) -> int:
	assert(minimum <= maximum, "minimum must not exceed maximum")
	var range_size: int = maximum - minimum + 1
	return minimum + int(float_01_2d(seed, x, z) * float(range_size))


static func chance_2d(seed: int, x: int, z: int, probability: float) -> bool:
	return float_01_2d(seed, x, z) < clampf(probability, 0.0, 1.0)


static func _reduce(value: int) -> int:
	return positive_mod(value, MODULUS)


static func _coordinate_mix(value: int) -> int:
	var mixed: int = _reduce(value)
	mixed = _reduce(mixed * 48271 + 8191)
	mixed = _reduce(mixed * 69621 + 12345)
	return mixed


static func _combine(left: int, right: int) -> int:
	return _reduce(left * 31 + right * 17 + 1013)


static func _finalize(value: int) -> int:
	var mixed: int = _reduce(value * 48271 + 1)
	if mixed == 0:
		return 1
	return mixed
