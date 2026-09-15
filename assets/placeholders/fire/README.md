# Fire placeholder textures

`fire.png` (a 64 px transparent flame sheet) and `smoke.png` (a soft grey puff)
are generated specifically for RedotCraft by `tools/gen_fire_texture.gd` from a
fixed RNG seed. They contain no third-party artwork and are safe to redistribute
with the repository.

`fire.png` is the standalone `BLOCK_FIRE` cross flame, which `world/block.gdshader`
scrolls and warps on the fire layer. `smoke.png` is sampled by
`world/smoke_overlay.gdshader` for the burning-block smoke billboards; the flame
billboards use `fire.png` through `world/fire_overlay.gdshader`.
