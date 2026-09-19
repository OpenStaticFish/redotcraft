## Unit-level geometry and ambient-occlusion fixtures for ChunkMesher.
class_name MesherUnitTest
extends RefCounted


func run(suite) -> void:
	suite.test("mesher water-top curve is bounded and ordered", func() -> void: _test_water_curve(suite))
	suite.test("mesher AO offsets cover each face corner", func() -> void: _test_ao_offsets(suite))
	suite.test("mesher culls shared cube faces", func() -> void: _test_face_culling(suite))
	suite.test("mesher AO uses all three occluders", func() -> void: _test_ao_shading(suite))


static func _test_water_curve(suite: UnitSuite) -> void:
	var mesher := ChunkMesher.new(BlockRegistry.new())
	var previous := 0.0
	for level in range(1, 9):
		var top := mesher._water_top(level)
		suite.expect(top > previous and top <= 0.9, "water top increases at level %d" % level)
		previous = top
	suite.expect_approx(mesher._water_top(1), 0.388125, "level-one water top")
	suite.expect_approx(mesher._water_top(8), 0.9, "source water top")


static func _test_ao_offsets(suite: UnitSuite) -> void:
	var mesher := ChunkMesher.new(BlockRegistry.new())
	suite.expect_equal(mesher._face_ao_offsets.size(), 6, "AO table has one row per face")
	for face in mesher._face_ao_offsets.size():
		var corners: Array = mesher._face_ao_offsets[face]
		suite.expect_equal(corners.size(), 4, "AO table has four corners for face %d" % face)
		for samples in corners:
			suite.expect_equal(samples.size(), 3, "AO corner has side A, side B, and diagonal samples")
	var top_corner: Array = mesher._face_ao_offsets[0][0]
	suite.expect_equal(top_corner[0], Vector3i(-1, 1, 0), "top AO side A offset")
	suite.expect_equal(top_corner[1], Vector3i(0, 1, 1), "top AO side B offset")
	suite.expect_equal(top_corner[2], Vector3i(-1, 1, 1), "top AO diagonal offset")


static func _test_face_culling(suite: UnitSuite) -> void:
	var mesher := ChunkMesher.new(BlockRegistry.new())
	var result := _build_fixture(mesher, [Vector3i(8, 8, 8), Vector3i(9, 8, 8)])
	suite.expect_equal(result.verts.size(), 40, "two adjacent cubes emit ten exposed faces")
	suite.expect_equal(result.indices.size(), 60, "two adjacent cubes emit ten quad index sets")


static func _test_ao_shading(suite: UnitSuite) -> void:
	var mesher := ChunkMesher.new(BlockRegistry.new())
	var result := _build_fixture(mesher, [
		Vector3i(8, 8, 8),
		Vector3i(7, 9, 8), Vector3i(8, 9, 9), Vector3i(7, 9, 9),
	])
	# The first emitted face is the source block's top face. Its first corner is
	# surrounded by the three offsets checked above, yielding AO_LEVELS[0].
	suite.expect_approx(result.colors[0].r, VoxelDefs.AO_LEVELS[0], "three occluders use darkest AO level")


static func _build_fixture(mesher: ChunkMesher, blocks: Array[Vector3i]) -> ChunkMesher.MeshResult:
	var data := PackedByteArray()
	data.resize(VoxelDefs.CHUNK_AREA * VoxelDefs.WORLD_HEIGHT)
	for position in blocks:
		data[position.x + position.z * VoxelDefs.DATA_STRIDE_Z + position.y * VoxelDefs.DATA_STRIDE_Y] = BlockRegistry.BLOCK_STONE
	var heights := PackedInt32Array()
	heights.resize(VoxelDefs.CHUNK_AREA)
	heights.fill(10)
	var tints := PackedColorArray()
	tints.resize(VoxelDefs.CHUNK_AREA)
	tints.fill(Color.WHITE)
	return mesher.build(data, 10, heights, tints, tints, ChunkMesher.NeighborSet.new(), false)
