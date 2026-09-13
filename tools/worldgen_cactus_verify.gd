extends SceneTree


func _initialize() -> void:
	var blocks := BlockRegistry.new()
	var failed := false
	for texture_name in ["cactus_side.png", "cactus_top.png"]:
		var source := blocks._load_image(BlockRegistry.TEXTURE_ROOT + texture_name)
		var image := blocks._prepare_solid_texture(source, texture_name)
		image.resize(BlockRegistry.TILE_PX, BlockRegistry.TILE_PX, Image.INTERPOLATE_NEAREST)
		for y in image.get_height():
			for x in image.get_width():
				if image.get_pixel(x, y).a < 0.99:
					push_error("Transparent pixel in solid cactus face: %s (%d, %d)" % [texture_name, x, y])
					failed = true
	var data := PackedByteArray()
	data.resize(VoxelDefs.CHUNK_AREA * VoxelDefs.WORLD_HEIGHT)
	var heights := PackedInt32Array()
	heights.resize(VoxelDefs.CHUNK_AREA)
	for y in range(10, 13):
		data[8 + 8 * VoxelDefs.DATA_STRIDE_Z + y * VoxelDefs.DATA_STRIDE_Y] = BlockRegistry.BLOCK_CACTUS
	heights[8 + 8 * VoxelDefs.DATA_STRIDE_Z] = 12
	var mesher := ChunkMesher.new(blocks)
	var result := mesher.build(data, 12, heights, PackedColorArray(), PackedColorArray(), ChunkMesher.NeighborSet.new())
	# Twelve side quads and two end caps; internal stacked faces are culled.
	if result.indices.size() != 14 * 6 or result.collision.size() != 14 * 6:
		push_error("Cactus column must have a closed, collidable exterior")
		failed = true
	print("WORLDGEN CACTUS VERIFY: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
