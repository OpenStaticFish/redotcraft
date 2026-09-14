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
		"biome_scale": 3072.0,
		"tree_density": 1.0,
		"decoration_density": 1.0,
	})
	var samples := {}
	var secondary_samples := {}
	var same_neighbors := 0
	var neighbor_pairs := 0
	var transition_count := 0
	var secondary_owned := 0
	for z in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1, SAMPLE_STEP):
		for x in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1, SAMPLE_STEP):
			var sample: Dictionary = generator.sample_point(x, z)
			var position := Vector2i(x, z)
			samples[position] = int(sample["dominant_biome_id"])
			if float(sample["ecotone_strength"]) >= 0.25:
				transition_count += 1
				if int(sample["dominant_biome_id"]) != int(sample["biome_id"]):
					secondary_owned += 1
					secondary_samples[position] = int(sample["dominant_biome_id"])
	var centers := _find_interior_centers(generator, samples)
	for position: Vector2i in samples:
		for offset in [Vector2i(SAMPLE_STEP, 0), Vector2i(0, SAMPLE_STEP)]:
			if samples.has(position + offset):
				neighbor_pairs += 1
				if samples[position] == samples[position + offset]:
					same_neighbors += 1
	var coherence := float(same_neighbors) / float(neighbor_pairs)
	# Ecotone patches intentionally lower exact-biome agreement while remaining
	# far above checkerboard randomness. Interior-radius checks below separately
	# protect the broad primary territories.
	_check(coherence >= 0.49, "biome-neighbor coherence %.3f fell below 0.49" % coherence)
	var transition_share := float(transition_count) / float(samples.size())
	var secondary_share := float(secondary_owned) / float(maxi(transition_count, 1))
	var coherent_secondary_links := 0
	var secondary_link_slots := 0
	for position: Vector2i in secondary_samples:
		for offset in [Vector2i(SAMPLE_STEP, 0), Vector2i(0, SAMPLE_STEP)]:
			secondary_link_slots += 1
			if secondary_samples.get(position + offset, -1) == secondary_samples[position]:
				coherent_secondary_links += 1
	var secondary_coherence := float(coherent_secondary_links) / float(maxi(secondary_link_slots, 1))
	_check(transition_share >= 0.08, "ecotones became too narrow (%.3f of samples)" % transition_share)
	_check(transition_share <= 0.55, "ecotones swallowed biome interiors (%.3f of samples)" % transition_share)
	_check(secondary_share >= 0.03, "ecotones no longer blend secondary surface/vegetation patches (%.3f)" % secondary_share)
	_check(secondary_coherence >= 0.08, "secondary ecotone ownership fragmented into isolated columns (%.3f coherence)" % secondary_coherence)
	for biome in TARGETS:
		_check(centers.has(biome), "could not find interior for %s" % BiomeCatalog.new().name_for(biome))
	if centers.size() == TARGETS.size():
		_verify_region_sizes(generator, samples, centers)
		_verify_vegetation(generator, centers)
	if _failed:
		quit(1)
		return
	print("WORLDGEN BIOME VERIFY: PASS coherence=%.3f ecotones=%.3f secondary=%.3f patch_coherence=%.3f" % [coherence, transition_share, secondary_share, secondary_coherence])
	quit(0)


func _find_interior_centers(generator: TerrainGenerator, samples: Dictionary) -> Dictionary:
	var centers := {}
	var best_scores := {}
	for position: Vector2i in samples:
		var biome: int = samples[position]
		if biome not in TARGETS:
			continue
		var score := _interior_score(generator, samples, position, biome)
		if score > int(best_scores.get(biome, -1)):
			best_scores[biome] = score
			centers[biome] = position
	# The coarse 32-block lattice can place the best sample on a bent biome
	# boundary. Refine locally so density checks sample a genuine interior
	# instead of an ill-placed edge that depends on the sampling grid.
	for biome in TARGETS:
		if not centers.has(biome):
			continue
		var best_position: Vector2i = centers[biome]
		var best_score: int = int(best_scores[biome])
		for dz in range(-4, 5):
			for dx in range(-4, 5):
				var candidate: Vector2i = centers[biome] + Vector2i(dx, dz) * 16
				var candidate_score := _interior_score(generator, samples, candidate, biome)
				if candidate_score > best_score:
					best_score = candidate_score
					best_position = candidate
		centers[biome] = best_position
		best_scores[biome] = best_score
	_check(int(best_scores.get(BiomeCatalog.FOREST, 0)) >= 12, "forest no longer forms a broad interior")
	_check(int(best_scores.get(BiomeCatalog.SWAMP, 0)) >= 12, "swamp no longer forms a broad interior")
	_check(int(best_scores.get(BiomeCatalog.JUNGLE, 0)) >= 20, "jungle no longer forms a broad interior")
	_check(int(best_scores.get(BiomeCatalog.TAIGA, 0)) >= 20, "taiga no longer forms a broad interior")
	return centers


func _interior_score(generator: TerrainGenerator, samples: Dictionary, center: Vector2i, biome: int) -> int:
	var score := 0
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var position := center + Vector2i(dx * SAMPLE_STEP, dz * SAMPLE_STEP)
			if not samples.has(position):
				samples[position] = int(generator.sample_point(position.x, position.y)["dominant_biome_id"])
			if samples[position] == biome:
				score += 1
	return score


## A biome can score full marks on a 5x5 lattice while still being a narrow
## ribbon. Walk outward from the interior until the dominant biome changes so
## the regression tracks territory size rather than just local coherence.
func _verify_region_sizes(generator: TerrainGenerator, samples: Dictionary, centers: Dictionary) -> void:
	var radius_total := 0
	var direction_count := 4 * TARGETS.size()
	for biome in TARGETS:
		var center: Vector2i = centers[biome]
		for direction in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var distance := 0
			while distance < 1024:
				distance += 16
				var position: Vector2i = center + direction * distance
				if not samples.has(position):
					samples[position] = int(generator.sample_point(position.x, position.y)["dominant_biome_id"])
				if samples[position] != biome:
					break
			radius_total += distance - 16
	var average_radius := radius_total / direction_count
	# Measured 72 blocks at the old 896 scale and 115 at 1792; 96 keeps the
	# larger-region guarantee while allowing ordinary boundary variation.
	_check(average_radius >= 96, "biome territories collapsed into patches (average radius %d blocks)" % average_radius)
	print("WORLDGEN BIOME REGIONS: average_radius=%d blocks" % average_radius)


func _verify_vegetation(generator: TerrainGenerator, centers: Dictionary) -> void:
	var counts_by_biome := {}
	for biome in TARGETS:
		var center: Vector2i = centers[biome]
		var center_chunk := Vector2i(floori(float(center.x) / 16.0), floori(float(center.y) / 16.0))
		var counts := {}
		# Larger biomes need a wider sample: one dense grove can otherwise
		# dominate or miss a 5x5 window at the chosen interior.
		for dz in range(-3, 4):
			for dx in range(-3, 4):
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
	_check(int(forest.get(BlockRegistry.BLOCK_LOG, 0)) >= 150, "forest interior is missing dense oak vegetation")
	_check(int(swamp.get(BlockRegistry.BLOCK_MANGROVE_LOG, 0)) >= 50, "swamp interior is missing mangroves")
	_check(int(jungle.get(BlockRegistry.BLOCK_JUNGLE_LOG, 0)) >= 300, "jungle interior is missing dense jungle trees")
	_check(int(jungle.get(BlockRegistry.BLOCK_VINE, 0)) >= 20, "jungle interior is missing vines")
	_check(int(taiga.get(BlockRegistry.BLOCK_SPRUCE_LOG, 0)) >= 300, "taiga interior is missing dense spruce vegetation")
	print("WORLDGEN BIOME DENSITY: forest_oak=%d swamp_mangrove=%d swamp_vine=%d jungle_log=%d jungle_vine=%d taiga_spruce=%d" % [
		int(forest.get(BlockRegistry.BLOCK_LOG, 0)),
		int(swamp.get(BlockRegistry.BLOCK_MANGROVE_LOG, 0)),
		int(swamp.get(BlockRegistry.BLOCK_VINE, 0)),
		int(jungle.get(BlockRegistry.BLOCK_JUNGLE_LOG, 0)),
		int(jungle.get(BlockRegistry.BLOCK_VINE, 0)),
		int(taiga.get(BlockRegistry.BLOCK_SPRUCE_LOG, 0))])
	var forest_grass := int(forest.get(BlockRegistry.BLOCK_TALL_GRASS, 0))
	var forest_flowers := int(forest.get(BlockRegistry.BLOCK_YELLOW_FLOWER, 0)) + int(forest.get(BlockRegistry.BLOCK_RED_FLOWER, 0))
	var taiga_grass := int(taiga.get(BlockRegistry.BLOCK_TALL_GRASS, 0))
	var jungle_bamboo := int(jungle.get(BlockRegistry.BLOCK_BAMBOO, 0))
	var swamp_reeds := int(swamp.get(BlockRegistry.BLOCK_TALL_GRASS, 0))
	_check(forest_grass >= 250, "forest ground cover thinned out (%d tall grass)" % forest_grass)
	_check(forest_flowers >= 40, "forest flowers thinned out (%d)" % forest_flowers)
	_check(taiga_grass >= 200, "taiga ground cover thinned out (%d tall grass)" % taiga_grass)
	_check(jungle_bamboo >= 100, "jungle bamboo thinned out (%d)" % jungle_bamboo)
	print("WORLDGEN BIOME COVER: forest_grass=%d forest_flowers=%d taiga_grass=%d jungle_bamboo=%d swamp_reeds=%d" % [
		forest_grass, forest_flowers, taiga_grass, jungle_bamboo, swamp_reeds])


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error("worldgen_biome_verify: %s" % message)
