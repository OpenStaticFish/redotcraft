## Headless regression check for the leaf shadow proxy wiring. The proxy lives
## entirely in world/block.gdshader: in the shadow pass leaf fragments write
## solid coverage so the shadow map never samples mip-filtered leaf alpha. This
## check pins the shader/source contract the mesher depends on, since a silent
## rename of the wind channel or the shader branch would otherwise break it.
## Run:
##   redot --headless --path . --script res://tools/shadow_proxy_verify.gd
extends SceneTree

const SHADER_PATH := "res://world/block.gdshader"

var _failures := 0


func _initialize() -> void:
	process_frame.connect(_verify, CONNECT_ONE_SHOT)


func _verify() -> void:
	_check_mesher_leaf_marker()
	_check_shader_proxy()
	_check_leaf_blocks_independent()
	_check_graphics_toggle()
	if _failures == 0:
		print("SHADOW PROXY VERIFY: PASS")
		quit(0)
		return
	print("SHADOW PROXY VERIFY: FAIL (%d)" % _failures)
	quit(1)


## The proxy is player-facing, so the graphics key must exist in every preset
## (AGENTS.md: a new key goes into all GRAPHICS_PRESETS entries) and have a UI
## row, or the setting silently does nothing.
func _check_graphics_toggle() -> void:
	# Autoloads and UI class_names are not available at --script parse time, so
	# fetch them at runtime.
	var config: Node = root.get_node_or_null("GameConfig")
	if config == null:
		_expect(false, "GameConfig autoload is missing")
		return
	for preset in config.GRAPHICS_PRESETS:
		_expect((config.GRAPHICS_PRESETS[preset] as Dictionary).has("solid_leaf_shadows"),
			"graphics preset %d is missing solid_leaf_shadows" % preset)
	var sections_script: GDScript = load("res://ui/graphics_sections.gd")
	var found := false
	if sections_script != null:
		for section in sections_script.SECTIONS:
			for row in section["rows"]:
				if row.get("key", "") == "solid_leaf_shadows":
					found = true
	_expect(found, "no graphics section row exposes solid_leaf_shadows")


## The shader keys the proxy off COLOR.a, which ChunkMesher writes as the wind
## weight. Leaves must be the only blocks with a full weight, or the proxy would
## solidify glass/foliage shadows too.
func _check_mesher_leaf_marker() -> void:
	var blocks := BlockRegistry.new()
	var mesher := ChunkMesher.new(blocks)
	var leaf_weights: Array[float] = []
	for id in 256:
		if blocks.has_flag(id, BlockRegistry.FLAG_LEAVES):
			leaf_weights.append(mesher._wind[id])
	var max_non_leaf := 0.0
	for id in 256:
		if blocks.has_flag(id, BlockRegistry.FLAG_LEAVES):
			continue
		max_non_leaf = maxf(max_non_leaf, mesher._wind[id])
	_expect(not leaf_weights.is_empty(), "block table has no leaf blocks to proxy")
	for weight in leaf_weights:
		_expect(is_equal_approx(weight, 1.0), "leaf wind weight is %.2f, not 1.0" % weight)
	_expect(max_non_leaf < 0.99, "non-leaf wind weight %.2f collides with the leaf marker" % max_non_leaf)
	mesher = null
	blocks = null


func _check_shader_proxy() -> void:
	var file := FileAccess.open(SHADER_PATH, FileAccess.READ)
	_expect(file != null, "cannot read %s" % SHADER_PATH)
	if file == null:
		return
	var source := file.get_as_text()
	file.close()
	_expect(source.contains("IN_SHADOW_PASS"), "shader does not test IN_SHADOW_PASS")
	_expect(source.contains("solid_leaf_shadows"), "shader is missing the solid_leaf_shadows uniform")
	_expect(source.contains("step(0.99, COLOR.a)"), "shader does not read the leaf wind marker")
	# The proxy must only apply in the shadow pass, never in the visible pass.
	var proxy_line := source.find("shadow_proxy")
	_expect(proxy_line >= 0, "shader has no shadow_proxy term")
	var fragment_start := source.find("void fragment()")
	_expect(fragment_start >= 0 and proxy_line > fragment_start, "shadow proxy must be in fragment()")
	_expect(source.contains("ALPHA = max(tex.a, shadow_proxy)"), "shader does not apply the proxy to ALPHA")


## The proxy is keyed off FLAG_LEAVES, so the flag must stay limited to the
## leaf family and every leaf block must still carry it. The expected set is
## derived from the block table names so a newly added leaf cannot silently
## miss the flag (and therefore the proxy).
func _check_leaf_blocks_independent() -> void:
	var blocks := BlockRegistry.new()
	var named_leaves := 0
	for id in 256:
		if not blocks.is_valid_id(id):
			continue
		var block_name := blocks.get_block_name(id)
		if not block_name.to_lower().contains("leaves"):
			continue
		named_leaves += 1
		_expect(blocks.has_flag(id, BlockRegistry.FLAG_LEAVES),
			"block %d ('%s') looks like a leaf but lacks FLAG_LEAVES" % [id, block_name])
	_expect(named_leaves >= 6, "expected at least six leaf blocks, found %d" % named_leaves)
	_expect(not blocks.has_flag(BlockRegistry.BLOCK_GLASS, BlockRegistry.FLAG_LEAVES), "glass must not be a leaf")
	_expect(not blocks.has_flag(BlockRegistry.BLOCK_TALL_GRASS, BlockRegistry.FLAG_LEAVES), "grass must not be a leaf")
	blocks = null


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("shadow_proxy_verify: " + message)
