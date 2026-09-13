## Stateless, global-coordinate rainfall/transport erosion used by default.
##
## The optional HydraulicErosion service provides the more expensive cached
## droplet solve. This default pass instead samples a bounded world-coordinate
## neighbourhood; each
## query samples a bounded world-coordinate neighbourhood, follows its steepest
## local downslope direction once, and estimates rainfall, sediment capacity, and
## downstream deposition. It is therefore deterministic, seam-safe, and meaningful
## without mutable generation state.
class_name RegionalErosion
extends RefCounted

const SAMPLE_RADIUS: int = 4
const FLOW_SAMPLE_DISTANCE: int = 3
const RAIN_SALT: int = 7129

var _seed: int = 0
var _strength: float = 0.0
var _configured: bool = false


func _init(config: WorldGenConfig = null) -> void:
	if config != null:
		configure(config)


## May be called once before worker use. Subsequent calls are ignored so instances
## remain immutable-after-init even if an owning object is accidentally reconfigured.
func configure(config: WorldGenConfig) -> void:
	if _configured:
		push_warning("RegionalErosion is immutable after initialization")
		return
	_seed = config.seed
	_strength = config.regional_erosion
	_configured = true


## Returns a signed vertical modifier. height_at must be a pure global-coordinate
## Callable taking (x: int, z: int) and returning a float.
func modifier(x: int, z: int, height_at: Callable) -> float:
	if _strength <= 0.0 or not height_at.is_valid():
		return 0.0
	var center: float = float(height_at.call(x, z))
	var west: float = float(height_at.call(x - SAMPLE_RADIUS, z))
	var east: float = float(height_at.call(x + SAMPLE_RADIUS, z))
	var north: float = float(height_at.call(x, z - SAMPLE_RADIUS))
	var south: float = float(height_at.call(x, z + SAMPLE_RADIUS))
	var downstream_west: float = float(height_at.call(x - FLOW_SAMPLE_DISTANCE, z))
	var downstream_east: float = float(height_at.call(x + FLOW_SAMPLE_DISTANCE, z))
	var downstream_north: float = float(height_at.call(x, z - FLOW_SAMPLE_DISTANCE))
	var downstream_south: float = float(height_at.call(x, z + FLOW_SAMPLE_DISTANCE))
	return modifier_from_samples(
		x, z, center, west, east, north, south,
		downstream_west, downstream_east, downstream_north, downstream_south)


## Packed-grid counterpart to modifier(). All samples are absolute world-coordinate
## heights: the four cardinal samples are SAMPLE_RADIUS cells from the center and
## the four downstream candidates are FLOW_SAMPLE_DISTANCE cells from it. Keeping
## this arithmetic here makes a chunk sampler able to eliminate Callable dispatch
## and repeated source-height evaluation without changing the erosion model.
func modifier_from_samples(
		x: int,
		z: int,
		center: float,
		west: float,
		east: float,
		north: float,
		south: float,
		downstream_west: float,
		downstream_east: float,
		downstream_north: float,
		downstream_south: float) -> float:
	if _strength <= 0.0:
		return 0.0
	var lowest: float = center
	var downstream: float = center
	if west < lowest:
		lowest = west
		downstream = downstream_west
	if east < lowest:
		lowest = east
		downstream = downstream_east
	if north < lowest:
		lowest = north
		downstream = downstream_north
	if south < lowest:
		lowest = south
		downstream = downstream_south

	var rainfall: float = 0.35 + WorldGenHash.float_01_2d(_seed + RAIN_SALT, x, z) * 0.65
	var drop: float = maxf(center - lowest, 0.0) / float(SAMPLE_RADIUS)
	if drop <= 0.025:
		# A local basin receives deposited material from its surrounding catchment.
		var surrounding: float = (west + east + north + south) * 0.25
		var basin: float = maxf(surrounding - center, 0.0)
		return minf(basin * rainfall * 0.045, 0.65) * _strength

	# One fixed downstream transport sample. This mimics sediment moving out of a
	# steep cell then depositing when the downstream slope loses carrying capacity.
	var downstream_drop: float = maxf(lowest - downstream, 0.0) / float(FLOW_SAMPLE_DISTANCE)
	var carrying_capacity: float = rainfall * drop
	var deposition: float = rainfall * maxf(drop - downstream_drop, 0.0)
	var incision: float = minf(carrying_capacity * 0.28, 1.35)
	return (deposition * 0.12 - incision) * _strength
