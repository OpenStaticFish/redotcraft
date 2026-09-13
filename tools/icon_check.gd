extends SceneTree

func _init() -> void:
	var registry := BlockRegistry.new()
	var ids := [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 27]
	for id in ids:
		var icon := BlockIcon.make_icon(registry, id, 48)
		if icon == null:
			push_error("Block icon %d could not be generated; run this check with a rendering display, not --headless." % id)
			quit(1)
			return
	print("BLOCK ICON VERIFY: PASS")
	quit(0)
