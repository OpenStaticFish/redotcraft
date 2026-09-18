class_name WorldStorage
extends RefCounted

## Durable world metadata plus sparse final block edits. Procedural chunk data is
## never saved: chunks regenerate from their frozen worldgen config and replay
## these edits last.

const METADATA_MAGIC := "redotcraft-world"
const METADATA_VERSION := 1
const REGION_MAGIC := "RCRG"
const REGION_VERSION := 2
const REGION_VERSION_LEGACY := 1
const REGION_CHUNKS := 32
const MAX_REGION_CHUNKS := REGION_CHUNKS * REGION_CHUNKS
const MAX_REGION_EDITS := 2_000_000
const MAX_PALETTE_ENTRIES := 256
const MAX_CACHED_REGIONS := 16
const DEFAULT_ROOT := "user://worlds"
const DEFAULT_BACKUP_ROOT := "user://world_backups"
const LAST_WORLD_FILE := "last_world.txt"

var root_path := DEFAULT_ROOT
var world_id := ""
var metadata: Dictionary = {}

var _regions: Dictionary = {}
var _loaded_regions: Dictionary = {}
var _dirty_regions: Dictionary = {}
var _region_access: Dictionary = {}
var _access_tick := 0
var _regions_loaded_from_backup: Dictionary = {}
var _metadata_loaded_from_backup := false
var _unreadable_regions: Dictionary = {}


func _init(p_root_path: String = DEFAULT_ROOT) -> void:
	root_path = p_root_path.trim_suffix("/")


func create_world(world_config: Dictionary, initial_state: Dictionary = {}, requested_id: String = "",
		activate: bool = true) -> Dictionary:
	_reset_cache()
	metadata = {}
	var normalized_config := WorldGenConfig.new(world_config).to_dictionary()
	world_id = _safe_id(requested_id)
	if not requested_id.is_empty() and world_id != requested_id:
		return {}
	if world_id.is_empty():
		world_id = "%d-%d-%d" % [
			int(Time.get_unix_time_from_system()),
			abs(int(normalized_config.get("seed", 0))),
			Time.get_ticks_usec(),
		]
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_world_path())):
		return {}
	var now := int(Time.get_unix_time_from_system())
	metadata = {
		"magic": METADATA_MAGIC,
		"format_version": METADATA_VERSION,
		"id": world_id,
		"name": "World %d" % int(normalized_config.get("seed", 0)),
		"created_unix": now,
		"updated_unix": now,
		"worldgen": normalized_config,
		"layout": {
			"chunk_size": VoxelDefs.CHUNK_SIZE,
			"world_height": VoxelDefs.WORLD_HEIGHT,
			"region_chunks": REGION_CHUNKS,
		},
		"block_registry_revision": 1,
		"state": initial_state.duplicate(true),
	}
	if not _ensure_world_directories():
		metadata = {}
		return {}
	if _write_metadata() != OK:
		metadata = {}
		return {}
	if activate:
		_write_last_world_id()
	return metadata.duplicate(true)


func open_world(p_world_id: String) -> Dictionary:
	_reset_cache()
	world_id = _safe_id(p_world_id)
	if world_id.is_empty() or world_id != p_world_id:
		return {}
	metadata = _read_metadata_file(_metadata_path())
	if metadata.is_empty() or not _validate_metadata(metadata) \
			or String(metadata.get("id", "")) != world_id:
		metadata = {}
		return {}
	_write_last_world_id()
	return metadata.duplicate(true)


func load_chunk_edits(chunk_pos: Vector2i) -> Dictionary:
	var region_pos := _chunk_region(chunk_pos)
	_load_region(region_pos)
	var region: Dictionary = _regions.get(region_pos, {})
	var edits: Dictionary = region.get(chunk_pos, {})
	return edits.duplicate()


func stage_chunk_edits(chunk_pos: Vector2i, edits: Dictionary) -> void:
	var region_pos := _chunk_region(chunk_pos)
	_load_region(region_pos)
	if _unreadable_regions.has(region_pos):
		return
	var region: Dictionary = _regions.get(region_pos, {})
	if edits.is_empty():
		region.erase(chunk_pos)
	else:
		region[chunk_pos] = edits.duplicate()
	_regions[region_pos] = region
	_dirty_regions[region_pos] = true


func flush(state: Dictionary = {}) -> Error:
	var region_error := flush_dirty_regions()
	if region_error != OK:
		return region_error
	if not state.is_empty():
		metadata["state"] = state.duplicate(true)
	metadata["updated_unix"] = int(Time.get_unix_time_from_system())
	var metadata_error := _write_metadata()
	if metadata_error == OK:
		_write_last_world_id()
	return metadata_error


func flush_dirty_regions() -> Error:
	var dirty: Array[Vector2i] = []
	for key in _dirty_regions:
		dirty.append(key)
	dirty.sort_custom(_vector2_less)
	for region_pos in dirty:
		var error := _write_region(region_pos)
		if error != OK:
			return error
		_dirty_regions.erase(region_pos)
	_evict_clean_regions()
	return OK


func has_dirty_regions() -> bool:
	return not _dirty_regions.is_empty()


func unreadable_region_count() -> int:
	return _unreadable_regions.size()


static func latest_world_metadata(p_root_path: String = DEFAULT_ROOT) -> Dictionary:
	var root := p_root_path.trim_suffix("/")
	var last_path := root + "/" + LAST_WORLD_FILE
	if not FileAccess.file_exists(last_path):
		return {}
	var id := FileAccess.get_file_as_string(last_path).strip_edges()
	if id.is_empty():
		return {}
	var storage := WorldStorage.new(root)
	return storage.open_world(id)


## Read-only library view for menus. Unlike open_world(), listing never changes
## the last-played pointer. Worlds from a newer build remain visible but are
## marked incompatible so players can still delete them deliberately.
static func list_world_summaries(p_root_path: String = DEFAULT_ROOT) -> Array[Dictionary]:
	var root := p_root_path.trim_suffix("/")
	var found: Array[Dictionary] = []
	var directory := DirAccess.open(root)
	if directory == null:
		return found
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != ".." and directory.current_is_dir() \
				and _safe_id(entry) == entry:
			var summary := _read_world_summary(root, entry)
			if not summary.is_empty():
				found.append(summary)
		entry = directory.get_next()
	directory.list_dir_end()
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_time := int(a.get("updated_unix", 0))
		var b_time := int(b.get("updated_unix", 0))
		return a_time > b_time or (a_time == b_time and String(a.get("id", "")) < String(b.get("id", "")))
	)
	return found


## Permanently removes one validated world directory. The caller owns user
## confirmation; this boundary rejects traversal and unrelated directories.
static func delete_world(p_world_id: String, p_root_path: String = DEFAULT_ROOT) -> bool:
	var id := _safe_id(p_world_id)
	if id.is_empty() or id != p_world_id:
		return false
	var root := p_root_path.trim_suffix("/")
	var world_path := root + "/" + id
	if _read_world_summary(root, id).is_empty() \
			or not _remove_directory_tree(ProjectSettings.globalize_path(world_path)):
		return false
	var last_path := root + "/" + LAST_WORLD_FILE
	if FileAccess.file_exists(last_path) \
			and FileAccess.get_file_as_string(last_path).strip_edges() == id:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(last_path))
	return true


static func rename_world(p_world_id: String, new_name: String, p_root_path: String = DEFAULT_ROOT) -> bool:
	var name := new_name.strip_edges()
	if name.is_empty() or name.length() > 64:
		return false
	var storage := WorldStorage.new(p_root_path)
	if storage._read_world_for_management(p_world_id).is_empty():
		return false
	storage.metadata["name"] = name
	return storage._write_metadata() == OK


static func duplicate_world(p_world_id: String, p_root_path: String = DEFAULT_ROOT) -> Dictionary:
	var source := WorldStorage.new(p_root_path)
	var source_metadata := source._read_world_for_management(p_world_id)
	if source_metadata.is_empty():
		return {}
	var copy := WorldStorage.new(p_root_path)
	var created := copy.create_world(
		source_metadata.get("worldgen", {}), source_metadata.get("state", {}), "", false)
	if created.is_empty():
		return {}
	var source_name := String(source_metadata.get("name", "World"))
	copy.metadata["name"] = "%s Copy" % source_name.substr(0, 59)
	var source_regions := p_root_path.trim_suffix("/") + "/" + p_world_id + "/regions"
	var destination_regions := p_root_path.trim_suffix("/") + "/" + copy.world_id + "/regions"
	if not _copy_directory_contents(source_regions, destination_regions) or copy._write_metadata() != OK:
		_remove_directory_tree(ProjectSettings.globalize_path(copy._world_path()))
		return {}
	return copy.metadata.duplicate(true)


static func backup_world(p_world_id: String, p_root_path: String = DEFAULT_ROOT,
		p_backup_root: String = DEFAULT_BACKUP_ROOT) -> String:
	var source := WorldStorage.new(p_root_path)
	if source._read_world_for_management(p_world_id).is_empty():
		return ""
	var backup_root := p_backup_root.trim_suffix("/")
	var backup_id := "%s-%d-%d" % [p_world_id, int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	var destination := backup_root + "/" + backup_id
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination)) != OK:
		return ""
	var source_path := p_root_path.trim_suffix("/") + "/" + p_world_id
	if not _copy_directory_contents(source_path, destination):
		_remove_directory_tree(ProjectSettings.globalize_path(destination))
		return ""
	return destination


func _read_world_for_management(p_world_id: String) -> Dictionary:
	_reset_cache()
	world_id = _safe_id(p_world_id)
	if world_id.is_empty() or world_id != p_world_id:
		return {}
	metadata = _read_metadata_file(_metadata_path())
	if metadata.is_empty() or String(metadata.get("id", "")) != world_id:
		metadata = {}
	return metadata.duplicate(true)


static func _read_world_summary(root: String, id: String) -> Dictionary:
	var path := root + "/" + id + "/metadata.json"
	var storage := WorldStorage.new(root)
	storage.world_id = id
	var validated := storage._read_metadata_file(path)
	if not validated.is_empty() and String(validated.get("id", "")) == id:
		return _summary_from_metadata(validated, id)
	for candidate in [path, path + ".bak"]:
		if not FileAccess.file_exists(candidate):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(candidate))
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var summary := _summary_from_metadata(parsed, id)
		if not summary.is_empty():
			return summary
	return {}


static func _summary_from_metadata(value: Dictionary, id: String) -> Dictionary:
	if value.get("magic", "") != METADATA_MAGIC or String(value.get("id", "")) != id \
			or typeof(value.get("worldgen", null)) != TYPE_DICTIONARY:
		return {}
	var worldgen: Dictionary = value["worldgen"]
	var worldgen_version := int(worldgen.get("worldgen_version", -1))
	return {
		"id": id,
		"name": String(value.get("name", "")),
		"created_unix": int(value.get("created_unix", 0)),
		"updated_unix": int(value.get("updated_unix", 0)),
		"seed": int(worldgen.get("seed", 0)),
		"world_type": clampi(int(worldgen.get("world_type", 0)), 0, 2),
		"worldgen_version": worldgen_version,
		"compatible": int(value.get("format_version", -1)) == METADATA_VERSION \
			and worldgen_version >= 1 and worldgen_version <= WorldGenConfig.CURRENT_VERSION,
	}


static func _remove_directory_tree(path: String) -> bool:
	var directory := DirAccess.open(path)
	if directory == null:
		return false
	var files: Array[String] = []
	var directories: Array[String] = []
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			if directory.current_is_dir():
				directories.append(entry)
			else:
				files.append(entry)
		entry = directory.get_next()
	directory.list_dir_end()
	for file_name in files:
		if DirAccess.remove_absolute(path.path_join(file_name)) != OK:
			return false
	for directory_name in directories:
		if not _remove_directory_tree(path.path_join(directory_name)):
			return false
	return DirAccess.remove_absolute(path) == OK


static func _copy_directory_contents(source_path: String, destination_path: String) -> bool:
	var source_abs := ProjectSettings.globalize_path(source_path)
	var destination_abs := ProjectSettings.globalize_path(destination_path)
	var source := DirAccess.open(source_abs)
	if source == null:
		return false
	var make_error := DirAccess.make_dir_recursive_absolute(destination_abs)
	if make_error != OK and make_error != ERR_ALREADY_EXISTS:
		return false
	source.list_dir_begin()
	var entry := source.get_next()
	while not entry.is_empty():
		if entry != "." and entry != ".." and not entry.ends_with(".tmp"):
			var source_entry := source_abs.path_join(entry)
			var destination_entry := destination_abs.path_join(entry)
			if source.current_is_dir():
				if not _copy_directory_contents(source_entry, destination_entry):
					source.list_dir_end()
					return false
			elif DirAccess.copy_absolute(source_entry, destination_entry) != OK:
				source.list_dir_end()
				return false
		entry = source.get_next()
	source.list_dir_end()
	return true


func _load_region(region_pos: Vector2i) -> void:
	if _loaded_regions.has(region_pos):
		_touch_region(region_pos)
		return
	_loaded_regions[region_pos] = true
	var loaded := _read_region_file(_region_path(region_pos))
	if not bool(loaded.get("valid", false)) and FileAccess.file_exists(_region_backup_path(region_pos)):
		loaded = _read_region_file(_region_backup_path(region_pos))
		if bool(loaded.get("valid", false)):
			_regions_loaded_from_backup[region_pos] = true
	var valid := bool(loaded.get("valid", false))
	_regions[region_pos] = loaded.get("region", {}) if valid else {}
	if not valid and (FileAccess.file_exists(_region_path(region_pos)) \
			or FileAccess.file_exists(_region_backup_path(region_pos))):
		var first_warning := not _unreadable_regions.has(region_pos)
		_unreadable_regions[region_pos] = true
		if first_warning:
			push_warning("World region %s is corrupt or from an unsupported version; edits to this region are blocked to preserve it." % region_pos)
	_touch_region(region_pos)
	_evict_clean_regions()


func _write_region(region_pos: Vector2i) -> Error:
	if not _ensure_world_directories():
		return ERR_CANT_CREATE
	var region: Dictionary = _regions.get(region_pos, {})
	if not _validate_region_for_write(region_pos, region):
		return ERR_INVALID_DATA
	var path := _region_path(region_pos)
	var temporary := path + ".tmp"
	var file := FileAccess.open_compressed(temporary, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(REGION_MAGIC.to_utf8_buffer())
	file.store_16(REGION_VERSION)
	var chunks: Array[Vector2i] = []
	for key in region:
		if key is Vector2i and not (region[key] as Dictionary).is_empty():
			chunks.append(key)
	chunks.sort_custom(_vector2_less)
	file.store_32(chunks.size())
	for chunk_pos in chunks:
		var edits: Dictionary = region[chunk_pos]
		var positions: Array[Vector3i] = []
		var palette_values: Dictionary = {}
		for key in edits:
			if key is Vector3i:
				positions.append(key)
				palette_values[int(edits[key])] = true
		positions.sort_custom(_vector3_less)
		var palette: Array[int] = []
		for block_id in palette_values:
			palette.append(int(block_id))
		palette.sort()
		var palette_indices: Dictionary = {}
		for palette_index in range(palette.size()):
			palette_indices[palette[palette_index]] = palette_index
		file.store_32(chunk_pos.x)
		file.store_32(chunk_pos.y)
		file.store_16(palette.size())
		for block_id in palette:
			file.store_8(block_id)
		file.store_32(positions.size())
		var runs: Array[Vector3i] = [] # x=start local index, y=length, z=palette index
		for position in positions:
			var local_x := position.x - chunk_pos.x * VoxelDefs.CHUNK_SIZE
			var local_z := position.z - chunk_pos.y * VoxelDefs.CHUNK_SIZE
			var local_index := local_x + local_z * VoxelDefs.CHUNK_SIZE \
				+ position.y * VoxelDefs.CHUNK_AREA
			var palette_index := int(palette_indices[int(edits[position])])
			if not runs.is_empty():
				var last := runs[runs.size() - 1]
				if last.x + last.y == local_index and last.z == palette_index and last.y < 65535:
					last.y += 1
					runs[runs.size() - 1] = last
					continue
			runs.append(Vector3i(local_index, 1, palette_index))
		file.store_32(runs.size())
		var previous_end := 0
		for run in runs:
			file.store_32(run.x - previous_end)
			file.store_16(run.y)
			file.store_16(run.z)
			previous_end = run.x + run.y
	file.flush()
	var write_error := file.get_error()
	file = null
	if write_error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		return write_error
	var result := _replace_with_backup(temporary, path, _region_backup_path(region_pos),
		bool(_regions_loaded_from_backup.get(region_pos, false)))
	if result == OK:
		_regions_loaded_from_backup.erase(region_pos)
	return result


func _read_region_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"valid": false, "region": {}}
	var file := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if file == null or not _can_read(file, 6):
		return {"valid": false, "region": {}}
	if file.get_buffer(4).get_string_from_utf8() != REGION_MAGIC:
		return {"valid": false, "region": {}}
	var version := int(file.get_16())
	if version == REGION_VERSION_LEGACY:
		return _read_region_v1(file, path) if file.get_error() == OK else {"valid": false, "region": {}}
	if version != REGION_VERSION:
		return {"valid": false, "region": {}}
	return _read_region_v2(file, path) if file.get_error() == OK else {"valid": false, "region": {}}


func _read_region_v1(file: FileAccess, path: String) -> Dictionary:
	if not _can_read(file, 4):
		return {"valid": false, "region": {}}
	var chunk_count := int(file.get_32())
	if chunk_count < 0 or chunk_count > MAX_REGION_CHUNKS:
		return {"valid": false, "region": {}}
	var result: Dictionary = {}
	var total_edits := 0
	var expected_region := _chunk_region_from_path(path)
	for _chunk_index in range(chunk_count):
		if not _can_read(file, 12):
			return {"valid": false, "region": {}}
		var chunk_pos := Vector2i(_signed_32(file.get_32()), _signed_32(file.get_32()))
		var edit_count := int(file.get_32())
		total_edits += edit_count
		if edit_count < 0 or total_edits > MAX_REGION_EDITS or result.has(chunk_pos) \
				or _chunk_region(chunk_pos) != expected_region:
			return {"valid": false, "region": {}}
		var edits: Dictionary = {}
		for _edit_index in range(edit_count):
			if not _can_read(file, 11):
				return {"valid": false, "region": {}}
			var x := _signed_32(file.get_32())
			var y := int(file.get_16())
			var z := _signed_32(file.get_32())
			var block_id := int(file.get_8())
			if y < 0 or y >= VoxelDefs.WORLD_HEIGHT or not _is_valid_block_id(block_id):
				return {"valid": false, "region": {}}
			var position := Vector3i(x, y, z)
			if edits.has(position) or _chunk_for_block(position) != chunk_pos:
				return {"valid": false, "region": {}}
			edits[position] = block_id
		result[chunk_pos] = edits
	return {"valid": file.get_position() == file.get_length(), "region": result}


func _read_region_v2(file: FileAccess, path: String) -> Dictionary:
	if not _can_read(file, 4):
		return {"valid": false, "region": {}}
	var chunk_count := int(file.get_32())
	if chunk_count < 0 or chunk_count > MAX_REGION_CHUNKS:
		return {"valid": false, "region": {}}
	var result: Dictionary = {}
	var total_edits := 0
	var expected_region := _chunk_region_from_path(path)
	for _chunk_index in range(chunk_count):
		if not _can_read(file, 10):
			return {"valid": false, "region": {}}
		var chunk_pos := Vector2i(_signed_32(file.get_32()), _signed_32(file.get_32()))
		var palette_count := int(file.get_16())
		if palette_count <= 0 or palette_count > MAX_PALETTE_ENTRIES or result.has(chunk_pos) \
				or _chunk_region(chunk_pos) != expected_region or not _can_read(file, palette_count + 8):
			return {"valid": false, "region": {}}
		var palette := PackedByteArray()
		palette.resize(palette_count)
		var previous_block_id := -1
		for palette_index in range(palette_count):
			palette[palette_index] = file.get_8()
			if int(palette[palette_index]) <= previous_block_id or not _is_valid_block_id(palette[palette_index]):
				return {"valid": false, "region": {}}
			previous_block_id = int(palette[palette_index])
		var edit_count := int(file.get_32())
		var run_count := int(file.get_32())
		total_edits += edit_count
		if edit_count <= 0 or total_edits > MAX_REGION_EDITS or run_count <= 0 \
				or run_count > edit_count:
			return {"valid": false, "region": {}}
		var edits: Dictionary = {}
		var previous_end := 0
		var decoded := 0
		for _run_index in range(run_count):
			if not _can_read(file, 8):
				return {"valid": false, "region": {}}
			var delta := int(file.get_32())
			var length := int(file.get_16())
			var palette_index := int(file.get_16())
			var start := previous_end + delta
			if delta < 0 or length <= 0 or palette_index < 0 or palette_index >= palette_count \
					or start < previous_end or start + length > VoxelDefs.CHUNK_AREA * VoxelDefs.WORLD_HEIGHT:
				return {"valid": false, "region": {}}
			for local_index in range(start, start + length):
				var y := local_index / VoxelDefs.CHUNK_AREA
				var horizontal := local_index % VoxelDefs.CHUNK_AREA
				var local_z := horizontal / VoxelDefs.CHUNK_SIZE
				var local_x := horizontal % VoxelDefs.CHUNK_SIZE
				var position := Vector3i(
					chunk_pos.x * VoxelDefs.CHUNK_SIZE + local_x, y,
					chunk_pos.y * VoxelDefs.CHUNK_SIZE + local_z)
				edits[position] = int(palette[palette_index])
			decoded += length
			previous_end = start + length
		if decoded != edit_count:
			return {"valid": false, "region": {}}
		result[chunk_pos] = edits
	return {"valid": file.get_position() == file.get_length(), "region": result}


func _write_metadata() -> Error:
	if not _ensure_world_directories() or not _validate_metadata(metadata):
		return ERR_INVALID_DATA
	var path := _metadata_path()
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(metadata, "\t"))
	file.flush()
	var write_error := file.get_error()
	file = null
	if write_error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		return write_error
	var result := _replace_with_backup(temporary, path, path + ".bak", _metadata_loaded_from_backup)
	if result == OK:
		_metadata_loaded_from_backup = false
	return result


func _read_metadata_file(path: String) -> Dictionary:
	_metadata_loaded_from_backup = false
	if FileAccess.file_exists(path):
		var primary: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(primary) == TYPE_DICTIONARY and _validate_metadata(primary):
			return primary
	var backup := path + ".bak"
	if FileAccess.file_exists(backup):
		var recovered: Variant = JSON.parse_string(FileAccess.get_file_as_string(backup))
		if typeof(recovered) == TYPE_DICTIONARY and _validate_metadata(recovered):
			_metadata_loaded_from_backup = true
			return recovered
	return {}


func _validate_metadata(value: Dictionary) -> bool:
	if value.get("magic", "") != METADATA_MAGIC or int(value.get("format_version", -1)) != METADATA_VERSION:
		return false
	if _safe_id(String(value.get("id", ""))) != String(value.get("id", "")):
		return false
	if typeof(value.get("worldgen", null)) != TYPE_DICTIONARY or typeof(value.get("state", null)) != TYPE_DICTIONARY:
		return false
	var worldgen: Dictionary = value["worldgen"]
	var worldgen_version := int(worldgen.get("worldgen_version", -1))
	if worldgen_version < 1 or worldgen_version > WorldGenConfig.CURRENT_VERSION:
		return false
	var layout: Variant = value.get("layout", {})
	if typeof(layout) != TYPE_DICTIONARY:
		return false
	return int(layout.get("chunk_size", -1)) == VoxelDefs.CHUNK_SIZE \
		and int(layout.get("world_height", -1)) == VoxelDefs.WORLD_HEIGHT \
		and int(layout.get("region_chunks", -1)) == REGION_CHUNKS


func _ensure_world_directories() -> bool:
	if world_id.is_empty():
		return false
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_regions_path()))
	return error == OK or error == ERR_ALREADY_EXISTS


func _replace_with_backup(temporary: String, path: String, backup: String,
		preserve_recovery_backup: bool = false) -> Error:
	var temp_abs := ProjectSettings.globalize_path(temporary)
	var path_abs := ProjectSettings.globalize_path(path)
	var backup_abs := ProjectSettings.globalize_path(backup)
	if preserve_recovery_backup:
		if FileAccess.file_exists(path):
			var remove_error := DirAccess.remove_absolute(path_abs)
			if remove_error != OK:
				DirAccess.remove_absolute(temp_abs)
				return remove_error
	elif FileAccess.file_exists(path):
		if FileAccess.file_exists(backup):
			DirAccess.remove_absolute(backup_abs)
		var backup_error := DirAccess.rename_absolute(path_abs, backup_abs)
		if backup_error != OK:
			DirAccess.remove_absolute(temp_abs)
			return backup_error
	var error := DirAccess.rename_absolute(temp_abs, path_abs)
	if error != OK and not preserve_recovery_backup and FileAccess.file_exists(backup):
		DirAccess.rename_absolute(backup_abs, path_abs)
	return error


func _reset_cache() -> void:
	_regions.clear()
	_loaded_regions.clear()
	_dirty_regions.clear()
	_region_access.clear()
	_regions_loaded_from_backup.clear()
	_metadata_loaded_from_backup = false
	_unreadable_regions.clear()
	_access_tick = 0


func _touch_region(region_pos: Vector2i) -> void:
	_access_tick += 1
	_region_access[region_pos] = _access_tick


func _evict_clean_regions() -> void:
	while _regions.size() > MAX_CACHED_REGIONS:
		var oldest_position: Variant = null
		var oldest_tick := 9223372036854775807
		for region_pos in _regions:
			if _dirty_regions.has(region_pos):
				continue
			var tick := int(_region_access.get(region_pos, 0))
			if tick < oldest_tick:
				oldest_tick = tick
				oldest_position = region_pos
		if oldest_position == null:
			return
		_regions.erase(oldest_position)
		_loaded_regions.erase(oldest_position)
		_region_access.erase(oldest_position)
		_regions_loaded_from_backup.erase(oldest_position)


func _validate_region_for_write(region_pos: Vector2i, region: Dictionary) -> bool:
	if region.size() > MAX_REGION_CHUNKS:
		return false
	var total_edits := 0
	for chunk_value in region:
		if not chunk_value is Vector2i or _chunk_region(chunk_value) != region_pos:
			return false
		var edits: Variant = region[chunk_value]
		if typeof(edits) != TYPE_DICTIONARY:
			return false
		total_edits += edits.size()
		if total_edits > MAX_REGION_EDITS:
			return false
		for position_value in edits:
			if not position_value is Vector3i:
				return false
			var position: Vector3i = position_value
			var block_value: Variant = edits[position]
			if position.y < 0 or position.y >= VoxelDefs.WORLD_HEIGHT \
					or _chunk_for_block(position) != chunk_value \
					or typeof(block_value) != TYPE_INT or not _is_valid_block_id(block_value):
				return false
	return true


func _write_last_world_id() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root_path))
	var file := FileAccess.open(root_path + "/" + LAST_WORLD_FILE, FileAccess.WRITE)
	if file != null:
		file.store_string(world_id)


func _metadata_path() -> String:
	return _world_path() + "/metadata.json"


func _regions_path() -> String:
	return _world_path() + "/regions"


func _region_path(region_pos: Vector2i) -> String:
	return _regions_path() + "/r.%d.%d.rcregion" % [region_pos.x, region_pos.y]


func _region_backup_path(region_pos: Vector2i) -> String:
	return _region_path(region_pos) + ".bak"


func _world_path() -> String:
	return root_path + "/" + world_id


func _chunk_region(chunk_pos: Vector2i) -> Vector2i:
	return Vector2i(WorldGenHash.floor_div(chunk_pos.x, REGION_CHUNKS), WorldGenHash.floor_div(chunk_pos.y, REGION_CHUNKS))


func _chunk_region_from_path(path: String) -> Vector2i:
	var file_name := path.get_file().trim_suffix(".bak")
	var parts := file_name.split(".")
	if parts.size() < 4:
		return Vector2i(2147483647, 2147483647)
	return Vector2i(int(parts[1]), int(parts[2]))


static func _chunk_for_block(position: Vector3i) -> Vector2i:
	return Vector2i(floori(float(position.x) / float(VoxelDefs.CHUNK_SIZE)), floori(float(position.z) / float(VoxelDefs.CHUNK_SIZE)))


static func _signed_32(value: int) -> int:
	return value - 4294967296 if value > 2147483647 else value


static func _can_read(file: FileAccess, byte_count: int) -> bool:
	return byte_count >= 0 and file.get_position() <= file.get_length() - byte_count


static func _is_valid_block_id(block_id: int) -> bool:
	for definition in BlockRegistry.BLOCK_DEFS:
		if int(definition[0]) == block_id:
			return true
	return false


static func _safe_id(value: String) -> String:
	var result := ""
	for character in value:
		if character.to_lower() in "abcdefghijklmnopqrstuvwxyz0123456789-_":
			result += character
	return result


static func _vector2_less(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)


static func _vector3_less(a: Vector3i, b: Vector3i) -> bool:
	return a.y < b.y or (a.y == b.y and (a.z < b.z or (a.z == b.z and a.x < b.x)))
