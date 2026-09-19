extends SceneTree

# Golden hashes are captured from the unoptimized mesher, not regenerated on success.
const EXPECTED := {
	"normal_true": "d66408ad7adbb6bc62ebf27c28773d93d1f1c36fa4c04a5eb9c9a1c6b8452391",
	"normal_false": "0694cd4e68e6dad1e63ec2cba41177987df7833903bb10e8fcfb2f5a217470cb",
	"missing_true": "ad70bd22ffd1bfa9c8216929d7a12e421f13da21cdcc2c857548667ef845c845",
	"missing_false": "27e27f4a81b502db87e7c99f5f47563a97cd100e86931150de38f196370d04af",
	"emissive_true": "918cc0e96dc192e1506676582690ba24b86565400ae1722692e9fa6307d43347",
	"emissive_false": "7bbab113d6155c85110e58f62575c37fdf1865929ec4c8d63398ace01a2f78ef",
	"compact_true": "4d897666a4fb76e5283a3fe391f0e6ec7df9ec6c410d22149db11f02d1ee5559",
	"compact_false": "3695d59fb72df384cc6ece9e8747a8be1d783880a5d897238c30ba4a8ffabf39",
	"lod": "bda211a4c5ef034d5fedc5b0e9d6a0e23f8f99d13d120c4960779dfdc9541cdc",
	# Captured before adding the bounded dense-emitter fallback.
	"dense_emitters": "2421949d3e488e69ec11e1ddbb7cba70f6d89cf215d1add52d3d12f26a3d27bc",
	"mesh_upload_contract": "3d299eed5994959d845cbe670b2d6a14fdfcf8ef2184fc5f62c24124ef5f061b",
}
const OUTPUT_FIELDS := [
	"data", "heights", "foliage_tints", "water_tints", "max_y", "mask",
	"verts", "normals", "uvs", "colors", "light", "layers", "indices", "collision",
	"water_verts", "water_normals", "water_uvs", "water_colors", "water_light", "water_indices",
	"build_collision", "lod_solid_y", "lod_solid_id", "lod_sub_id", "lod_water_y", "lod_water_level",
]


func _initialize() -> void:
	var registry := BlockRegistry.new()
	var mesher := ChunkMesher.new(registry)
	var data := PackedByteArray()
	data.resize(VoxelDefs.CHUNK_AREA * VoxelDefs.WORLD_HEIGHT)
	var heights := PackedInt32Array()
	heights.resize(VoxelDefs.CHUNK_AREA)
	var tints := PackedColorArray()
	tints.resize(VoxelDefs.CHUNK_AREA)
	for column in VoxelDefs.CHUNK_AREA:
		tints[column] = Color(0.6 + float(column % 3) * 0.1, 0.8, 0.7, 1.0)
		var top := 2 + column % 5
		heights[column] = top
		for y in range(top + 1):
			data[column + y * VoxelDefs.CHUNK_AREA] = BlockRegistry.BLOCK_STONE
	# Every registered material/state, separated by air, plus ceiling/bottom bounds.
	var n := 0
	for row in BlockRegistry.BLOCK_DEFS:
		var id: int = row[0]
		if id == BlockRegistry.BLOCK_AIR or BlockRegistry.EMISSIVE_COLORS.has(id):
			continue
		var x := (n % 8) * 2
		var z := (int(n / 8) % 8) * 2
		var y := 10 + int(n / 64) * 3
		data[x + z * 16 + y * 256] = id
		heights[x + z * 16] = y
		n += 1
	data[255 + (VoxelDefs.WORLD_HEIGHT - 1) * 256] = BlockRegistry.BLOCK_STONE
	heights[255] = VoxelDefs.WORLD_HEIGHT - 1
	var solid := PackedInt32Array()
	solid.resize(256)
	solid.fill(5)
	var ids := PackedByteArray()
	ids.resize(256)
	ids.fill(BlockRegistry.BLOCK_GRASS)
	var subs := ids.duplicate()
	subs.fill(BlockRegistry.BLOCK_STONE)
	var water := solid.duplicate()
	water.fill(7)
	var levels := ids.duplicate()
	levels.fill(8)
	var failed := false
	for fixture in ["normal", "missing", "emissive", "compact"]:
		var input := data.duplicate()
		if fixture == "emissive":
			input[1 + 16 + 9 * 256] = BlockRegistry.BLOCK_TORCH
		var neighbors := ChunkMesher.NeighborSet.new()
		if fixture != "missing":
			neighbors.mask = 255
			for z in range(-1, 2):
				for x in range(-1, 2):
					if x == 0 and z == 0:
						continue
					neighbors.samples[Vector2i(x, z)] = ChunkMesher.NeighborSample.from_lod(solid, ids, subs, water) if fixture == "compact" else ChunkMesher.NeighborSample.new(input, 191, heights)
		for collision in [true, false]:
			var result := mesher.build(input, 191, heights, tints, tints, neighbors, collision)
			var values: Array = []
			for field in OUTPUT_FIELDS:
				values.append(result.get(field))
			var volume := mesher.build_light_volume(input, 191, heights, neighbors)
			values.append([volume.w, volume.d, volume.h, volume.blocks, volume.heights, volume.sky, volume.block_r, volume.block_g, volume.block_b])
			var key := "%s_%s" % [fixture, collision]
			failed = not _verify(key, values) or failed
	var lod := mesher.build_lod(solid, ids, subs, water, levels, 7, tints, tints, ChunkMesher.LodNeighbors.new())
	var values: Array = []
	for field in OUTPUT_FIELDS:
		values.append(lod.get(field))
	failed = not _verify("lod", values) or failed
	var dense := ChunkMesher.LightVolume.new()
	dense.w = 48
	dense.d = 48
	dense.h = 8
	dense.blocks.resize(dense.w * dense.d * dense.h)
	var source_ids := [BlockRegistry.BLOCK_GLOWSTONE, BlockRegistry.BLOCK_TORCH,
		BlockRegistry.BLOCK_LAVA, BlockRegistry.BLOCK_AIR]
	for index in dense.blocks.size():
		dense.blocks[index] = source_ids[index % source_ids.size()]
	mesher._compute_block_light(dense)
	failed = not _verify("dense_emitters", [dense.block_r, dense.block_g, dense.block_b]) or failed
	# Headless rendering cannot validate GPU surfaces. Pin the unchanged upload
	# function as well, including material assignment and custom-attribute flags.
	var source := FileAccess.get_file_as_string("res://world/chunk_mesher.gd")
	var upload := source.get_slice("static func arrays_to_mesh", 1).get_slice("\n\nfunc _build_light_tables", 0)
	failed = not _verify("mesh_upload_contract", [upload]) or failed
	if not failed:
		print("MESH PARITY VERIFY: PASS")
	quit(1 if failed else 0)


func _verify(key: String, values: Array) -> bool:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(var_to_bytes(values))
	var digest := hashing.finish().hex_encode()
	print("MESH PARITY ", key, " ", digest)
	if not EXPECTED.has(key) or EXPECTED[key] != digest:
		push_error("Missing or mismatched golden mesh hash: " + key)
		return false
	return true
