## Headless regression check for deterministic tree stamping and chunk borders.
extends SceneTree

const VoxelPopulatorScript = preload("res://world/worldgen/voxel_populator.gd")
const WorldGenConfigScript = preload("res://world/worldgen/world_gen_config.gd")
const BiomeCatalogScript = preload("res://world/worldgen/biome_catalog.gd")
const ChunkTerrainDataScript = preload("res://world/worldgen/chunk_terrain_data.gd")
const BlockRegistryScript = preload("res://world/block_registry.gd")
const VoxelDefsScript = preload("res://world/voxel_defs.gd")

var failed := false


func _init() -> void:
	var populator := VoxelPopulatorScript.new(WorldGenConfigScript.new({"seed": 918273}), BiomeCatalogScript.new())
	const ground_y := 40
	const trunk_height := 8
	const hash_value := 123456789
	var edge_blocks := _stamp_tree_chunks(populator, Vector2i(32, 32), ground_y, trunk_height, hash_value)
	var repeated_blocks := _stamp_tree_chunks(populator, Vector2i(32, 32), ground_y, trunk_height, hash_value)
	var centered_blocks := _stamp_tree_chunks(populator, Vector2i(56, 56), ground_y, trunk_height, hash_value)

	_check(_same_blocks(edge_blocks, repeated_blocks), "spruce stamping must be repeatable")
	_check(_same_blocks(_translated(centered_blocks, Vector3i(-24, 0, -24)), edge_blocks), "edge-stamped spruce must match translated in-chunk geometry")
	_check(edge_blocks.get(Vector3i(32, ground_y + 1, 32), -1) == BlockRegistryScript.BLOCK_SPRUCE_LOG, "spruce must retain an exposed lower trunk")
	_check(edge_blocks.get(Vector3i(32, ground_y + 2, 32), -1) == BlockRegistryScript.BLOCK_SPRUCE_LOG, "spruce must retain a second exposed trunk block")
	_check(_leaf_reach(edge_blocks, Vector2i(32, 32), ground_y + 3) == 3, "spruce lower whorl must reach radius three")
	_check(_leaf_reach(edge_blocks, Vector2i(32, 32), ground_y + 5) == 2, "spruce middle whorl must taper to radius two")
	_check(_leaf_reach(edge_blocks, Vector2i(32, 32), ground_y + 8) == 1, "spruce upper whorl must taper to radius one")
	_check(_leaf_reach(edge_blocks, Vector2i(32, 32), ground_y + 9) == 0, "spruce must finish in a centered leaf tip")
	for radius in [2, 3]:
		var crown_edge := _stamp_tree_chunks(populator, Vector2i(32, 32), ground_y, trunk_height, hash_value, radius)
		var crown_repeat := _stamp_tree_chunks(populator, Vector2i(32, 32), ground_y, trunk_height, hash_value, radius)
		var crown_center := _stamp_tree_chunks(populator, Vector2i(56, 56), ground_y, trunk_height, hash_value, radius)
		_check(_same_blocks(crown_edge, crown_repeat), "broadleaf stamping must be repeatable")
		_check(_same_blocks(_translated(crown_center, Vector3i(-24, 0, -24)), crown_edge), "broadleaf geometry must match across chunk borders")
		for position: Vector3i in crown_edge:
			_check(absi(position.x - 32) <= radius and absi(position.z - 32) <= radius, "broadleaf canopy/limbs exceeded the bounded footprint")
		_check(_all_connected(crown_edge), "broadleaf crown must not contain disconnected leaves or limb ends")
		_check(_leaf_reach_for(crown_edge, Vector2i(32, 32), ground_y + trunk_height - 1, BlockRegistryScript.BLOCK_LEAVES) == radius, "broadleaf crown must retain a full middle canopy tier")

	_verify_tree_ground_validation()
	_verify_grove_distribution()
	_verify_overlapping_border_candidates(populator)
	_benchmark_full_generation()

	if failed:
		quit(1)
		return
	print("worldgen_tree_verify: passed")
	quit(0)


func _stamp_tree_chunks(populator: VoxelPopulator, center: Vector2i, ground_y: int, trunk_height: int, hash_value: int, broadleaf_radius: int = 0) -> Dictionary:
	var blocks := {}
	for chunk_z in range(1, 5):
		for chunk_x in range(1, 5):
			var origin_x: int = chunk_x * VoxelDefsScript.CHUNK_SIZE
			var origin_z: int = chunk_z * VoxelDefsScript.CHUNK_SIZE
			var data := PackedByteArray()
			data.resize(VoxelDefsScript.CHUNK_AREA * VoxelDefsScript.WORLD_HEIGHT)
			if broadleaf_radius == 0:
				var highest: int = populator._stamp_spruce(data, origin_x, origin_z, center.x, ground_y, center.y, trunk_height, hash_value)
				_check(highest == ground_y + trunk_height + 1, "spruce max_y must include its leaf tip")
			else:
				var highest: int = populator._stamp_tree(data, origin_x, origin_z, center.x, ground_y, center.y, BlockRegistryScript.BLOCK_LOG, BlockRegistryScript.BLOCK_LEAVES, trunk_height, broadleaf_radius, hash_value)
				_check(highest == ground_y + trunk_height + 2, "broadleaf max_y must include its canopy tip")
			for y in range(VoxelDefsScript.WORLD_HEIGHT):
				for local_z in VoxelDefsScript.CHUNK_SIZE:
					for local_x in VoxelDefsScript.CHUNK_SIZE:
						var block_id: int = data[local_x + local_z * VoxelDefsScript.CHUNK_SIZE + y * VoxelDefsScript.CHUNK_AREA]
						if block_id != BlockRegistryScript.BLOCK_AIR:
							blocks[Vector3i(origin_x + local_x, y, origin_z + local_z)] = block_id
	return blocks


func _leaf_reach(blocks: Dictionary, center: Vector2i, y: int) -> int:
	return _leaf_reach_for(blocks, center, y, BlockRegistryScript.BLOCK_SPRUCE_LEAVES)


func _leaf_reach_for(blocks: Dictionary, center: Vector2i, y: int, leaf_id: int) -> int:
	var reach := -1
	for position in blocks:
		if position.y == y and blocks[position] == leaf_id:
			reach = maxi(reach, maxi(absi(position.x - center.x), absi(position.z - center.y)))
	return reach


func _verify_tree_ground_validation() -> void:
	var config := WorldGenConfigScript.new({"seed": 918273, "cave_density": 0.0})
	var populator := VoxelPopulatorScript.new(config, BiomeCatalogScript.new())
	var field := ChunkTerrainDataScript.new()
	const ground_y := 60
	for index in ChunkTerrainDataScript.CELL_COUNT:
		field.set_height(index, ground_y, ground_y, ground_y, 0.0)
		field.set_biome(index, BiomeCatalogScript.FOREST, BiomeCatalogScript.FOREST, 0, BiomeCatalogScript.FOREST)
	field.seal()
	_check(populator._tree_site_is_safe(field, {}, 8, ground_y, 8, 3, 10), "solid generated terrain must permit a tree root")
	# Entrance tunnels are the one cave operation permitted to touch a terrain
	# surface. The common immutable predicate, rather than owner-chunk voxel
	# state, must reject them for every canopy chunk.
	var cave_populator := VoxelPopulatorScript.new(WorldGenConfigScript.new({"seed": 918273, "cave_density": 4.0}), BiomeCatalogScript.new())
	var entrance_found := false
	var entrance_position := Vector2i.ZERO
	for z in range(-256, 257):
		for x in range(-256, 257):
			if cave_populator._tree_root_is_near_cave_entrance(x, z):
				entrance_found = true
				entrance_position = Vector2i(x, z)
				break
		if entrance_found:
			break
	_check(entrance_found, "surface-cave fixture must find an immutable entrance exclusion")
	_check(not cave_populator._tree_site_is_safe(field, {}, entrance_position.x, ground_y, entrance_position.y, 3, 10), "surface-cave roots must be excluded consistently before stamping")


func _verify_grove_distribution() -> void:
	var populator := VoxelPopulatorScript.new(WorldGenConfigScript.new({"seed": 918273}), BiomeCatalogScript.new())
	var dense_candidates := 0
	var clearing_candidates := 0
	var dense_trees := 0
	var clearing_trees := 0
	for cell_z in range(-24, 25):
		for cell_x in range(-24, 25):
			var anchor_hash: int = WorldGenHash.hash_2d(918273 + 1223, cell_x, cell_z)
			var world_x: int = cell_x * 6 + 2 + anchor_hash % 2
			var world_z: int = cell_z * 6 + 2 + (anchor_hash / 23) % 2
			var strength: float = populator._tree_grove_strength(world_x, world_z)
			var probability: float = populator._grove_tree_probability(BiomeCatalogScript.DECORATION_FOREST, strength)
			var accepted: bool = WorldGenHash.float_01_2d(918273 + 1237, cell_x, cell_z) < probability
			if strength >= 0.80:
				dense_candidates += 1
				if accepted:
					dense_trees += 1
			elif strength <= 0.01:
				clearing_candidates += 1
				if accepted:
					clearing_trees += 1
	_check(dense_candidates > 0 and clearing_candidates > 0, "grove field must provide both cluster interiors and clearings")
	_check(dense_trees > dense_candidates / 2, "forest grove interiors should be densely populated")
	_check(clearing_trees == 0, "forest grove clearings must stay open")
	var zero_tree := VoxelPopulatorScript.new(WorldGenConfigScript.new({"seed": 918273, "tree_density": 0.0}), BiomeCatalogScript.new())
	var zero_decoration := VoxelPopulatorScript.new(WorldGenConfigScript.new({"seed": 918273, "decoration_density": 0.0}), BiomeCatalogScript.new())
	_check(zero_tree._grove_tree_probability(BiomeCatalogScript.DECORATION_FOREST, 1.0) == 0.0, "tree_density=0 must disable grove trees")
	_check(zero_decoration._grove_tree_probability(BiomeCatalogScript.DECORATION_FOREST, 1.0) == 0.0, "decoration_density=0 must disable grove trees")


## Two jittered neighboring lattice cells stay five blocks apart. Their radius-3
## jungle crowns overlap across x=32, while both root owners and all canopy-only
## chunks stamp the same combined geometry.
func _verify_overlapping_border_candidates(populator: VoxelPopulator) -> void:
	var left_center := Vector2i(27, 32)
	var right_center := Vector2i(32, 32)
	var edge_blocks := _stamp_overlapping_tree_chunks(populator, left_center, right_center)
	var repeated_blocks := _stamp_overlapping_tree_chunks(populator, left_center, right_center)
	var translated_blocks := _stamp_overlapping_tree_chunks(populator, left_center + Vector2i(24, 24), right_center + Vector2i(24, 24))
	_check(_same_blocks(edge_blocks, repeated_blocks), "overlapping border candidates must be repeatable")
	_check(_same_blocks(_translated(translated_blocks, Vector3i(-24, 0, -24)), edge_blocks), "overlapping border crowns must match translated geometry")
	_check(edge_blocks.get(Vector3i(left_center.x, 61, left_center.y), -1) == BlockRegistryScript.BLOCK_JUNGLE_LOG, "left overlapping tree lost its root trunk")
	_check(edge_blocks.get(Vector3i(right_center.x, 62, right_center.y), -1) == BlockRegistryScript.BLOCK_JUNGLE_LOG, "right overlapping tree lost its root trunk")


func _stamp_overlapping_tree_chunks(populator: VoxelPopulator, left_center: Vector2i, right_center: Vector2i) -> Dictionary:
	var blocks := {}
	for chunk_z in range(1, 5):
		for chunk_x in range(1, 5):
			var origin_x: int = chunk_x * VoxelDefsScript.CHUNK_SIZE
			var origin_z: int = chunk_z * VoxelDefsScript.CHUNK_SIZE
			var data := PackedByteArray()
			data.resize(VoxelDefsScript.CHUNK_AREA * VoxelDefsScript.WORLD_HEIGHT)
			populator._stamp_tree(data, origin_x, origin_z, left_center.x, 60, left_center.y, BlockRegistryScript.BLOCK_JUNGLE_LOG, BlockRegistryScript.BLOCK_JUNGLE_LEAVES, 7, 3, 73129)
			populator._stamp_tree(data, origin_x, origin_z, right_center.x, 61, right_center.y, BlockRegistryScript.BLOCK_JUNGLE_LOG, BlockRegistryScript.BLOCK_JUNGLE_LEAVES, 7, 3, 91573)
			for y in range(VoxelDefsScript.WORLD_HEIGHT):
				for local_z in VoxelDefsScript.CHUNK_SIZE:
					for local_x in VoxelDefsScript.CHUNK_SIZE:
						var block_id: int = data[local_x + local_z * VoxelDefsScript.CHUNK_SIZE + y * VoxelDefsScript.CHUNK_AREA]
						if block_id != BlockRegistryScript.BLOCK_AIR:
							blocks[Vector3i(origin_x + local_x, y, origin_z + local_z)] = block_id
	return blocks


func _benchmark_full_generation() -> void:
	var generator := TerrainGenerator.new()
	generator.configure({"seed": 918273, "tree_density": 1.0, "decoration_density": 1.0})
	var populate_us := 0
	var generation_us := 0
	var chunks: Array[Vector2i] = [Vector2i(-5, -4), Vector2i(-1, 3), Vector2i(4, -2), Vector2i(7, 6)]
	for chunk in chunks:
		var result := generator.generate_data(chunk, {}, false)
		populate_us += int(result.timings["populate_us"])
		generation_us += int(result.timings["generation_us"])
	print("worldgen_tree_verify: full_detail_chunks=%d avg_populate_us=%d avg_generation_us=%d" % [chunks.size(), populate_us / chunks.size(), generation_us / chunks.size()])


func _all_connected(blocks: Dictionary) -> bool:
	if blocks.is_empty():
		return false
	var pending: Array[Vector3i] = [blocks.keys()[0]]
	var visited := {}
	var directions: Array[Vector3i] = [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]
	while not pending.is_empty():
		var position: Vector3i = pending.pop_back()
		if visited.has(position):
			continue
		visited[position] = true
		for direction in directions:
			var neighbor: Vector3i = position + direction
			if blocks.has(neighbor) and not visited.has(neighbor):
				pending.append(neighbor)
	return visited.size() == blocks.size()


func _translated(blocks: Dictionary, offset: Vector3i) -> Dictionary:
	var translated := {}
	for position in blocks:
		translated[position + offset] = blocks[position]
	return translated


func _same_blocks(left: Dictionary, right: Dictionary) -> bool:
	if left.size() != right.size():
		return false
	for position in left:
		if right.get(position, -1) != left[position]:
			return false
	return true


func _check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error("worldgen_tree_verify: %s" % message)
