extends SceneTree


func _initialize() -> void:
	var generator := TerrainGenerator.new()
	generator.configure({
		"seed": 123456789,
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
	})
	var positions: Array[Vector2i] = [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-4, 7), Vector2i(20, -12)]
	var total_full := 0.0
	var total_lod := 0.0
	for position in positions:
		var start := Time.get_ticks_usec()
		var full := generator.generate_data(position, {}, false)
		var full_ms := float(Time.get_ticks_usec() - start) / 1000.0
		total_full += full_ms
		start = Time.get_ticks_usec()
		var lod := generator.generate_data(position, {}, true)
		var lod_ms := float(Time.get_ticks_usec() - start) / 1000.0
		total_lod += lod_ms
		var repeat := generator.generate_data(position, {}, false)
		print("CHUNK ", position, " full_ms=", full_ms, " lod_ms=", lod_ms,
			" max_y=", full.max_y, " deterministic=", full.data == repeat.data,
			" heights=", full.heights == repeat.heights)
	print("AVERAGE full_ms=", total_full / positions.size(), " lod_ms=", total_lod / positions.size())
	quit()
