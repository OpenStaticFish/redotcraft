## Headless check for the sound bank, mixer buses, material mapping, and the
## playback entry points. Run:
##   redot --headless --path . --script res://tools/audio_verify.gd
extends SceneTree

const AudioManagerScript = preload("res://autoload/audio_manager.gd")

var _failures := 0


## Runs on the first real frame: a SceneTree script's _initialize can run
## before the root window is active, which would leave added nodes out of tree.
func _initialize() -> void:
	process_frame.connect(_verify, CONNECT_ONE_SHOT)


func _verify() -> void:
	var manager := AudioManagerScript.new()
	manager.name = "AudioManager"
	get_root().add_child(manager)

	for bus_name in ["Master", "SFX", "Ambient"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			_fail("missing audio bus %s" % bus_name)

	for base in _expected_bases():
		var path := base + ".ogg"
		if not ResourceLoader.exists(path):
			_fail("missing sound %s" % path)
			continue
		if not load(path) is AudioStream:
			_fail("sound did not import as AudioStream: %s" % path)
		if ResourceLoader.exists(base + ".wav"):
			_fail("synthesized placeholder still present: %s.wav" % base)

	_expect_material(manager, BlockRegistry.BLOCK_GRASS, "grass")
	_expect_material(manager, BlockRegistry.BLOCK_LEAVES, "grass")
	_expect_material(manager, BlockRegistry.BLOCK_DIRT, "dirt")
	_expect_material(manager, BlockRegistry.BLOCK_COBBLESTONE, "stone")
	_expect_material(manager, BlockRegistry.BLOCK_SAND, "sand")
	_expect_material(manager, BlockRegistry.BLOCK_SNOW, "snow")
	_expect_material(manager, BlockRegistry.BLOCK_GRAVEL, "gravel")
	_expect_material(manager, BlockRegistry.BLOCK_JUNGLE_LOG, "wood")
	_expect_material(manager, BlockRegistry.BLOCK_WATER, "water")
	_expect_material(manager, BlockRegistry.BLOCK_WATER_FLOW_3, "water")

	manager.play_footstep("stone", Vector3.ZERO)
	manager.play_block_break(BlockRegistry.BLOCK_LOG, Vector3.ZERO)
	manager.play_block_place(BlockRegistry.BLOCK_SAND, Vector3.ZERO)
	manager.play_ui("click")
	manager.play_ui("not_a_cue")
	manager.play_footstep("water", Vector3.ZERO)
	manager.set_rain(true)
	manager.set_wind(true)
	manager.play_thunder()
	manager.apply_volumes()
	for tween in manager._bed_tweens.values():
		if tween != null and tween.is_valid():
			tween.kill()

	for child in get_root().get_children():
		if child is AudioStreamPlayer3D:
			child.free()
	manager.free()
	if _failures == 0:
		print("AUDIO VERIFY: PASS")
		quit(0)
		return
	print("AUDIO VERIFY: FAIL (%d)" % _failures)
	quit(1)


## Cue bases without an extension. Every cue is a recorded CC0 OGG; the WAV
## check at the end of the loop keeps synthesized placeholders out for good.
func _expected_bases() -> Array[String]:
	var bases: Array[String] = []
	var materials := ["grass", "dirt", "stone", "sand", "snow", "gravel", "wood", "water"]
	for material in materials:
		for variation in 3:
			bases.append("res://assets/audio/sfx/footstep_%s_%d" % [material, variation + 1])
	for variation in 2:
		bases.append("res://assets/audio/sfx/block_break_%d" % (variation + 1))
		bases.append("res://assets/audio/sfx/block_place_%d" % (variation + 1))
	for kind in ["click", "hover", "confirm", "cancel"]:
		bases.append("res://assets/audio/sfx/ui_%s" % kind)
	bases.append("res://assets/audio/ambient/rain_loop")
	bases.append("res://assets/audio/ambient/wind_loop")
	bases.append("res://assets/audio/ambient/thunder_1")
	return bases


func _expect_material(manager: Node, block_id: int, material: String) -> void:
	var actual: String = manager.material_for_block(block_id)
	if actual != material:
		_fail("block %d mapped to %s instead of %s" % [block_id, actual, material])


func _fail(message: String) -> void:
	_failures += 1
	push_error("audio_verify: %s" % message)
