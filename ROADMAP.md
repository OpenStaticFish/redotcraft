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
- [ ] Chunk LOD meshes — cheaper distant geometry (biggest rendering win)

## Post-processing
- [x] Per-time-of-day color grading — `DayNightCycle` scales preset saturation/contrast at night (`Main._apply_graphics()` sets `base_saturation`/`base_contrast`), keeping nights muted instead of neon
- [x] Night glow tuning — `DayNightCycle` lowers `glow_hdr_threshold` from 1.15 (day) to 1.05 (night); glowstone light is emissive, so the old 0.9 threshold caused a bloom sheen on water and other bright pixels
- [x] Water receives voxel light — `ChunkMesher._append_water_face()` samples the same light volume (front cell + diagonal smoothing) and writes `MeshResult.water_light` into the water mesh's `ARRAY_CUSTOM0`; `water.gdshader` multiplies sky light into albedo and adds block light as `EMISSION`, matching `block.gdshader`
- [ ] Tune volumetric fog density per time of day (`DayNightCycle` can animate it)

## Gameplay
- [ ] World saving/loading — persist `VoxelWorld._edited_blocks`, player position/inventory, and world config per world (biggest missing gameplay feature)

## Audio
- [ ] Audio pass — footsteps, block break/place, UI clicks, and rain ambience (needs audio assets)

## World / simulation
- [ ] Water polish — flowing water and better shore blending; water is currently a static block with a wavy shader
