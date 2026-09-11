# Graphics Upgrade Checklist

Engine-level rendering improvements for RedotCraft (Redot 4.x, Forward+).
Tick items as they land. Property names are included so each item is easy to find.

## Batch 1 — renderer settings
- [x] Volumetric fog + god rays — `Environment.volumetric_fog_*`; density is preset-driven (Low 0 / Medium 0.006 / High 0.01)
- [x] Screen-space reflections — `Environment.ssr_enabled`
- [x] Tonemapper — ACES by default (`tonemap=3`); AgX selectable in Advanced Graphics
- [x] Debanding — `rendering/anti_aliasing/quality/use_debanding=true`
- [x] FSR 2.2 upscaling — `rendering/scaling_3d/mode=2`; runtime scale from preset (0.66 / 0.77 / 0.9); TAA is auto-disabled by FSR2
- [x] Low/Medium/High graphics presets — `GameConfig.GRAPHICS_PRESETS`, Medium default
- [x] Colour grade — ACES + saturation/contrast lift to avoid the grey/gloomy look (per-preset values)

## Settings & presets
- [x] Preset selector in Settings panel (`graphics_preset`)
- [x] Full per-option menu — `ui/graphics_panel.tscn` ("Advanced Graphics..." in Settings); sections: Lighting, Shadows, Sky & Atmosphere, Post-Processing, Performance
- [x] Per-option overrides on top of a preset with "Custom" indicator + "Reset to Preset"
- [x] Graphics settings persist to `user://settings.cfg` (`[graphics] values` dictionary)

## Lighting
- [x] Block-light propagation — mesh-time BFS over a 3x3 chunk light volume in `ChunkMesher` (sky column pass + lateral flood, plus RGB block light seeded from emissive blocks); per-vertex light joined with AO and packed into `ARRAY_CUSTOM0`, baked by `world/block.gdshader` (sky occlusion in albedo, warm block light as emission). Runs on chunk worker threads; supersedes the old pooled `OmniLight3D` glowstone lights (removed)
- [ ] Sky-light pass optimization — the column walk costs ~8-9 ms/chunk; feed generator heightmaps into the light volume to skip it. Streaming at render distance 16 takes roughly 2x longer than before lighting
- [x] Torches — `world/block_registry.gd` `BLOCK_TORCH` (27) with `FLAG_CUTOUT | FLAG_CROSS | FLAG_EMISSIVE` and a warm entry in `EMISSIVE_COLORS`; `ChunkMesher` renders cross blocks as two intersecting inset quads (cell light, no AO, no collision), and the BFS seeds non-opaque emitters directly. Hotbar slot appended (scroll only); other emissive blocks only need a color entry
- [x] SDFGI — intentionally off in every preset: no update throttling, re-bakes every frame with a moving sun

## Sky / atmosphere
- [x] Custom sky shader (`shader_type sky`) — procedural stars + moon phases (8 in-game day lunar cycle, moon tied to the anti-sun direction)
- [ ] Milky way band + twinkle in the sky shader
- [ ] Weather particles — `GPUParticles3D` rain/snow/mist per biome, camera-following
- [ ] Volumetric mist — swamp-biome volumetric fog boost

## Geometry / materials
- [ ] `Texture2DArray` instead of the block atlas — removes UV/mip bleeding at distance
- [ ] Chunk merging / MultiMesh — fewer draw calls for distant chunks
- [ ] Chunk LOD meshes

## Post-processing extras
- [ ] Per-time-of-day color grading (animated `adjustment_*` or LUT texture)
- [x] Night glow tuning — `DayNightCycle` lowers `glow_hdr_threshold` from 1.15 (day) to 0.9 (night) so glowstone pools bloom after dark
- [ ] Water receives voxel light — the water shader ignores the light attribute, so water next to glowstone stays dark at night
- [ ] Tune volumetric fog density per time of day (`DayNightCycle` can animate it)
