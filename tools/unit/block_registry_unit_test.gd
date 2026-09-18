## Tests the persistent block table and its runtime texture-layer packing.
class_name BlockRegistryUnitTest
extends RefCounted


func run(suite) -> void:
	suite.test("block definitions have contiguous byte IDs", func() -> void: _test_definition_ids(suite))
	suite.test("block texture layers follow packed definitions", func() -> void: _test_texture_packing(suite))
	suite.test("water IDs round trip through levels", func() -> void: _test_water_levels(suite))


static func _test_definition_ids(suite: UnitSuite) -> void:
	suite.expect(BlockRegistry.BLOCK_DEFS.size() <= 256, "persistent IDs fit PackedByteArray")
	for index in BlockRegistry.BLOCK_DEFS.size():
		var definition: Array = BlockRegistry.BLOCK_DEFS[index]
		suite.expect_equal(int(definition[0]), index, "definition ID is its table index")
		suite.expect(int(definition[0]) >= 0 and int(definition[0]) < 256, "definition ID is byte-packable")


static func _test_texture_packing(suite: UnitSuite) -> void:
	var expected_layers := {}
	for definition in BlockRegistry.BLOCK_DEFS:
		for texture_index in range(2, 5):
			var texture_name: String = definition[texture_index]
			if not texture_name.is_empty() and not expected_layers.has(texture_name):
				expected_layers[texture_name] = expected_layers.size()
	var registry := BlockRegistry.new()
	suite.expect(registry.texture_array != null, "texture array was built")
	suite.expect_equal(registry.texture_array.get_layers(), expected_layers.size(), "one texture-array layer per unique texture")
	const FACE_TEXTURE_COLUMNS := [2, 4, 3]
	for definition in BlockRegistry.BLOCK_DEFS:
		var id: int = definition[0]
		for face in 3:
			var texture_name: String = definition[FACE_TEXTURE_COLUMNS[face]]
			var expected_layer: int = int(expected_layers.get(texture_name, 0))
			suite.expect_equal(registry.layer_for(id, face), expected_layer,
				"packed layer for block %d face %d" % [id, face])
	suite.expect_equal(registry.get_block_name(BlockRegistry.BLOCK_WOOD_BED_LAST), "WOOD BED WEST", "last persistent ID name")


static func _test_water_levels(suite: UnitSuite) -> void:
	var registry := BlockRegistry.new()
	for level in range(0, 9):
		var id := registry.water_id_for_level(level)
		var expected_level := level
		suite.expect_equal(registry.water_level(id), expected_level, "water level round trip %d" % level)
		suite.expect_equal(registry.is_water_id(id), level > 0, "water identity at level %d" % level)
	for id in range(BlockRegistry.BLOCK_WATER_FLOW_7, BlockRegistry.BLOCK_WATER_FLOW_1 + 1):
		var level := registry.water_level(id)
		suite.expect_equal(registry.water_id_for_level(level), id, "flowing water inverse for ID %d" % id)
	suite.expect_equal(registry.water_level(BlockRegistry.BLOCK_STONE), 0, "solid is not water")
	suite.expect_equal(registry.water_id_for_level(-3), BlockRegistry.BLOCK_AIR, "negative level is air")
	suite.expect_equal(registry.water_id_for_level(42), BlockRegistry.BLOCK_WATER, "large level is a source")
