# RedotCraft Roadmap

One list of everything planned for RedotCraft (Redot 4.x, Forward+). Tick items as they land.
Property names and file references are included so each item is easy to find.

## Renderer settings
- [x] Volumetric fog + god rays — `Environment.volumetric_fog_*`; density is preset-driven (Low 0 / Medium 0.006 / High 0.01)
- [x] Screen-space reflections — `Environment.ssr_enabled`
- [x] Tonemapper — ACES by default (`tonemap=3`); AgX selectable in Advanced Graphics
- [x] Debanding — `rendering/anti_aliasing/quality/use_debanding=true`
- [x] FSR 2.2 upscaling — `rendering/scaling_3d/mode=2`; runtime scale from preset (0.66 / 0.77 / 0.9); TAA is auto-disabled by FSR2
- [x] Low/Medium/High graphics presets — `GameConfig.GRAPHICS_PRESETS`, Medium default
- [x] Colour grade — ACES + saturation/contrast lift to avoid the grey/gloomy look (per-preset values)
- [x] Preset selector in Settings panel (`graphics_preset`)
- [x] Full per-option menu — `ui/graphics_panel.tscn` ("Advanced Graphics..." in Settings); sections: Lighting, Shadows, Sky & Atmosphere, Post-Processing, Performance
- [x] Per-option overrides on top of a preset with "Custom" indicator + "Reset to Preset"
- [x] Graphics settings persist to `user://settings.cfg` (`[graphics] values` dictionary)
- [x] Render distance slider 4-32 chunks — `ui/settings_panel.gd` raises the cap from 16; full detail stays within 6 chunks (`VoxelWorld.MAX_FULL_DETAIL_DISTANCE`) and everything farther streams as compact LOD. Measured RD 32 ring (4225 chunks) drains in ~80 s in-game at 60 FPS on the test desktop

## Shadows
- [x] Near-shadow resolution — `Main.NEAR_SHADOW_DISTANCE` reserves the first cascade for 6 m around the player, keeping close-up shadow texels dense enough to stop edge crawl (user-confirmed fixed)
- [x] Directional atlas 4096 -> 8192 -> 16384 — `rendering/lights_and_shadows/directional_shadow/size` in `project.godot`; `Main._apply_graphics()` scales the narrow PCF blur by atlas resolution so its world-space width stays constant. Distant pulsation measured ~47% lower at 16384 (costs ~384 MiB VRAM), user-confirmed fixed
- [x] Narrow PCF on hard shadows — Medium directional filter at half blur width (`RenderingServer.directional_soft_shadow_filter_set_quality`) when `soft_shadows` is off; the soft-shadow toggle keeps its contact-hardening path
- [x] F9 shadow capture tool — `game/shadow_capture.gd` + `Main._get_shadow_capture_state()` save 30 lossless frames and per-frame camera/sun/time/pause/edits state to `user://shadow_captures/`, so reported artifacts can be replayed deterministically
- [ ] Residual angle-dependent edge aliasing on direct sun shadows — try `alpha_hash` for leaves, or shadow-only proxy geometry for solid canopy shadows (changes the dappled leaf-shadow look)
- [x] Cascade split ratios — `Main._apply_graphics()` reserves the first split for the 6 m near range and scales the remaining splits from it; together with the 16384 atlas this resolved the remaining distant pulsation. 32-bit shadow depth and extra PCF samples measured no benefit
- [ ] Isolate volumetric fog and SSIL/SSAO in a controlled A/B (both are temporally reprojected; never tested for localized shimmer)

## Lighting
- [x] Block-light propagation — mesh-time BFS over a 3x3 chunk light volume in `ChunkMesher` (sky column pass + lateral flood, plus RGB block light seeded from emissive blocks); per-vertex light joined with AO and packed into `ARRAY_CUSTOM0`, baked by `world/block.gdshader` (sky occlusion in albedo, warm block light as emission). Runs on chunk worker threads; supersedes the old pooled `OmniLight3D` glowstone lights (removed)
- [x] Sky-light pass optimization — `TerrainGenerator` now outputs a per-column top-block heightmap (`GenResult.heights`), threaded through `VoxelWorld` into the mesher's light volume; the sky pass starts at each column's top instead of walking from volume height. Measured chunk build 50.7 ms -> 33.3 ms (1.5x); baked light is unchanged apart from a 3-level approximation at some overhang faces
- [x] Torches — `world/block_registry.gd` `BLOCK_TORCH` (27) with `FLAG_CUTOUT | FLAG_CROSS | FLAG_EMISSIVE` and a warm entry in `EMISSIVE_COLORS`; `ChunkMesher` renders cross blocks as two intersecting inset quads (cell light, no AO, no collision), and the BFS seeds non-opaque emitters directly. Hotbar slot appended (scroll only); other emissive blocks only need a color entry
- [x] SDFGI — intentionally off in every preset: no update throttling, re-bakes every frame with a moving sun

## Sky / atmosphere
- [x] Custom sky shader (`shader_type sky`) — procedural stars + moon phases (8 in-game day lunar cycle, moon tied to the anti-sun direction)
- [x] Milky way band + twinkle — `world/sky.gdshader` fbm band with a broken-up dust lane, band-concentrated faint stars, and a per-star `TIME` twinkle; all gated by `star_intensity` so the day sky is unaffected, and `milky_way_intensity` defaults to 0.1 (a faint variation, not a beam)
- [x] Weather system — sunny/rain toggle button in the inventory overlay; rain is a camera-following billboarded `GPUParticles3D` field that pauses when under cover, and `DayNightCycle.set_weather_dim()` grades sun/ambient/fog/sky/clouds toward overcast
- [ ] Snow and swamp mist per biome, plus weather ambience (sound) — biome-aware fog particles; overlaps with the audio pass below
- [ ] Weather depth — thunder/lightning, snow in cold biomes, wind sway on leaves

## Geometry / materials
- [x] `Texture2DArray` instead of the block atlas — `BlockRegistry` now builds one 64px layer per texture (per-image tint, alpha edge fix-up, mipmaps) and the mesher writes each face's layer into `ARRAY_CUSTOM1` (`ARRAY_CUSTOM_R_FLOAT`); `block.gdshader` samples `vec3(UV, layer)`, so there is no atlas inset and no cross-tile UV/mip bleeding
- [ ] Chunk merging / MultiMesh — fewer draw calls for distant chunks
- [x] Chunk LOD meshes — `ChunkMesher.build_lod()` distance meshes (top quad per column + exposed side runs, no light volume/AO/collision) for chunks beyond `lod_distance` (a third of the render distance, capped at 6 chunks); full detail stays near the player and rebuilds LOD<->full on approach/retreat with the same version checks as edits. Distance chunks carry compact per-column top/sub/water arrays (~3 KB) instead of a full 192-block data array (~50 KB), and full chunks expand compact neighbors on worker threads for correct light and culling. Pinned benchmark: full mesh CPU averages ~181 ms vs ~13 ms for LOD, and LOD generation ~12 ms vs ~41 ms full

## Post-processing
- [x] Per-time-of-day color grading — `DayNightCycle` scales preset saturation/contrast at night (`Main._apply_graphics()` sets `base_saturation`/`base_contrast`), keeping nights muted instead of neon
- [x] Night glow tuning — `DayNightCycle` lowers `glow_hdr_threshold` from 1.15 (day) to 1.05 (night); glowstone light is emissive, so the old 0.9 threshold caused a bloom sheen on water and other bright pixels
- [x] Water receives voxel light — `ChunkMesher._append_water_face()` samples the same light volume (front cell + diagonal smoothing) and writes `MeshResult.water_light` into the water mesh's `ARRAY_CUSTOM0`; `water.gdshader` multiplies sky light into albedo and adds block light as `EMISSION`, matching `block.gdshader`
- [ ] Tune volumetric fog density per time of day (`DayNightCycle` can animate it)

## Gameplay
- [ ] World saving/loading — persist `VoxelWorld._edited_blocks`, player position/inventory, and world config per world (biggest missing gameplay feature)

## Audio
- [ ] Audio pass — footsteps, block break/place, UI clicks, and rain ambience (needs audio assets)

## World generation overhaul
Current state: the TerraForged-inspired staged pipeline is live under `world/worldgen/`. It builds immutable padded terrain fields, domain-warped continents and blended profiles, analytic erosion and optional cached hydraulic erosion, river/coast masks, climate-selected biomes, data-driven surfaces, caves/ores, and deterministic cross-chunk decoration. `TerrainGenerator` remains an immutable worker-safe facade. The world is 192 blocks high with sea level 48; generation verification and live F3/F4 diagnostics are available for tuning.

### Research / decisions (do first)
- [x] Choose the world-gen reference model — use a custom RedotCraft pipeline inspired by TerraForged 0.3.x, not a literal port. TerraForged's useful pattern is staged data generation (continent/terrain profiles -> erosion/rivers -> climate/biomes -> voxel fill -> surfaces/caves/decorations), but the archived project depends on an unavailable `Engine` module and Minecraft-specific chunk, registry, structure, and decoration APIs. Reimplement the ideas with `FastNoiseLite`, immutable GDScript data, and Redot's worker pool; do not target seed- or output-compatibility.
- [x] Define the first architecture — generate one padded 18x18 `ChunkTerrainData` field per chunk (one-cell border for gradients) containing height, base height, slope, continentalness, river mask, temperature, moisture, terrain profile, and biome. Consume that same snapshot in ordered passes: macro geography and blended terrain profiles; cheap erosion/slope shaping and river carving; voxel fill; surface/subsurface rules; caves/ores; deterministic vegetation. Keep it local to the worker job initially; only add a bounded `(seed, config revision, chunk)` cache if profiling shows repeated sampling is material.
- [x] Decide the vertical range — use 192 blocks with sea level 48. Heightmaps now use `PackedInt32Array` and `ChunkMesher.LOD_NONE = -1`, removing the old byte sentinel conflict. A 256-block range was unnecessary after sampled peaks stayed below the 192-block cap. Normal full generation averages ~40 ms over the pinned benchmark chunks; LOD generation averages ~25 ms.
- [x] Define the biome set and layers — 15 biomes now provide climate centers, surface/subsurface/underwater blocks, soil depth, foliage and water tint, and weighted decoration sets; smooth profile/climate fields plus deterministic dithering avoid hard block-border transitions.
- [x] Expose worldgen tuning — the world-creation panel adds Landmass Scale, River Density, Slope Erosion, Regional Erosion, a Hydraulic Erosion (quality) toggle, Cave Density, and Ground Cover to the existing seed/type/terrain/tree controls (`ui/world_gen_panel.gd`); `GameConfig.DEFAULT_WORLD` stores them and `WorldGenConfig.CURRENT_VERSION` version-tags new worlds for future migration.

### TerraForged-inspired implementation phases
- [x] Phase 0 — worldgen diagnostics: F3 opens an asynchronous metrics/map overlay and F4 cycles nine map modes (biome, final and raw height, slope, temperature, moisture, continentalness, river, profile). Generation reports terrain/population timings and `VoxelWorld` tracks generation/mesh EMAs.
- [x] Phase 1 — macro terrain: the 18x18 field separates continent/ocean/coast level from relief and smoothly blends plains, hills, plateau, mountain, and ridged-mountain profiles across domain-warped regions.
- [x] Phase 2 — rivers and analytic erosion: padded gradients drive talus smoothing and terracing, regional rainfall/transport modifiers shape slopes, and continuous river masks carve valleys before surface filling. River water is limited to lowland channels to avoid isolated mountaintop ribbons.
- [x] Phase 3 — climate and biome layers: large-scale warped temperature/moisture fields select and blend climate biomes, with explicit ocean, deep-ocean, beach, river, and highland overrides.
- [x] Phase 4 — surfaces and decoration: biome catalogs own layer/tint/feature rules, and global hash-cell origins let trees and larger decorations cross chunk edges independently of generation order.
- [x] Phase 5 — cave regions: deterministic worm segments, bounded caverns, rare multi-lobed mega-caves, aquifers/lava, ore veins, and sparse cave decoration run after surface fill with surface/river protection.
- [x] Phase 6 — optional regional hydraulic erosion: deterministic 64x64 droplet tiles are cached by immutable worldgen configuration and sampled seam-safely. It remains off by default because a cold tile solve is intentionally a high-quality/slower option.
- [x] Phase 7 — streaming robustness: every chunk job carries a worldgen config revision, so results generated under an old configuration are discarded and requeued; worker concurrency scales with half the logical cores (4-8) after measuring 8 jobs ~40% faster than 4 while 16 added only ~10% more.
- [x] Phase 8 — compact distance chunks: LOD population writes per-column top/sub/water arrays instead of a full 192-block data array, making far chunks ~3x cheaper to generate and kilobyte-sized. Decorations (including distant tree canopies) are omitted from LOD on purpose: the full tree pass costs ~6 ms per chunk, which would halve the streaming gain. Measured 8-job ring loads: RD 10 ~4.2 s (was ~5.9), RD 16 ~10.7 s (was ~14.0), RD 32 ~31 s with full detail capped at 6.

### Terrain and biomes
- [x] Vertical limit fix — 192-block storage, typed heights, profile-specific relief, and sampled cap verification remove the old flat-topped 104-block limit.
- [x] Continentalness/ocean/coast system — separate continent, ocean/deep-ocean, beach, and lowland river fields plus deterministic coarse-to-fine spawn search.
- [x] Climate-driven biomes with smooth transitions — warped temperature/moisture fields, secondary-biome blend weights, deterministic dithering, and live debug maps.
- [x] Per-biome terrain shaping — smooth climate weights add wetland basins, dry dunes/terraces, tropical relief, and sharper cold highlands on top of blended terrain profiles.
- [x] Expanded biome list — plains, forest, desert, snow, swamp, ocean, deep ocean, beach, river, jungle, savanna, taiga, badlands, meadow, and highlands, each with layers, tint, and vegetation metadata.
- [x] Surface/subsurface rules — biome topsoil depths, stone/gravel/clay and badlands strata, snow bands, cliff exposure, and underwater materials.

### Vegetation and ground cover
- [x] Ground-cover system — tinted grasses/flowers, mushrooms, reeds, vines, bamboo, bushes, cacti, and biome-specific small plants use cutout/cross meshes without collision.
- [x] Deterministic per-chunk scatter — global hash-cell placement and neighboring-origin evaluation keep decoration seam-safe and worker-order independent.
- [x] Vegetation density and variety pass — oak, birch, spruce, acacia, jungle, and mangrove forms plus bushes, fallen logs, boulders, melons, bamboo, and cacti; `tree_density` and `decoration_density` remain configurable.
- [x] Foliage colour variation — per-column biome tints are carried into full and LOD mesh vertex colors; water has independent biome tinting.

### Caves and underground
- [x] Phase 1 — wormhole tunnels: connected cell-anchored tunnel segments and sparse seam-safe diagonal surface entrances replace the old per-voxel threshold caves.
- [x] Phase 2 — large caverns: cell-anchored varied caverns and rare mega-caves, lava lakes, aquifers, damp floor patches, and ceiling/floor stone formations.
- [x] Phase 3 — underground features: deep cobblestone variation, damp mud/mycelium cave patches, depth-banded ore veins, aquifers, lava pockets, and stone formations. Mineshafts/ruins remain separate future structure work.
- [ ] Cave-aware lighting and meshing — verify sky-light flood fill around large openings, that caves stay dark, and that `ChunkMesher` light-volume bounds hold for big caverns.
- [x] Ore distribution overhaul — deterministic cell-anchored coal, iron, and gold vein segments use depth bands and replace stone after caves are carved.
- [x] Cave performance guardrails — cell-anchored carving replaces full-height 3D cave scans; clipped ellipsoids hoist column limits, aquifer decisions are chunk-local, and normal full generation averages ~40 ms in the pinned CLI benchmark.

### Verification
- [x] Tree integrity / groves / cactus closure — fuller connected broadleaf crowns cover limb ends; immutable tree-site decisions and overlap regressions prevent chunk-owner/canopy disagreements. Forest, taiga, and jungle use a dedicated deterministic grove field with denser patches and clearings while respecting density controls. Cactus placeholder margins are cropped in runtime texture preparation to close cube edges/caps; opacity and stacked-mesh tests pass. Forward+ grove and cactus captures inspected.
- [x] Grass/shore material cleanup — foliage tint blends climate colors instead of per-column biome dithering; sparse independently scattered crossed-quad grass grows only on exposed grass soil. Shallow seabeds retain thicker sand shelves before deep gravel. Water uses sharp, weak refraction without chromatic separation, faint foam, and depth-dependent absorption rather than vivid surface patterns. Generation regressions and Forward+ close-up captures checked.
- [x] Restore detail between large landforms and individual blocks — profile-tuned 24/64-block knolls/shoulders, shallow upland gullies, and low-amplitude 10-block surface variation preserve broad terrain without returning to needles. Spruce now has tapered whorls; broadleaf crowns have bounded hash-directed limbs. Added detail-amplitude and tree-boundary regressions.
- [x] Correct the first overhaul's visual regressions — decouple broad mountain regions from fine ridge detail, blend fixed-frequency noise outputs, restrict beaches to the waterline, replace dithered surface snow with coherent blankets, and keep river carving/water in lowlands. Added field/point parity, flat-world, surface-blanket, and multi-seed near/far roughness checks. Pinned-seed Forward+ mountain/lowland captures were inspected; this does not imply final art direction or performance acceptance.
- [x] Seeded worldgen verification — `tools/worldgen_verify.gd` checks repeatability, seams, edits, concurrency, biome distribution, rivers, height caps, field/point parity, flat-world height, surface blankets, and near/far roughness; F9 capture metadata includes worldgen parameters and the F3/F4 overlay supports pinned-seed visual tours.
- [x] Vegetation and texture regressions — `tools/worldgen_tree_verify.gd` checks crown connectivity, footprints, chunk borders, site rejection, and density controls; `tools/worldgen_cactus_verify.gd` checks prepared-texture opacity and closed stacked meshes.
- [x] Pinned benchmarks — `tools/worldgen_benchmark.gd` and `tools/worldgen_mesh_benchmark.gd` record full/LOD generation and mesh CPU times for fixed chunks.
- [x] LOD seam verification — `tools/worldgen_lod_verify.gd` compares compact columns against a decoration-free full chunk (top/sub/water, height map), checks distance-mesh top-face geometry, and meshes a full chunk against compact neighbor samples.
- [x] Streaming benchmark — `tools/worldgen_stream_benchmark.gd` records ring-load wall time and throughput at render distances 10/16/32 with 4/8/16 concurrent jobs.
- [x] Perf budget — recorded at render distance 32 across six representative biomes plus spawn (ocean, snow, jungle, forest, badlands, desert): max ~3.8k draw calls, ~3.1M primitives, ~286 MB process memory, ~1.28 GB VRAM at 60 FPS (2048 test shadow atlas; the production 16384 atlas adds ~0.5 GB). Pinned generation/mesh/streaming benchmarks and F3 EMAs cover CPU cost, and mesher work stays worker-thread safe and deterministic per seed.

## World / simulation
- [x] Water polish — flowing water levels (IDs 28-34) with a 4 Hz cellular spill/dry sim seeded by edits, falling cascades, settled state persisted through `_edited_blocks`; the mesher renders `_water_top(level)` surfaces with a flowing vertex-color flag. `water.gdshader` uses sharp, gently distorted scene refraction with chromatic split disabled, progressive depth absorption, and faint narrow shore foam.
