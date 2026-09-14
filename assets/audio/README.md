# Audio

Every cue is a recorded CC0 sample. There is no synthesized bank; a missing
file warns once and plays silence.

## Layout

- `sfx/footstep_<material>_<1..3>.ogg` (material-aware)
- `sfx/block_break_<1..2>.ogg` (one uniform cue for every block)
- `sfx/block_place_<1..2>.ogg` (one uniform cue for every block)
- `sfx/ui_{click,hover,confirm,cancel}.ogg`
- `ambient/rain_loop.ogg` (weather: rain bed)
- `ambient/wind_loop.ogg` (weather: cold/snow biome wind bed)
- `ambient/thunder_1.ogg` (weather: lightning clap)

Footstep materials: grass, dirt, stone, sand, snow, gravel, wood, water.

## Source mapping

VoxeLibre `mcl_sounds` (Minecraft-style; CC BY-SA 3.0 / CC BY 3.0 / CC0 per
file — see `LICENSE-voxelibre-mcl-sounds.txt`):

- Footsteps: grass -> `default_grass_footstep`; dirt -> `default_dirt_footstep`;
  stone -> `default_hard_footstep`; sand -> `default_sand_footstep`;
  snow -> `pedology_snow_soft_footstep`; gravel -> `default_gravel_footstep`;
  wood -> `default_wood_footstep`; water -> `default_water_footstep`
  (dirt/wood have two variants; the second is duplicated for the third slot)
- Break (uniform): `default_dug_node`
- Place (uniform): `default_place_node`

Kenney UI Audio (CC0): `click1` (UI click), `rollover1` (hover),
`switch1`/`switch2` (confirm/cancel).

Rain (loopable) (OpenGameArt, CC0): `1.ogg` -> `ambient/rain_loop.ogg`.

Wind (OpenGameArt, CC0): `wind1.wav` -> `ambient/wind_loop.ogg` (60 s loop).

Thunder (OpenGameArt, CC0, `sfx_100_v2` pack): `sfx100v2_thunder_01.ogg`
-> `ambient/thunder_1.ogg`.

## Sources and licensing

- VoxeLibre `mcl_sounds` (mix of CC BY-SA 3.0, CC BY 3.0, CC0):
  https://github.com/VoxeLibre/VoxeLibre — `mods/CORE/mcl_sounds`
- Kenney UI Audio (CC0): https://kenney.nl/assets/ui-audio
- Rain (loopable), CC0: https://opengameart.org/content/rain-loopable
- Wind, CC0, by Luke.RUSTLTD: https://opengameart.org/content/wind1
- Thunder, CC0, by rubberduck (`100 CC0 SFX #2`):
  https://opengameart.org/content/100-cc0-sfx-2

License texts: `LICENSE-voxelibre-mcl-sounds.txt`,
`LICENSE-kenney-ui-audio.txt`.

## Replacing sounds

Drop a replacement `.ogg` with the same filename; no code changes needed.
