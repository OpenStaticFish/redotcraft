extends SceneTree

## Simulates the initial chunk-ring load for a pinned world and prints the wall
## time at several job-concurrency levels. Use it to size MAX_ACTIVE_JOBS and to
## check that render-distance increases stay streamable. Mesh results are
## discarded immediately so peak memory stays bounded.


const SEED := 123456789
const CONFIG := {
	"seed": SEED,
	"world_type": 0,
	"terrain_scale": 1.0,
	"tree_density": 1.0,
	"macro_scale": 384.0,
	"river_density": 1.0,
	"erosion_strength": 0.55,
	"regional_erosion": 0.5,
	"hydraulic_erosion": false,
	"cave_density": 1.0,
	"decoration_density": 1.0,
}


func _initialize() -> void:
	var generator := TerrainGenerator.new()
	generator.configure(CONFIG)
	var mesher := ChunkMesher.new(BlockRegistry.new())
	print("STREAM BENCH seed=", SEED, " workers=", OS.get_processor_count())
	_breakdown(generator, mesher)
	for render_distance in [10, 16, 32]:
		var lod_distance := render_distance
		var positions := _ring(render_distance)
		var full := 0
		for pos in positions:
			if maxi(absi(pos.x), absi(pos.y)) <= lod_distance:
				full += 1
		print("---- render_distance=", render_distance, " chunks=", positions.size(),
			" full=", full, " lod=", positions.size() - full)
		for concurrency in [4, 8, 16]:
			var start := Time.get_ticks_usec()
			_run_batch(generator, mesher, positions, lod_distance, concurrency)
			var wall_ms := float(Time.get_ticks_usec() - start) / 1000.0
			print("  concurrency=", concurrency, " wall_ms=", wall_ms,
				" chunks/s=", snappedf(float(positions.size()) * 1000.0 / wall_ms, 0.1))
	quit()


func _breakdown(generator: TerrainGenerator, mesher: ChunkMesher) -> void:
	var sample: Array[Vector2i] = [Vector2i.ZERO, Vector2i(8, -5)]
	var field_total := 0.0
	var populate_total := 0.0
	var heights_total := 0.0
	var lod_populate_total := 0.0
	var lod_heights_total := 0.0
	var lod_mesh_total := 0.0
	for pos in sample:
		var start := Time.get_ticks_usec()
		var field: ChunkTerrainData = generator._sampler.build_field(pos)
		field_total += float(Time.get_ticks_usec() - start) / 1000.0
		start = Time.get_ticks_usec()
		var populated: Dictionary = generator._populator.populate(pos, field, {}, true)
		populate_total += float(Time.get_ticks_usec() - start) / 1000.0
		start = Time.get_ticks_usec()
		generator._build_heights(populated["data"], populated["max_y"])
		heights_total += float(Time.get_ticks_usec() - start) / 1000.0
		var lod := generator.generate_data(pos, {}, true)
		lod_populate_total += float(lod.timings["populate_us"]) / 1000.0
		lod_heights_total += float(lod.timings["heightmap_us"]) / 1000.0
		start = Time.get_ticks_usec()
		mesher.build_lod(lod.lod_solid_y, lod.lod_solid_id, lod.lod_sub_id, lod.lod_water_y, lod.lod_water_level, lod.max_y, lod.foliage_tints, lod.water_tints, ChunkMesher.LodNeighbors.new())
		lod_mesh_total += float(Time.get_ticks_usec() - start) / 1000.0
	var count := float(sample.size())
	print("BREAKDOWN avg field_ms=", field_total / count,
		" populate_full_ms=", populate_total / count,
		" heights_ms=", heights_total / count,
		" lod_populate_ms=", lod_populate_total / count,
		" lod_heights_ms=", lod_heights_total / count,
		" lod_mesh_ms=", lod_mesh_total / count)


func _ring(render_distance: int) -> Array[Vector2i]:
	var positions: Array[Vector2i] = []
	for dx in range(-render_distance, render_distance + 1):
		for dz in range(-render_distance, render_distance + 1):
			positions.append(Vector2i(dx, dz))
	positions.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.length_squared() < b.length_squared()
	)
	return positions


func _run_batch(generator: TerrainGenerator, mesher: ChunkMesher, positions: Array[Vector2i], lod_distance: int, concurrency: int) -> void:
	var in_flight: Array[int] = []
	var index := 0
	while index < positions.size() or not in_flight.is_empty():
		while in_flight.size() < concurrency and index < positions.size():
			var pos: Vector2i = positions[index]
			index += 1
			var lod := maxi(absi(pos.x), absi(pos.y)) > lod_distance
			var slot: Dictionary = {}
			in_flight.append(WorkerThreadPool.add_task(
				_job.bind(generator, mesher, pos, lod, slot), true, "stream_bench"))
		var task: int = in_flight.pop_front()
		WorkerThreadPool.wait_for_task_completion(task)


func _job(generator: TerrainGenerator, mesher: ChunkMesher, pos: Vector2i, lod: bool, slot: Dictionary) -> void:
	var generated := generator.generate_data(pos, {}, lod)
	if lod:
		slot["result"] = mesher.build_lod(generated.lod_solid_y, generated.lod_solid_id, generated.lod_sub_id, generated.lod_water_y, generated.lod_water_level, generated.max_y, generated.foliage_tints, generated.water_tints, ChunkMesher.LodNeighbors.new())
	else:
		slot["result"] = mesher.build(generated.data, generated.max_y, generated.heights, generated.foliage_tints, generated.water_tints, ChunkMesher.NeighborSet.new())
