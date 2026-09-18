extends SceneTree

var _failures := PackedStringArray()
var _root := "user://world_storage_verify_%d" % Time.get_ticks_usec()


func _initialize() -> void:
	_verify_game_modes()
	_verify_v1_compatibility_fixture()
	_verify_round_trip_and_regions()
	_verify_future_metadata_rejection()
	_verify_library_listing_and_delete()
	_verify_world_management()
	_verify_v2_compression_round_trip_and_corruption()
	_verify_generation_edit_priority()
	if _failures.is_empty():
		print("WORLD STORAGE VERIFY: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("WORLD STORAGE VERIFY: FAIL (", _failures.size(), ")")
	quit(1)


func _verify_game_modes() -> void:
	for value in [0, 1, 0.0, 1.0]:
		_expect(GameMode.is_valid(value), "valid mode rejected: %s" % value)
	for value in [true, false, "0", "1", null, -1, 2, 0.5, 1.5, INF, NAN, [], {}]:
		_expect(not GameMode.is_valid(value), "invalid mode accepted: %s" % str(value))
	var storage := WorldStorage.new(_root)
	_expect(storage.create_world({}, {}, "bad-mode", false, 2).is_empty(), "invalid creation mode accepted")
	for mode in [GameMode.CREATIVE, GameMode.SURVIVAL]:
		var id := "mode-%d" % mode
		var created := storage.create_world({}, {}, id, false, mode)
		_expect(created.get("game_mode", -1) == mode, "creation lost mode")
		_expect(storage.flush({"test": true}) == OK, "mode fixture flush failed")
		_expect(storage.open_world(id).get("game_mode", -1) == mode, "reopen lost mode")
		_expect(WorldStorage.duplicate_world(id, _root).get("game_mode", -1) == mode, "duplicate lost mode")
		var backup := WorldStorage.backup_world(id, _root, _root + "-backups")
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(backup + "/metadata.json"))
		_expect(saved is Dictionary and saved.get("game_mode", -1) == mode, "backup lost mode")
		var path := _root + "/" + id + "/metadata.json"
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string("{}")
		file = null
		_expect(storage.open_world(id).get("game_mode", -1) == mode, "recovery backup lost mode")
	var legacy := storage.create_world({}, {}, "legacy-mode", false)
	_expect(legacy.get("game_mode", -1) == GameMode.CREATIVE, "old caller default changed")
	legacy.erase("game_mode")
	var legacy_path := _root + "/legacy-mode/metadata.json"
	var fixture := FileAccess.open(legacy_path, FileAccess.WRITE)
	fixture.store_string(JSON.stringify(legacy))
	fixture = null
	_expect(storage.open_world("legacy-mode").get("game_mode", -1) == GameMode.CREATIVE, "legacy absent mode not creative")
	for invalid in [true, "1", 0.5, 2, null]:
		legacy["game_mode"] = invalid
		fixture = FileAccess.open(legacy_path, FileAccess.WRITE)
		fixture.store_string(JSON.stringify(legacy))
		fixture = null
		_expect(storage.open_world("legacy-mode").is_empty(), "invalid metadata mode loaded")
	for summary in WorldStorage.list_world_summaries(_root):
		if summary["id"] == "legacy-mode":
			_expect(not summary["compatible"], "invalid mode summary is loadable")
		elif String(summary["id"]).begins_with("mode-"):
			_expect(summary["game_mode"] == int(String(summary["id"]).trim_prefix("mode-")), "summary lost mode")


func _verify_v1_compatibility_fixture() -> void:
	var storage := WorldStorage.new(_root)
	var config := WorldGenConfig.new({"seed": -10101}).to_dictionary()
	_expect(not storage.create_world(config, {}, "legacy-v1-world").is_empty(),
		"could not create v1 compatibility world")
	var legacy_path := _root + "/legacy-v1-world/regions/r.-1.-1.rcregion"
	var fixture := FileAccess.open_compressed(legacy_path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if fixture == null:
		_expect(false, "could not write handcrafted v1 fixture")
		return
	fixture.store_buffer(WorldStorage.REGION_MAGIC.to_utf8_buffer())
	fixture.store_16(WorldStorage.REGION_VERSION_LEGACY)
	fixture.store_32(2)
	fixture.store_32(-1)
	fixture.store_32(-1)
	fixture.store_32(2)
	fixture.store_32(-1)
	fixture.store_16(10)
	fixture.store_32(-1)
	fixture.store_8(BlockRegistry.BLOCK_AIR)
	fixture.store_32(-16)
	fixture.store_16(55)
	fixture.store_32(-16)
	fixture.store_8(BlockRegistry.BLOCK_TORCH)
	fixture.store_32(-2)
	fixture.store_32(-1)
	fixture.store_32(1)
	fixture.store_32(-17)
	fixture.store_16(33)
	fixture.store_32(-2)
	fixture.store_8(BlockRegistry.BLOCK_WATER)
	fixture.flush()
	fixture = null
	var reopened := WorldStorage.new(_root)
	_expect(not reopened.open_world("legacy-v1-world").is_empty(), "could not reopen v1 fixture world")
	_expect(reopened.load_chunk_edits(Vector2i(-1, -1)) == {
		Vector3i(-1, 10, -1): BlockRegistry.BLOCK_AIR,
		Vector3i(-16, 55, -16): BlockRegistry.BLOCK_TORCH,
	}, "handcrafted v1 negative-coordinate edits did not load")
	_expect(reopened.load_chunk_edits(Vector2i(-2, -1)) == {
		Vector3i(-17, 33, -2): BlockRegistry.BLOCK_WATER,
	}, "handcrafted v1 second chunk did not load")
	print("WORLD STORAGE V1: handcrafted_fixture=true negative_coordinates=true")


func _verify_round_trip_and_regions() -> void:
	var config := WorldGenConfig.new({"seed": -918273, "world_type": 2, "terrain_scale": 1.25}).to_dictionary()
	var initial_state := {
		"player": {"position": [-17.5, 71.0, -2.5], "flying": true},
		"inventory": [[1, 23], [27, 4]],
		"selected_slot": 1,
	}
	var storage := WorldStorage.new(_root)
	var metadata := storage.create_world(config, initial_state, "verify-world")
	_expect(not metadata.is_empty(), "could not create verification world")
	_expect(metadata.get("worldgen", {}) == config, "worldgen metadata did not round-trip on creation")

	var chunk_a := Vector2i(-1, -1)
	var chunk_b := Vector2i(-2, -1)
	var chunk_c := Vector2i(0, 0)
	var edits_a := {
		Vector3i(-1, 10, -1): BlockRegistry.BLOCK_AIR,
		Vector3i(-16, 55, -16): BlockRegistry.BLOCK_TORCH,
	}
	var edits_b := {Vector3i(-17, 33, -2): BlockRegistry.BLOCK_WATER}
	var edits_c := {Vector3i(0, 1, 0): BlockRegistry.BLOCK_STONE}
	storage.stage_chunk_edits(chunk_a, edits_a)
	storage.stage_chunk_edits(chunk_b, edits_b)
	storage.stage_chunk_edits(chunk_c, edits_c)
	_expect(storage.flush(initial_state) == OK, "first world flush failed")

	var reopened := WorldStorage.new(_root)
	var loaded_metadata := reopened.open_world("verify-world")
	_expect(_equivalent(loaded_metadata.get("worldgen", {}), config), "frozen worldgen config changed after reopen")
	_expect(_equivalent(loaded_metadata.get("state", {}), initial_state), "gameplay metadata changed after reopen")
	_expect(reopened.load_chunk_edits(chunk_a) == edits_a, "negative chunk A edits changed after reopen")
	_expect(reopened.load_chunk_edits(chunk_b) == edits_b, "same-region chunk B edits were lost")
	_expect(reopened.load_chunk_edits(chunk_c) == edits_c, "positive-region chunk edits were lost")

	# Rewriting identical, sorted content must produce identical compressed bytes.
	var negative_region_path := _root + "/verify-world/regions/r.-1.-1.rcregion"
	var before := FileAccess.get_file_as_bytes(negative_region_path)
	reopened.stage_chunk_edits(chunk_b, edits_b)
	reopened.stage_chunk_edits(chunk_a, edits_a)
	_expect(reopened.flush(initial_state) == OK, "deterministic rewrite flush failed")
	var after := FileAccess.get_file_as_bytes(negative_region_path)
	_expect(before == after, "region output changed when identical edits were staged in another order")

	# A corrupt primary must recover the prior valid region from .bak.
	var corrupt := FileAccess.open(negative_region_path, FileAccess.WRITE)
	if corrupt != null:
		corrupt.store_string("not a compressed region")
		corrupt = null
	var recovered := WorldStorage.new(_root)
	_expect(not recovered.open_world("verify-world").is_empty(), "metadata failed while testing region backup")
	_expect(recovered.load_chunk_edits(chunk_a) == edits_a, "corrupt primary did not recover chunk A from backup")
	_expect(recovered.load_chunk_edits(chunk_b) == edits_b, "corrupt primary did not recover chunk B from backup")
	recovered.stage_chunk_edits(chunk_a, edits_a)
	_expect(recovered.flush(initial_state) == OK, "recovered region repair flush failed")
	_expect(FileAccess.file_exists(negative_region_path + ".bak"),
		"repair discarded the only valid region backup")
	corrupt = FileAccess.open(negative_region_path, FileAccess.WRITE)
	if corrupt != null:
		corrupt.store_string("corrupt after repair")
		corrupt = null
	var recovered_twice := WorldStorage.new(_root)
	recovered_twice.open_world("verify-world")
	_expect(recovered_twice.load_chunk_edits(chunk_a) == edits_a,
		"preserved region backup could not recover a second corrupt primary")

	# A future/corrupt region with no backup is rejected rather than partially read.
	var backup_path := negative_region_path + ".bak"
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(backup_path))
	var future := FileAccess.open_compressed(negative_region_path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if future != null:
		future.store_buffer(WorldStorage.REGION_MAGIC.to_utf8_buffer())
		future.store_16(WorldStorage.REGION_VERSION + 1)
		future.store_32(0)
		future = null
	var rejected := WorldStorage.new(_root)
	rejected.open_world("verify-world")
	_expect(rejected.load_chunk_edits(chunk_a).is_empty(), "future region version was not rejected")
	var unreadable_bytes := FileAccess.get_file_as_bytes(negative_region_path)
	_expect(rejected.unreadable_region_count() == 1,
		"unreadable region was not exposed for one-time player feedback")
	rejected.stage_chunk_edits(chunk_a, edits_a)
	rejected.stage_chunk_edits(chunk_c, edits_c)
	_expect(rejected.flush_dirty_regions() == OK,
		"an unreadable region blocked unrelated region saves")
	_expect(FileAccess.get_file_as_bytes(negative_region_path) == unreadable_bytes,
		"an unreadable region was overwritten after staging an edit")

	# Metadata also recovers from a syntactically valid but structurally corrupt primary.
	var metadata_path := _root + "/verify-world/metadata.json"
	var invalid_metadata := FileAccess.open(metadata_path, FileAccess.WRITE)
	if invalid_metadata != null:
		invalid_metadata.store_string(JSON.stringify({"magic": "wrong-but-valid-json"}))
		invalid_metadata = null
	var metadata_recovery := WorldStorage.new(_root).open_world("verify-world")
	_expect(not metadata_recovery.is_empty(), "invalid metadata primary did not recover from backup")
	print("WORLD STORAGE REGIONS: negative=true same_region=true deterministic=true backup=true")


func _verify_future_metadata_rejection() -> void:
	var storage := WorldStorage.new(_root)
	var config := WorldGenConfig.new({"seed": 42}).to_dictionary()
	var metadata := storage.create_world(config, {}, "future-world")
	metadata["format_version"] = WorldStorage.METADATA_VERSION + 1
	var path := _root + "/future-world/metadata.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(metadata))
		file = null
	_expect(WorldStorage.new(_root).open_world("future-world").is_empty(), "future metadata format was accepted")
	var invalid_storage := WorldStorage.new(_root)
	invalid_storage.create_world(config, {}, "invalid-block-world")
	invalid_storage.stage_chunk_edits(Vector2i.ZERO, {Vector3i.ZERO: 255})
	_expect(invalid_storage.flush_dirty_regions() == ERR_INVALID_DATA, "unknown block ID was written to a region")
	var invalid_position_storage := WorldStorage.new(_root)
	invalid_position_storage.create_world(config, {}, "invalid-position-world")
	invalid_position_storage.stage_chunk_edits(Vector2i.ZERO, {
		Vector3i(VoxelDefs.CHUNK_SIZE, 1, 0): BlockRegistry.BLOCK_STONE,
	})
	_expect(invalid_position_storage.flush_dirty_regions() == ERR_INVALID_DATA,
		"edit outside its staged chunk was written to a region")


func _verify_library_listing_and_delete() -> void:
	var summaries := WorldStorage.list_world_summaries(_root)
	var by_id: Dictionary = {}
	for summary in summaries:
		by_id[String(summary.get("id", ""))] = summary
	_expect(by_id.has("verify-world"), "saved-world library omitted a valid world")
	_expect(by_id.has("future-world") and not bool((by_id["future-world"] as Dictionary).get("compatible", true)),
		"saved-world library did not retain an incompatible world for deletion")
	var storage := WorldStorage.new(_root)
	_expect(not storage.create_world({"seed": 777}, {}, "delete-me").is_empty(),
		"could not create deletion fixture")
	_expect(not WorldStorage.delete_world("../delete-me", _root),
		"world deletion accepted a traversal id")
	_expect(WorldStorage.delete_world("delete-me", _root), "valid world deletion failed")
	_expect(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_root + "/delete-me")),
		"deleted world directory remains on disk")
	_expect(not FileAccess.file_exists(_root + "/" + WorldStorage.LAST_WORLD_FILE),
		"deleting the last-played world left a stale pointer")


func _verify_world_management() -> void:
	var storage := WorldStorage.new(_root)
	var metadata := storage.create_world({"seed": 2468}, {"inventory": [[1, 7]]}, "manage-world")
	_expect(not metadata.is_empty(), "could not create world-management fixture")
	storage.stage_chunk_edits(Vector2i.ZERO, {Vector3i(1, 2, 3): BlockRegistry.BLOCK_STONE})
	_expect(storage.flush(metadata.get("state", {})) == OK, "could not flush world-management fixture")
	_expect(WorldStorage.rename_world("manage-world", "Managed World", _root), "world rename failed")
	var renamed := WorldStorage.new(_root).open_world("manage-world")
	_expect(String(renamed.get("name", "")) == "Managed World", "renamed title did not persist")
	_expect(not WorldStorage.rename_world("manage-world", "", _root), "empty world name was accepted")
	var maximum_name := "W".repeat(64)
	_expect(WorldStorage.rename_world("manage-world", maximum_name, _root),
		"maximum-length world name was rejected")
	_expect(WorldStorage.new(_root).create_world({"seed": 1}, {}, "manage-world").is_empty(),
		"world creation overwrote an existing requested id")

	var duplicated := WorldStorage.duplicate_world("manage-world", _root)
	var duplicate_id := String(duplicated.get("id", ""))
	_expect(not duplicate_id.is_empty() and duplicate_id != "manage-world", "world duplication did not create a new id")
	_expect(String(WorldStorage.latest_world_metadata(_root).get("id", "")) == "manage-world",
		"management operation changed Continue Last World to an unplayed duplicate")
	var duplicate_storage := WorldStorage.new(_root)
	_expect(not duplicate_storage.open_world(duplicate_id).is_empty(), "duplicated world could not be opened")
	_expect(duplicate_storage.load_chunk_edits(Vector2i.ZERO) == {
		Vector3i(1, 2, 3): BlockRegistry.BLOCK_STONE,
	}, "duplicated world lost region edits")
	_expect(String(duplicated.get("name", "")) == "%s Copy" % maximum_name.substr(0, 59),
		"duplicated world name did not stay within the rename limit")

	var backup_root := _root + "_backups"
	var backup_path := WorldStorage.backup_world("manage-world", _root, backup_root)
	_expect(not backup_path.is_empty() and FileAccess.file_exists(backup_path + "/metadata.json"),
		"manual world backup did not copy metadata")
	_expect(FileAccess.file_exists(backup_path + "/regions/r.0.0.rcregion"),
		"manual world backup did not copy region data")
	_expect(WorldStorage.new(_root).open_world("../manage-world").is_empty(),
		"world opening accepted a traversal id")


func _verify_v2_compression_round_trip_and_corruption() -> void:
	var storage := WorldStorage.new(_root)
	var config := WorldGenConfig.new({"seed": 13579}).to_dictionary()
	storage.create_world(config, {}, "cache-world")
	for region_x in WorldStorage.MAX_CACHED_REGIONS + 5:
		storage.load_chunk_edits(Vector2i(region_x * WorldStorage.REGION_CHUNKS, 0))
	_expect(storage._regions.size() <= WorldStorage.MAX_CACHED_REGIONS,
		"clean region cache exceeded its bound")
	_expect(storage._loaded_regions.size() <= WorldStorage.MAX_CACHED_REGIONS,
		"loaded-region markers were not evicted with cached regions")

	for region_x in WorldStorage.MAX_CACHED_REGIONS + 1:
		var chunk_pos := Vector2i(region_x * WorldStorage.REGION_CHUNKS, 0)
		storage.stage_chunk_edits(chunk_pos, {
			Vector3i(chunk_pos.x * VoxelDefs.CHUNK_SIZE, 1, 0): BlockRegistry.BLOCK_STONE,
		})
	_expect(storage._dirty_regions.size() == WorldStorage.MAX_CACHED_REGIONS + 1,
		"dirty regions were evicted before flushing")
	_expect(storage.flush_dirty_regions() == OK, "multi-region cache flush failed")
	_expect(storage._regions.size() <= WorldStorage.MAX_CACHED_REGIONS,
		"clean cache was not trimmed after flushing")
	storage.create_world(config, {}, "cache-reset-world")
	_expect(storage._regions.is_empty() and storage._loaded_regions.is_empty(),
		"creating another world retained stale region cache entries")

	var dense_edits: Dictionary = {}
	for y in 64:
		for z in VoxelDefs.CHUNK_SIZE:
			for x in VoxelDefs.CHUNK_SIZE:
				dense_edits[Vector3i(x, y, z)] = BlockRegistry.BLOCK_STONE
	storage.stage_chunk_edits(Vector2i.ZERO, dense_edits)
	_expect(storage.flush_dirty_regions() == OK, "dense compression fixture flush failed")
	var region_path := _root + "/cache-reset-world/regions/r.0.0.rcregion"
	var compressed_size := FileAccess.get_file_as_bytes(region_path).size()
	var raw_record_size := dense_edits.size() * 11
	_expect(compressed_size > 0 and compressed_size < raw_record_size,
		"v2 compressed region was not smaller than its raw v1 edit records")
	var compressed := FileAccess.open_compressed(region_path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if compressed == null:
		_expect(false, "could not read v2 compression fixture")
	else:
		_expect(compressed.get_buffer(4).get_string_from_utf8() == WorldStorage.REGION_MAGIC
				and compressed.get_16() == WorldStorage.REGION_VERSION,
			"dense fixture was not written using the v2 region format")
		var chunk_count := compressed.get_32()
		var chunk_x := compressed.get_32()
		var chunk_z := compressed.get_32()
		var palette_count := compressed.get_16()
		var palette_block := compressed.get_8()
		var edit_count := compressed.get_32()
		var run_count := compressed.get_32()
		var delta := compressed.get_32()
		var run_length := compressed.get_16()
		var palette_index := compressed.get_16()
		_expect(chunk_count == 1 and chunk_x == 0 and chunk_z == 0 and palette_count == 1 \
				and palette_block == BlockRegistry.BLOCK_STONE and edit_count == dense_edits.size() \
				and run_count == 1 and delta == 0 and run_length == dense_edits.size() \
				and palette_index == 0 and compressed.get_position() == compressed.get_length(),
			"v2 dense fixture did not use the expected palette plus delta-RLE record")
		compressed = null
	var reopened := WorldStorage.new(_root)
	_expect(not reopened.open_world("cache-reset-world").is_empty(), "could not reopen v2 compression fixture")
	_expect(reopened.load_chunk_edits(Vector2i.ZERO) == dense_edits,
		"v2 palette and delta-RLE data did not round-trip")

	var corrupt_storage := WorldStorage.new(_root)
	_expect(not corrupt_storage.create_world(config, {}, "corrupt-v2-world").is_empty(),
		"could not create v2 corruption world")
	var corrupt_path := _root + "/corrupt-v2-world/regions/r.0.0.rcregion"
	var corrupt := FileAccess.open_compressed(corrupt_path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if corrupt == null:
		_expect(false, "could not write v2 corruption fixture")
	else:
		corrupt.store_buffer(WorldStorage.REGION_MAGIC.to_utf8_buffer())
		corrupt.store_16(WorldStorage.REGION_VERSION)
		corrupt.store_32(1)
		corrupt.store_32(0)
		corrupt.store_32(0)
		corrupt.store_16(1)
		corrupt.store_8(BlockRegistry.BLOCK_STONE)
		corrupt.store_32(1)
		corrupt.store_32(1)
		corrupt.store_32(0)
		corrupt.store_16(1)
		corrupt.store_16(1) # Palette index 1 is outside the one-entry palette.
		corrupt.flush()
		corrupt = null
	var rejected := WorldStorage.new(_root)
	rejected.open_world("corrupt-v2-world")
	_expect(rejected.load_chunk_edits(Vector2i.ZERO).is_empty(),
		"corrupt v2 palette index was partially decoded")
	print("WORLD STORAGE V2: cache_max=%d compressed=%d raw_v1_records=%d round_trip=true corruption_rejected=true" % [
		WorldStorage.MAX_CACHED_REGIONS, compressed_size, raw_record_size])


func _verify_generation_edit_priority() -> void:
	var generator := TerrainGenerator.new()
	generator.configure({"seed": 77123, "tree_density": 0.0, "decoration_density": 0.0})
	var forced := Vector3i(3, 100, 4)
	var removed := Vector3i(5, 1, 6)
	var result := generator.generate_data(Vector2i.ZERO, {
		forced: BlockRegistry.BLOCK_TORCH,
		removed: BlockRegistry.BLOCK_AIR,
	}, false)
	_expect(_block(result.data, forced) == BlockRegistry.BLOCK_TORCH, "loaded edit did not override generated air/terrain")
	_expect(_block(result.data, removed) == BlockRegistry.BLOCK_AIR, "loaded AIR edit did not override generated terrain")


func _block(data: PackedByteArray, position: Vector3i) -> int:
	return data[position.x + position.z * VoxelDefs.DATA_STRIDE_Z + position.y * VoxelDefs.DATA_STRIDE_Y]


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _equivalent(left: Variant, right: Variant) -> bool:
	if (typeof(left) == TYPE_INT or typeof(left) == TYPE_FLOAT) \
			and (typeof(right) == TYPE_INT or typeof(right) == TYPE_FLOAT):
		return is_equal_approx(float(left), float(right))
	if typeof(left) != typeof(right):
		return false
	if typeof(left) == TYPE_DICTIONARY:
		if left.size() != right.size():
			return false
		for key in left:
			if not right.has(key) or not _equivalent(left[key], right[key]):
				return false
		return true
	if typeof(left) == TYPE_ARRAY:
		if left.size() != right.size():
			return false
		for index in left.size():
			if not _equivalent(left[index], right[index]):
				return false
		return true
	return left == right
