extends Node

## Central audio service: buses, small player pools, and a stream registry keyed
## by block material. Gameplay code names a material or UI cue, never a file.
## Every cue is a recorded CC0 sample under assets/audio; there is no
## synthesized bank. Missing files warn once and play silence.
##
## GameConfig is looked up through the scene tree instead of by autoload name so
## this script also compiles in headless verification scripts with no autoloads.

const BUS_MASTER := "Master"
const BUS_SFX := "SFX"
const BUS_AMBIENT := "Ambient"

const SFX_DIR := "res://assets/audio/sfx"
const AMBIENT_DIR := "res://assets/audio/ambient"

const MATERIALS: PackedStringArray = ["grass", "dirt", "stone", "sand", "snow", "gravel", "wood", "water"]
const FOOTSTEP_VARIATIONS := 3
const BREAK_VARIATIONS := 2
const PLACE_VARIATIONS := 2
const UI_SOUNDS: PackedStringArray = ["click", "hover", "confirm", "cancel"]

const SFX_POOL_SIZE := 10
const UI_POOL_SIZE := 4
const WORLD_POOL_SIZE := 12
const FOOTSTEP_DB := -13.0
const BREAK_DB := -9.0
const PLACE_DB := -11.0
const RAIN_DB := -12.0
const WIND_DB := -15.0
const THUNDER_DB := -4.0
const SILENT_DB := -80.0
# Weather beds loop for as long as their state holds; thunder is a one-shot.
const AMBIENT_BEDS := {"rain": "rain_loop.ogg", "wind": "wind_loop.ogg"}
const THUNDER_STREAM := "thunder_1.ogg"
# Submerging the camera muffles the whole mix; the cutoff is restored when the
# camera surfaces. A low-pass on Master keeps this independent of every cue.
const SURFACE_CUTOFF_HZ := 20500.0
const UNDERWATER_CUTOFF_HZ := 620.0

var _sfx_pool: Array[AudioStreamPlayer] = []
var _ui_pool: Array[AudioStreamPlayer] = []
var _world_pool: Array[AudioStreamPlayer3D] = []
var _streams := {}
var _missing := {}
var _block_materials := {}
var _pool_cursor := 0
var _bed_players: Dictionary = {}
var _bed_tweens: Dictionary = {}
var _thunder_player: AudioStreamPlayer
var _underwater_filter: AudioEffectLowPassFilter
var _underwater_active := false
var _rng := RandomNumberGenerator.new()


## Buses and the material table need no scene tree, so they are ready even in
## headless verification scripts that never attach the manager to a scene.
func _init() -> void:
	_rng.randomize()
	_ensure_buses()
	_build_block_materials()


func _ready() -> void:
	_build_pools()
	apply_volumes()
	# Loading the small bank up front avoids a first-use hitch when the player
	# breaks the first block; deferred so startup never blocks a frame.
	_preload_streams.call_deferred()


func _preload_streams() -> void:
	var total := 0
	for material in MATERIALS:
		for variation in FOOTSTEP_VARIATIONS:
			total += 1
			_get_stream("%s/footstep_%s_%d.ogg" % [SFX_DIR, material, variation + 1])
	for variation in BREAK_VARIATIONS:
		total += 1
		_get_stream("%s/block_break_%d.ogg" % [SFX_DIR, variation + 1])
	for variation in PLACE_VARIATIONS:
		total += 1
		_get_stream("%s/block_place_%d.ogg" % [SFX_DIR, variation + 1])
	for kind in UI_SOUNDS:
		total += 1
		_get_stream("%s/ui_%s.ogg" % [SFX_DIR, kind])
	for bed_file in AMBIENT_BEDS.values():
		total += 1
		_get_stream("%s/%s" % [AMBIENT_DIR, bed_file])
	total += 1
	_get_stream("%s/%s" % [AMBIENT_DIR, THUNDER_STREAM])
	print("AudioManager: %d recorded cues loaded" % total)


## Builds the mapping from block ids to the eight material families. Leaf and
## plant blocks reuse the grass set; glass and ores reuse stone; logs reuse wood.
func _build_block_materials() -> void:
	var groups := {
		"grass": [BlockRegistry.BLOCK_GRASS, BlockRegistry.BLOCK_LEAVES, BlockRegistry.BLOCK_SPRUCE_LEAVES,
			BlockRegistry.BLOCK_BIRCH_LEAVES, BlockRegistry.BLOCK_ACACIA_LEAVES, BlockRegistry.BLOCK_JUNGLE_LEAVES,
			BlockRegistry.BLOCK_MANGROVE_LEAVES, BlockRegistry.BLOCK_TALL_GRASS, BlockRegistry.BLOCK_YELLOW_FLOWER,
			BlockRegistry.BLOCK_RED_FLOWER, BlockRegistry.BLOCK_DEAD_BUSH, BlockRegistry.BLOCK_VINE,
			BlockRegistry.BLOCK_BROWN_MUSHROOM, BlockRegistry.BLOCK_RED_MUSHROOM, BlockRegistry.BLOCK_MYCELIUM,
			BlockRegistry.BLOCK_MELON, BlockRegistry.BLOCK_SEAGRASS, BlockRegistry.BLOCK_KELP,
			BlockRegistry.BLOCK_CORAL_FAN, BlockRegistry.BLOCK_CORAL_BRANCH, BlockRegistry.BLOCK_SPONGE,
			BlockRegistry.BLOCK_ANEMONE],
		"dirt": [BlockRegistry.BLOCK_DIRT, BlockRegistry.BLOCK_CLAY, BlockRegistry.BLOCK_MUD],
		"stone": [BlockRegistry.BLOCK_STONE, BlockRegistry.BLOCK_COBBLESTONE, BlockRegistry.BLOCK_BEDROCK,
			BlockRegistry.BLOCK_COAL_ORE, BlockRegistry.BLOCK_IRON_ORE, BlockRegistry.BLOCK_GOLD_ORE,
			BlockRegistry.BLOCK_TERRACOTTA, BlockRegistry.BLOCK_GLOWSTONE, BlockRegistry.BLOCK_GLASS,
			BlockRegistry.BLOCK_TORCH, BlockRegistry.BLOCK_CORAL_SUBSTRATE],
		"sand": [BlockRegistry.BLOCK_SAND, BlockRegistry.BLOCK_RED_SAND],
		"snow": [BlockRegistry.BLOCK_SNOW],
		"gravel": [BlockRegistry.BLOCK_GRAVEL],
		"wood": [BlockRegistry.BLOCK_LOG, BlockRegistry.BLOCK_BIRCH_LOG, BlockRegistry.BLOCK_SPRUCE_LOG,
			BlockRegistry.BLOCK_JUNGLE_LOG, BlockRegistry.BLOCK_ACACIA_LOG, BlockRegistry.BLOCK_MANGROVE_LOG,
			BlockRegistry.BLOCK_MANGROVE_ROOTS, BlockRegistry.BLOCK_BAMBOO, BlockRegistry.BLOCK_CACTUS],
		"water": [BlockRegistry.BLOCK_WATER],
	}
	for material in groups.keys():
		for block_id in groups[material]:
			_block_materials[block_id] = material
	for level in range(BlockRegistry.BLOCK_WATER_FLOW_7, BlockRegistry.BLOCK_WATER_FLOW_1 + 1):
		_block_materials[level] = "water"


func material_for_block(block_id: int) -> String:
	return _block_materials.get(block_id, "stone")


func play_footstep(material: String, world_position: Vector3) -> void:
	var stream := _variation("footstep_%s" % material, FOOTSTEP_VARIATIONS)
	if stream == null:
		return
	_play_3d(stream, world_position, _rng.randf_range(0.97, 1.03), FOOTSTEP_DB)


## Breaking and placing use one subtle cue for every block type. The block id
## is accepted only so call sites keep the material context for future use.
func play_block_break(_block_id: int, world_position: Vector3) -> void:
	var stream := _variation("block_break", BREAK_VARIATIONS)
	if stream == null:
		return
	_play_3d(stream, world_position, _rng.randf_range(0.97, 1.01), BREAK_DB)


func play_block_place(_block_id: int, world_position: Vector3) -> void:
	var stream := _variation("block_place", PLACE_VARIATIONS)
	if stream == null:
		return
	_play_3d(stream, world_position, _rng.randf_range(1.03, 1.07), PLACE_DB)


func play_ui(kind: String) -> void:
	var safe_kind := kind if kind in UI_SOUNDS else "click"
	var stream := _get_stream("%s/ui_%s.ogg" % [SFX_DIR, safe_kind])
	if stream == null:
		return
	_play_in_pool(_ui_pool, stream, 0.0)


## Fades the rain bed in or out.
func set_rain(active: bool) -> void:
	_set_bed("rain", active, RAIN_DB)


## Fades the cold-biome wind bed in or out. Snow and highlands share it; the
## caller decides when the camera has entered or left a cold biome.
func set_wind(active: bool) -> void:
	_set_bed("wind", active, WIND_DB)


## One-shot thunder clap for a lightning strike. Played non-positionally on the
## Ambient bus with a small random pitch so repeated strikes do not phase.
func play_thunder(volume_scale: float = 1.0) -> void:
	if _thunder_player == null or not is_inside_tree():
		return
	var stream := _get_stream("%s/%s" % [AMBIENT_DIR, THUNDER_STREAM])
	if stream == null:
		return
	_thunder_player.stream = stream
	_thunder_player.pitch_scale = _rng.randf_range(0.92, 1.06)
	_thunder_player.volume_db = THUNDER_DB + linear_to_db(clampf(volume_scale, 0.05, 1.0))
	_thunder_player.play()


## Generic looping weather bed: loads the recorded OGG, starts it silent on
## first use, then tweens to the target volume (or silence when inactive).
func _set_bed(bed: String, active: bool, active_db: float) -> void:
	if not AMBIENT_BEDS.has(bed) or not is_inside_tree():
		return
	var player: AudioStreamPlayer = _bed_players.get(bed)
	if player == null:
		return
	var stream := _get_stream("%s/%s" % [AMBIENT_DIR, AMBIENT_BEDS[bed]])
	if stream == null:
		return
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	player.stream = stream
	if not player.playing:
		player.volume_db = SILENT_DB
		player.play()
	var tween: Tween = _bed_tweens.get(bed)
	if tween != null and tween.is_valid():
		tween.kill()
	tween = create_tween()
	_bed_tweens[bed] = tween
	tween.tween_property(player, "volume_db", active_db if active else SILENT_DB, 1.5)


## Muffles the mix while the camera is submerged and restores it on surfacing.
## The filter is created lazily so headless verification never touches the bus.
func set_underwater(active: bool) -> void:
	if active == _underwater_active:
		return
	_underwater_active = active
	if _underwater_filter == null:
		var master := AudioServer.get_bus_index(BUS_MASTER)
		if master == -1:
			return
		_underwater_filter = AudioEffectLowPassFilter.new()
		_underwater_filter.cutoff_hz = SURFACE_CUTOFF_HZ
		AudioServer.add_bus_effect(master, _underwater_filter)
	_underwater_filter.cutoff_hz = UNDERWATER_CUTOFF_HZ if active else SURFACE_CUTOFF_HZ


func is_underwater() -> bool:
	return _underwater_active


func apply_volumes() -> void:
	if not is_inside_tree():
		return
	var config: Variant = get_node_or_null("/root/GameConfig")
	if config == null:
		return
	_set_bus_volume(BUS_MASTER, config.get_audio_volume("master_volume"))
	_set_bus_volume(BUS_SFX, config.get_audio_volume("sfx_volume"))
	_set_bus_volume(BUS_AMBIENT, config.get_audio_volume("ambient_volume"))


func _ensure_buses() -> void:
	for bus_name in [BUS_SFX, BUS_AMBIENT]:
		if AudioServer.get_bus_index(bus_name) != -1:
			continue
		var index := AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, BUS_MASTER)


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index == -1:
		return
	AudioServer.set_bus_volume_db(index, SILENT_DB if linear <= 0.001 else linear_to_db(linear))


func _build_pools() -> void:
	for index in SFX_POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = BUS_SFX
		add_child(player)
		_sfx_pool.append(player)
	for index in UI_POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = BUS_SFX
		add_child(player)
		_ui_pool.append(player)
	for bed in AMBIENT_BEDS.keys():
		var player := AudioStreamPlayer.new()
		player.name = "Bed_%s" % bed
		player.bus = BUS_AMBIENT
		player.volume_db = SILENT_DB
		add_child(player)
		_bed_players[bed] = player
	_thunder_player = AudioStreamPlayer.new()
	_thunder_player.name = "Thunder"
	_thunder_player.bus = BUS_AMBIENT
	_thunder_player.volume_db = SILENT_DB
	add_child(_thunder_player)


func _variation(prefix: String, variations: int) -> AudioStream:
	return _get_stream("%s/%s_%d.ogg" % [SFX_DIR, prefix, _rng.randi_range(1, variations)])


func _play_in_pool(pool: Array[AudioStreamPlayer], stream: AudioStream, volume_db: float) -> void:
	if pool.is_empty():
		return
	var player := pool[_pool_cursor % pool.size()]
	_pool_cursor += 1
	player.stream = stream
	player.volume_db = volume_db
	player.play()


## Reuses a small pool attached to the root viewport world instead of spawning
## a node per cue: node creation showed up as a delay on the first footstep or
## block action after a quiet moment.
func _play_3d(stream: AudioStream, world_position: Vector3, pitch: float, volume_db: float) -> void:
	if not is_inside_tree():
		return
	if _world_pool.is_empty():
		_build_world_pool()
	var player: AudioStreamPlayer3D = null
	for candidate in _world_pool:
		if not candidate.playing:
			player = candidate
			break
	if player == null:
		player = _world_pool[_pool_cursor % _world_pool.size()]
		_pool_cursor += 1
	player.stream = stream
	player.pitch_scale = pitch
	player.volume_db = volume_db
	player.global_position = world_position
	player.play()


func _build_world_pool() -> void:
	for index in WORLD_POOL_SIZE:
		var player := AudioStreamPlayer3D.new()
		player.bus = BUS_SFX
		player.max_distance = 48.0
		player.unit_size = 6.0
		# Root viewport keeps the pool alive across scene changes and shares
		# the same World3D as the gameplay scene.
		get_tree().root.add_child(player)
		_world_pool.append(player)


func _get_stream(path: String) -> AudioStream:
	if _streams.has(path):
		return _streams[path]
	if not ResourceLoader.exists(path):
		if not _missing.has(path):
			_missing[path] = true
			push_warning("AudioManager: missing sound %s; playing silence" % path)
		_streams[path] = null
		return null
	var stream := load(path) as AudioStream
	_streams[path] = stream
	return stream
