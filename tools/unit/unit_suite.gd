## Small dependency-free assertion harness for pure GDScript unit tests.
class_name UnitSuite
extends RefCounted

var test_count: int = 0
var assertion_count: int = 0
var failures := PackedStringArray()
var _current_test := ""


func test(name: String, body: Callable) -> void:
	test_count += 1
	_current_test = name
	var failures_before := failures.size()
	body.call()
	if failures.size() == failures_before:
		print("  PASS ", name)


func expect(condition: bool, message: String) -> void:
	assertion_count += 1
	if not condition:
		failures.append("%s: %s" % [_current_test, message])


func expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	expect(actual == expected, "%s (expected %s, got %s)" % [message, expected, actual])


func expect_approx(actual: float, expected: float, message: String, tolerance: float = 0.00001) -> void:
	expect(is_equal_approx(actual, expected) or absf(actual - expected) <= tolerance,
		"%s (expected %.6f, got %.6f)" % [message, expected, actual])
