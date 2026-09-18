# Asset verification

Run the deterministic source-asset audit with:

```sh
redot --headless --path . --script res://tools/asset_license_verify.gd
```

It checks the shipped placeholder textures, audio-bank names, font references,
asset references used by `BlockRegistry` and `FireOverlay`, committed `.import`
recipes, headless import-cache availability, and the required license and
attribution documents.

The checker deliberately does **not** scan `.godot/imported/`, `user://`, or
images/textures created at runtime. It permits unreferenced ZigCraft placeholder
textures because that pack intentionally includes assets reserved for future
blocks. `tools/icon_check.gd` remains display-only and is not a CI/headless
check.

After adding or regenerating a shipped PNG, OGG, or font, run:

```sh
redot --headless --import --path .
```

Then commit the corresponding `.import` metadata along with the source asset.
