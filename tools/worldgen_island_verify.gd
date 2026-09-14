## Headless regression for detached large and small island landmasses.
extends SceneTree

const SEED: int = 123456789
const SAMPLE_RADIUS: int = 2048
const SAMPLE_STEP: int = 16
const ISLAND_THRESHOLD: float = 0.06

var _failed := false


func _initialize() -> void:
	var config := WorldGenConfig.new({"seed": SEED, "worldgen_version": WorldGenConfig.CURRENT_VERSION})
	var sampler := TerrainSampler.new(config, TerrainProfileCatalog.new(), BiomeCatalog.new())
	var island_cells := {}
	var unchanged_mainland := true
	for z in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1, SAMPLE_STEP):
		for x in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1, SAMPLE_STEP):
			var mainland: float = sampler._mainland_continentalness_at(x, z)
			var effective: float = sampler._continentalness_at(x, z)
			if mainland >= 0.38 and not is_equal_approx(mainland, effective):
				unchanged_mainland = false
			if effective - mainland >= ISLAND_THRESHOLD:
				island_cells[Vector2i(x / SAMPLE_STEP, z / SAMPLE_STEP)] = effective - mainland
	_check(unchanged_mainland, "island uplift changed established continental interiors")
	var components := _components(island_cells)
	var large_count := 0
	var small_count := 0
	var dry_large := 0
	var dry_small := 0
	var large_peak := Vector2i.ZERO
	var small_peak := Vector2i.ZERO
	for component: Dictionary in components:
		var span: int = maxi(
			(int(component["max_x"]) - int(component["min_x"]) + 1) * SAMPLE_STEP,
			(int(component["max_z"]) - int(component["min_z"]) + 1) * SAMPLE_STEP)
		var peak_grid: Vector2i = component["peak"]
		var peak := sampler.sample_point(peak_grid.x * SAMPLE_STEP, peak_grid.y * SAMPLE_STEP)
		var dry: bool = float(peak["final_height"]) > float(VoxelDefs.SEA_LEVEL) \
			and not BiomeCatalog.new().is_ocean_biome(int(peak["biome_id"]))
		if span >= 144:
			large_count += 1
			if dry:
				dry_large += 1
				large_peak = peak_grid * SAMPLE_STEP
		elif span >= 16 and span <= 112:
			small_count += 1
			if dry:
				dry_small += 1
				small_peak = peak_grid * SAMPLE_STEP
	_check(large_count > 0, "no large offshore island landmass appeared in pinned sample")
	_check(small_count > 0, "no small offshore island appeared in pinned sample")
	_check(dry_large > 0, "large island uplift never rose above sea level")
	_check(dry_small > 0, "small island uplift never rose above sea level")
	if dry_large > 0 and dry_small > 0:
		var generator := TerrainGenerator.new()
		generator.configure({
			"seed": SEED,
			"worldgen_version": WorldGenConfig.CURRENT_VERSION,
			"tree_density": 0.0,
			"decoration_density": 0.0,
		})
		_verify_lod_peak(generator, large_peak, "large")
		_verify_lod_peak(generator, small_peak, "small")
	if _failed:
		quit(1)
		return
	print("WORLDGEN ISLAND VERIFY: PASS components=%d large=%d small=%d dry_large=%d dry_small=%d" % [
		components.size(), large_count, small_count, dry_large, dry_small])
	quit(0)


func _verify_lod_peak(generator: TerrainGenerator, position: Vector2i, label: String) -> void:
	var chunk := Vector2i(
		WorldGenHash.floor_div(position.x, VoxelDefs.CHUNK_SIZE),
		WorldGenHash.floor_div(position.y, VoxelDefs.CHUNK_SIZE))
	var local_x: int = WorldGenHash.floor_mod(position.x, VoxelDefs.CHUNK_SIZE)
	var local_z: int = WorldGenHash.floor_mod(position.y, VoxelDefs.CHUNK_SIZE)
	var column: int = local_x + local_z * VoxelDefs.DATA_STRIDE_Z
	var field: ChunkTerrainData = generator._sampler.build_field(chunk)
	var field_index: int = ChunkTerrainData.cell_index(local_x, local_z)
	var point: Dictionary = generator.sample_point(position.x, position.y)
	var decoration_ground: Vector2i = generator._sampler.sample_decoration_ground(position.x, position.y)
	_check(absf(float(field.final_height[field_index]) - float(point["final_height"])) <= 0.001,
		"%s island field/point height diverged" % label)
	_check(absf(float(field.river[field_index]) - float(point["river"])) <= 0.001,
		"%s island field/point river gate diverged" % label)
	_check(int(field.dominant_biome[field_index]) == int(point["dominant_biome_id"]),
		"%s island field/point ecotone biome diverged" % label)
	_check(decoration_ground.y == int(point["dominant_biome_id"]),
		"%s island decorator biome diverged" % label)
	var full := generator.generate_data(chunk, {}, false)
	var lod := generator.generate_data(chunk, {}, true)
	var full_y: int = int(full.heights[column])
	_check(full_y == int(lod.lod_solid_y[column]), "%s island full/LOD surface height diverged" % label)
	var full_id: int = int(full.data[column + full_y * VoxelDefs.DATA_STRIDE_Y])
	_check(full_id == int(lod.lod_solid_id[column]), "%s island full/LOD surface material diverged" % label)


func _components(cells: Dictionary) -> Array[Dictionary]:
	var remaining: Dictionary = cells.duplicate()
	var result: Array[Dictionary] = []
	while not remaining.is_empty():
		var start: Vector2i = remaining.keys()[0]
		var queue: Array[Vector2i] = [start]
		remaining.erase(start)
		var cursor := 0
		var component := {
			"min_x": start.x, "max_x": start.x,
			"min_z": start.y, "max_z": start.y,
			"peak": start, "peak_strength": float(cells[start]),
		}
		while cursor < queue.size():
			var cell: Vector2i = queue[cursor]
			cursor += 1
			component["min_x"] = mini(int(component["min_x"]), cell.x)
			component["max_x"] = maxi(int(component["max_x"]), cell.x)
			component["min_z"] = mini(int(component["min_z"]), cell.y)
			component["max_z"] = maxi(int(component["max_z"]), cell.y)
			if float(cells[cell]) > float(component["peak_strength"]):
				component["peak"] = cell
				component["peak_strength"] = float(cells[cell])
			for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var neighbor: Vector2i = cell + direction
				if remaining.has(neighbor):
					remaining.erase(neighbor)
					queue.append(neighbor)
		result.append(component)
	return result


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error("worldgen_island_verify: %s" % message)
