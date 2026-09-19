# Optimization change sets

All changes below are currently uncommitted relative to `f7404af`. They should
be reviewed as separate groups, not described as one proven FPS improvement.
Some files contain changes from multiple groups; whole-file staging would mix
them. This document does not create commits or modify the index.

## A. Proven loading and CPU work

Production changes:

- `world/worldgen/voxel_populator.gd`: footprint rejection before terrain queries,
  exact cave-noise short-circuiting, call-local height thresholds.
- `world/chunk_mesher.gd`: immutable face/AO strides, lazy tint calculation,
  reduced temporary allocations, bounded native emitter discovery.
- `world/voxel_world.gd`: paused streaming with simulation gated, desired-ring
  enumeration, incremental progress, distance-priority generation/mesh heaps,
  collision repair guards, and cumulative profiling counters. Excludes the
  `_lod_batch_*` renderer subsystem and its call sites.
- `ui/settings_category_panel.gd`: render-distance debounce and close-time flush.
  Excludes the experimental batching checkbox.

Coverage: `chunk_priority_verify.gd`, `mesh_parity_verify.gd`,
`population_benchmark.gd`, `population_pruning_verify.gd`, and the non-batching
portions of `stream_transition_verify.gd`, `stream_full_verify.gd`,
`player_target_verify.gd`, and `ui_flow_verify.gd`.

Evidence: approximately 12 s to 7.7-7.9 s for the pinned RD10 loading fixture;
roughly 2.2x population speedup in paired comparisons. These are loading/CPU
measurements, not GPU FPS promises. No quality reduction or terrain version bump.

## B. Experimental render batching

Production changes:

- `world/voxel_world.gd`: render-only 2x2 opaque compact-LOD aggregates and their
  lifecycle, caps, foreground-pressure checks, refill/sleep, and rejection state.
- `autoload/game_config.gd`: default-false `lod_batching` setting and getter.
- `game/main.gd`: initial/live application of that setting.
- `ui/settings_category_panel.gd`: Experimental LOD Batching checkbox.

Coverage and measurement: `lod_batch_verify.gd`,
`lod_batch_render_profile.gd/.tscn`, batching assertions in
`stream_transition_verify.gd`, and the setting assertions in
`frame_pacing_verify.gd`.

Evidence: fewer draw calls, but inconsistent frame-time changes including
regressions. Default off. Balanced LOD only; no Full Detail batching, no water
batching, and no terrain beyond the chosen render distance. Keep experimental
until representative gameplay GPU measurements justify enabling it.

## C. Measurement only

`gameplay_render_profile.gd/.tscn` loads the actual gameplay scene with isolated
persistence hooks. It measures viewport CPU/GPU render times and wall intervals
using a pinned camera, seed, time, preset, and viewport at RD10/RD16. Controlled
effect toggles are temporary and are not production graphics changes.

This work identifies rendering costs; it does not claim to fix them. Disabling
shadows, shrinking the atlas, or lowering effects would be quality tradeoffs,
not output-preserving optimizations.

## Shared documentation and CI

Split `.github/workflows/tests.yml`, `ROADMAP.md`, `world/worldgen/README.md`,
and `CHUNK_PERFORMANCE.md` by the corresponding tests/features when preparing
separate commits. Preserve the default-off batching boundary. No horizon
impostor implementation is included in any group.
