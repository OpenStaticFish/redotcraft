# RedotCraft UI

The interface uses a shared "Deepslate & Ember" design system built from native Redot `Control` nodes.

## Foundations

- `ui_theme.gd` owns palette, typography, spacing, style boxes, generated control textures, and small component factories. Screens apply it with `UITheme.apply(root)` (which registers the host for live scale refresh) and size fonts through `UITheme.apply_font_size()` so the Display text-size setting can rescale them.
- `motion.gd` owns the restrained entrance, selection, and status tween vocabulary.
- `block_icon.gd` renders cached isometric item icons from `BlockRegistry.texture_array`; UI icons therefore stay synchronized with world textures.
- `minimap.gd` (corner HUD map, `]`) and `map_overlay.gd` (full-screen `M` atlas with wheel/`+`/`-` zoom and drag/arrow pan) both sample `VoxelWorld.request_debug_map()` on worker threads, so refreshes reuse the F3 overlay's modes and never block the frame; `map_view.gd` holds their shared view projection and color packing, and `N` cycles modes.
- Static hierarchy remains in `.tscn` scenes. Scripts compose dynamic rows, inventory slots, HUD slots, and decorative title-screen layers.
- Iosevka font subsets and their license live in `assets/fonts/`.

## Visual Language

- Slate surfaces and hairline borders establish hierarchy without heavy texture assets.
- Ember is reserved for primary actions, focus, and selection.
- Cyan is reserved for values, quantities, and telemetry.
- Eyebrows, dividers, modal chrome, form rows, and button variants come from `UITheme` rather than per-screen styling.

## Menu hierarchy

- **Play** opens `play_panel`, a landing hub: **Continue** (ember, when a last
  saved world exists), **New World**, and **Load World** (disabled while the
  library is empty). **New World** reveals the creation form (world type, seed,
  clipboard import, Create Game); its **Advanced** button opens
  `world_gen_panel`, which owns only the detailed world tunables;
  `build_config()` returns them and the play screen merges seed/type in.
  **Load World** lists every saved world (name, type, seed, created, last
  played) via `WorldStorage.list_world_summaries()`, which does not rewrite the
  "last world" pointer. Cards select on first
  activation, load on the second (or double-click, or Load World); Delete
  swaps the footer for an inline confirmation whose safe choice takes focus.
  Incompatible worlds (newer metadata/worldgen format) list but cannot load.
  `ui_cancel` unwinds one layer at a time: delete confirmation -> load list or
  create form -> landing -> main menu, restoring focus to each layer's opener.
- **Settings** opens `settings_menu`, a category hub. Categories are
  `settings_category_panel` instances (`category` property): Display (render
  distance + extreme toggle, FOV, fullscreen, UI scale, text size, V-Sync, FPS
  cap, dynamic resolution + target), Graphics (preset + advanced),
  Sound (three buses), Gameplay (mouse sensitivity), and Controls (key
  rebinding). `controls_panel` extends `settings_category_panel` and builds one
  row per `GameConfig.rebindable_actions()` entry; clicking a key starts capture
  and `GameConfig` applies and persists the result. `graphics_panel` is the
  nested advanced screen, reachable only from the Graphics category, and is
  itself a hub: each `GraphicsSections.SECTIONS` entry (Lighting, Shadows,
  Sky & Atmosphere, Post-Processing, Performance) opens a
  `graphics_section_panel` with that section's rows.
- `ui_cancel` unwinds one layer at a time: advanced section -> advanced hub ->
  category -> settings hub. The `settings_menu` hub drives that routing (it
  calls `graphics_panel.close_section()` first), and the pause menu reuses the
  same settings hub.

## Interaction Contract

- Every modal provides initial keyboard/controller focus and handles `ui_cancel`.
- Nested screens close before their parent and restore focus to the control that opened them.
- Main-menu panels restore focus to the button that opened them.
- Settings and gameplay signals remain presentation-independent; UI scripts do not reach into the player.
- Inventory columns and hotbar slots adapt to available viewport width.
- `redot --headless --path . --script res://tools/ui_flow_verify.gd` checks the
  Play/Advanced and Settings/category/advanced flows, cancel order, and focus
  restoration.
- `redot --headless --path . --script res://tools/ui_scale_verify.gd` checks the
  UI-scale/content-scale application, the text-size multiplier and live theme
  refresh, the Display rows, and the open modal re-fitting at 200%.

When adding a screen, apply `UITheme.apply(root)` at its root, use the shared factories and button styles, preserve natural container layout, and add only motion that does not delay closing or scene changes.
