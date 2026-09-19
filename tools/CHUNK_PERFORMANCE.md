# Chunk streaming investigation

Measured on the Ryzen 7 7700 (8 cores / 16 logical CPUs) with the installed
Redot 26.2 engine. These are headless CPU/streaming measurements, not GPU FPS
claims. Benchmark processes ran serially. Timing varies with machine load.

## Confirmed stall

Changing distance from the pause menu rebuilt the desired queues while the
paused scene tree prevented `VoxelWorld._process()` from collecting, committing,
or scheduling work. The flat-world regression remained at 25/49 chunks with
24 queued jobs for the entire 20-second timeout. Resuming allowed it to recover;
this investigation did not reproduce a permanent post-resume queue deadlock.

Streaming now runs while paused; water, gravity, and fire clocks remain frozen.
The regression's paused expansion completes in about 0.2 seconds for flat terrain
and 0.7 seconds for normal terrain. Distance-slider changes are coalesced over
200 ms and flushed when the settings panel closes.

## Retained optimizations

- Enumerate each desired ring's perimeter directly. The old nested square scan
  visited every interior cell on every ring, taking O(radius^3) work despite its
  nearest-first ordering. Queue construction now takes O(radius^2).
- Check bounded near-queue membership before searching large distant queues for
  urgent work. This avoids scanning up to 40,401 entries every scheduling tick
  when no urgent job exists, without changing urgent queue ordering.
- Maintain the current-mode loaded count during desired rebuilds, commits, and
  unloads. Progress updates no longer scan the entire desired square.
- Exclude non-desired retained chunks from collision-repair scheduling, and skip
  obsolete queue entries before submission.
- Precompute immutable face and AO linear strides; avoid repeated per-corner
  coordinate arithmetic and redundant horizontal bounds checks.
- Resolve cube tint only when a visible face exists, avoid temporary cube-face
  index/collision arrays, and skip collision vertex reads for non-collision jobs.

Worker snapshots remain independent copies. Full Detail still generates full
chunks through the requested distance; Balanced LOD remains explicitly opt-in.
No terrain, lighting, collision, or draw-distance quality was reduced.

## Measurements

The four-fixture `worldgen_mesh_benchmark.gd` uses empty neighbor sets; its mesh
timings must not be substituted for real streaming timings.

| CPU mesh measurement | Before | After |
| --- | ---: | ---: |
| Full mesh average | 77.18 ms | 61.63 ms |
| Face emission average | 61.38 ms | 46.23 ms |
| Compact LOD mesh average | 2.58 ms | 2.45 ms |

Full meshing is about 20% cheaper on these fixtures. Nine exact SHA-256 fixtures
pin normal, missing, emissive, and compact neighbors, collision on/off, LOD,
all mesh attributes, and full light arrays in `mesh_parity_verify.gd`.

Actual `stream_full_verify.gd`, seed 918273, RD10 Full Detail, 441 chunks with
169 near collision shapes:

| Normal worker limit (+1 urgent permitted) | Settled load |
| --- | ---: |
| 8, before changes | 12.00 s |
| 4, after changes | 13.28 s |
| 8, after changes, repeated final runs | 10.96-11.48 s |
| 12, after changes | 10.97 s |
| 16, after changes | 10.70 s |

Keep the production limit at 8: extra workers offered only a small gain in this
sample and increased measured main-thread work. This is roughly a 4-9% reduction
in settled load time at the normal limit, not a 10x improvement. The timer polls
settlement every 250 ms, so differences of that size need repeated runs.

The final 8-worker traces submitted 432 generation jobs (the verifier's first
nine spawn chunks are synchronous), 448 mesh jobs, and discarded zero results.
Aggregate worker generation elapsed time was 38.5-41.7 s, versus 19.3-19.5 s
meshing. These totals overlap across workers and are not wall time or measured
CPU utilization. Main-thread streaming work totalled about 1.41 s, including
about 0.99 s in commits. Generation/population is therefore the larger remaining
worker cost on this stream, not just meshing or the number of threads.

## Rejected experiments and remaining work

- Per-face resize/indexed writes were slower than direct packed-array pushes.
- An enclosed-cube fast path was within timing noise and was not retained.
- Reusing terrain warp/profile inputs measured 74.42 ms full generation versus
  74.06 ms before; the small compact gain did not justify retaining the change.
- Do not remove neighbor snapshot copies merely to reduce allocations: generated
  data can become live editable chunk data while dependent mesh jobs still run.
- The population follow-up below measures caves, vegetation, and structure
  subphases and removes queries for candidates that cannot affect the chunk.
- GPU draw calls, rendered frame-time percentiles, and RD16/RD32/Extreme resource
  budgets still require separate measurements. Chunk batching and horizon work
  are separate roadmap features, not part of this correctness fix.
- Running obsolete workers still finish before their results are rejected.
  Cooperative cancellation is a future option, but needs a thread-safe contract;
  unsafe shared mutable cancellation state is not an acceptable shortcut.

## Reproduction

```sh
redot --editor --headless --path . --quit
redot --headless --path . --script res://tools/stream_transition_verify.gd
redot --headless --path . --script res://tools/stream_transition_verify.gd -- --normal
redot --headless --path . --script res://tools/worldgen_mesh_benchmark.gd
redot --headless --path . --script res://tools/stream_full_verify.gd
redot --headless --path . --script res://tools/stream_full_verify.gd -- --workers=16
redot --headless --path . --script res://tools/mesh_parity_verify.gd
```

`get_worldgen_stats()` now exposes submitted generation/mesh counts, discarded
results, active-worker limits, aggregate worker generation/mesh time, and total
main-thread streaming/commit time. Counters are cumulative for the world instance.

## Population follow-up

`population_benchmark.gd` measures the full population pipeline in production
order over twelve pinned chunks (two seeds, three repetitions). It checks each
profiled result against `populate()` and twelve preoptimization golden hashes.
The fixtures cover plains, river, highlands, and deep ocean; forest/taiga/jungle/
swamp density and seams are covered separately by the biome/tree verifiers.

The largest cost was terrain sampling for decoration candidates whose eventual
stamps could not reach the current chunk. Sparse POI candidates can be almost
an entire 160-block owner cell away. Checking the conservative write/clear
footprint before terrain/site queries removes that work without changing any
accepted overlapping candidate, stamp order, density, or worldgen version.
Underwater tufts get a second point-in-chunk check before querying their ground.

Noise caves additionally short-circuit the second ridge when the first already
rejects a tunnel, and skip cheese noise for cells already carved by spaghetti.
Height-dependent thresholds are computed once per call using float64 arrays;
all scratch remains local to the worker job and the noise sources are immutable.

| Population phase average | Before | Final sample |
| --- | ---: | ---: |
| Surface decoration | 20.18 ms | 4.59 ms |
| Underwater decoration | 5.60 ms | 0.55 ms |
| Structures | 5.22 ms | 0.02 ms |
| Noise caves | 5.78 ms | 4.47 ms |
| All population phases | 49.23 ms | 22.12 ms |

To reduce the effect of changing machine load, the benchmark can alternate the
old and new production `populate()` in the same process against identical fields:

```sh
redot --headless --path . --script res://tools/population_benchmark.gd -- --compare-ref=f7404af
```

This optional local-only mode reads the old GDScript from that git revision and
checks old/new data and max-height equality on every invocation. CI does not need
git history: it runs the normal golden-fixture mode and footprint verifier.
Paired results: **54.75 -> 24.18 ms (2.26x)** and
**49.50 -> 22.27 ms (2.22x)**. This is population speedup, not whole-game speedup.

RD10 Full Detail reached **8.17 s** on two final normal-load runs, compared with
10.96-11.48 s after the first optimization pass and the original 12.00 s.
Earlier follow-up runs were 9.93/9.96 s, with a slower 12.49 s run during machine
load variation (unmodified phases also slowed). These are not fixed performance
guarantees. The final traces retained 441 chunks, 169 collision shapes, and 0-2
discarded results; worker generation total dropped to 23.23-23.28 s versus the first
pass's 38.5-41.7 s, with comparable mesh-worker time (18.69 s).

`population_pruning_verify.gd` exercises inclusive bounds, negative coordinates,
all land/underwater stamp extents, structure clear bounds, sampler-call pruning,
legacy catalogs, and full/compact max-height invariants. Historical v1-v14 hashes,
tree/biome density, POI, LOD, water, and the fourteen-corner worldgen config sweep
also passed. No terrain version bump or reduction in world content is needed.

## Closest-first scheduling follow-up

Replaced dispatch arrays with min-heaps, retaining separate generation and mesh
membership maps. Both stages now compare the same priorities before submission:

1. The player's current stream-center chunk.
2. The immediate 3x3 ring, with local edited-owner feedback ahead of neighbor work.
3. The remaining collision-radius ring, nearest first; far edits cannot bypass it.
4. Distant chunks, nearest first.

Squared distance orders each tier and coordinates break ties deterministically.
Ready meshes win equal priorities, but a farther mesh no longer bypasses nearby
generation just because it completed its terrain stage first. Camera/player
re-centering rebuilds priorities. Photo mode continues to follow its active
camera, and the single urgent overflow worker limit is unchanged. This prioritizes
dispatch, not strict completion order: existing worker jobs cannot be preempted,
and a chunk's mesh still needs its terrain-neighbor snapshots.

Heap construction is O(N); push/pop are O(log N), except rare edit promotions
which locate an existing entry before moving it upward. This replaces repeated
front-of-array shifts and queue scans, particularly useful at Extreme distances.

Also replaced the interpreted full light-volume emitter scan with native packed
byte searches. Source indices are sorted to preserve exact flood seeding order.
At 4096 hits the code switches back to the original spatial scan, bounding index
scratch to 4096 integers and avoiding a large dense-emitter sort. Sparse and
dense mixed-emitter fixtures retain exact light/output hashes.

Measured full-mesh average: **61.63 -> 58.00 ms**; the sampled block-light phase
fell from **4.13 -> 0.36 ms**. Settled RD10 Full Detail now measured **7.66-7.89 s**
on the original synchronous-spawn verifier, versus 8.17 s after population work.
The additional asynchronous entry run measured **7.97 s** for all 441 chunks,
with its 3x3 collision-safe ring ready at **345.7 ms**, recorded directly from
`initial_stream_ready`. This excludes application/asset startup and is one pinned
world fixture, not a promise for every world or a GPU frame-rate measurement.

```sh
redot --headless --path . --script res://tools/chunk_priority_verify.gd
redot --headless --path . --script res://tools/stream_full_verify.gd -- --async-start
```

Priority ordering, duplicate suppression, edit promotion, recentering, Extreme
heap invariants, live LOD/distance changes, fast-flight soak, collision targeting,
explosions, fire, gravity, and mesh/light parity passed regression checks.

## Compact LOD render batching

Balanced LOD (already an explicit terrain-detail opt-in) can aggregate eligible
**opaque** compact chunks into aligned 2x2 `ArrayMesh` render groups. It never
creates terrain outside `render_distance`, never changes Full Detail, and never
turns full chunks into compact data. Each original chunk retains its data, edits,
neighbour snapshots, water mesh, and collision ownership; the aggregate only
hides its four opaque source `MeshInstance3D`s. Water stays per chunk because
combining transparent water would change transparent ordering/culling behaviour.

An aggregate is invalidated before a member commits, unloads, or crosses the
LOD/full boundary. Missing or stale members render their source meshes instead,
so a batch can never make a hole. It hides the old aggregate before restoring
source meshes, avoiding one-frame overlap during deferred `queue_free()`.
Building is scene-thread-only (no worker task, no collision body), capped at one
upload per frame, and only starts after all commits and collision-ring work are
settled. A soft remaining-commit-budget guard avoids beginning its nonpreemptible
upload late in a streaming frame. Groups over 16,384 vertices or 24,576 indices
remain individual meshes. Rejected groups are not repeatedly retried until a
member changes or the stream configuration is rebuilt.

The pending queue is capped at 64 nearest groups. That cap is not a permanent
coverage limit: a cursor scans the existing desired grid in 12 bounded candidates
per frame and revisits skipped eligible groups after foreground work/nearer uploads
drain, without retaining an unbounded candidate list. Once a full scan finds no
remaining candidates and the queue drains, batching sleeps until chunk changes
wake it, avoiding steady-state scanning overhead. Experimental LOD batching
defaults **off**, is exposed in Display settings, and applies only when the player
also selects Balanced LOD; Full Detail is unaffected. `lod_batch_verify.gd` checks
source exclusivity, custom attributes, foreground commit deferral, invalidation,
no batch collision node, default state, refill, and bounds.

### Rendered Forward+ A/B (2026-09-19)

`lod_batch_render_profile.tscn -- --normal --rd24` ran with installed Redot 26.2,
Vulkan Forward+, X11, **AMD Radeon RX 5700 XT (RADV NAVI10)**, normal seed
**918273**, a fixed 1280×720 viewport/camera/render parameters, Balanced LOD,
V-Sync/FPS cap disabled, 30 warmup + 120 sampled rendered frames per phase. It
runs **off → on → off control** at every distance. `RenderingServer`
draw-call/primitives counters are collected after `frame_post_draw`; frame time
is wall-clock rendered-frame interval, not a GPU timestamp query. Runs were
serial.

| Render distance | Batching | Draw calls/frame | Primitives/frame | p50 / p95 / p99 ms |
| --- | --- | ---: | ---: | ---: |
| 10 | Off | 648 | 1,200,924 | 1.92 / 2.34 / 2.35 |
| 10 | On (19 groups) | 596 | 1,205,752 | 1.93 / 2.21 / 2.37 |
| 10 | Off control | — | — | 1.93 / 2.32 / 2.37 |
| 16 | Off | 1,453 | 1,769,020 | 2.48 / 2.83 / 2.96 |
| 16 | On (175 groups) | 1,013 | 1,791,940 | 2.34 / 2.75 / 2.88 |
| 16 | Off control | — | — | 2.33 / 2.78 / 2.82 |
| 24 | Off | 3,067 | 2,870,816 | 3.25 / 3.48 / 3.64 |
| 24 | On (495 groups) | 1,840 | 2,901,186 | 3.52 / 3.91 / 3.94 |
| 24 | Off control | — | — | 3.26 / 3.53 / 3.66 |

The feature reduced draws by 8.0%, 30.3%, and 40.0%. The 2x2 culling bound
submitted 0.4–1.3% more primitives. RD16 improved across this one sample's
percentiles, but RD10 was mixed and RD24 regressed about 8–12% despite fewer
draws; the off control tracks the original baseline. It is therefore explicitly
experimental/off by default, with an in-game Display setting and
`set_lod_batching_enabled(false)` fallback. These numbers are one driver/GPU/
scene fixture, not portable GPU timing claims. Re-run target hardware rather
than extrapolating headless streaming timings.

Repeat after removing idle scanning (same configuration and counters):

| RD | Off p50/p95/p99 ms | On p50/p95/p99 ms | Off-control p50/p95/p99 ms |
| --- | --- | --- | --- |
| 10 | 1.93 / 2.33 / 2.35 | 1.93 / 2.34 / 2.40 | 1.92 / 2.33 / 2.34 |
| 16 | 2.33 / 2.73 / 2.73 | 2.58 / 2.98 / 3.13 | 2.32 / 2.71 / 2.73 |
| 24 | 3.46 / 4.02 / 4.82 | 3.28 / 3.49 / 3.56 | 3.30 / 3.57 / 3.69 |

The draw reductions reproduce, but frame-time gains do not: RD16 regressed in
this repeat, while RD24's on phase was close to its warmed off control. This
reinforces the default-off decision; fewer draws alone are not proof of faster
rendering. Full Detail remained at 441/441 chunks with 169 collision shapes in
the follow-up headless verifier (7.89 s on that run).

```sh
redot --headless --path . --script res://tools/lod_batch_verify.gd
redot --path . res://tools/lod_batch_render_profile.tscn -- --normal
redot --path . res://tools/lod_batch_render_profile.tscn -- --normal --rd24
```

## Rendered gameplay bottleneck profile (separate from loading and batching)

The CPU/loading measurements above remain headless worker/streaming evidence.
They do **not** imply an in-game FPS improvement. Likewise, the compact-LOD
batching experiment above remains opt-in/default-off and is not part of this
profile. The profiler below forces Full Detail and unbatched rendering at both
distances, so it cannot be used to claim a batching win.

`gameplay_render_profile.tscn` instantiates the actual `game/main.tscn`, then
sets an isolated `Main` subclass as its root script *before it enters the tree*.
The subclass overrides the inspected `_prepare_world_storage() -> Dictionary`,
`_flush_world_save() -> bool`, `_exit_tree() -> void`, and
`_build_first_run_hints() -> void` hooks. It therefore performs ordinary Main
startup (world, player, HUD, sky, sun, weather, post-processing, and streaming)
without creating/opening/flushing a world, saving `settings.cfg`, or recording
onboarding completion. Fixture values are in-memory only and restored before
exit.

### Method

- Installed Redot 26.2, Forward+, Vulkan, AMD Radeon RX 5700 XT (RADV NAVI10).
- Normal world, seed `918273`; fixed noon (`12.0`), parked camera, 1280×720
  window, default **Medium** preset, Full Detail, and batching off.
- Player physics/input and photo-camera input are disabled during profiling.
  Camera placement uses the generator's deterministic spawn, not the adjusted
  safe spawn chosen from resident chunks; its transform is printed in the log.
- Medium's 3D scale is 0.77. The engine warned that FSR2 is incompatible with
  TAA and disabled TAA internally; the profile reports the configured viewport
   property as `TAA requested=true`, not proof that separate TAA ran.
- Each phase has 60 rendered-frame warmup frames and 120 sampled frames. The
  profile asks `RenderingServer` to measure this viewport, reads its CPU/GPU
  render-time values after `frame_post_draw`, and separately reports wall-frame
  intervals and rendered draw/primitives counters.
- One production effect is toggled at a time in **off → on → off-control**
  order (SSAO/SSIL are one production setting). A numeric GPU result was
  returned by this driver; a backend that supplies `0.0` is reported as
  `reported-zero`, not silently treated as an unavailable timer. Missing engine
  timing APIs are reported as unavailable. Wall time is not a GPU timestamp.

### Results

`p50/p95`, milliseconds. GPU measurements were stable through each repeated
off control; viewport CPU values were below GPU values in the steady reference
frames. This fixture is GPU-bound, not evidence of a general default-FPS gain.

| RD / phase | Draws | Primitives | viewport CPU p50/p95 | viewport GPU p50/p95 | wall p50/p95 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 10 reference, all Medium effects on | 1,080 | 2,287,270 | 0.561/0.847 | 7.016/7.030 | 7.522/7.657 |
| 16 reference, all Medium effects on | 2,092 | 4,640,437 | 0.884/1.290 | 8.614/8.629 | 8.886/9.171 |

| RD / effect | GPU off p50 | GPU on p50 | GPU off-control p50 |
| --- | ---: | ---: | ---: |
| 10 sun shadows | 5.569 | 7.019 | 5.570 |
| 10 SSAO+SSIL | 6.300 | 7.018 | 6.300 |
| 10 SSR | 6.644 | 7.017 | 6.646 |
| 10 volumetric fog | 6.835 | 7.013 | 6.837 |
| 16 sun shadows | 6.637 | 8.613 | 6.638 |
| 16 SSAO+SSIL | 7.876 | 8.616 | 7.869 |
| 16 SSR | 8.225 | 8.614 | 8.227 |
| 16 volumetric fog | 8.434 | 8.612 | 8.435 |

These replace the exploratory measurements whose camera was anchored to the
adjusted player spawn. The changed shadow cost reflects a different pinned
view, not a production optimization. Both final distances use camera origin
`(-15.5, 90.1684, 58.5)` and the same orientation.

### Interpretation and candidates

1. **Profile shadows first.** They are the largest measured GPU cost here:
   about 1.45 ms at RD10 and 1.98 ms at RD16, while adding 341/627 draws and
   roughly 1.27M/2.40M primitives. Investigate shadow-caster coverage, cascade
   distance/resolution, and leaf caster cost with a visual-regression capture
   before changing a default.
2. **SSAO+SSIL is the next stable GPU candidate** at about 0.72-0.74 ms at both
   distances. It deserves a quality/half-resolution investigation; it should
   not be disabled speculatively because the current test is one camera/GPU.
3. **SSR (~0.37-0.39 ms) and volumetric fog (~0.18 ms)** are materially smaller
   on this fixture. Do not prioritize them ahead of shadows or SSAO+SSIL.
4. RD16 grows GPU p50 from 7.02 to 8.61 ms and draws from 1,080 to 2,092, but
   viewport CPU p50 remains below 1 ms in the reference. This points to GPU
   raster/shadow/post work rather than a renderer-CPU draw-submission bottleneck
   on this driver. CPU p95 varied across controls, so it is not sufficient
   evidence for a CPU-side optimization by itself.

These are bounded, stationary views on one GPU/driver. They exclude loading
and moving-player streaming churn, do not measure every camera/weather/biome,
and must be rerun on target hardware. They do not reduce production quality or
change defaults.

A shadow-only leaf texture-fetch bypass was tested and removed: GPU p50
off/on/off-control was 7.022/7.025/7.024 ms at RD10 and
8.630/8.636/8.633 ms at RD16. It offered no measurable win. No shader change,
atlas reduction, or disabled-effect default was retained. The proven loading
work and experimental batching remain distinct from this measurement-only pass;
see `tools/OPTIMIZATION_CHANGESETS.md` for the review boundaries.

### Reproduction

Run serially (the render profile refuses headless mode):

```sh
redot --editor --headless --path . --quit
redot --path . res://tools/gameplay_render_profile.tscn
```
