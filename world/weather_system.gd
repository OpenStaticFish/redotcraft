class_name WeatherSystem
extends Node3D

## Toggles between clear skies and rain. Precipitation is biome-aware: cold
## biomes fall as snow and keep a light ambient snowfall even when clear, while
## swamps carry a low ground mist. Rain/snow are camera-following GPU particle
## fields that pause when the camera is under cover; the atmosphere grading
## (sun, ambient, fog, sky, clouds) lives in DayNightCycle. Lightning strikes
## are scheduled here and surfaced through the `lightning` signal.

enum State { SUNNY, RAIN }

## What is falling right now. `NONE` when clear (cold biomes still get ambient
## snow, reported by `is_snowing()` rather than this value).
enum Precipitation { NONE, RAIN, SNOW }

signal weather_changed(state: int)
## Emitted on a thunder strike; strength scales the flash and sound.
signal lightning(strength: float)
## Emitted when the camera crosses into/out of a cold or wetland biome so the
## audio layer and HUD can follow the biome (cold bed, mist).
signal ambience_changed(cold: bool, wetland: bool)

const RAIN_PARTICLES := 1600
const SNOW_PARTICLES := 1200
const MIST_PARTICLES := 200
const COVER_CHECK_INTERVAL := 0.3
const COVER_HEIGHT := 24.0
const BIOME_CHECK_INTERVAL := 1.5
const LIGHTNING_FIRST_DELAY := 3.0
const LIGHTNING_MIN_INTERVAL := 5.0
const LIGHTNING_MAX_INTERVAL := 16.0
# Snow falls slowly and drifts; mist is a large, near-static soft quad field.
const SNOW_FALL_SPEED := Vector3(0.25, -1.4, 0.15)
const MIST_RISE_SPEED := Vector3(0.08, 0.02, 0.05)

@export var transition_seconds := 2.0
@export var rain_color := Color(0.62, 0.72, 0.88, 0.32)
@export var snow_color := Color(0.94, 0.96, 1.0, 0.85)
@export var mist_color := Color(0.74, 0.8, 0.74, 0.14)

var state: State = State.SUNNY
var rain_amount := 0.0

var _camera: Camera3D
var _day_night: DayNightCycle
var _world: VoxelWorld
var _rain: GPUParticles3D
var _snow: GPUParticles3D
var _mist: GPUParticles3D
var _cover_timer := 0.0
var _covered := false
var _biome_timer := 0.0
var _biome_id := -1
var _cold := false
var _wetland := false
var _lightning_timer := -1.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_rain = _build_rain()
	_snow = _build_snow()
	_mist = _build_mist()


func setup(camera: Camera3D, day_night: DayNightCycle) -> void:
	_camera = camera
	_day_night = day_night
	if _day_night:
		_day_night.set_weather_dim(rain_amount)


## Supplies the world used for biome queries (snow / mist selection).
func set_world(world: VoxelWorld) -> void:
	_world = world


## Re-targets the weather field and cover checks at the active render camera
## (photo mode swaps in a detached camera).
func set_camera(camera: Camera3D) -> void:
	_camera = camera


func set_state(new_state: State) -> void:
	if new_state == state:
		return
	state = new_state
	weather_changed.emit(state)


func toggle() -> void:
	set_state(State.SUNNY if state == State.RAIN else State.RAIN)


func is_raining() -> bool:
	return state == State.RAIN


## Precipitation identity for the current biome. Cold biomes snow, everything
## else rains. Returns `NONE` while clear.
func get_precipitation() -> int:
	if state != State.RAIN:
		return Precipitation.NONE
	return precipitation_for_biome(_biome_id)


static func precipitation_for_biome(biome: int) -> int:
	return Precipitation.SNOW if BiomeCatalog.is_cold_biome(biome) else Precipitation.RAIN


## Ambient cold-biome snowfall / swamp mist, independent of the rain toggle.
func is_snowing() -> bool:
	return _cold


func is_misty() -> bool:
	return _wetland


func get_biome_id() -> int:
	return _biome_id


func _process(delta: float) -> void:
	var target := 1.0 if state == State.RAIN else 0.0
	if not is_equal_approx(rain_amount, target):
		rain_amount = move_toward(rain_amount, target, delta / maxf(transition_seconds, 0.01))
		if _day_night:
			_day_night.set_weather_dim(rain_amount)
	if _camera:
		global_position = _camera.global_position + Vector3(0.0, 8.0, 0.0)
	_biome_timer -= delta
	if _biome_timer <= 0.0:
		_biome_timer = BIOME_CHECK_INTERVAL
		_update_biome()
	_cover_timer -= delta
	if _cover_timer <= 0.0:
		_cover_timer = COVER_CHECK_INTERVAL
		_update_cover()
	_update_particles()
	_update_lightning(delta)


## Re-reads the camera's dominant biome on an interval. Only crosses the noise
## sample and emits when the cold/wetland identity actually changes.
func _update_biome() -> void:
	if _camera == null or _world == null:
		return
	var biome := _world.get_biome_id(_camera.global_position)
	if biome == _biome_id:
		return
	_biome_id = biome
	var cold := BiomeCatalog.is_cold_biome(biome)
	var wetland := BiomeCatalog.is_wetland_biome(biome)
	if cold != _cold or wetland != _wetland:
		_cold = cold
		_wetland = wetland
		ambience_changed.emit(_cold, _wetland)


func _update_particles() -> void:
	var precipitating := state == State.RAIN and not _covered
	# Cold biomes keep a light snowfall even when clear; the rain toggle just
	# thickens it (snow replaces rain rather than falling through it).
	_snow.emitting = _cold and not _covered
	_rain.emitting = precipitating and not _cold
	_mist.emitting = _wetland


## Thunder only during rain, above ground, and outside cold (snow) biomes.
func _update_lightning(delta: float) -> void:
	var active := state == State.RAIN and not _covered and not _cold and rain_amount > 0.5
	if not active:
		_lightning_timer = -1.0
		return
	if _lightning_timer < 0.0:
		_lightning_timer = LIGHTNING_FIRST_DELAY
		return
	_lightning_timer -= delta
	if _lightning_timer <= 0.0:
		_lightning_timer = _rng.randf_range(LIGHTNING_MIN_INTERVAL, LIGHTNING_MAX_INTERVAL)
		lightning.emit(_rng.randf_range(0.55, 1.0))


func _update_cover() -> void:
	if _camera == null:
		return
	var query := PhysicsRayQueryParameters3D.create(
		_camera.global_position + Vector3(0.0, 0.5, 0.0),
		_camera.global_position + Vector3(0.0, COVER_HEIGHT, 0.0))
	query.collision_mask = VoxelDefs.COLLISION_LAYER_WORLD
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	_covered = not hit.is_empty()


func _build_rain() -> GPUParticles3D:
	var rain := _new_field("RainParticles", RAIN_PARTICLES, 0.7, AABB(Vector3(-24, -28, -24), Vector3(48, 48, 48)))
	var process_material := ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_material.emission_box_extents = Vector3(16.0, 1.0, 16.0)
	process_material.direction = Vector3(0.0, -1.0, 0.0)
	process_material.spread = 4.0
	process_material.initial_velocity_min = 16.0
	process_material.initial_velocity_max = 22.0
	process_material.gravity = Vector3(0.0, -12.0, 0.0)
	rain.process_material = process_material
	var quad := QuadMesh.new()
	quad.size = Vector2(0.025, 0.5)
	quad.material = _particle_material(rain_color, false, false, null)
	rain.draw_pass_1 = quad
	add_child(rain)
	return rain


func _build_snow() -> GPUParticles3D:
	var snow := _new_field("SnowParticles", SNOW_PARTICLES, 4.0, AABB(Vector3(-30, -24, -30), Vector3(60, 60, 60)))
	var process_material := ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_material.emission_box_extents = Vector3(22.0, 1.0, 22.0)
	process_material.direction = Vector3(-0.12, -1.0, -0.08).normalized()
	process_material.spread = 24.0
	process_material.initial_velocity_min = 0.7
	process_material.initial_velocity_max = 1.7
	process_material.gravity = SNOW_FALL_SPEED
	snow.process_material = process_material
	var quad := QuadMesh.new()
	quad.size = Vector2(0.1, 0.1)
	var texture := _soft_texture()
	quad.material = _particle_material(snow_color, true, false, texture)
	snow.draw_pass_1 = quad
	add_child(snow)
	return snow


func _build_mist() -> GPUParticles3D:
	var mist := _new_field("MistParticles", MIST_PARTICLES, 9.0, AABB(Vector3(-26, -8, -26), Vector3(52, 16, 52)))
	# Sit the fog field at camera level instead of the rain field's +8 offset.
	mist.position = Vector3(0.0, -8.0, 0.0)
	var process_material := ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_material.emission_box_extents = Vector3(18.0, 2.0, 18.0)
	process_material.direction = Vector3(1.0, 0.0, 0.0)
	process_material.spread = 180.0
	process_material.initial_velocity_min = 0.04
	process_material.initial_velocity_max = 0.22
	process_material.gravity = MIST_RISE_SPEED
	mist.process_material = process_material
	var quad := QuadMesh.new()
	quad.size = Vector2(7.0, 3.2)
	quad.material = _particle_material(mist_color, true, true, _soft_texture())
	mist.draw_pass_1 = quad
	add_child(mist)
	return mist


func _new_field(field_name: String, amount: int, lifetime: float, bounds: AABB) -> GPUParticles3D:
	var field := GPUParticles3D.new()
	field.name = field_name
	field.amount = amount
	field.lifetime = lifetime
	field.preprocess = lifetime
	field.local_coords = false
	field.visibility_aabb = bounds
	field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	field.emitting = false
	return field


func _particle_material(color: Color, soft: bool, keep_scale: bool, texture: Texture2D) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED if soft else BaseMaterial3D.BILLBOARD_FIXED_Y
	material.billboard_keep_scale = keep_scale
	material.albedo_color = color
	material.albedo_texture = texture
	material.vertex_color_use_as_albedo = false
	return material


## Soft radial alpha disc so flakes and mist read as soft puffs. Generated at
## runtime (not a recorded cue) and reused by both fields.
func _soft_texture() -> Texture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 32
	texture.height = 32
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	return texture
