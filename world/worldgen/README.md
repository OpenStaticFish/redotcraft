# RedotCraft world generation

This directory contains a custom deterministic terrain pipeline inspired by
TerraForged's staged design. It is not a source port and does not target
TerraForged or Minecraft seed compatibility.

## Pipeline

`TerrainGenerator.configure()` constructs an immutable `WorldGenConfig` and the
catalogs/samplers used by worker jobs. A chunk then runs these ordered stages:

1. `TerrainSampler.build_field()` creates a seam-safe 18x18 field with expanded
   scratch rings for regional erosion and gradients.
2. Domain-warped continentalness and blended terrain profiles establish ocean,
   coast, plains, hills, plateaus, and mountain relief.
3. Analytic erosion, optional cached hydraulic erosion, and river carving alter
   heights before climate and surface selection.
4. Temperature/moisture choose primary and secondary biomes. Continuous fields
   shape terrain and tint foliage/water; primary biomes choose coherent surface
   blankets and decoration profiles without per-block biome dithering.
5. `VoxelPopulator.populate()` fills strata, carves caves, adds liquids and ore
   veins, stamps global-cell decorations, then applies player edits last.
6. `VoxelPopulator.populate_lod()` handles distance chunks: it writes compact
   per-column top/sub/water arrays instead of a full voxel volume and skips
   caves, ores, and ground flora. Real tree crowns are baked in using in-field
   anchors only and the shared stamp functions; site-validity probes are
   skipped because they leave the padded field and cost nearly full
   population. `ChunkMesher.build_lod()` consumes those arrays directly, and
   full chunks expand compact neighbors on the worker thread. Keep the compact
   and full surface choices in sync: both come from `_surface_rule_values()`.

All coordinates are global and all generation state is read-only after
configuration. Do not add mutable sampler caches or scene-tree access to worker
code. Any cache must be bounded, synchronized, and keyed by the complete config
revision. `VoxelWorld.configure()` must still run before chunk jobs are queued.

## Main tuning controls

Defaults and persisted values live in `autoload/game_config.gd`; validation and
ranges live in `world_gen_config.gd`.

- `terrain_scale`: multiplies local relief; Amplified applies an additional scale.
- `macro_scale`: size of continents and broad terrain regions.
- `biome_scale`: size of temperature/moisture regions, independent of landforms
  (default 3072 blocks; larger values make biome territories broader).
- `river_density`: controls channel-mask width and can disable rivers at zero.
- `erosion_strength`: local talus smoothing and profile terracing.
- `regional_erosion`: broad rainfall/transport erosion strength.
- `hydraulic_erosion`: deterministic 64x64 droplet tiles. This is deliberately
  off by default because cold generation is substantially slower.
- `cave_density`: worm, cavern, and mega-cave occurrence.
- `tree_density`: multiplier for tree-class decorations only.
- `decoration_density`: multiplier for all surface decoration.

Tune profile geometry in `terrain_profile_catalog.gd`, biome climate/layers/tints
in `biome_catalog.gd`, and weighted feature sets in `decoration_catalog.gd`.
Keep block IDs below 256 and add placeable blocks through `BlockRegistry` first.

Local detail is controlled separately from mountain height: each profile has
`FIELD_LOCAL_RELIEF` (24/64-block knolls and shoulders, with shallow 48-block
gullies in uplands) and `FIELD_SURFACE_DETAIL` (10-block undulations). These are
amplitudes in blocks, smoothly blended across profiles and faded near shores.
Increase these rather than shortening the mountain-region wavelength. The fine
layer is deliberately weakest in plains so walking terrain stays usable.

Forest, jungle, taiga, and swamp trees use broad deterministic grove fields with
dense interiors and open clearings. Spruce crowns use tapered whorls and an
exposed lower trunk; broadleaf crowns use short hash-directed limbs and
asymmetric rounded layers. Their maximum horizontal reach stays at three blocks,
within the six-block feature halo. Groves wider than a threshold strength grow
`FEATURE_ANCIENT_TREE` interiors with a full understory so forests have
old-growth cores. Ecological flags keep dry plants on sand, reeds and mangroves
near wet ground, and shade plants inside grove cover.
Ground cover mixes wildflowers into grass tufts, and a short bush layer (1-2
leaf blocks) sits between ground cover and trees. Deliberate props (pebbles,
rock outcrops, stumps, dead and large trees, fallen logs) and a floor-patch
pass (worn dirt, mud, gravel scars) add near-field detail; patches also apply
to compact LOD columns so distance matches. Raising any of these counts must be
checked against the full-generation budget in `worldgen_benchmark.gd`.

### Terrain-shape guardrails

- Mountain regions use the broad landform field, independently of ridge detail.
  Using short-scale ridges both to choose a profile and raise it produces needles.
- Blend noise **outputs** between profile frequencies. Blending frequencies first
  and multiplying by absolute world coordinates makes roughness grow with distance.
- Beaches are classified by waterline elevation, not an entire continentalness
  interval; otherwise sand blankets elevated coastal hills.
- Rivers carve only lowlands and share sea level for water fill. Do not place a
  source at `surface_y + 1` in every river-mask column; it makes raised ribbons.
- Surface snow uses the primary biome and a high-altitude cold band, never an
  independent random choice at every column. Alpine snow sits on stone.
- Wetland basins are gated by the lowland profile weight. The river mask boosts
  the shaping moisture, and a one-block channel-edge change without that gate
  can pull a tall mountain column tens of blocks into a basin in one step.
- Chunk fields and point/decoration queries classify climate at the same final
  height, so feature placement cannot disagree across chunk boundaries.
- Local relief is dominated by 80-block shoulders with a smaller 32-block knoll
  accent; the 13-block fine layer is a fraction of a block to two blocks. Keep
  the talus weight (`smoothstep(0.6, 5.5, gradient) * 0.33`) and profile fine
  amplitudes low or the surface reads as broken voxel steps. Isolated
  one-to-two block deviations are also relaxed 35% toward the local mean in
  `_final_from_raw_neighborhood`, which removes rice-terrace bumps on gentle
  ground without touching consistent slopes.

Terrain tuning changes the output for existing seeds. Restart into a fresh world
to review it; an already-running world retains its configured sampler and chunks.

## Diagnostics and verification

- F3 toggles live worldgen timings and a regional map.
- F4 cycles biome, final/raw height, slope, temperature, moisture,
  continentalness, river, and terrain-profile maps.
- `redot --headless --path . --script res://tools/worldgen_verify.gd` checks
  deterministic output, neighboring seams, edit priority, concurrent generation,
  biome/river coverage, height limits, field/point parity, flat-world height,
  coherent surface blankets, and adjacent height/slope limits plus the share of
  2-block steps (`rough_ratio`) near and far from the origin. These are
  regression guardrails, not a substitute for visual review.
- `redot --headless --path . --script res://tools/worldgen_benchmark.gd`
  records full and LOD voxel-generation time for pinned chunks.
- `redot --headless --path . --script res://tools/worldgen_mesh_benchmark.gd`
  records full and LOD mesh CPU time for pinned chunks.
- `redot --headless --path . --script res://tools/worldgen_tree_verify.gd`
  checks spruce taper/tips and repeatable, bounded broadleaf/spruce geometry
  across chunk edges. The main verifier also checks nonzero local detail and
  its amplitude budget, to guard against both flattening and runaway roughness.
- `redot --headless --path . --script res://tools/worldgen_biome_verify.gd`
  checks biome-neighbor coherence, contiguous forest/swamp/jungle/taiga territory
  radius, signature vegetation density, and the absence of procedural
  cobblestone debris.
- `redot --headless --path . res://tools/player_target_verify.tscn`
  checks that voxel traversal skips water and selects breakable cross plants even
  though their meshes intentionally have no movement collision.
- `redot --headless --path . --script res://tools/worldgen_lod_verify.gd`
  checks compact LOD columns against a decoration-free full chunk, distance-
  mesh top geometry, full chunks meshing against compact neighbors, baked tree
  crowns over forest chunks (never open water), and LOD occlusion shading that
  varies on hills while staying uniform on flat ground.
- `redot --headless --path . --script res://tools/stream_full_verify.gd`
  checks that the render distance really renders full chunks: no LOD inside
  the configured distance, collision only near the player, and collision added
  when approaching a distant chunk.
- `redot --headless --path . --script res://tools/worldgen_stream_benchmark.gd`
  records ring-load wall time and throughput at render distances 10/16/32 and
  several job-concurrency levels.

The pinned normal-generation sample currently averages about 40 ms for full
voxel generation and 12 ms for compact LOD data on the development machine.
Full mesh CPU remains much more expensive because it builds a 3x3 light volume,
floods sky and RGB light, computes AO, and emits collision triangles; keep that
work on workers and compare total chunk throughput when changing concurrency.
