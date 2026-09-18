extends SceneTree

const ORIGINS: Array[Vector2i] = [
	Vector2i(0, 0),
	Vector2i(16, 0),
	Vector2i(-16, -16),
	Vector2i(320, -240),
]
const EXPECTED_DIGESTS := {
	Vector2i(0, 0): "06c3fd62e76de1de59f2297d0f26c3b16c51c82df23ca3af34fed58b3085f564",
	Vector2i(16, 0): "bbc4089cc87bc9991912079b14d651c148565043d801d5a0ff19546cb45c40ba",
	Vector2i(-16, -16): "6090fdc16b1f2b0384ca3894e3c6944f129cf4e4418390ed539f69d9628ad94a",
	Vector2i(320, -240): "4ac2a91eb2003603f629bbc05bc289f16d52f7ed39cbb1045b2a6dfc6595cc23",
}

var _failures := PackedStringArray()


func _initialize() -> void:
	var populator := VoxelPopulator.new(WorldGenConfig.new({
		"seed": 123456789,
		"world_type": WorldGenConfig.WORLD_TYPE_NORMAL,
		"worldgen_version": 8,
	}), BiomeCatalog.new())
	_verify_selector(populator)
	_verify_catalog(populator)
	_verify_stage_fingerprints(populator)
	_verify_replacement_semantics(populator)
	_verify_compact_stamps(populator)
	_verify_generator_versions()
	if _failures.is_empty():
		print("WORLDGEN ORE VERIFY: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("WORLDGEN ORE VERIFY: FAIL (", _failures.size(), ")")
	quit(1)


func _verify_selector(populator: VoxelPopulator) -> void:
	for y in [0, 20, 31, 32, 40, 57, 58, 60, 80, 89, 90, 120]:
		for roll in 100:
			var expected := _expected_ore(y, roll)
			_expect(populator._ore_for_anchor(roll, y) == expected,
				"selector changed at y=%d roll=%d" % [y, roll])
	_expect(BlockRegistry.BLOCK_COAL_ORE == 13, "coal ore ID changed")
	_expect(BlockRegistry.BLOCK_IRON_ORE == 14, "iron ore ID changed")
	_expect(BlockRegistry.BLOCK_GOLD_ORE == 15, "gold ore ID changed")


func _verify_catalog(populator: VoxelPopulator) -> void:
	var rules: Array = populator._ore_catalog.rules
	var expected := [
		[BlockRegistry.BLOCK_GOLD_ORE, 32, 17],
		[BlockRegistry.BLOCK_IRON_ORE, 58, 34],
		[BlockRegistry.BLOCK_COAL_ORE, 90, 57],
	]
	_expect(rules.size() == expected.size(), "legacy ore catalog rule count changed")
	for index in mini(rules.size(), expected.size()):
		var rule: OreCatalog.OreRule = rules[index]
		_expect([rule.block_id, rule.max_anchor_y_exclusive, rule.roll_exclusive] == expected[index],
			"legacy ore catalog rule %d changed" % index)


func _verify_stage_fingerprints(populator: VoxelPopulator) -> void:
	for origin in ORIGINS:
		var data := _stone_volume()
		populator._place_ore_veins(data, origin.x, origin.y)
		var digest := _sha256(data)
		print("ORE FIXTURE ", origin, " sha256=", digest, " counts=", _ore_counts(data))
		_expect(digest == String(EXPECTED_DIGESTS[origin]),
			"ore fixture changed at %s: %s" % [origin, digest])


func _verify_replacement_semantics(populator: VoxelPopulator) -> void:
	var data := PackedByteArray()
	data.resize(VoxelDefs.CHUNK_AREA * VoxelDefs.WORLD_HEIGHT)
	data.fill(BlockRegistry.BLOCK_COBBLESTONE)
	var before := data.duplicate()
	populator._place_ore_veins(data, 0, 0)
	_expect(data == before, "ore generation replaced a non-stone block")


func _verify_compact_stamps(populator: VoxelPopulator) -> void:
	# Compare every possible exposed height to the frozen full-volume stage,
	# including negative origins, ore-band boundaries and non-stone surfaces.
	for origin in ORIGINS:
		var full := _stone_volume()
		populator._place_ore_veins(full, origin.x, origin.y)
		var solid_y := PackedInt32Array()
		var solid_id := PackedByteArray()
		var sub_id := PackedByteArray()
		solid_y.resize(VoxelDefs.CHUNK_AREA)
		solid_id.resize(VoxelDefs.CHUNK_AREA)
		sub_id.resize(VoxelDefs.CHUNK_AREA)
		for y in range(1, VoxelDefs.WORLD_HEIGHT):
			solid_y.fill(y)
			solid_id.fill(BlockRegistry.BLOCK_STONE)
			sub_id.fill(BlockRegistry.BLOCK_STONE)
			for column in range(0, VoxelDefs.CHUNK_AREA, 3):
				solid_id[column] = BlockRegistry.BLOCK_GRASS
			for column in range(0, VoxelDefs.CHUNK_AREA, 5):
				sub_id[column] = BlockRegistry.BLOCK_DIRT
			populator._place_ore_veins(PackedByteArray(), origin.x, origin.y, solid_y, solid_id, sub_id)
			for column in VoxelDefs.CHUNK_AREA:
				var expected_top: int = BlockRegistry.BLOCK_GRASS if column % 3 == 0 else full[column + y * VoxelDefs.DATA_STRIDE_Y]
				var expected_sub: int = BlockRegistry.BLOCK_DIRT if column % 5 == 0 else full[column + (y - 1) * VoxelDefs.DATA_STRIDE_Y]
				_expect(solid_id[column] == expected_top and sub_id[column] == expected_sub,
					"compact ore stamp differs at %s column=%d y=%d" % [origin, column, y])


func _verify_generator_versions() -> void:
	var generator := TerrainGenerator.new()
	_expect(WorldGenConfig.new().worldgen_version == 14, "new worlds must default to v14")
	for version in [13, 14]:
		generator.configure({"seed": 123456789, "worldgen_version": version})
		var data: PackedByteArray = generator.generate_data(Vector2i.ZERO, {}).data
		_expect(_sha256(data) == "8a589915d1d2e84b4f8f38a312f1176fa894ec62cce323b6c0136fed756715e7",
			"v%d default cave fixture changed" % version)
		for world_type in [WorldGenConfig.WORLD_TYPE_NORMAL, WorldGenConfig.WORLD_TYPE_AMPLIFIED,
				WorldGenConfig.WORLD_TYPE_FLAT]:
			generator.configure({"seed": 123456789, "worldgen_version": version,
				"cave_density": 0.0, "world_type": world_type})
			data = generator.generate_data(Vector2i.ZERO, {}).data
			var total := 0
			for count in _ore_counts(data).values():
				total += int(count)
			var needs_ores: bool = version >= 14 and world_type != WorldGenConfig.WORLD_TYPE_FLAT
			_expect(total > 0 if needs_ores else total == 0,
				"v%d type %d cave-free ore count: %d" % [version, world_type, total])
			print("CAVE-FREE v", version, " type=", world_type, " ores=", total)
	# Flat layout remains byte-identical regardless of the ore version or caves.
	generator.configure({"seed": 123456789, "worldgen_version": 13,
		"world_type": WorldGenConfig.WORLD_TYPE_FLAT})
	var flat_before: PackedByteArray = generator.generate_data(Vector2i.ZERO, {}).data
	for density in [0.0, 1.0]:
		generator.configure({"seed": 123456789, "worldgen_version": 14,
			"world_type": WorldGenConfig.WORLD_TYPE_FLAT, "cave_density": density})
		_expect(generator.generate_data(Vector2i.ZERO, {}).data == flat_before,
			"v14 changed the Flat layout at cave density %s" % density)


func _stone_volume() -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(VoxelDefs.CHUNK_AREA * VoxelDefs.WORLD_HEIGHT)
	data.fill(BlockRegistry.BLOCK_STONE)
	return data


func _expected_ore(y: int, roll: int) -> int:
	if y < 32 and roll < 17:
		return BlockRegistry.BLOCK_GOLD_ORE
	if y < 58 and roll < 34:
		return BlockRegistry.BLOCK_IRON_ORE
	if y < 90 and roll < 57:
		return BlockRegistry.BLOCK_COAL_ORE
	return BlockRegistry.BLOCK_AIR


func _sha256(data: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(data)
	return context.finish().hex_encode()


func _ore_counts(data: PackedByteArray) -> Dictionary:
	var counts := {13: 0, 14: 0, 15: 0}
	for block_id in data:
		if counts.has(block_id):
			counts[block_id] += 1
	return counts


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
