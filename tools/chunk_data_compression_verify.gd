## Focused checks for distant full-detail chunk palette/RLE storage.
## Run: redot --headless --path . --script res://tools/chunk_data_compression_verify.gd
extends SceneTree

var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var data := _make_varied_data()
	var compressed := VoxelWorld.compress_chunk_data(data)
	_expect(compressed == VoxelWorld.compress_chunk_data(data), "encoding was not deterministic")
	_expect(VoxelWorld.decompress_chunk_data(compressed) == data, "varied block runs did not round-trip")
	_expect(compressed.size() < data.size(), "palette/RLE did not reduce representative chunk data")

	var world := VoxelWorld.new()
	root.add_child(world)
	world._stream_center = Vector2i.ZERO
	world.lod_distance = 10
	var remote_pos := Vector2i(7, 0)
	var remote := world._create_chunk_nodes(remote_pos)
	remote.data = data.duplicate()
	remote.heights.resize(VoxelDefs.CHUNK_AREA)
	remote.heights[0] = 31
	remote.foliage_tints.resize(VoxelDefs.CHUNK_AREA)
	remote.foliage_tints[0] = Color(0.2, 0.7, 0.3)
	remote.water_tints.resize(VoxelDefs.CHUNK_AREA)
	remote.water_tints[0] = Color(0.1, 0.4, 0.8)
	remote.max_y = 31
	world._chunks[remote_pos] = remote
	var lod_chunk := VoxelWorld.Chunk.new()
	lod_chunk.lod = true
	lod_chunk.data = data.duplicate()
	world._chunks[Vector2i(8, 0)] = lod_chunk
	world._compress_distant_chunks()
	_expect(remote.data.is_empty() and not remote.compressed_data.is_empty(),
		"distant full-detail chunk was not compacted")
	_expect(remote.heights[0] == 31 and remote.foliage_tints[0] == Color(0.2, 0.7, 0.3) \
			and remote.water_tints[0] == Color(0.1, 0.4, 0.8),
		"compression changed authoritative heights or tints")
	_expect(not lod_chunk.data.is_empty() and lod_chunk.compressed_data.is_empty(),
		"LOD chunk was compacted")
	print("CHUNK DATA COMPRESSION: raw_bytes=%d compressed_bytes=%d saved_bytes=%d" % [
		data.size(), remote.compressed_data.size(), data.size() - remote.compressed_data.size()])

	_verify_negative_position(world, data)
	_verify_neighbor_snapshot(world, remote_pos, data)
	_verify_approach_and_edit(world, remote_pos)

	world.queue_free()
	if _failures == 0:
		print("CHUNK DATA COMPRESSION VERIFY: PASS")
		quit(0)
		return
	print("CHUNK DATA COMPRESSION VERIFY: FAIL (%d)" % _failures)
	quit(1)


func _make_varied_data() -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(VoxelDefs.CHUNK_AREA * VoxelDefs.WORLD_HEIGHT)
	for index in range(192, 768):
		data[index] = BlockRegistry.BLOCK_STONE
	for index in range(2048, 2176):
		data[index] = BlockRegistry.BLOCK_DIRT
	for index in range(5000, 5048):
		data[index] = BlockRegistry.BLOCK_LOG if index % 3 == 0 else BlockRegistry.BLOCK_LEAVES
	for index in range(9000, 9100):
		data[index] = BlockRegistry.BLOCK_WATER
	return data


func _verify_negative_position(world: VoxelWorld, data: PackedByteArray) -> void:
	var negative_pos := Vector2i(-8, -7)
	var negative := VoxelWorld.Chunk.new()
	negative.data = data.duplicate()
	world._chunks[negative_pos] = negative
	world._compress_distant_chunks()
	_expect(negative.data.is_empty() and not negative.compressed_data.is_empty(),
		"negative-coordinate full chunk was not compacted")
	_expect(world._chunk_for_block(Vector3i(-113, 12, -97)) == negative_pos,
		"negative chunk coordinate conversion changed")
	_expect(VoxelWorld.decompress_chunk_data(negative.compressed_data) == data,
		"negative-coordinate compressed data did not round-trip")


func _verify_neighbor_snapshot(world: VoxelWorld, remote_pos: Vector2i, data: PackedByteArray) -> void:
	var neighbors := world._gather_neighbors(Vector2i(6, 0))
	var sample: ChunkMesher.NeighborSample = neighbors.get_sample(Vector2i(1, 0))
	_expect(sample != null, "compressed full-detail neighbor was omitted")
	_expect(sample != null and sample.data == data,
		"neighbor meshing snapshot did not decode immutable full-detail data")
	_expect(world._chunks[remote_pos].data.is_empty(),
		"neighbor snapshot restored mutable data instead of decoding a copy")


func _verify_approach_and_edit(world: VoxelWorld, remote_pos: Vector2i) -> void:
	var remote: VoxelWorld.Chunk = world._chunks[remote_pos]
	world._stream_center = remote_pos
	# Collision restoration only services the authoritative desired set. This
	# focused fixture builds chunks directly instead of calling setup_player().
	world._desired[remote_pos] = true
	world._ensure_near_collision()
	_expect(not remote.data.is_empty() and remote.compressed_data.is_empty(),
		"approaching a collision chunk did not restore mutable data")
	var edit_position := Vector3i(remote_pos.x * VoxelDefs.CHUNK_SIZE + 2, 40, 2)
	_expect(world.place_block(edit_position, BlockRegistry.BLOCK_STONE),
		"edit into restored chunk failed")
	_expect(world.get_block_world(edit_position) == BlockRegistry.BLOCK_STONE,
		"restored chunk edit was not readable")
	world._stream_center = Vector2i.ZERO
	world._compress_distant_chunks()
	_expect(remote.data.is_empty() and not remote.compressed_data.is_empty(),
		"retreated edited chunk was not recompressed")
	_expect(world.get_block_world(edit_position) == BlockRegistry.BLOCK_STONE,
		"edit did not survive recompression and query restoration")
	_expect(world._edited_blocks.get(edit_position, -1) == BlockRegistry.BLOCK_STONE,
		"edit persistence changed while chunk data was compacted")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("chunk_data_compression_verify: %s" % message)
