## Padded, structure-of-arrays terrain inputs for one chunk.
## Populate it on a worker, then call seal() before handing it to another stage.
class_name ChunkTerrainData
extends RefCounted

const VoxelDefsScript = preload("res://world/voxel_defs.gd")
const PADDING: int = 1
const SIDE: int = VoxelDefsScript.CHUNK_SIZE + PADDING * 2
const CELL_COUNT: int = SIDE * SIDE

var chunk_x: int
var chunk_z: int

var continentalness: PackedFloat32Array = PackedFloat32Array()
var raw_height: PackedFloat32Array = PackedFloat32Array()
var base_height: PackedFloat32Array = PackedFloat32Array()
var final_height: PackedFloat32Array = PackedFloat32Array()
var slope: PackedFloat32Array = PackedFloat32Array()
var river: PackedFloat32Array = PackedFloat32Array()
var inland_water_y: PackedInt32Array = PackedInt32Array()
var temperature: PackedFloat32Array = PackedFloat32Array()
var moisture: PackedFloat32Array = PackedFloat32Array()

var profile_id: PackedByteArray = PackedByteArray()
var profile_blend: PackedByteArray = PackedByteArray()
var biome_id: PackedByteArray = PackedByteArray()
var biome_secondary_id: PackedByteArray = PackedByteArray()
var biome_blend: PackedByteArray = PackedByteArray()
var ecotone_strength: PackedByteArray = PackedByteArray()
var dominant_biome: PackedByteArray = PackedByteArray()

var _sealed: bool = false


func _init(chunk_x_value: int = 0, chunk_z_value: int = 0) -> void:
	chunk_x = chunk_x_value
	chunk_z = chunk_z_value
	_resize_fields()


static func padded_index(padded_x: int, padded_z: int) -> int:
	return padded_z * SIDE + padded_x


## local_x and local_z include the one-cell border: [-1, CHUNK_SIZE].
static func cell_index(local_x: int, local_z: int) -> int:
	return padded_index(local_x + PADDING, local_z + PADDING)


static func is_valid_local(local_x: int, local_z: int) -> bool:
	return local_x >= -PADDING and local_x < VoxelDefsScript.CHUNK_SIZE + PADDING and local_z >= -PADDING and local_z < VoxelDefsScript.CHUNK_SIZE + PADDING


func world_x(local_x: int) -> int:
	return chunk_x * VoxelDefsScript.CHUNK_SIZE + local_x


func world_z(local_z: int) -> int:
	return chunk_z * VoxelDefsScript.CHUNK_SIZE + local_z


func set_climate(index: int, continental: float, river_value: float, temperature_value: float, moisture_value: float) -> void:
	if not _can_write(index):
		return
	continentalness[index] = continental
	river[index] = river_value
	temperature[index] = temperature_value
	moisture[index] = moisture_value


func set_height(index: int, raw_value: float, base_value: float, final_value: float, slope_value: float) -> void:
	if not _can_write(index):
		return
	raw_height[index] = raw_value
	base_height[index] = base_value
	final_height[index] = final_value
	slope[index] = slope_value


func set_profile(index: int, id: int, blend: int) -> void:
	if not _can_write(index):
		return
	profile_id[index] = clampi(id, 0, 255)
	profile_blend[index] = clampi(blend, 0, 255)


func set_biome(index: int, id: int, secondary_id: int, blend: int, dominant_id: int, ecotone: int = 0) -> void:
	if not _can_write(index):
		return
	biome_id[index] = clampi(id, 0, 255)
	biome_secondary_id[index] = clampi(secondary_id, 0, 255)
	biome_blend[index] = clampi(blend, 0, 255)
	ecotone_strength[index] = clampi(ecotone, 0, 255)
	dominant_biome[index] = clampi(dominant_id, 0, 255)


func seal() -> void:
	_sealed = true


func is_sealed() -> bool:
	return _sealed


func _resize_fields() -> void:
	continentalness.resize(CELL_COUNT)
	raw_height.resize(CELL_COUNT)
	base_height.resize(CELL_COUNT)
	final_height.resize(CELL_COUNT)
	slope.resize(CELL_COUNT)
	river.resize(CELL_COUNT)
	inland_water_y.resize(CELL_COUNT)
	inland_water_y.fill(-1)
	temperature.resize(CELL_COUNT)
	moisture.resize(CELL_COUNT)
	profile_id.resize(CELL_COUNT)
	profile_blend.resize(CELL_COUNT)
	biome_id.resize(CELL_COUNT)
	biome_secondary_id.resize(CELL_COUNT)
	biome_blend.resize(CELL_COUNT)
	ecotone_strength.resize(CELL_COUNT)
	dominant_biome.resize(CELL_COUNT)


func _can_write(index: int) -> bool:
	if _sealed:
		push_error("ChunkTerrainData is sealed")
		return false
	if index < 0 or index >= CELL_COUNT:
		push_error("ChunkTerrainData cell index is out of range")
		return false
	return true
