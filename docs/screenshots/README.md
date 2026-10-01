# README screenshot gallery

Captured from RedotCraft's production `game/main.tscn` with installed Redot
26.2 stable, the Forward+ Vulkan renderer, and an AMD Radeon RX 5700 XT.
These are rendered in-game frames, not editor views or concept art.

## Capture settings

- World seed: **918273**, Normal terrain, **WorldGenConfig v14** defaults
  from source revision `e1d24df`.
- Mode: Creative; no block edits or staged builds.
- Terrain: Full Detail, render distance 10; the initial stream settled to 441/441 chunks.
- Graphics: High preset with native render scale (100%) and volumetric fog
  density lowered to **0.002**, using the same setting supported by Advanced Graphics.
- Free-camera views with the HUD hidden for landscape shots.
- Captures were resized to 1600 × 900 and WebP-compressed for the README;
  lighting and colors were not edited after capture.

| File | View |
| --- | --- |
| `forest.webp` | Forest near (2432, -3584), noon; camera approximately (2462, 71, -3529), looking toward (2432, 56, -3584). |
| `coast.webp` | Coast near the deterministic spawn (-15.5, 56.2, -15.5), noon; elevated view looking toward the shore. |
| `evening.webp` | The same coastal viewpoint at 17:00, with reflected sunlight on the water. |
| `inventory.webp` | Creative inventory opened over the forest view, showing the backpack and time/weather controls. |

## Refreshing the gallery

Create a Normal Creative world with seed 918273, let nearby chunks finish
streaming, and use **P** for the detached camera. **F2** saves clean PNGs to
`user://screenshots/`; capture the viewport with the UI visible for interface
shots. Match the settings above for comparable images. Terrain-generation
versions, cloud animation, and camera composition can affect the result.

Keep descriptive filenames and alt text in the root README. `docs/.gdignore`
keeps documentation images out of Redot's game-asset import pipeline.
