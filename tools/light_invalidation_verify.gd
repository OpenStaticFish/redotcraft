extends SceneTree

## Verifies the selective invalidation predicate used for one-cell edits.
## Batch explosion, fire, and water paths intentionally retain full rings.

var _failures := 0


func _initialize() -> void:
	_verify_enclosed_edits()
	_verify_border_edits()
	_verify_opaque_swaps()
	_verify_attenuation_and_emission_changes()
	_verify_negative_coordinates()
	_verify_exact_reachable_neighbors()
	if _failures == 0:
		print("LIGHT INVALIDATION VERIFY: PASS")
	else:
		print("LIGHT INVALIDATION VERIFY: FAIL (%d checks)" % _failures)
	quit(1 if _failures > 0 else 0)


func _verify_enclosed_edits() -> void:
	var edit := Vector3i(8, 64, 8)
	_expect_neighbor(true, BlockRegistry.BLOCK_AIR, BlockRegistry.BLOCK_STONE, edit,
		Vector2i(1, 0), "enclosed air/solid reaches cardinal light neighbor")
	_expect_neighbor(false, BlockRegistry.BLOCK_AIR, BlockRegistry.BLOCK_STONE, edit,
		Vector2i(1, 1), "enclosed air/solid excludes diagonal outside light range")
	_expect_neighbor(false, BlockRegistry.BLOCK_WATER, BlockRegistry.BLOCK_LEAVES, edit,
		Vector2i(1, 0), "enclosed equal-attenuation edit stays in owner")


func _verify_border_edits() -> void:
	var edge := Vector3i(15, 64, 8)
	_expect_neighbor(true, BlockRegistry.BLOCK_AIR, BlockRegistry.BLOCK_GLASS, edge,
		Vector2i(1, 0), "transparent boundary swap preserves direct face visibility")
	_expect_neighbor(false, BlockRegistry.BLOCK_AIR, BlockRegistry.BLOCK_GLASS, edge,
		Vector2i(0, 1), "transparent edge swap excludes non-touching neighbor")
	var corner := Vector3i(15, 64, 15)
	_expect_neighbor(true, BlockRegistry.BLOCK_WATER_FLOW_7, BlockRegistry.BLOCK_WATER_FLOW_6,
		corner, Vector2i(1, 1), "water level corner swap preserves diagonal water face")
	_expect_neighbor(false, BlockRegistry.BLOCK_WATER_FLOW_7, BlockRegistry.BLOCK_WATER_FLOW_6,
		corner, Vector2i(-1, -1), "water level corner swap excludes opposite diagonal")
	_expect_neighbor(true, BlockRegistry.BLOCK_SEAGRASS, BlockRegistry.BLOCK_AIR, edge,
		Vector2i(1, 0), "cross block boundary swap preserves adjacent water faces")


func _verify_opaque_swaps() -> void:
	_expect_equal(_requires_light_neighbor(BlockRegistry.BLOCK_STONE, BlockRegistry.BLOCK_DIRT),
		false, "opaque material swap keeps light attenuation")
	_expect_equal(_changes_boundary_visibility(BlockRegistry.BLOCK_STONE, BlockRegistry.BLOCK_DIRT),
		false, "opaque material swap keeps boundary faces and AO")
	_expect_neighbor(false, BlockRegistry.BLOCK_STONE, BlockRegistry.BLOCK_DIRT,
		Vector3i(15, 64, 8), Vector2i(1, 0), "opaque border swap does not rebuild neighbor")


func _verify_attenuation_and_emission_changes() -> void:
	_expect_equal(_requires_light_neighbor(BlockRegistry.BLOCK_AIR, BlockRegistry.BLOCK_STONE),
		true, "air/solid changes attenuation")
	_expect_equal(_requires_light_neighbor(BlockRegistry.BLOCK_WATER, BlockRegistry.BLOCK_LEAVES),
		false, "water/leaves share non-emissive attenuation")
	_expect_equal(_changes_boundary_visibility(BlockRegistry.BLOCK_WATER, BlockRegistry.BLOCK_LEAVES),
		true, "water/leaves boundary swap conservatively preserves water faces")
	_expect_equal(_changes_boundary_visibility(BlockRegistry.BLOCK_LEAVES, BlockRegistry.BLOCK_SPRUCE_LEAVES),
		false, "like-for-like leaves keep boundary face visibility")
	_expect_equal(_requires_light_neighbor(BlockRegistry.BLOCK_WATER_FLOW_7, BlockRegistry.BLOCK_WATER_FLOW_6),
		false, "water flow levels share attenuation")
	_expect_equal(_changes_boundary_visibility(BlockRegistry.BLOCK_WATER_FLOW_7, BlockRegistry.BLOCK_WATER_FLOW_6),
		true, "water flow level swap preserves face culling")
	_expect_equal(_requires_light_neighbor(BlockRegistry.BLOCK_AIR, BlockRegistry.BLOCK_TORCH),
		true, "torch emission adds neighbor light")
	_expect_equal(_requires_light_neighbor(BlockRegistry.BLOCK_TORCH, BlockRegistry.BLOCK_GLOWSTONE),
		true, "torch/glowstone emission color change rebuilds neighbor light")


func _verify_negative_coordinates() -> void:
	var edit := Vector3i(-1, 64, -1)
	_expect_neighbor(true, BlockRegistry.BLOCK_AIR, BlockRegistry.BLOCK_STONE, edit,
		Vector2i(0, 0), "negative corner reaches positive diagonal")
	_expect_neighbor(false, BlockRegistry.BLOCK_AIR, BlockRegistry.BLOCK_STONE, edit,
		Vector2i(-2, -2), "negative corner excludes opposite diagonal")
	_expect_neighbor(true, BlockRegistry.BLOCK_AIR, BlockRegistry.BLOCK_GLASS, edit,
		Vector2i(0, -1), "negative boundary detects positive-x geometry neighbor")


func _verify_exact_reachable_neighbors() -> void:
	var edit := Vector3i(15, 64, 15)
	var expected := {
		Vector2i(1, 0): true,
		Vector2i(0, 1): true,
		Vector2i(1, 1): true,
		Vector2i(-1, 0): false,
		Vector2i(0, -1): false,
		Vector2i(-1, -1): false,
	}
	for candidate in expected:
		_expect_neighbor(expected[candidate], BlockRegistry.BLOCK_AIR, BlockRegistry.BLOCK_STONE,
			edit, candidate, "exact reachable neighbor %s" % candidate)


func _requires_light_neighbor(old_block_id: int, new_block_id: int) -> bool:
	return VoxelWorld._single_edit_requires_light_neighbor_rebuild(old_block_id, new_block_id)


func _changes_boundary_visibility(old_block_id: int, new_block_id: int) -> bool:
	return VoxelWorld._single_edit_can_change_boundary_visibility(old_block_id, new_block_id)


func _expect_neighbor(expected: bool, old_block_id: int, new_block_id: int,
		edit: Vector3i, chunk: Vector2i, label: String) -> void:
	_expect_equal(VoxelWorld._single_edit_can_invalidate_neighbor(old_block_id, new_block_id,
		edit, chunk), expected, label)


func _expect_equal(actual: bool, expected: bool, label: String) -> void:
	if actual != expected:
		_fail("%s: expected %s, got %s" % [label, expected, actual])


func _fail(message: String) -> void:
	_failures += 1
	print("LIGHT INVALIDATION VERIFY FAIL: ", message)
