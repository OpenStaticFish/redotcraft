extends SceneTree

var _failures := PackedStringArray()


func _initialize() -> void:
	_verify_versioned_catalog()
	_verify_boulder_stamp(Vector3i(16, 60, 16), 7109)
	_verify_boulder_stamp(Vector3i(-16, 60, -16), 7109)
	if _failures.is_empty():
		print("WORLDGEN STRUCTURE VERIFY: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("WORLDGEN STRUCTURE VERIFY: FAIL (", _failures.size(), ")")
	quit(1)


func _verify_versioned_catalog() -> void:
	var v8 := DecorationCatalog.new(8).entries_for_set(BiomeCatalog.DECORATION_ALPINE)
	var v9 := DecorationCatalog.new(9).entries_for_set(BiomeCatalog.DECORATION_ALPINE)
	var v11_snow := DecorationCatalog.new(11).entries_for_set(BiomeCatalog.DECORATION_SNOWFIELD)
	var v12_snow := DecorationCatalog.new(12).entries_for_set(BiomeCatalog.DECORATION_SNOWFIELD)
	var v11_alpine := DecorationCatalog.new(11).entries_for_set(BiomeCatalog.DECORATION_ALPINE)
	var v12_alpine := DecorationCatalog.new(12).entries_for_set(BiomeCatalog.DECORATION_ALPINE)
	var v11_badlands := DecorationCatalog.new(11).entries_for_set(BiomeCatalog.DECORATION_BADLANDS)
	var v12_badlands := DecorationCatalog.new(12).entries_for_set(BiomeCatalog.DECORATION_BADLANDS)
	var legacy_catalog := DecorationCatalog.new(12)
	var current_catalog := DecorationCatalog.new(13)
	_expect(not _contains_feature(v8, DecorationCatalog.FEATURE_BOULDER),
		"version 8 unexpectedly gained highland boulders")
	_expect(_contains_feature(v9, DecorationCatalog.FEATURE_BOULDER),
		"version 9 highland boulder is unreachable from the catalog")
	_expect(_contains_feature(v11_snow, DecorationCatalog.FEATURE_ROCK_OUTCROP) \
		and _contains_feature(v11_alpine, DecorationCatalog.FEATURE_ROCK_OUTCROP) \
		and _contains_feature(v11_badlands, DecorationCatalog.FEATURE_ROCK_OUTCROP),
		"version 11 rock-outcrop compatibility changed")
	_expect(not _contains_feature(v12_snow, DecorationCatalog.FEATURE_ROCK_OUTCROP) \
		and not _contains_feature(v12_alpine, DecorationCatalog.FEATURE_ROCK_OUTCROP) \
		and not _contains_feature(v12_badlands, DecorationCatalog.FEATURE_ROCK_OUTCROP),
		"version 12 still selects artificial cobblestone outcrops")
	_expect(_contains_feature(v12_alpine, DecorationCatalog.FEATURE_BOULDER),
		"version 12 unexpectedly removed rare alpine boulders")
	for set_id in [BiomeCatalog.DECORATION_FOREST, BiomeCatalog.DECORATION_TROPICAL, BiomeCatalog.DECORATION_TAIGA]:
		_expect(_contains_feature(legacy_catalog.entries_for_set(set_id), DecorationCatalog.FEATURE_FALLEN_LOG),
			"version 12 fallen-log compatibility changed for set %d" % set_id)
		_expect(not _contains_feature(current_catalog.entries_for_set(set_id), DecorationCatalog.FEATURE_FALLEN_LOG),
			"version 13 still selects fallen logs for set %d" % set_id)
	for set_id in [BiomeCatalog.DECORATION_SWAMP, BiomeCatalog.DECORATION_RIVERBANK, BiomeCatalog.DECORATION_BEACH]:
		_expect(_contains_feature(legacy_catalog.entries_for_set(set_id), DecorationCatalog.FEATURE_DRIFTWOOD),
			"version 12 driftwood compatibility changed for set %d" % set_id)
		_expect(not _contains_feature(current_catalog.entries_for_set(set_id), DecorationCatalog.FEATURE_DRIFTWOOD),
			"version 13 still selects driftwood for set %d" % set_id)


func _verify_boulder_stamp(anchor: Vector3i, hash_value: int) -> void:
	var config := WorldGenConfig.new({"seed": 918273, "worldgen_version": 9})
	var populator := VoxelPopulator.new(config, BiomeCatalog.new())
	var actual: Dictionary = {}
	var duplicate: Dictionary = {}
	for chunk_z in range(WorldGenHash.floor_div(anchor.z - 2, VoxelDefs.CHUNK_SIZE),
			WorldGenHash.floor_div(anchor.z + 2, VoxelDefs.CHUNK_SIZE) + 1):
		for chunk_x in range(WorldGenHash.floor_div(anchor.x - 2, VoxelDefs.CHUNK_SIZE),
				WorldGenHash.floor_div(anchor.x + 2, VoxelDefs.CHUNK_SIZE) + 1):
			var origin := Vector2i(chunk_x * VoxelDefs.CHUNK_SIZE, chunk_z * VoxelDefs.CHUNK_SIZE)
			_collect_stamp(populator, actual, origin, anchor, hash_value)
			_collect_stamp(populator, duplicate, origin, anchor, hash_value)
	var expected: Dictionary = {}
	var radius := 1 + hash_value % 2
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dz * dz <= radius * radius:
				expected[Vector3i(anchor.x + dx, anchor.y + 1, anchor.z + dz)] = true
	_expect(actual == expected, "cross-chunk boulder stamp changed at %s" % anchor)
	_expect(actual == duplicate, "boulder stamp is not deterministic at %s" % anchor)
	for position in actual:
		_expect(maxi(absi(position.x - anchor.x), absi(position.z - anchor.z)) <= 2,
			"boulder exceeded its two-block structure halo")
		_expect(position.y == anchor.y + 1, "boulder exceeded its one-block vertical footprint")


func _collect_stamp(populator: VoxelPopulator, output: Dictionary, origin: Vector2i,
		anchor: Vector3i, hash_value: int) -> void:
	var data := PackedByteArray()
	data.resize(VoxelDefs.CHUNK_AREA * VoxelDefs.WORLD_HEIGHT)
	populator._stamp_boulder(data, origin.x, origin.y, anchor.x, anchor.y, anchor.z, hash_value)
	for local_z in VoxelDefs.CHUNK_SIZE:
		for local_x in VoxelDefs.CHUNK_SIZE:
			var index := local_x + local_z * VoxelDefs.DATA_STRIDE_Z \
				+ (anchor.y + 1) * VoxelDefs.DATA_STRIDE_Y
			if data[index] == BlockRegistry.BLOCK_COBBLESTONE:
				output[Vector3i(origin.x + local_x, anchor.y + 1, origin.y + local_z)] = true


func _contains_feature(entries: Array, feature: int) -> bool:
	for entry in entries:
		if int(entry[0]) == feature:
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
