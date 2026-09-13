extends SceneTree


func _initialize() -> void:
	var generator := TerrainGenerator.new()
	generator.configure({"seed": 123456789, "world_type": 0, "terrain_scale": 1.0, "tree_density": 1.0, "macro_scale": 384.0, "river_density": 1.0, "erosion_strength": 0.55, "regional_erosion": 0.5, "hydraulic_erosion": false, "cave_density": 1.0, "decoration_density": 1.0})
	var blocks := BlockRegistry.new()
	var mesher := ChunkMesher.new(blocks)
	var positions: Array[Vector2i] = [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-4, 7), Vector2i(20, -12)]
	var full_total := 0.0
	var lod_total := 0.0
	for position in positions:
		var full := generator.generate_data(position, {}, false)
		var start := Time.get_ticks_usec()
		var mesh := mesher.build(full.data, full.max_y, full.heights, full.foliage_tints, full.water_tints, ChunkMesher.NeighborSet.new())
		var full_ms := float(Time.get_ticks_usec() - start) / 1000.0
		var lod := generator.generate_data(position, {}, true)
		start = Time.get_ticks_usec()
		var lod_mesh := mesher.build_lod(lod.lod_solid_y, lod.lod_solid_id, lod.lod_sub_id, lod.lod_water_y, lod.lod_water_level, lod.max_y, lod.foliage_tints, lod.water_tints, ChunkMesher.LodNeighbors.new())
		var lod_ms := float(Time.get_ticks_usec() - start) / 1000.0
		full_total += full_ms
		lod_total += lod_ms
		print(position, " max=", full.max_y, " full_mesh_ms=", full_ms, " tris=", mesh.indices.size() / 3, " lod_mesh_ms=", lod_ms, " lod_tris=", lod_mesh.indices.size() / 3)
	print("MESH AVERAGE full=", full_total / positions.size(), " lod=", lod_total / positions.size())
	quit()
