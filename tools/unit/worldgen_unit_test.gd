## Deterministic world-generation primitive and field fixtures.
class_name WorldgenUnitTest
extends RefCounted

const TEST_CONFIG := {
	"seed": 123456789,
	"world_type": WorldGenConfig.WORLD_TYPE_NORMAL,
	"terrain_scale": 1.0,
	"tree_density": 0.0,
	"macro_scale": 384.0,
	"river_density": 1.0,
	"erosion_strength": 0.55,
	"regional_erosion": 0.5,
	"cave_density": 0.0,
	"decoration_density": 0.0,
}

const FIELD_FIXTURES := [
	[Vector2i(0, 0), 65.557, 0, 0.0],
	[Vector2i(7, 11), 68.470, 0, 0.0],
	[Vector2i(15, 15), 66.610, 0, 0.0],
]


func run(suite) -> void:
	suite.test("worldgen hash fixed vectors", func() -> void: _test_hash_vectors(suite))
	suite.test("worldgen floor division and ranges", func() -> void: _test_hash_bounds(suite))
	suite.test("worldgen field fixtures are deterministic", func() -> void: _test_field_fixture(suite))


static func _test_hash_vectors(suite: UnitSuite) -> void:
	suite.expect_equal(WorldGenHash.hash_1d(123456789, -17), 746319822, "1D hash fixture")
	suite.expect_equal(WorldGenHash.hash_2d(123456789, 0, 0), 991826124, "origin hash fixture")
	suite.expect_equal(WorldGenHash.hash_2d(123456789, -17, 31), 554134520, "negative-coordinate hash fixture")
	suite.expect_equal(WorldGenHash.hash_2d(-987654321, 999, -444), 466599662, "negative-seed hash fixture")
	suite.expect_equal(WorldGenHash.hash_3d(123456789, -17, 9, 31), 778180355, "3D hash fixture")


static func _test_hash_bounds(suite: UnitSuite) -> void:
	for value in [-33, -17, -1, 0, 1, 17, 33]:
		suite.expect_equal(WorldGenHash.floor_mod(value, 16), posmod(value, 16), "floor modulus at %d" % value)
		suite.expect_equal(WorldGenHash.floor_div(value, 16) * 16 + WorldGenHash.floor_mod(value, 16), value,
			"division identity at %d" % value)
		var unit := WorldGenHash.float_01_2d(918273, value, -value)
		suite.expect(unit >= 0.0 and unit < 1.0, "unit hash range at %d" % value)
	for minimum in [-4, 0, 5]:
		for maximum in [minimum, minimum + 1, minimum + 7]:
			var sample := WorldGenHash.int_range_2d(42, minimum, maximum, minimum, maximum)
			suite.expect(sample >= minimum and sample <= maximum, "integer hash range %d..%d" % [minimum, maximum])


static func _test_field_fixture(suite: UnitSuite) -> void:
	var sampler := TerrainSampler.new(WorldGenConfig.new(TEST_CONFIG), TerrainProfileCatalog.new(), BiomeCatalog.new())
	var first: ChunkTerrainData = sampler.build_field(Vector2i(3, -2))
	var second: ChunkTerrainData = sampler.build_field(Vector2i(3, -2))
	suite.expect_equal(first.final_height, second.final_height, "field heights repeat")
	suite.expect_equal(first.dominant_biome, second.dominant_biome, "field biomes repeat")
	for fixture in FIELD_FIXTURES:
		var cell: Vector2i = fixture[0]
		var index := ChunkTerrainData.cell_index(cell.x, cell.y)
		var point: Dictionary = sampler.sample_point(3 * VoxelDefs.CHUNK_SIZE + cell.x, -2 * VoxelDefs.CHUNK_SIZE + cell.y)
		suite.expect_approx(float(first.final_height[index]), float(point["final_height"]), "field/point height parity at %s" % cell)
		suite.expect_equal(int(first.dominant_biome[index]), int(point["dominant_biome_id"]), "field/point biome parity at %s" % cell)
		suite.expect_approx(float(first.final_height[index]), float(fixture[1]), "field height fixture at %s" % cell, 0.001)
		suite.expect_equal(int(first.dominant_biome[index]), int(fixture[2]), "field biome fixture at %s" % cell)
		suite.expect_approx(float(first.river[index]), float(fixture[3]), "field river fixture at %s" % cell, 0.000001)
