extends SceneTree

var _failures := PackedStringArray()
var _root := "user://world_storage_verify_%d" % Time.get_ticks_usec()
const WORLDGEN_MIGRATION_HASHES := {
	1: "f6aa67c78f19b7f8f9baee9133eac78f27a21f0d719a926311fdc19c75ab1f93",
	2: "c743ab6db11f64ce777aeb4d3ea06a6ec175cd0b876043ed56b1a7ef84c7d760",
	3: "be1c9c3712afd597e637463a5bebf25a7813ccd68bddf7efa5080ad9958486f5",
	4: "1e72a0207cfca8da8acea5efadd508cdea38d4acdd7d4347b38a2acb20ec5920",
	5: "4ddb5f1c3a9bb198a882069e56c20417d41b24d84f49de8aaa86b9d77cf684ae",
	6: "da705fd0f749518a73f4e41f7c9b93a964783c828f28e81428d6772891ff0cf7",
	7: "1d88708dd2dd9c8eb0f1fa7e6510b2815f2cbf5572cc80a59e67b97cd51b04d5",
	8: "6a27c9f03e665f6c40f4500eeb6fbb2ca6d7681b6791461bfe829968cbf27f85",
	9: "64bc2a9d1c27b5a99e93f9eaf9525ef580ecf26fa4eb3987f767d0f5b98dc65a",
	10: "5db38b3f49509f3eb5cea281017a9c4e86161ebf92ffcab889329c5d665eb91a",
	11: "bea6af0ec518980f6a38c26826584a719c0e1aef5f21bf83584bb9652e2b30ab",
	12: "987cb6224bd2772c0125acc58050692b0df668e92402443040ccef3d45fc57ee",
	13: "8553843f78fd5bcdedbc14cdb7f6e8d6226ea745b377843556509f15dd951ed3",
	14: "bf288934dc42421719ad8c04b95be0d051fe1634a4a40fedfd588adad1139498",
}


func _initialize() -> void:
	_verify_game_modes()
	_verify_metadata_and_worldgen_migration_fixtures()
	_verify_v1_compatibility_fixture()
	_verify_session_state_migration_fixtures()
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


## These fixtures deliberately use the sparse dictionaries written by older
## releases. Do not build them with WorldGenConfig: that would recreate today's
## format and stop exercising absent historical keys.
func _verify_metadata_and_worldgen_migration_fixtures() -> void:
	for version in range(1, WorldGenConfig.CURRENT_VERSION + 1):
		var id := "metadata-worldgen-v%d" % version
		var source_worldgen := _historical_worldgen_fixture(version)
		_expect(_write_metadata_fixture(id, source_worldgen, {"fixture": version}),
			"could not write metadata fixture for worldgen v%d" % version)
		var loaded := WorldStorage.new(_root).open_world(id)
		_expect(not loaded.is_empty(), "metadata fixture for worldgen v%d was rejected" % version)
		if loaded.is_empty():
			continue
		_expect(_equivalent(loaded.get("worldgen", {}), source_worldgen),
			"metadata fixture for worldgen v%d changed before generation" % version)
		var first_config := WorldGenConfig.new(loaded["worldgen"]).to_dictionary()
		var second_config := WorldGenConfig.new(loaded["worldgen"]).to_dictionary()
		_expect(first_config == second_config and int(first_config.get("worldgen_version", -1)) == version,
			"worldgen v%d did not migrate to a stable canonical config" % version)
		var first_generator := TerrainGenerator.new()
		var second_generator := TerrainGenerator.new()
		first_generator.configure(loaded["worldgen"])
		second_generator.configure(loaded["worldgen"])
		var chunk := Vector2i(-version, version - WorldGenConfig.CURRENT_VERSION)
		var first_data: PackedByteArray = first_generator.generate_data(chunk, {}).data
		var second_data: PackedByteArray = second_generator.generate_data(chunk, {}).data
		_expect(not first_data.is_empty() and first_data == second_data,
			"worldgen v%d fixture generation was not deterministic" % version)
		_expect(_sha256(first_data) == WORLDGEN_MIGRATION_HASHES.get(version, ""),
			"worldgen v%d historical output changed" % version)

	var malformed_id := "metadata-malformed"
	var malformed := _metadata_fixture(malformed_id, _historical_worldgen_fixture(8), {})
	malformed.erase("state")
	_expect(_write_raw_metadata(malformed_id, malformed), "could not write malformed metadata fixture")
	_expect(WorldStorage.new(_root).open_world(malformed_id).is_empty(),
		"metadata fixture missing state was accepted")
	var obsolete_format_id := "metadata-format-v0"
	var obsolete_format := _metadata_fixture(obsolete_format_id, _historical_worldgen_fixture(8), {})
	obsolete_format["format_version"] = WorldStorage.METADATA_VERSION - 1
	_expect(_write_raw_metadata(obsolete_format_id, obsolete_format),
		"could not write obsolete metadata format fixture")
	_expect(WorldStorage.new(_root).open_world(obsolete_format_id).is_empty(),
		"unsupported older metadata format was accepted")
	var invalid_json_id := "metadata-invalid-json"
	_expect(_write_raw_metadata_text(invalid_json_id, "{not valid json"),
		"could not write invalid JSON metadata fixture")
	_expect(WorldStorage.new(_root).open_world(invalid_json_id).is_empty(),
		"invalid JSON metadata fixture was accepted without a backup")
	print("WORLD STORAGE METADATA MIGRATION: worldgen_versions=1-%d malformed_rejected=true obsolete_rejected=true" % WorldGenConfig.CURRENT_VERSION)


func _verify_v1_compatibility_fixture() -> void:
	var config := WorldGenConfig.new({"seed": -10101, "worldgen_version": 8}).to_dictionary()
	for id: String in ["legacy-v1-world-a", "legacy-v1-world-b"]:
		var storage := WorldStorage.new(_root)
		_expect(not storage.create_world(config, {}, id).is_empty(),
			"could not create v1 compatibility world %s" % id)
		_expect(_write_v1_region_fixture(id), "could not write handcrafted v1 fixture %s" % id)
	var expected_a := {
		Vector3i(-1, 10, -1): BlockRegistry.BLOCK_AIR,
		Vector3i(-16, 55, -16): BlockRegistry.BLOCK_TORCH,
	}
	var expected_b := {
		Vector3i(-17, 33, -2): BlockRegistry.BLOCK_WATER,
	}
	var migrated_bytes := PackedByteArray()
	for id: String in ["legacy-v1-world-a", "legacy-v1-world-b"]:
		var reopened := WorldStorage.new(_root)
		_expect(not reopened.open_world(id).is_empty(), "could not reopen v1 fixture world %s" % id)
		_expect(reopened.load_chunk_edits(Vector2i(-1, -1)) == expected_a,
			"handcrafted v1 negative-coordinate edits did not load for %s" % id)
		_expect(reopened.load_chunk_edits(Vector2i(-2, -1)) == expected_b,
			"handcrafted v1 second chunk did not load for %s" % id)
		# Staging a loaded legacy chunk forces its next write through the v2 codec.
		reopened.stage_chunk_edits(Vector2i(-2, -1), expected_b)
		reopened.stage_chunk_edits(Vector2i(-1, -1), expected_a)
		_expect(reopened.flush_dirty_regions() == OK, "v1 to v2 fixture migration failed for %s" % id)
		var path: String = _root + "/" + id + "/regions/r.-1.-1.rcregion"
		_expect(_read_region_version(path) == WorldStorage.REGION_VERSION,
			"v1 fixture was not rewritten as v2 for %s" % id)
		var converted := FileAccess.get_file_as_bytes(path)
		if migrated_bytes.is_empty():
			migrated_bytes = converted
		else:
			_expect(converted == migrated_bytes, "v1 to v2 migration bytes were not deterministic")
		var verified := WorldStorage.new(_root)
		verified.open_world(id)
		_expect(verified.load_chunk_edits(Vector2i(-1, -1)) == expected_a \
				and verified.load_chunk_edits(Vector2i(-2, -1)) == expected_b,
			"v2 rewrite changed v1 fixture edits for %s" % id)
	print("WORLD STORAGE V1: handcrafted_fixture=true negative_coordinates=true migrated_to_v2=true")


func _verify_session_state_migration_fixtures() -> void:
	var version_main: Variant = _new_session_main()
	if version_main == null:
		_expect(false, "could not instantiate Main to read the session state version")
		return
	var session_version := int(version_main.SESSION_STATE_VERSION)
	_free_session_main(version_main)
	# v0 and v1 used count rows rather than positioned inventory stacks. Keep the
	# rows literal so this verifies the wire format, not ItemInventory's current
	# serializer.
	var v0 := {
		"inventory": [[BlockRegistry.BLOCK_STONE, 7], [BlockRegistry.BLOCK_STONE, 5],
			[BlockRegistry.BLOCK_TORCH, 2]],
		"selected_slot": 4,
		"day_night": null,
		"weather": null,
	}
	var v0_main: Variant = _restore_session_fixture(v0)
	_expect(v0_main.inventory.count_item(BlockRegistry.BLOCK_STONE) == 12
			and v0_main.inventory.count_item(BlockRegistry.BLOCK_TORCH) == 2
			and v0_main.selected_slot == 4,
		"v0 session fixture did not migrate legacy count rows")
	var v1 := {
		"state_version": 1,
		"inventory": [[BlockRegistry.BLOCK_DIRT, 9], [BlockRegistry.BLOCK_TORCH, 3]],
		"selected_slot": 99,
		"day_night": null,
		"weather": null,
	}
	var v1_main: Variant = _restore_session_fixture(v1)
	_expect(v1_main.inventory.count_item(BlockRegistry.BLOCK_DIRT) == 9
			and v1_main.inventory.count_item(BlockRegistry.BLOCK_TORCH) == 3
			and v1_main.selected_slot == ItemInventory.HOTBAR_SIZE - 1,
		"v1 session fixture did not migrate legacy count rows")

	var current := {
		"state_version": session_version,
		"inventory": [
			{"id": BlockRegistry.BLOCK_STONE, "count": 6, "durability": 0},
			{},
			{"id": ItemRegistry.ITEM_WOOD_PICKAXE, "count": 1, "durability": 42},
		],
		"selected_slot": 2,
		"day_night": null,
		"weather": null,
	}
	var current_main: Variant = _restore_session_fixture(current)
	_expect(current_main.inventory.persistent_state().slice(0, 3) == current["inventory"]
			and current_main.selected_slot == 2,
		"current session fixture did not retain positioned stacks")
	# This is the current tagged wire representation a subsequent save uses for
	# a restored legacy inventory; it must load without changing stack positions.
	var migrated_current := {
		"state_version": session_version,
		"inventory": v0_main.inventory.persistent_state(),
		"selected_slot": v0_main.selected_slot,
		"day_night": null,
		"weather": null,
	}
	var round_tripped: Variant = _restore_session_fixture(migrated_current)
	_expect(round_tripped.inventory.persistent_state() == migrated_current["inventory"],
		"v0 session did not produce a loadable current inventory wire format")

	var future_main: Variant = _new_session_main()
	_expect(future_main._migrate_session_state({"state_version": session_version + 1,
		"inventory": current["inventory"]}).is_empty(), "future session version was accepted")
	_expect(future_main._migrate_session_state([]).is_empty(), "non-dictionary session fixture was accepted")
	var malformed_main: Variant = _restore_session_fixture({
		"state_version": session_version,
		"inventory": "not an inventory array",
		"selected_slot": "not a slot",
		"day_night": null,
		"weather": null,
	})
	_expect(_all_inventory_slots_empty(malformed_main.inventory.persistent_state())
			and malformed_main.selected_slot == 0,
		"malformed current session did not fall back to an empty survival state")
	for main in [v0_main, v1_main, current_main, round_tripped, future_main, malformed_main]:
		_free_session_main(main)
	print("WORLD STORAGE SESSION MIGRATION: v0=true v1=true current=true future_rejected=true malformed_safe=true")


func _new_session_main() -> Variant:
	var script: Variant = load("res://game/main.gd")
	return script.new() if script != null and script.can_instantiate() else null


func _restore_session_fixture(fixture: Variant) -> Variant:
	var main: Variant = _new_session_main()
	if main == null:
		_expect(false, "could not instantiate Main for session migration fixture")
		return null
	main._game_mode = GameMode.SURVIVAL
	main._restore_session_state(main._migrate_session_state(fixture))
	return main


func _free_session_main(value: Variant) -> void:
	if value is Node:
		value.free()


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


func _historical_worldgen_fixture(version: int) -> Dictionary:
	var fixture := {
		"seed": -400_000 - version,
		"world_type": version % 3,
		"terrain_scale": 1.25,
		"tree_density": 0.75,
		"worldgen_version": version,
	}
	# v10 introduced the two opt-in terrain experiments and v11 introduced
	# climate variants/region structures. Earlier fixtures intentionally omit
	# those keys to exercise their historical defaults.
	if version >= WorldGenConfig.SPLINE_TERRAIN_VERSION:
		fixture["spline_terrain"] = true
		fixture["elevated_hydrology"] = true
	if version >= WorldGenConfig.VARIANT_WORLDGEN_VERSION:
		fixture["climate_variants"] = false
		fixture["region_structures"] = false
	return fixture


func _metadata_fixture(id: String, worldgen: Dictionary, state: Dictionary) -> Dictionary:
	return {
		"magic": WorldStorage.METADATA_MAGIC,
		"format_version": WorldStorage.METADATA_VERSION,
		"id": id,
		"name": "Migration fixture %s" % id,
		"created_unix": 1_700_000_000,
		"updated_unix": 1_700_000_000,
		"worldgen": worldgen.duplicate(true),
		"game_mode": GameMode.SURVIVAL,
		"layout": {
			"chunk_size": VoxelDefs.CHUNK_SIZE,
			"world_height": VoxelDefs.WORLD_HEIGHT,
			"region_chunks": WorldStorage.REGION_CHUNKS,
		},
		"block_registry_revision": 1,
		"state": state.duplicate(true),
	}


func _write_metadata_fixture(id: String, worldgen: Dictionary, state: Dictionary) -> bool:
	return _write_raw_metadata(id, _metadata_fixture(id, worldgen, state))


func _write_raw_metadata(id: String, metadata: Dictionary) -> bool:
	return _write_raw_metadata_text(id, JSON.stringify(metadata))


func _write_raw_metadata_text(id: String, contents: String) -> bool:
	var world_path := _root + "/" + id
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(world_path + "/regions")) != OK:
		return false
	var file := FileAccess.open(world_path + "/metadata.json", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(contents)
	file.flush()
	var error := file.get_error()
	file = null
	return error == OK


## Exact pre-palette region records. Keep this separate from _write_region():
## it verifies the old on-disk layout rather than merely testing today's writer.
func _write_v1_region_fixture(id: String) -> bool:
	var path := _root + "/" + id + "/regions/r.-1.-1.rcregion"
	var fixture := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if fixture == null:
		return false
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
	var error := fixture.get_error()
	fixture = null
	return error == OK


func _read_region_version(path: String) -> int:
	var file := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if file == null or file.get_buffer(4).get_string_from_utf8() != WorldStorage.REGION_MAGIC:
		return -1
	var version := int(file.get_16())
	file = null
	return version


func _all_inventory_slots_empty(slots: Array) -> bool:
	for slot in slots:
		if slot is Dictionary and not slot.is_empty():
			return false
	return true


func _block(data: PackedByteArray, position: Vector3i) -> int:
	return data[position.x + position.z * VoxelDefs.DATA_STRIDE_Z + position.y * VoxelDefs.DATA_STRIDE_Y]


func _sha256(data: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(data)
	return context.finish().hex_encode()


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
