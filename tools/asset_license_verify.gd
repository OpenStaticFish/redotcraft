## Deterministic, display-free audit of shipped binary assets and attribution.
## Run: redot --headless --path . --script res://tools/asset_license_verify.gd
##
## This reads source metadata rather than instantiating render resources or
## project classes, which keeps it safe for headless CI. See assets/README.md.
extends SceneTree

const BLOCK_REGISTRY_SOURCE := "res://world/block_registry.gd"
const AUDIO_MANAGER_SOURCE := "res://autoload/audio_manager.gd"
const UI_THEME_SOURCE := "res://ui/ui_theme.gd"
const FIRE_OVERLAY_SOURCE := "res://world/fire_overlay.gd"
const TEXTURE_DIRECTORIES := [
	"res://assets/placeholders/zigcraft/default",
	"res://assets/placeholders/underwater",
	"res://assets/placeholders/explosives",
	"res://assets/placeholders/caves",
	"res://assets/placeholders/fire",
	"res://assets/placeholders/functional",
]
const AUDIO_DIRECTORIES := ["res://assets/audio/sfx", "res://assets/audio/ambient"]
const REQUIRED_DOCUMENTS := [
	"res://assets/audio/README.md",
	"res://assets/audio/LICENSE-voxelibre-mcl-sounds.txt",
	"res://assets/audio/LICENSE-kenney-ui-audio.txt",
	"res://assets/fonts/README.md",
	"res://assets/fonts/OFL.txt",
	"res://assets/placeholders/zigcraft/README.md",
	"res://assets/placeholders/underwater/README.md",
	"res://assets/placeholders/explosives/README.md",
	"res://assets/placeholders/caves/README.md",
	"res://assets/placeholders/fire/README.md",
	"res://assets/placeholders/functional/README.md",
]

var _failures := 0
var _snake_case: RegEx


func _initialize() -> void:
	_snake_case = RegEx.new()
	_snake_case.compile("^[a-z0-9]+(?:_[a-z0-9]+)*\\.(png|ogg)$")
	process_frame.connect(_verify, CONNECT_ONE_SHOT)


func _verify() -> void:
	_verify_required_documents()
	_verify_texture_sources()
	_verify_block_texture_references()
	_verify_fonts()
	_verify_audio_bank()
	_verify_fire_overlay_references()
	if _failures == 0:
		print("ASSET LICENSE VERIFY: PASS")
		quit(0)
		return
	print("ASSET LICENSE VERIFY: FAIL (%d)" % _failures)
	quit(1)


func _verify_required_documents() -> void:
	for path: String in REQUIRED_DOCUMENTS:
		if not FileAccess.file_exists(path):
			_fail("missing required license or attribution file: %s" % path)
			continue
		if FileAccess.get_file_as_string(path).strip_edges().is_empty():
			_fail("required license or attribution file is empty: %s" % path)


func _verify_texture_sources() -> void:
	for directory: String in TEXTURE_DIRECTORIES:
		if not _directory_exists(directory):
			_fail("missing texture directory: %s" % directory)
			continue
		for filename: String in DirAccess.get_files_at(directory):
			var path := directory.path_join(filename)
			if filename.ends_with(".png"):
				if _snake_case.search(filename) == null:
					_fail("texture filename must be lowercase snake_case: %s" % path)
				_verify_import(path, "texture")
			elif not (filename.ends_with(".png.import") or filename == "README.md"):
				_fail("unexpected texture-directory file: %s (only .png sources, .import metadata, and README.md belong here)" % path)


func _verify_block_texture_references() -> void:
	var source := _read_source(BLOCK_REGISTRY_SOURCE)
	if source.is_empty():
		return
	var texture_root := _string_constant(source, "TEXTURE_ROOT")
	var extra_paths := _extra_texture_paths(source)
	var runtime_textures := _runtime_texture_names(source)
	var referenced := {}
	for texture_name: String in _block_texture_names(source):
		if referenced.has(texture_name):
			continue
		referenced[texture_name] = true
		if runtime_textures.has(texture_name):
			continue
		var path: String = extra_paths.get(texture_name, texture_root + texture_name)
		_verify_referenced_texture(path, "BlockRegistry texture %s" % texture_name)

	var water_shader := _string_constant(source, "WATER_SHADER_PATH")
	if water_shader.is_empty() or not FileAccess.file_exists(water_shader):
		_fail("BlockRegistry water shader reference is missing: %s" % water_shader)


func _verify_fonts() -> void:
	var source := _read_source(UI_THEME_SOURCE)
	if source.is_empty():
		return
	var expected := {}
	var font_pattern := _regex("const\\s+FONT_[A-Z_]+PATH\\s*:=\\s*\"([^\"]+\\.ttf)\"")
	for match in font_pattern.search_all(source):
		var path: String = match.get_string(1)
		expected[path.get_file()] = true
		_verify_import(path, "font_data_dynamic")

	if expected.is_empty():
		_fail("no UI font references found in %s" % UI_THEME_SOURCE)
		return
	var font_directory := "res://assets/fonts"
	if not _directory_exists(font_directory):
		_fail("missing UI font directory: %s" % font_directory)
		return
	for filename: String in DirAccess.get_files_at(font_directory):
		if filename.ends_with(".ttf") and not expected.has(filename):
			_fail("unreferenced font source: %s (add a UITheme reference or remove it)" % font_directory.path_join(filename))
		elif not (filename.ends_with(".ttf") or filename.ends_with(".ttf.import") or filename == "README.md" or filename == "OFL.txt"):
			_fail("unexpected font-directory file: %s" % font_directory.path_join(filename))


func _verify_audio_bank() -> void:
	var source := _read_source(AUDIO_MANAGER_SOURCE)
	if source.is_empty():
		return
	var sfx_directory := _string_constant(source, "SFX_DIR")
	var ambient_directory := _string_constant(source, "AMBIENT_DIR")
	var expected := {}
	for material: String in _string_array_constant(source, "MATERIALS"):
		for variation in range(_int_constant(source, "FOOTSTEP_VARIATIONS")):
			expected["%s/footstep_%s_%d.ogg" % [sfx_directory, material, variation + 1]] = true
	for variation in range(_int_constant(source, "BREAK_VARIATIONS")):
		expected["%s/block_break_%d.ogg" % [sfx_directory, variation + 1]] = true
	for variation in range(_int_constant(source, "PLACE_VARIATIONS")):
		expected["%s/block_place_%d.ogg" % [sfx_directory, variation + 1]] = true
	for kind: String in _string_array_constant(source, "UI_SOUNDS"):
		expected["%s/ui_%s.ogg" % [sfx_directory, kind]] = true
	for filename: String in _audio_filenames(source):
		expected[ambient_directory.path_join(filename)] = true

	if expected.is_empty():
		_fail("no expected audio cues could be read from %s" % AUDIO_MANAGER_SOURCE)
		return
	for path: String in expected:
		if _snake_case.search(path.get_file()) == null:
			_fail("audio filename must be lowercase snake_case: %s" % path)
		_verify_import(path, "oggvorbisstr")

	for directory: String in AUDIO_DIRECTORIES:
		if not _directory_exists(directory):
			_fail("missing audio directory: %s" % directory)
			continue
		for filename: String in DirAccess.get_files_at(directory):
			var path := directory.path_join(filename)
			if filename.ends_with(".ogg"):
				if not expected.has(path):
					_fail("unexpected audio cue: %s (add it to AudioManager or remove it)" % path)
			elif not filename.ends_with(".ogg.import"):
				_fail("unsupported audio source or metadata: %s (only recorded .ogg cues are allowed)" % path)


func _verify_fire_overlay_references() -> void:
	var source := _read_source(FIRE_OVERLAY_SOURCE)
	if source.is_empty():
		return
	var pattern := _regex("preload\\(\"(res://assets/[^\"]+)\"\\)")
	for match in pattern.search_all(source):
		_verify_referenced_texture(match.get_string(1), "FireOverlay")


func _block_texture_names(source: String) -> Array[String]:
	var start := source.find("const BLOCK_DEFS := [")
	var finish := source.find("]\n\nconst TEXTURE_ROOT", start)
	if start == -1 or finish == -1:
		_fail("could not read BLOCK_DEFS from %s" % BLOCK_REGISTRY_SOURCE)
		return []
	return _quoted_pngs(source.substr(start, finish - start))


func _extra_texture_paths(source: String) -> Dictionary:
	var paths := {}
	var start := source.find("const EXTRA_TEXTURE_PATHS := {")
	var finish := source.find("}\nconst WATER_TEXTURE_PATH", start)
	if start == -1 or finish == -1:
		_fail("could not read EXTRA_TEXTURE_PATHS from %s" % BLOCK_REGISTRY_SOURCE)
		return paths
	var pattern := _regex("\"([^\"]+\\.png)\":\\s*([A-Z_]+)\\s*\\+\\s*\"([^\"]+\\.png)\"")
	for match in pattern.search_all(source.substr(start, finish - start)):
		var root := _string_constant(source, match.get_string(2))
		if root.is_empty():
			_fail("unknown texture root %s in EXTRA_TEXTURE_PATHS" % match.get_string(2))
			continue
		if match.get_string(1) != match.get_string(3):
			_fail("mismatched EXTRA_TEXTURE_PATHS key and filename: %s" % match.get_string(0))
		paths[match.get_string(1)] = root + match.get_string(3)
	return paths


func _runtime_texture_names(source: String) -> Dictionary:
	var names := {}
	var start := source.find("func _load_image(")
	if start == -1:
		return names
	var pattern := _regex("path\\s*==\\s*TEXTURE_ROOT\\s*\\+\\s*\"([^\"]+\\.png)\"")
	for match in pattern.search_all(source.substr(start)):
		names[match.get_string(1)] = true
	return names


func _audio_filenames(source: String) -> Array[String]:
	var names: Array[String] = []
	var section_start := source.find("const AMBIENT_BEDS :=")
	var section_end := source.find("const SURFACE_CUTOFF_HZ", section_start)
	if section_start == -1 or section_end == -1:
		_fail("could not read ambient audio references from %s" % AUDIO_MANAGER_SOURCE)
		return names
	return _quoted_oggs(source.substr(section_start, section_end - section_start))


func _string_array_constant(source: String, name: String) -> Array[String]:
	var pattern := _regex("const\\s+%s[^\\[]*\\[([^\\]]*)\\]" % name)
	var match := pattern.search(source)
	if match == null:
		_fail("could not read %s from %s" % [name, AUDIO_MANAGER_SOURCE])
		return []
	return _quoted_strings(match.get_string(1))


func _string_constant(source: String, name: String) -> String:
	var pattern := _regex("const\\s+%s\\s*:=\\s*\"([^\"]+)\"" % name)
	var match := pattern.search(source)
	if match == null:
		_fail("could not read %s from source" % name)
		return ""
	return match.get_string(1)


func _int_constant(source: String, name: String) -> int:
	var pattern := _regex("const\\s+%s\\s*:=\\s*(\\d+)" % name)
	var match := pattern.search(source)
	if match == null:
		_fail("could not read %s from %s" % [name, AUDIO_MANAGER_SOURCE])
		return 0
	return match.get_string(1).to_int()


func _quoted_pngs(text: String) -> Array[String]:
	var names: Array[String] = []
	for match in _regex("\"([^\"]+\\.png)\"").search_all(text):
		names.append(match.get_string(1))
	return names


func _quoted_oggs(text: String) -> Array[String]:
	var names: Array[String] = []
	for match in _regex("\"([^\"]+\\.ogg)\"").search_all(text):
		names.append(match.get_string(1))
	return names


func _quoted_strings(text: String) -> Array[String]:
	var names: Array[String] = []
	for match in _regex("\"([^\"]+)\"").search_all(text):
		names.append(match.get_string(1))
	return names


func _verify_referenced_texture(path: String, owner: String) -> void:
	if not FileAccess.file_exists(path):
		_fail("%s references a missing texture: %s" % [owner, path])
		return
	_verify_import(path, "texture")


func _verify_import(path: String, importer: String) -> void:
	if not FileAccess.file_exists(path):
		_fail("missing asset source: %s" % path)
		return
	var import_path := path + ".import"
	if not FileAccess.file_exists(import_path):
		_fail("missing import metadata: %s (run `redot --headless --import --path .` and commit the generated .import file)" % import_path)
		return
	var metadata := FileAccess.get_file_as_string(import_path)
	if not metadata.contains("importer=\"%s\"" % importer):
		_fail("wrong importer in %s: expected %s; reimport %s" % [import_path, importer, path])
	if not metadata.contains("source_file=\"%s\"" % path):
		_fail("stale import metadata in %s: source_file must reference %s; reimport it" % [import_path, path])
	if not ResourceLoader.exists(path):
		_fail("asset is not available through the headless import cache: %s (run `redot --headless --import --path .`)" % path)


func _read_source(path: String) -> String:
	if not FileAccess.file_exists(path):
		_fail("missing source file used for asset references: %s" % path)
		return ""
	return FileAccess.get_file_as_string(path)


func _directory_exists(path: String) -> bool:
	return DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path))


func _regex(pattern: String) -> RegEx:
	var regex := RegEx.new()
	if regex.compile(pattern) != OK:
		_fail("invalid checker regex: %s" % pattern)
	return regex


func _fail(message: String) -> void:
	_failures += 1
	push_error("asset_license_verify: %s" % message)
