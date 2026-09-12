# Bug: Shadow-edge ridges crawl even with a stationary camera

## Status

**User confirms roughly 95% improvement; small residual edge aliasing remains open.**
The large crawling ridges were reproduced from the user's F9 seed/camera/time
capture. A 6 m first cascade plus an 8192 directional shadow atlas reduced the
measured fitted-edge fluctuation from 7.846 px to 0.343 px in that replay.
The user initially thought it was fixed, but can still see tiny moving ridges
on the shadow boundary opposite the light while other sides look straight.
Keep the resolution fix; do not mark this issue completely resolved.
The earlier local-Z light-roll mitigation failed and was reverted.
The mip-filtering/cutout-AA attempt failed and was reverted; the user confirmed
sharpness returned. Their recording and clarification establish that shadow-edge
ridges move even with a completely stationary camera. See the research below.

## Summary

While moving (walking/looking around), surfaces visibly "vibrate" / boil around
shadow edges. The effect is worst under tree canopies where the ground shows a
soft, dappled leaf shadow. The user also describes it as the shadow edge being
"kind of rigid" and "moving around".

It is a **temporal artifact**: the edge changes across frames. Camera movement
is not required, as confirmed in the user's 2026-09-12 recording.

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

The initial interpretation was that texture / alpha-cutout aliasing dominated
the whole-frame measurement. This does **not** explain or rule out the user's
subsequently confirmed stationary-camera shadow-edge artifact. A shadow-map size
comparison (4096 vs 8192) was attempted but was invalid because the two runs
spawned in different places.

## Earlier tests (not conclusive exclusions for the stationary-camera artifact)

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
  antialiasing of cutout edges). The initial declaration alone did not resolve
  the report. The subsequent edge-AA inputs were reverted after the failed
  combined trial described below.

## Open leads / not yet tried

- `rendering/lights_and_shadows/directional_shadow/size = 8192` (project
  setting, restart, ~256 MB VRAM): halves shadow-map texel size and the
  resulting edge crawl. Needs a controlled test (same camera) to validate.
- Isolated tests of any future filtering changes must assess sharpness as well
  as shimmer; the combined mip-filtering/cutout-AA trial failed (see below).
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

## Code investigation (2026-09-12)

These are pre-fix source-level findings, not a new visual A/B or a verified fix.
Reference engine checkout: `2294bf7e89`; the reported installed binary is
`4f5b14aba`, so renderer behavior should still be verified on that binary.

### 1. Nearest mip selection also affects anisotropic filtering

In `servers/rendering/renderer_rd/storage_rd/material_storage.cpp:2429–2479`,
`samplers_rd_allocate()` reads `use_nearest_mipmap_filter` and applies its
`mip_filter` to **all mipmapped sampler variants**, including
`CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC`.
The shader's linear-anisotropic hint therefore does not force linear blending
between mip levels in this reference implementation. The project's `true`
setting is a concrete candidate for abrupt mip transitions during motion.

**First A/B:** set `textures/default_filters/use_nearest_mipmap_filter=false`
in `project.godot`, restart, and compare an identical seeded scene and camera
path. Keep TAA, MSAA and anisotropy identical.

### 2. The alpha-to-coverage mitigation is incomplete

`world/block.gdshader` declares `alpha_to_coverage` and writes
`ALPHA_SCISSOR_THRESHOLD`, but does not write `ALPHA_ANTIALIASING_EDGE` or
`ALPHA_TEXTURE_COORDINATE`.

In `servers/rendering/renderer_rd/shaders/forward_clustered/scene_forward_clustered.glsl:1305–1346`,
scissor first discards pixels below the threshold; when edge AA is not used,
the surviving alpha is then forced to **1.0**. Alpha-to-coverage consequently
has no fractional alpha to smooth those cutout edges in this path. This means
the previous report of no improvement does not establish that a fully
configured alpha-to-coverage implementation is ineffective.

The engine's generated StandardMaterial3D shader supplies both missing inputs
(`scene/resources/material.cpp:1843–1845`). A project-side candidate is to add
an edge threshold and texel-space coordinates (`UV` times the texture-array
layer dimensions), following that implementation. Tune the edge threshold in
a separate A/B with MSAA enabled; check foliage density and shadow appearance
as well as motion stability. The reference shader adds the edge value to the
scissor threshold internally, so copying an absolute threshold blindly can
over-trim leaves.

### 3. Existing measurements need narrower interpretation

Whole-frame differences during a camera pan include normal scene motion,
texture contrast and animated content. The recorded values support texture
filtering as a useful lead but cannot conclusively rule out a localized shadow
artifact. A mid-run switch also needs a temporal-history warm-up and a replay
of the same camera segment; otherwise the two windows view different content.

For the next capture, pin the seed and explicit camera transform/path, wait
for chunk loading and LOD changes to settle, freeze day/night and other scene
animation, and warm up temporal effects before each measurement. Compare
separate foliage, opaque-ground and shadow-edge crops, plus a static-camera
sequence. `DayNightCycle._process()` normally advances the sun, so a stationary
camera alone does not guarantee stationary shadows. The old harness is gone,
and this document does not establish whether it froze those animations.

**Updated priority:** reproduce the user's specific motion artifact and isolate
one rendering feature at a time. The combined filtering/edge-AA trial below
did not resolve it; do not treat those source findings as an established cause.

### Implementation verification

Applied both project-side changes described above. Ran the installed engine:

`redot --path /home/micqdf/game-dev/redot-minecraft/redot-minecraft res://game/main.tscn --quit-after 180`

The gameplay smoke run exited successfully on Redot
`26.2.stable.official.4f5b14aba`, Forward+, RX 5700 XT. No shader compilation
or script errors were reported. The X11 backend reported `ERROR: NO GRAB`
from mouse capture in `player/player.gd:47`; interactive motion was not verified.
A controlled before/after motion capture was not performed.

### User result and rollback

User feedback: "still not fixed and now everything is blurrry as hell".
Reverted `use_nearest_mipmap_filter` to `true` and removed the added
`ALPHA_ANTIALIASING_EDGE` / `ALPHA_TEXTURE_COORDINATE` assignments. A restart
is required to restore the previous sampler configuration. Both changes were
tested together, so this report does not isolate which caused the blur.
Successful shader compilation was only a smoke check, not evidence that the
visual bug was fixed. The user subsequently confirmed sharpness was restored,
while the shadow issue remained.

## Stationary-camera recording and sourced diagnosis (2026-09-12)

Recording: `/home/micqdf/Videos/2026-09-12 15-04-59.mkv` (1.934 s, 1920×1080,
60 fps). User explicitly confirmed no camera or player movement throughout.
Their description: small "vibrational ridges" moving along the shadow outline.
Extracted frames show a solid block shadow on grass, not just leaf-cutout noise.
The clock advances from 08:51 to 08:52; the day/night system continues rotating
the sun at 0.3 degrees per real second even when the camera is stationary.

### Matching upstream report

[Godot #90175 — Jumping Shadows](https://github.com/godotengine/godot/issues/90175)
describes a voxel scene with a slowly rotating day/night directional light.
Godot maintainer Calinou identifies shadow-map aliasing, aggravated by voxel
edges aligning with the shadow-map texture. The recommended mitigation is
rotating the light about its **local Z axis**, changing the shadow-map grid
orientation without changing the light direction. The supplied example uses
22.5 degrees. The maintainer explicitly notes residual shimmer can remain.

Supporting references:
- [MJP: A Sampling of Shadow Techniques](https://therealmjp.github.io/posts/shadow-maps/)
  explains shadow rasterization sampling, cascade stabilization/texel snapping,
  and the tradeoffs between regular aliasing and randomized filter noise.
- [Unity: Small movements of directional light produce oscillating shadows](https://discussions.unity.com/t/small-movements-of-directional-light-produce-oscillating-shadows/834429/8)
  discusses rotating-light interaction with shadow-grid stabilization. Later
  replies qualify mitigation claims; this is supporting evidence, not proof
  of an identical Redot defect.
- Redot reference `renderer_scene_cull.cpp:2309–2315` explicitly snaps the
  directional shadow projection to a grid for stabilization.

### Local-roll trial and checks (subsequently reverted)

`world/day_night_cycle.gd`: after reconstructing the normal sun orbit each
frame, apply a 22.5-degree `rotate_object_local(Vector3.BACK, ...)` roll.
Do not substitute a global/Euler Z rotation: the rotation must preserve the
sun's local Z direction. Resetting the orbit first prevents accumulating roll.
Texture filtering and AA settings remain at their restored values.

Installed-engine checks passed:
- Across 96 times of day, sun direction is unchanged, the shadow-grid basis is
  rotated, and repeated updates do not accumulate roll.
- Gameplay ran for 120 frames in Forward+ without reported errors.

These verified implementation, not visual resolution of the user's recorded
artifact. User result: "thats not fixed it". Removed the 22.5-degree local roll
and its constant. The similar upstream report does not establish the cause in
this project, and this mitigation must not be recorded as successful.

### Follow-up user isolation results

The user reports the shadow boundary still vibrates:
- While paused with Esc.
- Still paused, with TAA off at 100% render scale.
- Additionally disabling volumetric fog, then AO/SSIL, then soft shadows.

Setting shadow opacity to zero removes the shadow and its vibrating boundary.
The user emphasizes that this is the actual shadow outline, especially at
particular angles, not a separate contour. These are user-observed results;
the scene's live transforms and renderer state were not captured during them.
Do not continue treating continuous sun rotation as a sufficient explanation.

### Controlled paused-world check and remaining blocker

An external harness instantiated the actual `game/main.tscn`, generated flat
terrain with seed 12345, placed solid dirt blocks, fixed the camera, set the
sun to 08:51, and paused the tree. TAA, soft shadows, AO/SSIL and volumetric fog
were off at native scale, shadow opacity 0.9. On the installed engine, 20
lossless frames of the shadow region had mean luma frame difference **0.0**.
Separate captures with SSR and then debanding disabled also measured 0.0.
This does not reproduce the user's scene and does not invalidate their report.

The installed commit `4f5b14aba` exists in the reference repository. A diff
against the reference checkout showed no changes to the inspected forward-light
or volumetric-fog shaders, and only an unrelated spotlight trig change in
`renderer_scene_cull.cpp`; the directional stabilization code matches.

### F9 capture of the affected scene

Added `game/shadow_capture.gd`, attached by `Main`, to capture the user's actual
problem view without changing rendering settings. Press **F9** in gameplay or
while paused. It records 30 lossless viewport images at least 67 ms apart plus
per-frame runtime camera/sun transforms, pause state, day/night processing,
world seed/edits, viewport AA/scale, environment toggles and graphics config.
PNG compression runs after sampling; GPU readbacks can still affect timing.
Output: `user://shadow_captures/<timestamp>/frame_000.png…frame_029.png` and
`state.json`. It records the current visible viewport, including any menus.

Verified by injecting F9 into the actual gameplay viewport while paused:
30 PNGs and state.json were written successfully, and the tree stayed paused.
The capture is diagnostic tooling, **not a visual fix**. The user's capture was
subsequently received and replayed below. During the manual
isolation, graphics toggles were saved by the UI; restore desired settings after
capturing. In particular, shadow opacity must be nonzero to capture the edge.

## Captured-view reproduction and resolution fix

User capture: `user://shadow_captures/1789225925_38713/`.
- Seed: 738099433; camera origin `(1.177219, 35.55084, -6.690299)`, FOV 85°.
- Camera transform remains fixed in the recorded frames; game is unpaused,
  with day/night processing active. Time advances from 8.261645 to 8.310200 h.
- Native scale; TAA/MSAA/soft shadows/volumetric fog off; AO/SSIL and SSR on.
- Shadow distance 192 m, opacity 0.7, angular distance 0°.
- Images are 2378×1338, despite the canvas logical size reporting 1280×720.

The captured state was replayed using the real `game/main.tscn`, matching
world seed/edits, camera transform/FOV/far distance, image resolution, graphics
config, and each recorded sun time. A fixed camera and paused tree prevent
unrelated updates; `set_time()` explicitly replays the recorded sun angles.
Render distance was reduced to 4 chunks (81 loaded) for this harness, so this
is not an identical full-world runtime. It reproduces the visible near block,
receiver surface, and large shadow-edge ridges.

The default first split spans about 19.2 m at this shadow distance. Its shadow
texels project to conspicuous multi-pixel steps on a block shadow only a few
metres from the camera. Those steps change as the sun rotates. A smaller
first cascade concentrates shadow-map resolution on nearby geometry.

### Controlled results

All rows use 30 captured/replayed frames. Measured the upper sloping shadow
edge in a 600×550 crop at image position `(850, 330)`, columns 320–460 within
the crop. Locate the edge from the luminance gradient after a 2 px Gaussian
analysis filter, fit a straight line per frame, then measure residuals.
The analysis filter is **not** a rendering change. Residual frame difference
removes the overall line motion to focus on changes in the jagged contour.

| Variant | Edge deviation RMS | Residual frame-change RMS |
|---|---:|---:|
| Original 4096 atlas/default splits | 5.820 px | 7.846 px |
| Same settings, frozen sun | 6.195 px | 0.000 px |
| First cascade 6 m, 4096 atlas | 1.238 px | 1.767 px |
| First cascade 6 m, 8192 atlas | 0.483 px | 0.343 px |
| Fresh launch using production fix | 0.483 px | 0.343 px |

This is roughly 96% less residual edge fluctuation on this sampled edge, not
a claim of eliminating every shadow artifact. The earlier report of motion
while paused remains unverified by a runtime capture of that paused condition.

### Applied changes and verification

- `project.godot`: directional shadow atlas size 8192 (larger GPU memory use).
- `Main._apply_graphics()`: first split targets 6 m (capped at 0.1 of the
  configured shadow range); subsequent splits are at least 0.1 and 0.3 and at
  least twice the preceding split. They remain ordered over the UI's 64–512 m
  range and are reapplied when graphics settings change.
- Texture filtering, TAA, sun motion and light orientation are unchanged.
- A fresh installed-engine replay used the actual production configuration,
  without harness overrides for atlas/splits, reproduced the improved result,
  and reported no errors. Restart is needed for the project atlas setting.

Investigation artifacts: `/tmp/opencode/replay_shadow_capture.gd`,
`/tmp/opencode/measure_shadow_edge.py`, and
`/tmp/opencode/replay-{baseline,production}-*.png`. The replay script has since
been adapted for the filter trials below; baseline/production captures remain.

### Residual edge report and narrow-filter trials

The user's follow-up image shows tiny steps on the outer sloping boundary,
with the other sides much straighter. Different edge directions intersect the
shadow-map grid differently. The far end of a cast shadow is not necessarily
in a farther camera-depth cascade; the image alone does not establish that.

Retested the original captured-scene replay at the improved resolution, keeping
TAA off and angular distance at zero. Compared the hard-shadow baseline with
narrow spatial PCF (no contact-hardening/PCSS and no texture-filter changes).
In addition to the upper-edge metric, tracked the outer right-hand edge across
crop rows 230–380, fitting x as a function of y with the same gradient method.
This is the prior reproducible camera, not a reconstruction of the new image.

| Variant | Upper edge fluctuation RMS | Outer edge fluctuation RMS |
|---|---:|---:|
| Current resolution fix / hard shadows | 0.343 px | 0.709 px |
| Medium PCF, shadow blur 0.5 | 0.372 px | 0.657 px |
| Medium PCF, shadow blur 1.0 | 0.653 px | 0.997 px |
| High PCF, shadow blur 2/3 | 0.638 px | 1.007 px |

The narrowest filter gave only a small improvement on one edge while worsening
the other; wider filters worsened both measurements. No filter change was
applied to the project. These trials ran on the installed engine without
reported errors and left the existing shadow/texture settings intact.
Residual aliasing is angle-dependent and visible on close inspection; further
mitigation must improve the affected edge without degrading the already-clean
edges or texture sharpness. Existing measurements do not establish a zero-cost,
fully artifact-free replacement for the current fix.
