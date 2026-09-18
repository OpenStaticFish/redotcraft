## Entry point for dependency-free pure-logic unit tests.
extends SceneTree

const UnitSuiteScript = preload("res://tools/unit/unit_suite.gd")
const WorldgenUnitTestScript = preload("res://tools/unit/worldgen_unit_test.gd")
const BlockRegistryUnitTestScript = preload("res://tools/unit/block_registry_unit_test.gd")
const MesherUnitTestScript = preload("res://tools/unit/mesher_unit_test.gd")


func _initialize() -> void:
	var suite = UnitSuiteScript.new()
	print("UNIT TESTS: START")
	WorldgenUnitTestScript.new().run(suite)
	BlockRegistryUnitTestScript.new().run(suite)
	MesherUnitTestScript.new().run(suite)
	if suite.failures.is_empty():
		print("UNIT TESTS: PASS (%d tests, %d assertions)" % [suite.test_count, suite.assertion_count])
		quit(0)
		return
	for failure in suite.failures:
		push_error("UNIT TEST: %s" % failure)
	print("UNIT TESTS: FAIL (%d/%d tests, %d assertions)" % [suite.failures.size(), suite.test_count, suite.assertion_count])
	quit(1)
