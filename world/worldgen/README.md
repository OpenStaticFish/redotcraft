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
3. Analytic erosion and optional cached hydraulic erosion shape raw heights;
   the river channel is then carved from cached corridor fields, and climate
   shaping/smoothing follows before surface selection.
4. Temperature/moisture choose primary and secondary biomes. Continuous fields
   shape terrain and tint foliage/water; broad terrain-aware ecotones carry the
   secondary biome into coherent surface and vegetation patches without
   per-block biome dithering.
5. `VoxelPopulator.populate()` fills strata, carves caves, adds liquids and ore
   veins, cave biomes/dressing and geodes, stamps global-cell surface
   decorations, then applies player edits last.
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
- `river_density`: scales channel and floodplain width and can disable rivers at
  zero (default 1.0). Meandering, bank taper, and bed depth are tuning constants
  in `terrain_sampler.gd` (`RIVER_*`).
- `erosion_strength`: local talus smoothing and profile terracing.
- `regional_erosion`: broad rainfall/transport erosion strength.
- `hydraulic_erosion`: deterministic 64x64 droplet tiles. This is deliberately
  off by default because cold generation is substantially slower.
- `cave_density`: spaghetti thickness plus cross-link, chamber, cavern, and
  mega-cave frequency. A thin canonical trunk remains at every nonzero value.
- `tree_density`: multiplier for tree-class decorations only.
- `decoration_density`: multiplier for all surface decoration.

Tune profile geometry in `terrain_profile_catalog.gd`, biome climate/layers/tints
in `biome_catalog.gd`, and weighted feature sets in `decoration_catalog.gd`.
The underwater split constants (shelf/abyss depths, patch scales, biome
temperature/depth gates) live at the top of `terrain_sampler.gd`.
Keep block IDs below 256 and add placeable blocks through `BlockRegistry` first.

### Caves and geodes

Cave geometry is a hybrid based on the systems used by modern Minecraft and
Luanti/Minetest. Two absolute-coordinate 3D ridge fields are intersected to
produce organic, seam-free "spaghetti" tunnels; a low-frequency cheese field
opens irregular chambers. Those fields are unioned with a global 48-block graph
in five depth bands. Every graph node owns a curved east-or-south trunk, making
each route mathematically unbounded instead of a short random walk; deterministic
cross-links, one vertical connector per column, node chambers, cell caverns, and
rare mega-caves create loops and changes of scale. Chunks enumerate graph owners
through a 64-block halo and clip stamps locally, so results do not depend on load
order. Surface entrances continue from their protected mouth to a canonical
graph node rather than ending blindly in stone.

Cave biomes are a separate 3D layer in `BiomeCatalog.cave_biome_at()`, not
surface climate IDs. Broad global regions cover most underground territory:
lush caves dominate the damp middle depths, while deep dark and lush regions
share the lowest cavern band. `VoxelPopulator` only applies
their materials to stone exposed beside cave air: lush regions grow moss and
hanging cave growth, while deep-dark regions spread deepstone and faintly
emissive sculk. A sparse four-block lattice finds floors and ceilings for
dripstone, columns, and shallow pools without a full-volume decoration scan.
Surface entrances use the same deterministic anchor test as tree exclusion and
have an 18% candidate rate at default density (about 150 blocks mean spacing
before biome rejection), making natural access far less dependent on blind
digging. The HUD and environment ambience scan to the loaded column top, so tall
mega-caves show their cave-biome identity as well.

Geodes use 72-block global cells plus an 11-block halo (roughly one candidate
per thirteen cells), so every touched chunk
clips the same sphere independently. Their shell, calcite lining, hollow center,
amethyst deposits, and crystal buds run after ores/liquids and before cave
dressing; player edits remain the final authoritative stage. Generated cave
textures live in `assets/placeholders/caves/` and are reproducible through
`tools/gen_underwater_textures.gd` (which owns both generated texture sets).

`ChunkMesher` lights a 3x3 footprint because sky and block light have only 15
levels and cannot contribute from beyond that pad. Missing neighbor tiles are
opaque light boundaries until loaded, while face culling still uses the normal
neighbor snapshot. All eight sampled chunks invalidate one another on commits
and edits. `tools/worldgen_cave_verify.gd` checks a sealed cavern, a remote cave
opening and finite falloff, colored crystal emission, exact volume bounds, cave
materials/vegetation, pools, dripstone, and hollow geode layers. It also follows
a canonical trunk for 128 macro cells and flood-fills a separately carved 5x5
chunk fixture, requiring one component to span the region in X/Z and depth.

Large and small offshore islands are separate sparse peak fields layered onto
effective continentalness at 720- and 135-block scales. They are coast-gated
against the original mainland field, so they leave continental interiors and
shorelines coherent. Terrain profiles, climate, surfaces, vegetation, and LOD
all consume the combined field; river masks deliberately retain the mainland
field so analytic corridors do not arbitrarily slice detached islands.

Biome boundaries expose `ecotone_strength` alongside primary, secondary, and
dominant biome IDs. Climate-distance closeness controls transition width, terrain
affinity bends the mix toward suitable elevations/profiles, and a 160-block noise
field selects coherent secondary-material and decoration patches. Consumers must
use `dominant_biome` for discrete surface/vegetation choices and keep the smooth
primary/secondary blend for foliage and water tinting.

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

### Rivers

The channel centreline is the zero level set of a low-frequency noise with a
native `FastNoiseLite` domain warp, so reaches meander instead of following the
raw contour's straight segments and sharp corners. `_river_distance_at()`
converts the corridor value into blocks with `|n| / |grad n|` (forward
differences), which makes the wetted width independent of the local noise
gradient; the old gradient-space mask pinched to nothing in steep areas and
fanned into wide pans in flat areas. Width and bed-depth variation are sampled
unwarped because they only need coherence and point queries pay for every extra
noise call.

The cross-section is dished rather than a flat sea-relative pan: a nearly flat
thalweg at `RIVER_BED_DEPTH` (± pool/riffle variation), a bank run of
`RIVER_BANK_WIDTH` up to a floodplain crest, then a `RIVER_FLOODPLAIN_WIDTH`
apron that fades the carve into natural terrain. Terrain relief and fine detail
are damped inside a corridor-space floodplain apron so the cut blends into
graded ground. The carve runs on the eroded raw height in `build_field()` (and
`_raw_height_at()`), after regional/hydraulic erosion and before final
smoothing; the same cached corridor and distance grids feed both, so
field/point parity and seams hold. The lowland and continental gates keep
channels sea-connected and prevent cuts through uplands; only downward motion
is applied, so natural hollows are never filled.

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

### Underwater biomes

`OCEAN` and `DEEP_OCEAN` (IDs 5/6, displayed as shelf sea / deep sea) are split
into six water biomes: shelf sea, deep sea, coral reef, kelp forest, seagrass
meadow, and frozen sea. `TerrainSampler._ocean_floor_at()` uses the same
continental band as classification, so label and geometry cannot disagree: a
broad shelf across most of the ocean band, a steeper continental slope, and an
abyssal basin (SEA_LEVEL - 2.5 down to SEA_LEVEL - 19). Reef mounds rise up to
`REEF_MOUND_HEIGHT` on the mid-shelf, low seabed noise keeps long floors from
reading flat, and the result is clamped below the waterline so shaping never
creates dry land.

`TerrainSampler._underwater_biome()` labels the final height and the same
patch fields that shape the mounds: cold water becomes frozen sea,
`DEEP_SEA_DEPTH` or deeper is deep sea, and coral (warm, <= 12 deep), kelp
(cold/temperate, >= 4 deep), and seagrass (temperate/warm, <= 12 deep) patches
cover the remaining shelf with plain shelf sea as the fallback. Do not replace
the patch fields with hard depth stripes: bands read as artificial rings, and
patch scales must stay well above the biome sampling stride so territories stay
coherent. Seabed substrate is depth- and biome-led from
`BiomeCatalog.seabed_block()`/`seabed_subsurface()`; keep the waterline
`SHELF_SAND_DEPTH` rule so beaches never meet a foreign material.

`BiomeCatalog.is_ocean_biome()` is the single list used by spawn search, cave
entrances, and the LOD canopy check, so a new sea biome cannot be forgotten.

Seabed materials layer by depth and biome (`seabed_block()` /
`seabed_subsurface()`): waterline sand, then clay, silt, gravel, or coral
substrate, with exposed steps showing the buried layer. The abyssal floor mixes
gravel banks into the silt. The placeholder textures for the underwater blocks
live in `assets/placeholders/underwater/` and are generated by
`tools/gen_underwater_textures.gd`.

Seabed vegetation is a separate global-lattice pass
(`VoxelPopulator._decorate_underwater()`, `DecorationCatalog._underwater_sets`)
so the land feature lottery never touches water. It is `decoration_density`
gated, replaces water cells only, caps plant height by local depth, and is
skipped by compact LOD chunks. Reef, kelp, meadow, shelf, abyssal, and frozen
sets control species mix and per-cell density; raising those counts must be
checked against the full-generation budget in `worldgen_benchmark.gd`.

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
  2-block steps (`rough_ratio`) near and far from the origin. It also checks
  that all six underwater biomes appear at the right depth/climate, that no land
  biome strands below sea level, that reef mounds raise the shelf floor without
  breaking the water surface, and that seabed plants stay on their biome's
  floor, honour `decoration_density`, and never break the surface. These are
  regression guardrails, not a substitute for visual review.
- `redot --headless --path . --script res://tools/worldgen_benchmark.gd`
  records full and LOD voxel-generation time for pinned chunks.
- `redot --headless --path . --script res://tools/worldgen_cave_verify.gd`
  checks cave-biome classification and dressing, hollow layered geodes, crystal
  emission, sealed cave darkness, opening falloff, and mesher light bounds.
- `redot --headless --path . --script res://tools/worldgen_mesh_benchmark.gd`
  records full and LOD mesh CPU time for pinned chunks.
- `redot --headless --path . --script res://tools/worldgen_tree_verify.gd`
  checks spruce taper/tips and repeatable, bounded broadleaf/spruce geometry
  across chunk edges. The main verifier also checks nonzero local detail and
  its amplitude budget, to guard against both flattening and runaway roughness.
- `redot --headless --path . --script res://tools/worldgen_biome_verify.gd`
  checks biome-neighbor coherence, ecotone width and secondary ownership,
  contiguous forest/swamp/jungle/taiga territory radius, signature vegetation
  density, and the absence of procedural cobblestone debris.
- `redot --headless --path . --script res://tools/worldgen_island_verify.gd`
  finds connected offshore uplift components at both island scales, confirms
  each scale produces dry non-ocean terrain, and proves established mainland
  continentalness is unchanged.
- `redot --headless --path . --script res://tools/worldgen_river_verify.gd`
  checks river naturalization: bounded-channel wetted width (interquartile ratio
  at most 1.8), a dished cross-section instead of a constant-depth pan, tapered
  low-step banks, graded floodplains, and reach depth variation. Measured 1.5-1.65
  width ratios against 1.9-2.5 for the old gradient-space mask.
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

The pinned normal-generation sample currently averages about 44 ms for full
voxel generation and 15 ms for compact LOD data on the development machine.
Full mesh CPU remains much more expensive because it builds a 3x3 light volume,
floods sky and RGB light, computes AO, and emits collision triangles; keep that
work on workers and compare total chunk throughput when changing concurrency.
