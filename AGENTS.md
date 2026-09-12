# AGENTS.md

RedotCraft: a Minecraft-like voxel sandbox built with **Redot Engine** (Godot 4 fork, v26.2), GDScript only. There is no test suite, linter, typechecker, or CI. Verification = run the game and check output.

## Running & verification (use the Redot MCP tools)

- The `redot` MCP server is configured in `.opencode/opencode.jsonc`. Its command argument must be this repo root (the directory containing `project.godot`); if it points at the parent directory, `run` opens the Redot project-manager launcher instead of the game. Restart opencode after editing that file.
- `redot_project_config run` / `stop` / `output` — launch the game, read logs and runtime errors.
- `redot_game_control capture`, `click`, `type`, `trigger_action`, `inspect_live` — screenshots and input. Avoid `inspect_live` with `recursive=true`: chunk meshes make the dump megabytes large.
- `redot_code_intel validate` with `path=res://...gd` — GDScript parse check; run before launching. It does NOT work on `.gdshader` (misreports `shader_type`); shader compile errors appear in `redot_project_config output` after `run`.
- A game-only `run` does not import new `.png` assets. Call `redot_project_config open_editor` once to trigger import; until then `inspect_asset` reports "not imported".
- Use `redot_scene_action` to edit `.tscn` files rather than raw text edits.

## Entry points

- `project.godot` main scene is `res://ui/main_menu.tscn`. Menus live in `ui/`; the `GameConfig` autoload (`autoload/game_config.gd`) carries settings and world config between scenes.
- `res://game/main.tscn` (`game/main.gd`) is the gameplay scene: World, Clouds, WorldEnvironment/Sun/SkyFill, Player, HUD, DayNight.
- World settings flow: `GameConfig.world` (`seed`, `world_type` 0 normal / 1 flat / 2 amplified, `terrain_scale`, `tree_density`) → `Main._apply_config()` → `VoxelWorld.configure()`. `configure()` must run before `setup_player()` and never while chunk jobs are in flight (recreating noise invalidates running workers).

## World system (world/)

- `voxel_defs.gd`: CHUNK_SIZE 16, WORLD_HEIGHT 128, SEA_LEVEL 32, collision layer 1, padded-neighbor face/AO tables. Shared by the mesher and clouds.
- `voxel_world.gd`: streams chunks around the player (default render_distance 10, unload +2). Chunk generation and meshing run on `WorkerThreadPool` threads that may only read immutable state (`BlockRegistry`, `TerrainGenerator`, `ChunkMesher`); only the main thread touches scene nodes. Player edits are kept in `_edited_blocks` and re-applied when chunks regenerate.
  - Spawning: `TerrainGenerator.find_spawn_position()` only knows terrain height, so `VoxelWorld.find_safe_spawn()` searches outward in the generated chunk data for a column whose topmost block is solid (not leaves) with two air cells above; `Main` calls it after `setup_player()`.
- `terrain_generator.gd`: FastNoiseLite biomes (plains/forest/desert/snow/swamp), caves, ores, tree stamping. Deterministic per seed, no mutable state after `configure()`.
- `chunk_mesher.gd`: produces one ArrayMesh per chunk, a separate water mesh, and ConcavePolygonShape3D collision. Face shading, ambient occlusion, and voxel light are baked per vertex. Before meshing, a 3x3-chunk block volume is assembled and flood-filled on the worker thread: the generator's per-column heightmap (`GenResult.heights`) seeds a sky-light pass, then a lateral BFS carries it indoors, and an RGB block-light BFS runs when emissive blocks are present. Per-vertex light is packed into `ARRAY_CUSTOM0` (`ARRAY_CUSTOM_RGBA_FLOAT`: block RGB + sky level); `world/block.gdshader` multiplies sky light into albedo and adds block light as emission. Any custom-attribute mesh needs the `Mesh.ARRAY_FORMAT_CUSTOM0` flags in `arrays_to_mesh()`, and `world/block.gdshader` replaces the old StandardMaterial3D.
- `block_registry.gd`: block table `BLOCK_DEFS` rows `[id, name, top, side, bottom, flags]`, packed into a runtime texture atlas (8 columns, 64px tiles, 2px UV inset).
  - To add a block: append a row using an existing texture filename from `assets/placeholders/zigcraft/default/`, then add it to `Main.HOTBAR` / `INITIAL_INVENTORY` if it should be placeable. A missing texture logs a warning and renders magenta.
  - Emissive blocks: add the id to `EMISSIVE_COLORS` (and `FLAG_EMISSIVE` on the def row). The mesher BFS seeds colored light from it; the existing light volume makes new sources work with no other changes.
  - Cross blocks (torches, plants): `FLAG_CROSS` meshes two intersecting inset quads instead of a cube, samples the cell's light without AO, and adds no collision. Torches combine `FLAG_CUTOUT | FLAG_CROSS | FLAG_EMISSIVE`.
  - IDs are stored in `PackedByteArray`, so stay under 256. `TEXTURE_TINTS` applies per-texture tinting (grass, leaves, sand, ...).
- Water: non-opaque, non-breakable, no collision; meshed as its own surface. `VoxelWorld.is_water_at()` drives the HUD underwater overlay.

## Weather / atmosphere

- `world/weather_system.gd` toggles `SUNNY`/`RAIN`; the toggle button is in `ui/inventory_overlay.tscn` (signal `weather_toggled` -> `Main`). Rain particles follow the camera and stop when a raycast finds cover.
- `DayNightCycle.set_weather_dim(0..1)` owns the grading (sun/ambient energy, fog density, sky shader colors, cloud tint); `Main._apply_graphics()` sets `DayNightCycle.base_fog_density` so rain fog stacks on the preset value.
- `DayNightCycle` also owns the time-of-day colour grade: it scales `adjustment_saturation`/`adjustment_contrast` down at night (`base_saturation`/`base_contrast` come from the graphics preset) and animates `glow_hdr_threshold`.

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
