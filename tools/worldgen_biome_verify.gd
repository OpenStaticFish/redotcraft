## Headless regression check for coherent biome interiors and signature vegetation.
extends SceneTree

const SEED := 918273
const SAMPLE_STEP := 32
const SAMPLE_RADIUS := 2048
const TARGETS: Array[int] = [
	BiomeCatalog.FOREST,
	BiomeCatalog.SWAMP,
	BiomeCatalog.JUNGLE,
	BiomeCatalog.TAIGA,
]

var _failed := false


func _init() -> void:
	var generator := TerrainGenerator.new()
	generator.configure({
		"seed": SEED,
		"biome_scale": 896.0,
		"tree_density": 1.0,
		"decoration_density": 1.0,
	})
	var samples := {}
	var same_neighbors := 0
	var neighbor_pairs := 0
	for z in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1, SAMPLE_STEP):
		for x in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1, SAMPLE_STEP):
			var sample: Dictionary = generator.sample_point(x, z)
			samples[Vector2i(x, z)] = int(sample["dominant_biome_id"])
	var centers := _find_interior_centers(samples)
	for position: Vector2i in samples:
		for offset in [Vector2i(SAMPLE_STEP, 0), Vector2i(0, SAMPLE_STEP)]:
			if samples.has(position + offset):
				neighbor_pairs += 1
				if samples[position] == samples[position + offset]:
					same_neighbors += 1
	var coherence := float(same_neighbors) / float(neighbor_pairs)
	_check(coherence >= 0.55, "biome-neighbor coherence %.3f fell below 0.55" % coherence)
	for biome in TARGETS:
		_check(centers.has(biome), "could not find interior for %s" % BiomeCatalog.new().name_for(biome))
	if centers.size() == TARGETS.size():
		_verify_vegetation(generator, centers)
	if _failed:
		quit(1)
		return
	print("WORLDGEN BIOME VERIFY: PASS coherence=%.3f" % coherence)
	quit(0)


func _find_interior_centers(samples: Dictionary) -> Dictionary:
	var centers := {}
	var best_scores := {}
	for position: Vector2i in samples:
		var biome: int = samples[position]
		if biome not in TARGETS:
			continue
		var score := 0
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				if samples.get(position + Vector2i(dx * SAMPLE_STEP, dz * SAMPLE_STEP), -1) == biome:
					score += 1
		if score > int(best_scores.get(biome, -1)):
			best_scores[biome] = score
			centers[biome] = position
	_check(int(best_scores.get(BiomeCatalog.FOREST, 0)) >= 12, "forest no longer forms a broad interior")
	_check(int(best_scores.get(BiomeCatalog.SWAMP, 0)) >= 12, "swamp no longer forms a broad interior")
	_check(int(best_scores.get(BiomeCatalog.JUNGLE, 0)) >= 20, "jungle no longer forms a broad interior")
	_check(int(best_scores.get(BiomeCatalog.TAIGA, 0)) >= 20, "taiga no longer forms a broad interior")
	return centers


func _verify_vegetation(generator: TerrainGenerator, centers: Dictionary) -> void:
	var counts_by_biome := {}
	for biome in TARGETS:
		var center: Vector2i = centers[biome]
		var center_chunk := Vector2i(floori(float(center.x) / 16.0), floori(float(center.y) / 16.0))
		var counts := {}
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				var result := generator.generate_data(center_chunk + Vector2i(dx, dz), {}, false)
				for block_id in result.data:
					if block_id != BlockRegistry.BLOCK_AIR:
						counts[block_id] = counts.get(block_id, 0) + 1
		counts_by_biome[biome] = counts
		_check(int(counts.get(BlockRegistry.BLOCK_COBBLESTONE, 0)) == 0, "%s sample contains procedural cobblestone debris" % BiomeCatalog.new().name_for(biome))
	var forest: Dictionary = counts_by_biome[BiomeCatalog.FOREST]
	var swamp: Dictionary = counts_by_biome[BiomeCatalog.SWAMP]
	var jungle: Dictionary = counts_by_biome[BiomeCatalog.JUNGLE]
	var taiga: Dictionary = counts_by_biome[BiomeCatalog.TAIGA]
	_check(int(forest.get(BlockRegistry.BLOCK_LOG, 0)) >= 80, "forest interior is missing dense oak vegetation")
	_check(int(swamp.get(BlockRegistry.BLOCK_MANGROVE_LOG, 0)) >= 25, "swamp interior is missing mangroves")
	_check(int(swamp.get(BlockRegistry.BLOCK_VINE, 0)) >= 5, "swamp interior is missing vines")
	_check(int(jungle.get(BlockRegistry.BLOCK_JUNGLE_LOG, 0)) >= 150, "jungle interior is missing dense jungle trees")
	_check(int(jungle.get(BlockRegistry.BLOCK_VINE, 0)) >= 20, "jungle interior is missing vines")
	_check(int(taiga.get(BlockRegistry.BLOCK_SPRUCE_LOG, 0)) >= 150, "taiga interior is missing dense spruce vegetation")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error("worldgen_biome_verify: %s" % message)
