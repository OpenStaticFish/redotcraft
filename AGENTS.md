# AGENTS.md

RedotCraft: a Minecraft-like voxel sandbox built with **Redot Engine** (Godot 4 fork, v26.2), GDScript only. There is no test suite, linter, typechecker, or CI. Verification = run the game and check output.

## Engine & tooling

- Use the **installed** engine only: `redot` from PATH (`/home/micqdf/.nix-profile/bin/redot`, 26.2-stable). `./run.sh` and the MCP server both use it. The source at `/home/micqdf/Code/redot-engine` is reference-only for enum/API checks — never build or run the local engine binary.
- The `redot` MCP server is configured in `.opencode/opencode.jsonc` (installed redot, `--headless --mcp-server --path <this repo>`). Restart opencode after editing that file; the running session keeps the old server.
- `redot_project_config run` / `stop` / `output` — launch the game, read logs and runtime errors. Do not use its `set_setting`: it rewrites `project.godot`; edit the file directly instead.
- `redot_game_control capture`, `type`, `trigger_action`, `inspect_live` — screenshots and input; `click` does not fire HUD/menu buttons. Avoid `inspect_live` with `recursive=true` (chunk meshes make the dump megabytes).
- `redot_code_intel validate` is a parse check only: it does not resolve unknown enum constants (e.g. `Viewport.SCALING_3D_MODE_OFF` passes but fails at runtime) and does not work on `.gdshader`. Shader compile errors appear in `output` after `run`.
- `redot_scene_action` can rewrite a `.tscn` lossily (it has dropped node script `ExtResource`s and added `= null` shader params). For isolated property changes prefer a targeted text edit; if you use it, review `git diff` and restore from git when it drops anything.
- A game-only `run` does not import new `.png` assets. Call `redot_project_config open_editor` once to trigger import; until then `inspect_asset` reports "not imported".
- `ROADMAP.md` is the single feature list. Press **F9** in-game to save a shadow-capture bundle (`game/shadow_capture.gd` -> `user://shadow_captures/`); `ROADMAP.md` records the measured shadow findings and ruled-out mitigations.

## Entry points

- `project.godot` main scene is `res://ui/main_menu.tscn`. Menus live in `ui/`; the `GameConfig` autoload (`autoload/game_config.gd`) carries settings and world config between scenes.
- `res://game/main.tscn` (`game/main.gd`) is the gameplay scene: World, Clouds, WorldEnvironment/Sun/SkyFill, Player, HUD, DayNight.
- World settings flow: `GameConfig.world` (`seed`, `world_type` 0 normal / 1 flat / 2 amplified, `terrain_scale`, `tree_density`) → `Main._apply_config()` → `VoxelWorld.configure()`. `configure()` must run before `setup_player()` and never while chunk jobs are in flight (recreating noise invalidates running workers).

## World system (world/)

- `voxel_defs.gd`: CHUNK_SIZE 16, WORLD_HEIGHT 128, SEA_LEVEL 32, collision layer 1, padded-neighbor face/AO tables. Shared by the mesher and clouds.
- `voxel_world.gd`: streams chunks around the player (default render_distance 10, unload +2); chunks beyond `lod_distance` (a third of the render distance, minimum 3) are built as distance (LOD) meshes with no collision/light volume, near chunks stay full detail. `Chunk.lod` tracks the mode; jobs carry it and stale transitions are requeued (also checked against `_stream_center` on commit, like edit versions). Chunk generation and meshing run on `WorkerThreadPool` threads that may only read immutable state (`BlockRegistry`, `TerrainGenerator`, `ChunkMesher`); only the main thread touches scene nodes. Player edits are kept in `_edited_blocks` and re-applied when chunks regenerate.
  - Spawning: `TerrainGenerator.find_spawn_position()` only knows terrain height, so `VoxelWorld.find_safe_spawn()` searches outward in the generated chunk data for a column whose topmost block is solid (not leaves) with two air cells above; `Main` calls it after `setup_player()`. It depends on which chunk jobs have committed, so the result varies run to run — pin `GameConfig.world["seed"]` and use `get_spawn_position()` (deterministic) for reproducible captures.
- `terrain_generator.gd`: FastNoiseLite biomes (plains/forest/desert/snow/swamp), caves, ores, tree stamping. Deterministic per seed, no mutable state after `configure()`.
- `chunk_mesher.gd`: produces one ArrayMesh per chunk, a separate water mesh, and ConcavePolygonShape3D collision (the last two only for full-detail chunks). `build_lod()` instead emits one top quad per column plus vertical runs of side quads down to the neighbor's top, sampling generated data and compact per-edge top arrays (`LodNeighbors`); heights match the full mesh so seams stay closed, and light is full sky. Face shading, ambient occlusion, and voxel light are baked per vertex. Before meshing, a 3x3-chunk block volume is assembled and flood-filled on the worker thread: the generator's per-column heightmap (`GenResult.heights`) seeds a sky-light pass, then a lateral BFS carries it indoors, and an RGB block-light BFS runs when emissive blocks are present. Per-vertex light is packed into `ARRAY_CUSTOM0` (`ARRAY_CUSTOM_RGBA_FLOAT`: block RGB + sky level) and the texture-array layer into `ARRAY_CUSTOM1` (`ARRAY_CUSTOM_R_FLOAT`); `world/block.gdshader` samples `vec3(UV, layer)`, multiplies sky light into albedo, and adds block light as emission. Any custom-attribute mesh needs the matching `Mesh.ARRAY_FORMAT_CUSTOM*` flags in `arrays_to_mesh()`, and `world/block.gdshader` replaces the old StandardMaterial3D.
- `block_registry.gd`: block table `BLOCK_DEFS` rows `[id, name, top, side, bottom, flags]`, packed into a runtime `Texture2DArray` (one 64px layer per texture; per-image tinting, edge fix-up, and mipmaps). `layer_for(block_id, face)` returns the layer the mesher writes per vertex.
  - To add a block: append a row using an existing texture filename from `assets/placeholders/zigcraft/default/`, then add it to `Main.HOTBAR` / `INITIAL_INVENTORY` if it should be placeable. A missing texture logs a warning and renders magenta.
  - Emissive blocks: add the id to `EMISSIVE_COLORS` (and `FLAG_EMISSIVE` on the def row). The mesher BFS seeds colored light from it; the existing light volume makes new sources work with no other changes.
  - Cross blocks (torches, plants): `FLAG_CROSS` meshes two intersecting inset quads instead of a cube, samples the cell's light without AO, and adds no collision. Torches combine `FLAG_CUTOUT | FLAG_CROSS | FLAG_EMISSIVE`.
  - IDs are stored in `PackedByteArray`, so stay under 256. `TEXTURE_TINTS` applies per-texture tinting (grass, leaves, sand, ...).
  - Cutout blocks (leaves, glass, torch) are antialiased with `alpha_to_coverage`, so their edge quality depends on MSAA being enabled.
- Water: `BLOCK_WATER` (16) is a source; IDs 28-34 are flowing levels 7..1, resolved through `BlockRegistry.is_water_id()`/`water_level()`/`water_id_for_level()`. `VoxelWorld` runs a 4 Hz cellular flow tick (`_water_tick`, 1024 cells/tick) seeded by breaks/places near water; flow replaces only air or weaker flowing water, falls when the cell below is air, and dries when unfed. Every change goes through `_record_edit()`, so the settled state is reapplied on chunk regeneration; `_edited_blocks` is mirrored into `_edits_by_chunk` so job snapshots and `TerrainGenerator.generate_data()` only see the chunk's own edits. Meshes are non-opaque, non-breakable, no collision and get the same `ARRAY_CUSTOM0` light attribute as blocks; flowing surfaces render at `_water_top(level)` and set vertex-color alpha so `water.gdshader` can calm the waves. `water.gdshader` samples `hint_screen_texture` for screen-space refraction (wave-distorted background with a faint chromatic split, carried through `EMISSION` so the refracted scene is not lit twice), `hint_depth_texture` for shore blending (shallow water is lighter, more transparent, and foams at the edge), and block light for warm glow. `VoxelWorld.is_water_at()` drives the HUD underwater overlay.

## Weather / atmosphere

- `world/weather_system.gd` toggles `SUNNY`/`RAIN`; the toggle button is in `ui/inventory_overlay.tscn` (signal `weather_toggled` -> `Main`). Rain particles follow the camera and stop when a raycast finds cover.
- `DayNightCycle.set_weather_dim(0..1)` owns the grading (sun/ambient energy, fog density, sky shader colors, cloud tint); `Main._apply_graphics()` sets `DayNightCycle.base_fog_density` so rain fog stacks on the preset value.
- `DayNightCycle` also owns the time-of-day colour grade: it scales `adjustment_saturation`/`adjustment_contrast` down at night (`base_saturation`/`base_contrast` come from the graphics preset) and animates `glow_hdr_threshold`.
- `world/sky.gdshader` draws stars, the milky way band, and the phased moon (`moon_phase` uniform, 8 in-game day lunar cycle); `DayNightCycle` feeds it colors and `star_intensity` (0 during the day).

## Graphics settings

- `autoload/game_config.gd` holds `GRAPHICS_PRESETS` (Low/Medium/High, plus custom values in `user://settings.cfg`); `ui/graphics_panel.gd` renders rows from its `SECTIONS` list and `Main._apply_graphics()` applies them. The user's saved custom values override preset keys, so graphics state can differ from the preset defaults.
- `soft_shadows` sets directional/positional PCF quality plus `Sun.light_angular_distance` (0 when off, giving hard but stable edges); `taa` sets `Viewport.use_taa` (FSR2 below 100% scale takes over temporal AA automatically); `fsr_scale` at 100% disables FSR2 and renders native; `_apply_graphics()` also forces `Viewport.anisotropic_filtering_level = ANISOTROPY_16X`.
- Adding a graphics key: add it to every `GRAPHICS_PRESETS` entry. `GameConfig.load_settings()` only copies saved values for keys that already exist in the preset, so existing user configs automatically pick up the preset default for new keys.

## Player / HUD contract

- `player/player.gd` talks to `Main` only through signals (`block_broken`, `block_placed`, `status_requested`, `slot_cycled`, `slot_selected`, `pause_requested`), connected in `Main._connect_player()`. Keep that pattern instead of reaching into nodes.
- Targeting raycasts hit collision geometry and derives the block from the hit position and normal; it does not read node metadata.
- Controls: WASD, Space jump, double-tap Space toggles fly, Shift sprint, 1-9/0 and mouse wheel select hotbar slot, LMB mine, RMB place, Esc pause (`ui_cancel`).

## Assets & licensing

- `assets/placeholders/zigcraft/` is a copy of OpenStaticFish/ZigCraft placeholder textures (MIT) plus `water.gdshader`, a Godot port of ZigCraft's Vulkan water shader.
- Some upstream textures originate from third-party packs (Classic Faithful 64x Jappa). Treat them as placeholders and verify upstream terms before redistribution. The attribution note is `assets/placeholders/zigcraft/README.md`; do not re-add ZigCraft's MIT license file (it was removed intentionally).

## Conventions

- GDScript style: `class_name` where useful, typed parameters/returns, snake_case filenames. Redot's parser is stricter than Godot's about `:=` inference when mixing Variant math; add an explicit type when validation complains.
- Prefer `.tscn` for static node setup (HUD, environment, lights in `game/main.tscn`) and keep gameplay logic in `game/`, `player/`, `ui/`, `world/`.
