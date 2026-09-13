# RedotCraft UI

The interface uses a shared "Deepslate & Ember" design system built from native Redot `Control` nodes.

## Foundations

- `ui_theme.gd` owns palette, typography, spacing, style boxes, generated control textures, and small component factories.
- `motion.gd` owns the restrained entrance, selection, and status tween vocabulary.
- `block_icon.gd` renders cached isometric item icons from `BlockRegistry.texture_array`; UI icons therefore stay synchronized with world textures.
- Static hierarchy remains in `.tscn` scenes. Scripts compose dynamic rows, inventory slots, HUD slots, and decorative title-screen layers.
- Iosevka font subsets and their license live in `assets/fonts/`.

## Visual Language

- Slate surfaces and hairline borders establish hierarchy without heavy texture assets.
- Ember is reserved for primary actions, focus, and selection.
- Cyan is reserved for values, quantities, and telemetry.
- Eyebrows, dividers, modal chrome, form rows, and button variants come from `UITheme` rather than per-screen styling.

## Interaction Contract

- Every modal provides initial keyboard/controller focus and handles `ui_cancel`.
- Nested graphics settings close before their parent and restore focus to the opener.
- Main-menu panels restore focus to the button that opened them.
- Settings and gameplay signals remain presentation-independent; UI scripts do not reach into the player.
- Inventory columns and hotbar slots adapt to available viewport width.

When adding a screen, apply `UITheme.build()` at its root, use the shared factories and button styles, preserve natural container layout, and add only motion that does not delay closing or scene changes.
