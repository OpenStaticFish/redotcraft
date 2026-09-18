extends SceneTree

## Exercises the v11 region-structure pass without relying on scene state.

const CONFIG := {
	"seed": 481516234,
	"world_type": WorldGenConfig.WORLD_TYPE_NORMAL,
	"worldgen_version": 11,
	"cave_density": 0.0,
	"decoration_density": 0.0,
	"region_structures": true,
}

var _failures := PackedStringArray()


func _initialize() -> void:
	var generator := TerrainGenerator.new()
	generator.configure(CONFIG)
	var fixture := _find_cross_chunk_fixture(generator)
	if fixture.is_empty():
		_expect(false, "could not locate an accepted cross-chunk region structure")
	else:
		_verify_catalog_determinism(fixture)
		_verify_clipping_and_continuity(generator, fixture)
		_verify_lod_tops(generator, fixture)
		_verify_edits_last(generator, fixture)
		_verify_gates(fixture)
	if _failures.is_empty():
		print("WORLDGEN POI VERIFY: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("WORLDGEN POI VERIFY: FAIL (", _failures.size(), ")")
	quit(1)


func _find_cross_chunk_fixture(generator: TerrainGenerator) -> Dictionary:
	for owner_z in range(-5, 6):
		for owner_x in range(-5, 6):
			var candidate := StructureCatalog.candidate_for(int(CONFIG["seed"]), owner_x, owner_z)
			if candidate == null or not _crosses_chunk_boundary(candidate.anchor):
				continue
			var anchor_chunk := Vector2i(WorldGenHash.floor_div(candidate.anchor.x, VoxelDefs.CHUNK_SIZE),
				WorldGenHash.floor_div(candidate.anchor.y, VoxelDefs.CHUNK_SIZE))
			var field := generator._sampler.build_field(anchor_chunk)
			var scratch := VoxelPopulator.DecorationGroundScratch.new()
			var ground := generator._sampler.sample_decoration_ground(candidate.anchor.x, candidate.anchor.y)
			if not generator._populator._region_structure_site_is_valid(field, scratch, candidate, ground.x):
				continue
			return {
				"candidate": candidate,
				"ground_y": ground.x,
				"chunks": _structure_chunks(candidate.anchor),
			}
	return {}


func _crosses_chunk_boundary(anchor: Vector2i) -> bool:
	return WorldGenHash.floor_div(anchor.x - StructureCatalog.HORIZONTAL_HALO, VoxelDefs.CHUNK_SIZE) \
		!= WorldGenHash.floor_div(anchor.x + StructureCatalog.HORIZONTAL_HALO, VoxelDefs.CHUNK_SIZE) \
		or WorldGenHash.floor_div(anchor.y - StructureCatalog.HORIZONTAL_HALO, VoxelDefs.CHUNK_SIZE) \
		!= WorldGenHash.floor_div(anchor.y + StructureCatalog.HORIZONTAL_HALO, VoxelDefs.CHUNK_SIZE)


func _structure_chunks(anchor: Vector2i) -> Array[Vector2i]:
	var chunks: Array[Vector2i] = []
	for chunk_z in range(WorldGenHash.floor_div(anchor.y - StructureCatalog.HORIZONTAL_HALO, VoxelDefs.CHUNK_SIZE),
			WorldGenHash.floor_div(anchor.y + StructureCatalog.HORIZONTAL_HALO, VoxelDefs.CHUNK_SIZE) + 1):
		for chunk_x in range(WorldGenHash.floor_div(anchor.x - StructureCatalog.HORIZONTAL_HALO, VoxelDefs.CHUNK_SIZE),
			WorldGenHash.floor_div(anchor.x + StructureCatalog.HORIZONTAL_HALO, VoxelDefs.CHUNK_SIZE) + 1):
			chunks.append(Vector2i(chunk_x, chunk_z))
	return chunks


func _verify_catalog_determinism(fixture: Dictionary) -> void:
	var candidate = fixture["candidate"]
	var owner_x: int = WorldGenHash.floor_div(candidate.anchor.x, StructureCatalog.OWNER_CELL_SIZE)
	var owner_z: int = WorldGenHash.floor_div(candidate.anchor.y, StructureCatalog.OWNER_CELL_SIZE)
	var duplicate := StructureCatalog.candidate_for(int(CONFIG["seed"]), owner_x, owner_z)
	_expect(duplicate != null and duplicate.kind == candidate.kind and duplicate.anchor == candidate.anchor \
		and duplicate.orientation == candidate.orientation and duplicate.hash_value == candidate.hash_value,
		"owner-cell candidate is not deterministic")


func _verify_clipping_and_continuity(generator: TerrainGenerator, fixture: Dictionary) -> void:
	var expected := _expected_blocks(fixture)
	var chunks: Array[Vector2i] = fixture["chunks"]
	var actual := _collect_blocks(generator, chunks, expected, false)
	var reversed: Array[Vector2i] = chunks.duplicate()
	reversed.reverse()
	var repeated := _collect_blocks(generator, reversed, expected, false)
	_expect(actual == expected, "cross-chunk structure clipping did not reproduce the catalog stamp")
	_expect(repeated == expected and actual == repeated,
		"cross-chunk structure continuity depends on generation order")
	var sample: Vector2i = chunks[0]
	var first := generator.generate_data(sample, {}, false)
	var duplicate := generator.generate_data(sample, {}, false)
	_expect(first.data == duplicate.data, "full-detail POI chunk is not deterministic")


func _verify_lod_tops(generator: TerrainGenerator, fixture: Dictionary) -> void:
	var expected_tops := _expected_tops(fixture)
	for chunk: Vector2i in fixture["chunks"]:
		var full := generator.generate_data(chunk, {}, false)
		var lod := generator.generate_data(chunk, {}, true)
		var origin := chunk * VoxelDefs.CHUNK_SIZE
		for structure_column in expected_tops:
			if structure_column.x < origin.x or structure_column.x >= origin.x + VoxelDefs.CHUNK_SIZE \
					or structure_column.y < origin.y or structure_column.y >= origin.y + VoxelDefs.CHUNK_SIZE:
				continue
			var local_x: int = structure_column.x - origin.x
			var local_z: int = structure_column.y - origin.y
			var column: int = local_x + local_z * VoxelDefs.DATA_STRIDE_Z
			var top: Vector2i = expected_tops[structure_column]
			var full_top := _full_solid_top(full.data, full.max_y, column)
			_expect(full_top == top, "full POI top differs from catalog at %s" % structure_column)
			_expect(lod.lod_solid_y[column] == top.x and lod.lod_solid_id[column] == top.y,
				"LOD/full POI top mismatch at %s" % structure_column)


func _verify_edits_last(generator: TerrainGenerator, fixture: Dictionary) -> void:
	var expected_tops := _expected_tops(fixture)
	for structure_column in expected_tops:
		var top: Vector2i = expected_tops[structure_column]
		var position := Vector3i(structure_column.x, top.x, structure_column.y)
		var chunk := Vector2i(WorldGenHash.floor_div(position.x, VoxelDefs.CHUNK_SIZE),
			WorldGenHash.floor_div(position.z, VoxelDefs.CHUNK_SIZE))
		var edited := generator.generate_data(chunk, {position: BlockRegistry.BLOCK_AIR}, false)
		var local_x: int = WorldGenHash.floor_mod(position.x, VoxelDefs.CHUNK_SIZE)
		var local_z: int = WorldGenHash.floor_mod(position.z, VoxelDefs.CHUNK_SIZE)
		var index: int = local_x + local_z * VoxelDefs.DATA_STRIDE_Z + position.y * VoxelDefs.DATA_STRIDE_Y
		_expect(edited.data[index] == BlockRegistry.BLOCK_AIR, "saved edit did not override POI block at %s" % position)
		return
	_expect(false, "POI fixture had no solid stamp available for edit precedence")


func _verify_gates(fixture: Dictionary) -> void:
	var chunks: Array[Vector2i] = fixture["chunks"]
	var enabled := TerrainGenerator.new()
	enabled.configure(CONFIG)
	var disabled_config := CONFIG.duplicate()
	disabled_config["region_structures"] = false
	var disabled := TerrainGenerator.new()
	disabled.configure(disabled_config)
	var changed := false
	for chunk in chunks:
		if enabled.generate_data(chunk, {}, false).data != disabled.generate_data(chunk, {}, false).data:
			changed = true
	_expect(changed, "enabled region structures produced no gated output")
	var legacy_config := CONFIG.duplicate()
	legacy_config["worldgen_version"] = 10
	legacy_config["region_structures"] = true
	var legacy_enabled := TerrainGenerator.new()
	legacy_enabled.configure(legacy_config)
	legacy_config["region_structures"] = false
	var legacy_disabled := TerrainGenerator.new()
	legacy_disabled.configure(legacy_config)
	for chunk in chunks:
		_expect(legacy_enabled.generate_data(chunk, {}, false).data == legacy_disabled.generate_data(chunk, {}, false).data,
			"legacy v10 output changed when region_structures was requested at %s" % chunk)


func _expected_blocks(fixture: Dictionary) -> Dictionary:
	var expected: Dictionary = {}
	var candidate = fixture["candidate"]
	var ground_y: int = int(fixture["ground_y"])
	for offset_z in range(-StructureCatalog.HORIZONTAL_HALO, StructureCatalog.HORIZONTAL_HALO + 1):
		for offset_x in range(-StructureCatalog.HORIZONTAL_HALO, StructureCatalog.HORIZONTAL_HALO + 1):
			for local_y in range(1, StructureCatalog.max_height(candidate.kind) + 1):
				var block_id: int = StructureCatalog.block_at(candidate.kind, candidate.orientation,
					offset_x, local_y, offset_z)
				if block_id != BlockRegistry.BLOCK_AIR:
					expected[Vector3i(candidate.anchor.x + offset_x, ground_y + local_y,
						candidate.anchor.y + offset_z)] = block_id
	return expected


func _expected_tops(fixture: Dictionary) -> Dictionary:
	var tops: Dictionary = {}
	var blocks := _expected_blocks(fixture)
	for position in blocks:
		var block_id: int = int(blocks[position])
		if block_id == BlockRegistry.BLOCK_TORCH:
			continue
		var column := Vector2i(position.x, position.z)
		if not tops.has(column) or position.y > tops[column].x:
			tops[column] = Vector2i(position.y, block_id)
	return tops


func _collect_blocks(generator: TerrainGenerator, chunks: Array[Vector2i], expected: Dictionary,
		lod: bool) -> Dictionary:
	var actual: Dictionary = {}
	for chunk in chunks:
		var result := generator.generate_data(chunk, {}, lod)
		if lod:
			continue
		var origin := chunk * VoxelDefs.CHUNK_SIZE
		for position in expected:
			if position.x < origin.x or position.x >= origin.x + VoxelDefs.CHUNK_SIZE \
					or position.z < origin.y or position.z >= origin.y + VoxelDefs.CHUNK_SIZE:
				continue
			var local_x: int = position.x - origin.x
			var local_z: int = position.z - origin.y
			var index: int = local_x + local_z * VoxelDefs.DATA_STRIDE_Z + position.y * VoxelDefs.DATA_STRIDE_Y
			actual[position] = result.data[index]
	return actual


func _full_solid_top(data: PackedByteArray, max_y: int, column: int) -> Vector2i:
	for y in range(max_y, -1, -1):
		var block_id: int = data[column + y * VoxelDefs.DATA_STRIDE_Y]
		if block_id == BlockRegistry.BLOCK_AIR or block_id == BlockRegistry.BLOCK_TORCH:
			continue
		return Vector2i(y, block_id)
	return Vector2i(-1, BlockRegistry.BLOCK_AIR)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
