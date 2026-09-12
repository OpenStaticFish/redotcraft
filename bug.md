# Bug: Shadow edges / high-frequency surfaces shimmer ("vibrate") while moving

## Status

**Open.** Reported repeatedly, persists after all mitigation attempts so far.
Reported by user; reproducible on the installed Redot 26.2 build.

## Summary

While moving (walking/looking around), surfaces visibly "vibrate" / boil around
shadow edges. The effect is worst under tree canopies where the ground shows a
soft, dappled leaf shadow. The user also describes it as the shadow edge being
"kind of rigid" and "moving around".

It is a **motion artifact**: a single still frame looks fine (soft shadow, no
obvious defect).

## Environment

- Engine: installed `redot` 26.2.stable.official.4f5b14aba
  (`/home/micqdf/.nix-profile/bin/redot`, nix store path), Forward+.
- GPU: AMD Radeon RX 5700 XT (RADV NAVI10), Vulkan 1.4.
- Project graphics (user's custom values in
  `~/.local/share/redot/app_userdata/RedotCraft/settings.cfg`):
  - render scale 100% -> FSR2 disabled (`Main._apply_graphics()` maps
    `fsr_scale == 1.0` to `Viewport.SCALING_3D_MODE_BILINEAR`, engine resolves to OFF)
  - MSAA 4x, TAA on, soft shadows on, volumetric fog on, SSIL/SSAO on, SSR on
  - shadow distance 200 m, shadow opacity 0.9, shadow blur 1.0
  - render distance 16 chunks, anisotropic filtering now forced to 16x

## Reproduction

1. Launch the game and enter a world (`./run.sh` or MCP `run`).
2. Walk around under/near a tree so a dappled canopy shadow is on the ground.
3. Watch the shadow boundary and the grass/leaf texture inside and around it
   while moving. High-frequency texture detail and the shadow edge crawl /
   shimmer frame-to-frame.
4. The effect is present with Soft Shadows on and off, and with TAA on and off
   (TAA off is clearly worse).

## Evidence collected

Measurements were taken with a temporary, env-gated harness in `game/main.gd`
(since removed) that parked the camera, panned it at 0.005 m/frame, and saved
60 PNG frames. Frame-to-frame change was measured as the average luma of
`tblend=difference` accumulated over a frame window (`ffmpeg` YAVG). All A/B
tests below switch a setting **mid-run** so the same scene and motion are
compared; cross-run numbers are not comparable because
`VoxelWorld.find_safe_spawn()` is nondeterministic (chunk jobs complete at
different times), and `GameConfig.randomize_world()` picks a new seed each run.

| A/B test (mid-run switch)          | Before | After | Meaning |
|-----------------------------------|--------|-------|---------|
| shadows on -> off                 | 0.686  | 0.748 | Shadows are **not** the dominant mover |
| soft PCF -> hard single tap       | 0.539  | 0.510 | Shadow filtering makes no measurable difference |
| TAA on -> off                     | 0.444  | 0.964 | TAA is masking the effect ~2x; keep it on |
| anisotropic 4x -> 16x             | 1.464  | 1.108 | ~24% less crawling |
| static camera, frames 50 vs 60    | —      | 0.888 | Small residual temporal instability |

30x-amplified diff heatmaps of **static** frames show the residual flicker is
concentrated on:
- alpha-cutout foliage edges (leaves) — brightest, everywhere in the canopy;
- geometry silhouettes and texture detail (with purple/red TAA fringes);
- the shadow boundary (a small-amplitude wavy line).

The dominant contributor is high-frequency texture / alpha-cutout aliasing, not
the shadow map. A shadow-map size comparison (4096 vs 8192) was attempted but
was invalid because the two runs spawned in different places.

## Ruled out

- `shadow_bias`, `shadow_normal_bias`, `light_angular_distance`,
  `directional_shadow_blend_splits` and soft-shadow filter quality: changed to
  current values (`shadow_bias 0.05`, `shadow_normal_bias 2.0`,
  `light_angular_distance 0.3`, blend off), no effect on the shimmer.
- FSR2: disabling it at 100% render scale did not change the artifact.
- Rotating PCF dither in the engine shader
  (`servers/rendering/renderer_rd/shaders/scene_forward_lights_inc.glsl`,
  `quick_hash(gl_FragCoord.xy + taa_frame_count * ...)`) was an initial
  hypothesis; the soft-vs-hard A/B above shows shadow filtering is not the
  dominant contributor.
- Leaves casting alpha-cutout shadows alone: turning shadows off mid-run did
  not reduce the measured motion change.

## Attempted mitigations (currently in the tree)

- `game/main.gd`: `viewport.anisotropic_filtering_level = Viewport.ANISOTROPY_16X`
  (measured ~24% reduction), TAA on by default for Medium/High presets,
  `soft_shadows`/`taa` live toggles in the graphics panel.
- `world/block.gdshader`: `render_mode ... alpha_to_coverage` (MSAA-based
  antialiasing of cutout edges). Applied after the last user report; the user
  reports the shimmer is still present with it.

## Open leads / not yet tried

- `rendering/lights_and_shadows/directional_shadow/size = 8192` (project
  setting, restart, ~256 MB VRAM): halves shadow-map texel size and the
  resulting edge crawl. Needs a controlled test (same camera) to validate.
- `rendering/textures/default_filters/use_nearest_mipmap_filter` is `true` in
  `project.godot` (not the engine default `false`). Could contribute to mip
  popping/shimmer; the block shader's `filter_linear_mipmap_anisotropic` hint
  may override it, unverified.
- `alpha_hash` render mode for leaves (stochastic alpha resolved by TAA) as an
  alternative to `alpha_to_coverage`.
- Dappled leaf shadows: replacing alpha-cutout leaf shadows with solid canopy
  shadows (shadow-only proxy geometry) would remove the high-frequency shadow
  content entirely; changes the look of canopy shadows.
- Volumetric fog and SSIL/SSAO were never isolated in an A/B (both are
  screen-space / temporally reprojected and could contribute localized
  shimmer).
- Per-cascade split offsets (`directional_shadow_split_1..3`) to raise near
  shadow texel density without a larger atlas.

## Notes

- Motion cannot be judged from still screenshots; the artifact must be measured
  via frame sequences (see harness approach above) or judged live.
- The engine source is reference-only for this project; only the installed
  `redot` binary is used for builds/runs. Any fix must be project-side unless
  upstream changes.
