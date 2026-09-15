extends SceneTree

## Repeatable phase benchmark for chunk workers and detached main-thread mesh
## resources. It reports full-detail and compact-LOD latency,
## throughput, generation phase costs, mesh cost, and ArrayMesh/shape commit
## cost. Keep the seed, positions, and collision policy pinned so before/after
## runs are comparable.

const SEED := 123456789
const RADIUS := 2
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
	var blocks := BlockRegistry.new()
	var generator := TerrainGenerator.new()
	generator.configure(CONFIG)
	var mesher := ChunkMesher.new(blocks)
	var positions := _positions()
	var concurrency := clampi(OS.get_processor_count() / 2, 4, 8)
	_warm_up(generator, mesher, blocks)
	print("CHUNK LOAD BENCH seed=", SEED, " chunks=", positions.size(),
		" concurrency=", concurrency)
	_run_mode("full", false, generator, mesher, blocks, positions, concurrency)
	_run_mode("lod", true, generator, mesher, blocks, positions, concurrency)
	quit()


func _warm_up(generator: TerrainGenerator, mesher: ChunkMesher, blocks: BlockRegistry) -> void:
	var generated := generator.generate_data(Vector2i(3, 3), {}, false)
	var result := mesher.build(generated.data, generated.max_y, generated.heights,
		generated.foliage_tints, generated.water_tints, ChunkMesher.NeighborSet.new(), true)
	_warm_resources(result, blocks)
	generated = generator.generate_data(Vector2i(4, 3), {}, true)
	result = mesher.build_lod(generated.lod_solid_y, generated.lod_solid_id, generated.lod_sub_id,
		generated.lod_water_y, generated.lod_water_level, generated.max_y,
		generated.foliage_tints, generated.water_tints, ChunkMesher.LodNeighbors.new())
	_warm_resources(result, blocks)


func _warm_resources(result: ChunkMesher.MeshResult, blocks: BlockRegistry) -> void:
	ChunkMesher.arrays_to_mesh(result.verts, result.normals, result.uvs, result.colors,
		result.indices, blocks.material, result.light, result.layers)
	ChunkMesher.arrays_to_mesh(result.water_verts, result.water_normals, result.water_uvs,
		result.water_colors, result.water_indices, blocks.water_material, result.water_light)
	if not result.collision.is_empty():
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(result.collision)


func _positions() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for z in range(-RADIUS, RADIUS + 1):
		for x in range(-RADIUS, RADIUS + 1):
			out.append(Vector2i(x, z))
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.length_squared() < b.length_squared()
	)
	return out


func _run_mode(label: String, lod: bool, generator: TerrainGenerator, mesher: ChunkMesher,
		blocks: BlockRegistry, positions: Array[Vector2i], concurrency: int) -> void:
	var start := Time.get_ticks_usec()
	var next_position := 0
	var tasks: Array[Dictionary] = []
	var completed: Array[Dictionary] = []
	while next_position < positions.size() or not tasks.is_empty():
		while tasks.size() < concurrency and next_position < positions.size():
			var slot: Dictionary = {}
			var pos := positions[next_position]
			next_position += 1
			var task := WorkerThreadPool.add_task(
				_job.bind(generator, mesher, pos, lod, slot), true, "chunk_load_bench")
			tasks.append({"task": task, "slot": slot})
		var found := false
		for index in range(tasks.size() - 1, -1, -1):
			var entry: Dictionary = tasks[index]
			if not WorkerThreadPool.is_task_completed(int(entry["task"])):
				continue
			WorkerThreadPool.wait_for_task_completion(int(entry["task"]))
			completed.append(entry["slot"])
			tasks.remove_at(index)
			found = true
		if not found:
			OS.delay_usec(200)
	var worker_wall_us := Time.get_ticks_usec() - start
	var commit_start := Time.get_ticks_usec()
	var triangles := 0
	for slot in completed:
		var result: ChunkMesher.MeshResult = slot["result"]
		var mesh := ChunkMesher.arrays_to_mesh(result.verts, result.normals, result.uvs,
			result.colors, result.indices, blocks.material, result.light, result.layers)
		var water := ChunkMesher.arrays_to_mesh(result.water_verts, result.water_normals,
			result.water_uvs, result.water_colors, result.water_indices, blocks.water_material,
			result.water_light)
		var shape: ConcavePolygonShape3D = null
		if not result.collision.is_empty():
			shape = ConcavePolygonShape3D.new()
			shape.set_faces(result.collision)
		triangles += result.indices.size() / 3 + result.water_indices.size() / 3
		# Keep resources alive through the measured call.
		slot["mesh"] = mesh
		slot["water"] = water
		slot["shape"] = shape
	var commit_us := Time.get_ticks_usec() - commit_start
	var terrain_us := 0
	var populate_us := 0
	var heightmap_us := 0
	var generation_us := 0
	var mesh_us := 0
	for slot in completed:
		var timings: Dictionary = slot["timings"]
		terrain_us += int(timings["terrain_us"])
		populate_us += int(timings["populate_us"])
		heightmap_us += int(timings["heightmap_us"])
		generation_us += int(timings["generation_us"])
		mesh_us += int(slot["mesh_us"])
	var count := float(completed.size())
	var wall_ms := float(worker_wall_us) / 1000.0
	print(label.to_upper(), " wall_ms=", snappedf(wall_ms, 0.01),
		" chunks/s=", snappedf(count * 1000.0 / wall_ms, 0.1),
		" avg_ms={terrain:", snappedf(float(terrain_us) / count / 1000.0, 0.01),
		", populate:", snappedf(float(populate_us) / count / 1000.0, 0.01),
		", heightmap:", snappedf(float(heightmap_us) / count / 1000.0, 0.01),
		", generation:", snappedf(float(generation_us) / count / 1000.0, 0.01),
		", mesh:", snappedf(float(mesh_us) / count / 1000.0, 0.01),
		", commit:", snappedf(float(commit_us) / count / 1000.0, 0.01),
		"} triangles/chunk=", roundi(float(triangles) / count))


func _job(generator: TerrainGenerator, mesher: ChunkMesher, pos: Vector2i, lod: bool,
		slot: Dictionary) -> void:
	var generated := generator.generate_data(pos, {}, lod)
	var mesh_start := Time.get_ticks_usec()
	if lod:
		slot["result"] = mesher.build_lod(generated.lod_solid_y, generated.lod_solid_id,
			generated.lod_sub_id, generated.lod_water_y, generated.lod_water_level,
			generated.max_y, generated.foliage_tints, generated.water_tints,
			ChunkMesher.LodNeighbors.new())
	else:
		slot["result"] = mesher.build(generated.data, generated.max_y, generated.heights,
			generated.foliage_tints, generated.water_tints, ChunkMesher.NeighborSet.new(), true)
	slot["timings"] = generated.timings
	slot["mesh_us"] = Time.get_ticks_usec() - mesh_start
