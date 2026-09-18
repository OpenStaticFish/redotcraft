# Pure GDScript unit tests

The lightweight unit suite has no external framework dependency. It runs pure
worldgen, registry, water, mesher, and AO logic in one headless Redot process.

After a fresh clone, or after adding a new `class_name` test script, refresh
Redot's generated script-class cache once (CI does this in `setup-redot`):

```bash
redot --headless --import --path .
```

Run the suite:

```bash
redot --headless --path . --script res://tools/unit_tests.gd
```

The runner reports every failed assertion before returning a non-zero exit code.
Keep fixtures deterministic and use the existing focused `tools/*_verify.gd`
checks for scene, streaming, storage, or rendering integration coverage.

Current inventory:

- `worldgen_unit_test.gd`: fixed 1D/2D/3D hash vectors, negative-coordinate
  division/range behavior, deterministic padded terrain-field samples, and
  pinned field height/biome/river fixtures.
- `block_registry_unit_test.gd`: contiguous persistent byte IDs, runtime
  texture-array layer packing, and source/flowing-water level inverses.
- `mesher_unit_test.gd`: water-height curve, AO sample offsets, cube-face
  culling, and three-neighbor AO shading.
