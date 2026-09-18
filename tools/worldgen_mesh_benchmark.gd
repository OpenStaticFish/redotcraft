extends SceneTree

const USEC_PER_MSEC: float = 1000.0


func _initialize() -> void:
	var generator := TerrainGenerator.new()
	generator.configure({"seed": 123456789, "world_type": 0, "terrain_scale": 1.0, "tree_density": 1.0, "macro_scale": 384.0, "river_density": 1.0, "erosion_strength": 0.55, "regional_erosion": 0.5, "hydraulic_erosion": false, "cave_density": 1.0, "decoration_density": 1.0})
	var blocks := BlockRegistry.new()
	var mesher := ChunkMesher.new(blocks)
	var positions: Array[Vector2i] = [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-4, 7), Vector2i(20, -12)]
	var full_total_ms: float = 0.0
	var lod_total_ms: float = 0.0
	var light_assembly_total_ms: float = 0.0
	var sky_light_total_ms: float = 0.0
	var block_light_total_ms: float = 0.0
	var padding_total_ms: float = 0.0
	var face_emit_total_ms: float = 0.0
	for position in positions:
		var full := generator.generate_data(position, {}, false)
		var start_us: int = Time.get_ticks_usec()
		var mesh := mesher.build(full.data, full.max_y, full.heights, full.foliage_tints, full.water_tints, ChunkMesher.NeighborSet.new())
		var full_ms: float = float(Time.get_ticks_usec() - start_us) / USEC_PER_MSEC
		var lod := generator.generate_data(position, {}, true)
		start_us = Time.get_ticks_usec()
		var lod_mesh := mesher.build_lod(lod.lod_solid_y, lod.lod_solid_id, lod.lod_sub_id, lod.lod_water_y, lod.lod_water_level, lod.max_y, lod.foliage_tints, lod.water_tints, ChunkMesher.LodNeighbors.new())
		var lod_ms: float = float(Time.get_ticks_usec() - start_us) / USEC_PER_MSEC
		full_total_ms += full_ms
		lod_total_ms += lod_ms
		light_assembly_total_ms += float(mesh.timings.light_assembly_us) / USEC_PER_MSEC
		sky_light_total_ms += float(mesh.timings.sky_light_us) / USEC_PER_MSEC
		block_light_total_ms += float(mesh.timings.block_light_us) / USEC_PER_MSEC
		padding_total_ms += float(mesh.timings.padding_us) / USEC_PER_MSEC
		face_emit_total_ms += float(mesh.timings.face_emit_us) / USEC_PER_MSEC
		print(position, " max=", full.max_y, " full_mesh_ms=", full_ms, " tris=", mesh.indices.size() / 3, " lod_mesh_ms=", lod_ms, " lod_tris=", lod_mesh.indices.size() / 3)
	var sample_count: float = float(positions.size())
	var full_average_ms: float = full_total_ms / sample_count
	var lod_average_ms: float = lod_total_ms / sample_count
	var light_assembly_average_ms: float = light_assembly_total_ms / sample_count
	var sky_light_average_ms: float = sky_light_total_ms / sample_count
	var block_light_average_ms: float = block_light_total_ms / sample_count
	var padding_average_ms: float = padding_total_ms / sample_count
	var face_emit_average_ms: float = face_emit_total_ms / sample_count
	print("MESH AVERAGE full=", full_average_ms, " lod=", lod_average_ms)
	print("MESH PHASE AVERAGES ms assembly=%.3f sky=%.3f block=%.3f padding=%.3f emit=%.3f" % [
		light_assembly_average_ms,
		sky_light_average_ms,
		block_light_average_ms,
		padding_average_ms,
		face_emit_average_ms,
	])
	print("BENCHMARK_MARKDOWN_BEGIN")
	print("### Worldgen mesh benchmark")
	print("")
	print("| Samples | Full mesh | Compact LOD mesh | Light assembly | Sky light | Block light | Padding | Face emission |")
	print("|---:|---:|---:|---:|---:|---:|---:|---:|")
	print("| %d | %.2f ms | %.2f ms | %.2f ms | %.2f ms | %.2f ms | %.2f ms | %.2f ms |" % [
		positions.size(), full_average_ms, lod_average_ms, light_assembly_average_ms,
		sky_light_average_ms, block_light_average_ms, padding_average_ms,
		face_emit_average_ms,
	])
	print("BENCHMARK_MARKDOWN_END")
	quit()
