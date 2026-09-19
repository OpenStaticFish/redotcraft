## Phase timings for the real full-detail population stages, in production order.
## Every profiled result is compared with populate() to detect harness drift.
extends SceneTree

const POSITIONS: Array[Vector2i] = [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-4, 7),
	Vector2i(20, -12), Vector2i(-96, 80), Vector2i(120, -100)]
const REPEATS := 3
# Captured before footprint pruning and noise short-circuiting. Never regenerate
# these from the result being checked: deterministic output alone is insufficient.
const EXPECTED := {
	123456789: [
		"8a6181c55f7a1cc1e841a8352418c86e45dfc1627d2e70bd57b8f3858dd1f4e8",
		"f7f52098c7e95520fd627ccde4a599037bfaf58a2cc602b3c009adaa67687956",
		"46ff76c7ccaf6b2ffc4e0953fac90beec66339e622784528275f1c4f8578c8bd",
		"ebdc6300e0b3cb154d7d52793eafeb3467f7e0e7428a19a4fa031dcde2216575",
		"99c29703e33abcd1f3b2f19e06ff42ad68dc897ab1ce3a8e2b98fc2f8474624e",
		"d48ab91027b6915fb13e0d26fe950b16ffc86a8193bbfc0621a38492eab8ffe8",
	],
	918273: [
		"6980d141fb22dd70d2e83ca696a83f6d830e04cc85cbaef1335e91b7514803ee",
		"65f3a4f8567e0f9f1c827585a248c6e9561b0710b9d5a1759dcec9b18823c356",
		"4127b32d9ed2e6a0ab335cccae4ea0bf95cd46e9a4f2d978bff46e091c3e7fdb",
		"52a3320419a5d15d1369c68febde6fb9cc879015d124bd018656f6ca04e475d3",
		"75af8591fc3a1798ce66665dfe176e4d9605ed1990ca8068599d7d428e7e4316",
		"b3773199f962948f3ffae9f7f2e0f50490e74f50a69c7c3a479a1f688ea0be5f",
	],
}


func _initialize() -> void:
	var totals := {}
	var count := 0
	var failed := false
	var baseline_script: GDScript
	var baseline_usec := 0
	var current_usec := 0
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with("--compare-ref="):
			continue
		var output: Array = []
		var revision := argument.trim_prefix("--compare-ref=")
		if OS.execute("git", ["-C", ProjectSettings.globalize_path("res://"), "show",
				revision + ":world/worldgen/voxel_populator.gd"], output) != 0:
			push_error("Could not read local population baseline")
			quit(1)
			return
		baseline_script = GDScript.new()
		baseline_script.source_code = String(output[0]).replace("class_name VoxelPopulator", "")
		if baseline_script.reload() != OK:
			quit(1)
			return
	for seed_value in [123456789, 918273]:
		var generator := TerrainGenerator.new()
		generator.configure({"seed": seed_value, "worldgen_version": 14})
		var pop: VoxelPopulator = generator._populator
		var baseline: RefCounted = baseline_script.new(generator._config, generator._biomes, generator._sampler) \
			if baseline_script != null else null
		for position in POSITIONS:
			var field := generator._sampler.build_field(position)
			var reference := pop.populate(position, field, {})
			for iteration in REPEATS:
				if baseline != null:
					var started := Time.get_ticks_usec()
					var old_result: Dictionary = baseline.populate(position, field, {})
					baseline_usec += Time.get_ticks_usec() - started
					started = Time.get_ticks_usec()
					var current_result := pop.populate(position, field, {})
					current_usec += Time.get_ticks_usec() - started
					if old_result != current_result:
						push_error("Population differs from local baseline: %s" % position)
						failed = true
				var result := _profile(pop, position, field, totals)
				if result != reference:
					push_error("Profiled population differs from production: %s" % position)
					failed = true
				count += 1
			var hashing := HashingContext.new()
			hashing.start(HashingContext.HASH_SHA256)
			hashing.update(var_to_bytes([reference.data, reference.max_y]))
			var digest := hashing.finish().hex_encode()
			if digest != EXPECTED[seed_value][POSITIONS.find(position)]:
				push_error("Population changed from baseline: seed=%d chunk=%s" % [seed_value, position])
				failed = true
			print("POPULATION FIXTURE seed=%d chunk=%s biome=%d hash=%s" % [seed_value,
				position, field.dominant_biome[ChunkTerrainData.cell_index(8, 8)], digest])
	var total := 0.0
	for phase in totals:
		var milliseconds := float(totals[phase]) / (1000.0 * count)
		total += milliseconds
		print("POPULATION PHASE %s %.3f ms" % [phase, milliseconds])
	print("POPULATION AVERAGE %.3f ms (%d samples)" % [total, count])
	if baseline_script != null:
		print("POPULATION PAIRED old=%.3f ms current=%.3f ms speedup=%.2fx" % [
			float(baseline_usec) / (1000.0 * count), float(current_usec) / (1000.0 * count),
			float(baseline_usec) / maxi(current_usec, 1)])
	quit(1 if failed else 0)


func _profile(pop: VoxelPopulator, pos: Vector2i, field: ChunkTerrainData, totals: Dictionary) -> Dictionary:
	var data := PackedByteArray()
	data.resize(VoxelDefs.CHUNK_AREA * VoxelDefs.WORLD_HEIGHT)
	var x := pos.x * VoxelDefs.CHUNK_SIZE
	var z := pos.y * VoxelDefs.CHUNK_SIZE
	var max_y: int = _measure("base/surface", pop._fill_base_and_surface.bind(data, field), totals)
	_measure("floor patches", pop._decorate_floor_patches.bind(data, field, x, z), totals)
	_measure("noise caves", pop._carve_noise_caves.bind(data, field, x, z), totals)
	_measure("cave network", pop._carve_cave_network.bind(data, field, x, z), totals)
	_measure("entrances", pop._carve_cave_entrances.bind(data, field, x, z), totals)
	_measure("caverns", pop._carve_caverns.bind(data, field, x, z), totals)
	_measure("liquids", pop._fill_underground_liquids.bind(data, field, x, z), totals)
	_measure("ores", pop._place_ore_veins.bind(data, x, z), totals)
	_measure("geodes", pop._place_geodes.bind(data, field, x, z), totals)
	_measure("cave decoration", pop._decorate_caves.bind(data, field, x, z), totals)
	var scratch := VoxelPopulator.DecorationGroundScratch.new()
	max_y = _measure("surface decoration", pop._decorate.bind(data, field, x, z, max_y, scratch), totals)
	max_y = _measure("underwater decoration", pop._decorate_underwater.bind(data, field, x, z, max_y, scratch), totals)
	max_y = maxi(max_y, _measure("structures", pop._place_region_structures.bind(data, field, x, z), totals))
	max_y = _measure("edits", pop._apply_edits.bind(data, {}, x, z, max_y), totals)
	max_y = _measure("max height", pop._actual_max_y.bind(data, max_y), totals)
	return {"data": data, "max_y": max_y}


func _measure(phase: String, operation: Callable, totals: Dictionary) -> Variant:
	var started := Time.get_ticks_usec()
	var result: Variant = operation.call()
	totals[phase] = int(totals.get(phase, 0)) + Time.get_ticks_usec() - started
	return result
