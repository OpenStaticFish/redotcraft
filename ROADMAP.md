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
- [x] Render distance slider 4-32 chunks — `ui/settings_panel.gd` raises the cap from 16; full detail extends to half the render distance, capped at 8 chunks (`VoxelWorld.MAX_FULL_DETAIL_DISTANCE`), and everything farther streams as compact LOD. An "Extreme" toggle to the right of the slider raises the cap to 100 chunks and shows an inline load-time/memory warning. Measured RD 32 ring (4225 chunks) drains in ~80 s in-game at 60 FPS on the test desktop

## Interface
- [x] Deepslate & Ember UI overhaul — shared `UITheme`, bundled Iosevka typography, reusable motion and generated controls, dusk voxel title screen, sectioned settings/world creation, responsive inventory, texture-derived isometric block icons, compact telemetry HUD, item hotbar, focus restoration, and nested-modal cancel handling. Architecture notes live in `ui/README.md`

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
- [x] Chunk LOD meshes — `ChunkMesher.build_lod()` distance meshes (top quad per column + exposed side runs, no light volume/AO/collision) for chunks beyond `lod_distance` (half the render distance, capped at 8 chunks); full detail stays near the player and rebuilds LOD<->full on approach/retreat with the same version checks as edits. Distance chunks carry compact per-column top/sub/water arrays (~3 KB) instead of a full 192-block data array (~50 KB), and full chunks expand compact neighbors on worker threads for correct light and culling. Pinned benchmark: full mesh CPU averages ~181 ms vs ~13 ms for LOD, and LOD generation ~12 ms vs ~41 ms full
- [x] LOD tree canopies — compact columns bake the actual tree crowns using the same stamp functions as full chunks. Distance collection keeps only anchors inside the padded field and skips site-validity probes, which leave the field and re-enter the sampler (full parity cost ~19 ms per forest chunk, nearly full population). The top two tree blocks become the column's solid/sub pair, so distance forests read as real trees. Measured: LOD generation ~12.2 ms vs ~28.4 ms full, with the canopy pass ~1.2 ms; grove sample 142 canopy columns, open-ocean sample 0. `worldgen_lod_verify.gd` checks forest coverage and ocean exclusion
- [x] LOD occlusion shading — distance meshes carry no AO or block-light volume, so far terrain read flat and cliffs showed a single soil stripe to the ground. Top faces now darken under taller cardinal neighbors (`LOD_AO_PER_BLOCK` 0.14, floor 0.52), side faces darken with depth, and sides below `LOD_SOIL_DEPTH` switch to stone (leaf columns stay leaf-textured). Pinned verification: flat spread 0.0000, hilly spread 1.5036, 5273 stone side faces; LOD mesh stays ~14 ms vs ~183 ms full
- [ ] LOD ground cover — compact chunks only carry tree crowns, so distant fields look bare next to the full-detail ring. Bake a cheap per-column grass/flower/scrub mask into the compact arrays or emit a low-cost instanced scatter so far terrain reads as vegetated

## Post-processing
- [x] Per-time-of-day color grading — `DayNightCycle` scales preset saturation/contrast at night (`Main._apply_graphics()` sets `base_saturation`/`base_contrast`), keeping nights muted instead of neon
- [x] Night glow tuning — `DayNightCycle` lowers `glow_hdr_threshold` from 1.15 (day) to 1.05 (night); glowstone light is emissive, so the old 0.9 threshold caused a bloom sheen on water and other bright pixels
- [x] Water receives voxel light — `ChunkMesher._append_water_face()` samples the same light volume (front cell + diagonal smoothing) and writes `MeshResult.water_light` into the water mesh's `ARRAY_CUSTOM0`; `water.gdshader` multiplies sky light into albedo and adds block light as `EMISSION`, matching `block.gdshader`
- [ ] Water self-glow at night — water stays visibly bright after dark while the surrounding terrain goes black. The constant `tint * (0.06 + fresnel * 0.10)` term and the `max(light_data.a, 0.05)` floors in `assets/placeholders/zigcraft/water.gdshader` add unlit color regardless of sky light; scale them by sky light and re-check night/shore captures
- [ ] Tune volumetric fog density per time of day (`DayNightCycle` can animate it)

## Gameplay
- [ ] World saving/loading — persist `VoxelWorld._edited_blocks`, player position/inventory, and world config per world (biggest missing gameplay feature)
- [x] Fly boost — holding Ctrl while flying multiplies fly speed and acceleration 5x (`player/player.gd` `FLY_BOOST_MULTIPLIER`); pause menu controls updated

## Audio
- [x] Audio pass — `autoload/audio_manager.gd` adds SFX/Ambient buses, pooled 3D players, and a block-material registry; distance-based material-aware footsteps in `player/player.gd`, uniform subtle 3D block break/place cues for every block type, UI clicks wired through `UITheme` button styles, and a fading rain bed tied to `WeatherSystem`. All cues are recorded free assets with no synthesized bank: VoxeLibre `mcl_sounds` for material footsteps and the uniform block break/place cues (Minecraft-style; mixed CC BY-SA 3.0 / CC BY 3.0 / CC0 per file), Kenney UI Audio, and an OpenGameArt CC0 rain loop. Settings gained a Sound section with Master/SFX/Ambience sliders persisted through `GameConfig`; `tools/audio_verify.gd` checks the recordings, buses, mappings, and rejects any leftover placeholder WAV

## World generation overhaul
Current state: the TerraForged-inspired staged pipeline is live under `world/worldgen/`. It builds immutable padded terrain fields, domain-warped continents and blended profiles, analytic erosion and optional cached hydraulic erosion, river/coast masks, climate-selected biomes, data-driven surfaces, caves/ores, and deterministic cross-chunk decoration. `TerrainGenerator` remains an immutable worker-safe facade. The world is 192 blocks high with sea level 48; generation verification and live F3/F4 diagnostics are available for tuning.

### Research / decisions (do first)
- [x] Choose the world-gen reference model — use a custom RedotCraft pipeline inspired by TerraForged 0.3.x, not a literal port. TerraForged's useful pattern is staged data generation (continent/terrain profiles -> erosion/rivers -> climate/biomes -> voxel fill -> surfaces/caves/decorations), but the archived project depends on an unavailable `Engine` module and Minecraft-specific chunk, registry, structure, and decoration APIs. Reimplement the ideas with `FastNoiseLite`, immutable GDScript data, and Redot's worker pool; do not target seed- or output-compatibility.
- [x] Define the first architecture — generate one padded 18x18 `ChunkTerrainData` field per chunk (one-cell border for gradients) containing height, base height, slope, continentalness, river mask, temperature, moisture, terrain profile, and biome. Consume that same snapshot in ordered passes: macro geography and blended terrain profiles; cheap erosion/slope shaping and river carving; voxel fill; surface/subsurface rules; caves/ores; deterministic vegetation. Keep it local to the worker job initially; only add a bounded `(seed, config revision, chunk)` cache if profiling shows repeated sampling is material.
- [x] Decide the vertical range — use 192 blocks with sea level 48. Heightmaps now use `PackedInt32Array` and `ChunkMesher.LOD_NONE = -1`, removing the old byte sentinel conflict. A 256-block range was unnecessary after sampled peaks stayed below the 192-block cap. Normal full generation averages ~40 ms over the pinned benchmark chunks; LOD generation averages ~25 ms.
- [x] Define the biome set and layers — 15 biomes now provide climate centers, surface/subsurface/underwater blocks, soil depth, foliage and water tint, and weighted decoration sets; broad smooth climate fields give each column a coherent primary biome while continuous secondary blends preserve tint transitions.
- [x] Expose worldgen tuning — the world-creation panel adds independent Landmass and Biome Scale controls, River Density, Slope Erosion, Regional Erosion, a Hydraulic Erosion (quality) toggle, Cave Density, and Ground Cover to the existing seed/type/terrain/tree controls (`ui/world_gen_panel.gd`); `GameConfig.DEFAULT_WORLD` stores them and `WorldGenConfig.CURRENT_VERSION` version-tags new worlds for future migration.

### TerraForged-inspired implementation phases
- [x] Phase 0 — worldgen diagnostics: F3 opens an asynchronous metrics/map overlay and F4 cycles nine map modes (biome, final and raw height, slope, temperature, moisture, continentalness, river, profile). Generation reports terrain/population timings and `VoxelWorld` tracks generation/mesh EMAs.
- [x] Phase 1 — macro terrain: the 18x18 field separates continent/ocean/coast level from relief and smoothly blends plains, hills, plateau, mountain, and ridged-mountain profiles across domain-warped regions.
- [x] Phase 2 — rivers and analytic erosion: padded gradients drive talus smoothing and terracing, regional rainfall/transport modifiers shape slopes, and continuous river masks carve valleys before surface filling. River water is limited to lowland channels to avoid isolated mountaintop ribbons.
- [x] Phase 3 — climate and biome layers: large-scale warped temperature/moisture fields select and blend climate biomes, with explicit ocean, deep-ocean, beach, river, and highland overrides.
- [x] Phase 4 — surfaces and decoration: biome catalogs own layer/tint/feature rules, and global hash-cell origins let trees and larger decorations cross chunk edges independently of generation order.
- [x] Phase 5 — cave regions: deterministic worm segments, bounded caverns, rare multi-lobed mega-caves, aquifers/lava, ore veins, and sparse cave decoration run after surface fill with surface/river protection.
- [x] Phase 6 — optional regional hydraulic erosion: deterministic 64x64 droplet tiles are cached by immutable worldgen configuration and sampled seam-safely. It remains off by default because a cold tile solve is intentionally a high-quality/slower option.
- [x] Phase 7 — streaming robustness: every chunk job carries a worldgen config revision, so results generated under an old configuration are discarded and requeued; worker concurrency scales with half the logical cores (4-8) after measuring 8 jobs ~40% faster than 4 while 16 added only ~10% more.
- [x] Phase 8 — compact distance chunks: LOD population writes per-column top/sub/water arrays instead of a full 192-block data array, making far chunks ~3x cheaper to generate and kilobyte-sized. Ground flora, caves, ores, and sparse decorations are omitted from LOD; real tree crowns from in-field anchors are baked into the compact columns (LOD ~12 ms vs ~28 ms full). Measured 8-job ring loads: RD 10 ~4.2 s (was ~5.9), RD 16 ~10.7 s (was ~14.0), RD 32 ~31 s; full detail now extends up to 8 chunks so dense biome vegetation remains visible farther out.

### Terrain and biomes
- [x] Vertical limit fix — 192-block storage, typed heights, profile-specific relief, and sampled cap verification remove the old flat-topped 104-block limit.
- [x] Continentalness/ocean/coast system — separate continent, ocean/deep-ocean, beach, and lowland river fields plus deterministic coarse-to-fine spawn search.
- [x] Climate-driven biomes with smooth transitions — independently scaled warped temperature/moisture fields, coherent primary-biome regions, continuous secondary tint blends, and live debug maps.
- [x] Per-biome terrain shaping — smooth climate weights add wetland basins, dry dunes/terraces, tropical relief, and sharper cold highlands on top of blended terrain profiles.
- [x] Expanded biome list — plains, forest, desert, snow, swamp, ocean, deep ocean, beach, river, jungle, savanna, taiga, badlands, meadow, and highlands, each with layers, tint, and vegetation metadata.
- [x] Surface/subsurface rules — biome topsoil depths, stone/gravel/clay and badlands strata, snow bands, cliff exposure, and underwater materials.
- [x] Smooth terrain surface — local relief now rides on 80-block shoulders (`0.85`) with a small 32-block knoll accent (`0.15`) and a 13-block fine layer, profile fine amplitudes were cut roughly 40%, talus smoothing widened and strengthened (`smoothstep(0.6, 5.5)`, `0.33`), and plateau terracing softened (`0.38 -> 0.22`). Pinned continuity improved max step 5.75 -> 4.89, mean 0.481 -> 0.459, and adjacent steps above 2 blocks 2.44% -> 1.87% (new `rough_ratio` guardrail, max 6%). Shaded-relief render and Forward+ review show rolling land without lost macro relief
- [ ] River and cut naturalization — river channels and carved erosion cuts look angular and artificial. Add meandering, tapered banks, floodplain grading, and smoother channel profiles that blend into the surrounding terrain
- [ ] Biome transition accuracy — improve how neighboring biomes merge: broader organic ecotones, terrain-aware boundaries, and blended surface materials/vegetation near edges instead of abrupt climate cutoffs
- [ ] Island generation — land/water distribution rarely produces islands. Add large island landmasses plus small offshore islands while keeping continents coherent
- [ ] Landmark terrain — standout natural features: waterfalls where rivers meet cliffs, ravines, natural arches, and boulder fields. Should read as memorable landmarks rather than adding back procedural noise
- [x] Larger biome regions — default `biome_scale` doubled from 896 to 1792 blocks (worldgen version 3; world-creation slider now reaches 4096), so temperature/moisture fields and their terrain-shaping weights span broad territories. `tools/worldgen_biome_verify.gd` now measures contiguous territory radius: 72 blocks at the old scale vs 115 at 1792, with neighbor coherence 0.609. Restoring the `lowland` gate on wetland basins was required: without it the broader river-mask influence pulled a 119-block mountain river edge down 19 blocks in one step and tripped the terrain-continuity guardrail

### Vegetation and ground cover
- [x] Ground-cover system — tinted grasses/flowers, mushrooms, reeds, vines, bamboo, bushes, cacti, and biome-specific small plants use cutout/cross meshes without collision.
- [x] Deterministic per-chunk scatter — global hash-cell placement and neighboring-origin evaluation keep decoration seam-safe and worker-order independent.
- [x] Vegetation density and variety pass — oak, birch, spruce, acacia, jungle, and mangrove forms plus biome-specific grasses, flowers, reeds, vines, melons, bamboo, and cacti; `tree_density` and `decoration_density` remain configurable. Stray boulders/fallen logs were removed from active surface sets.
- [x] Foliage colour variation — per-column biome tints are carried into full and LOD mesh vertex colors; water has independent biome tinting.
- [ ] Vegetation density pass — increase tree, grass, flower, foliage, and small-detail counts across biomes. Layer ground cover, shrubs, and trees so dense areas feel full without exceeding the current worker-thread generation budget

### Underwater biomes and foliage
- [ ] Underwater biome overhaul — `OCEAN` and `DEEP_OCEAN` are single global biomes with `DECORATION_NONE`. Split them into depth- and climate-appropriate underwater biomes (shallow shelf sea, deep sea, coral reef, kelp forest, seagrass meadow, cold/frozen sea) with seabed terrain shaping for shelves, drop-offs, and reef mounds so each position reads naturally
- [ ] Seabed blocks and textures — overhaul underwater surface/subsurface materials (sand, gravel, clay, mud, coral substrate, stone) with depth-appropriate layering and new textures; add the required blocks to `BlockRegistry`
- [ ] Underwater vegetation — add seagrass, kelp, coral fans/branches, sponges, and anemone-like cross/cutout plants attached to the seabed, biome-driven and density-controlled like land flora
- [ ] Underwater lighting and ambience — make depth readable underwater: stronger light attenuation and fog with depth (bright shallows, dark deep ocean), biome-tinted water, and surface caustics; muffled audio overlaps the existing audio pass

### Structures and points of interest
- [ ] Structures / POIs — deterministic, seam-safe ruins, abandoned camps, mineshafts, and watchtowers placed from global anchors. Must respect player edits and regenerate consistently across chunks; loot and inventory hooks stay with the gameplay pass

### Caves and underground
- [x] Phase 1 — wormhole tunnels: connected cell-anchored tunnel segments and sparse seam-safe diagonal surface entrances replace the old per-voxel threshold caves.
- [x] Phase 2 — large caverns: cell-anchored varied caverns and rare mega-caves, lava lakes, aquifers, damp floor patches, and ceiling/floor stone formations.
- [x] Phase 3 — underground features: damp mud/mycelium cave patches, depth-banded ore veins, aquifers, lava pockets, and stone formations. Random deep cobblestone variation was removed so cobblestone remains player-made; mineshafts/ruins remain separate future structure work.
- [ ] Cave-aware lighting and meshing — verify sky-light flood fill around large openings, that caves stay dark, and that `ChunkMesher` light-volume bounds hold for big caverns.
- [x] Ore distribution overhaul — deterministic cell-anchored coal, iron, and gold vein segments use depth bands and replace stone after caves are carved.
- [x] Cave performance guardrails — cell-anchored carving replaces full-height 3D cave scans; clipped ellipsoids hoist column limits, aquifer decisions are chunk-local, and normal full generation averages ~40 ms in the pinned CLI benchmark.

### Verification
- [x] Tree integrity / groves / cactus closure — fuller connected broadleaf crowns cover limb ends; immutable tree-site decisions and overlap regressions prevent chunk-owner/canopy disagreements. Forest, taiga, and jungle use a dedicated deterministic grove field with denser patches and clearings while respecting density controls. Cactus placeholder margins are cropped in runtime texture preparation to close cube edges/caps; opacity and stacked-mesh tests pass. Forward+ grove and cactus captures inspected.
- [x] Grass/shore material cleanup — foliage tint blends climate colors instead of per-column biome dithering; sparse independently scattered crossed-quad grass grows only on exposed grass soil. Shallow seabeds retain thicker sand shelves before deep gravel. Water uses sharp, weak refraction without chromatic separation, faint foam, and depth-dependent absorption rather than vivid surface patterns. Generation regressions and Forward+ close-up captures checked.
- [x] Restore detail between large landforms and individual blocks — profile-tuned 24/64-block knolls/shoulders, shallow upland gullies, and low-amplitude 10-block surface variation preserve broad terrain without returning to needles. Spruce now has tapered whorls; broadleaf crowns have bounded hash-directed limbs. Added detail-amplitude and tree-boundary regressions.
- [x] Correct the first overhaul's visual regressions — decouple broad mountain regions from fine ridge detail, blend fixed-frequency noise outputs, restrict beaches to the waterline, replace dithered surface snow with coherent blankets, and keep river carving/water in lowlands. Added field/point parity, flat-world, surface-blanket, and multi-seed near/far roughness checks. Pinned-seed Forward+ mountain/lowland captures were inspected; this does not imply final art direction or performance acceptance.
- [x] Biome identity and vegetation cleanup — biome scale is independent from landmass scale, primary-biome ownership no longer creates one-block checkerboards, dense forest/jungle/taiga/swamp groves retain clearings, wetland shaping forms coherent low basins, and ecological placement flags constrain dry, shore, and shade flora. Removed procedural surface debris and random underground cobblestone; direct voxel-grid targeting makes non-colliding cross plants breakable. Pinned seed `918273` sampled coherent biome interiors with forest oak, swamp mangrove/vines, jungle trees/vines, taiga spruce, and zero cobblestone across the sampled regions.
- [x] Seeded worldgen verification — `tools/worldgen_verify.gd` checks repeatability, seams, edits, concurrency, biome distribution, rivers, height caps, field/point parity, flat-world height, surface blankets, and near/far roughness; F9 capture metadata includes worldgen parameters and the F3/F4 overlay supports pinned-seed visual tours.
- [x] Vegetation and texture regressions — `tools/worldgen_tree_verify.gd` checks crown connectivity, footprints, chunk borders, site rejection, and density controls; `tools/worldgen_cactus_verify.gd` checks prepared-texture opacity and closed stacked meshes.
- [x] Pinned benchmarks — `tools/worldgen_benchmark.gd` and `tools/worldgen_mesh_benchmark.gd` record full/LOD generation and mesh CPU times for fixed chunks.
- [x] LOD seam verification — `tools/worldgen_lod_verify.gd` compares compact columns against a decoration-free full chunk (top/sub/water, height map), checks distance-mesh top-face geometry, and meshes a full chunk against compact neighbor samples.
- [x] Streaming benchmark — `tools/worldgen_stream_benchmark.gd` records ring-load wall time and throughput at render distances 10/16/32 with 4/8/16 concurrent jobs.
- [x] Perf budget — recorded at render distance 32 across six representative biomes plus spawn (ocean, snow, jungle, forest, badlands, desert): max ~3.8k draw calls, ~3.1M primitives, ~286 MB process memory, ~1.28 GB VRAM at 60 FPS (2048 test shadow atlas; the production 16384 atlas adds ~0.5 GB). Pinned generation/mesh/streaming benchmarks and F3 EMAs cover CPU cost, and mesher work stays worker-thread safe and deterministic per seed.

## World / simulation
- [x] Water polish — flowing water levels (IDs 28-34) with a 4 Hz cellular spill/dry sim seeded by edits, falling cascades, settled state persisted through `_edited_blocks`; the mesher renders `_water_top(level)` surfaces with a flowing vertex-color flag. `water.gdshader` uses sharp, gently distorted scene refraction with chromatic split disabled, progressive depth absorption, and faint narrow shore foam.
- [ ] Ambient life — fireflies at night, butterflies/birds by day, and subtle particle life with per-biome density and time-of-day gating; fireflies can reuse the emissive block-light path for glow
