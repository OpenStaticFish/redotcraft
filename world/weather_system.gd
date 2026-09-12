class_name WeatherSystem
extends Node3D

## Toggles between clear skies and rain. Rain is a camera-following GPU
## particle field that pauses when the camera is under cover; the actual
## atmosphere grading (sun, ambient, fog, sky, clouds) lives in DayNightCycle.

enum State { SUNNY, RAIN }

signal weather_changed(state: int)

const RAIN_PARTICLES := 1600
const COVER_CHECK_INTERVAL := 0.3
const COVER_HEIGHT := 24.0

@export var transition_seconds := 2.0
@export var rain_color := Color(0.62, 0.72, 0.88, 0.32)

var state: State = State.SUNNY
var rain_amount := 0.0

var _camera: Camera3D
var _day_night: DayNightCycle
var _rain: GPUParticles3D
var _cover_timer := 0.0
var _covered := false


func _ready() -> void:
	_rain = GPUParticles3D.new()
	_rain.name = "RainParticles"
	_rain.amount = RAIN_PARTICLES
	_rain.lifetime = 0.7
	_rain.preprocess = 0.7
	_rain.local_coords = false
	_rain.visibility_aabb = AABB(Vector3(-24.0, -28.0, -24.0), Vector3(48.0, 48.0, 48.0))
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain.emitting = false

	var process_material := ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_material.emission_box_extents = Vector3(16.0, 1.0, 16.0)
	process_material.direction = Vector3(0.0, -1.0, 0.0)
	process_material.spread = 4.0
	process_material.initial_velocity_min = 16.0
	process_material.initial_velocity_max = 22.0
	process_material.gravity = Vector3(0.0, -12.0, 0.0)
	_rain.process_material = process_material

	var quad := QuadMesh.new()
	quad.size = Vector2(0.025, 0.5)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	material.albedo_color = rain_color
	quad.material = material
	_rain.draw_pass_1 = quad

	add_child(_rain)


func setup(camera: Camera3D, day_night: DayNightCycle) -> void:
	_camera = camera
	_day_night = day_night
	if _day_night:
		_day_night.set_weather_dim(rain_amount)


func set_state(new_state: State) -> void:
	if new_state == state:
		return
	state = new_state
	weather_changed.emit(state)


func toggle() -> void:
	set_state(State.SUNNY if state == State.RAIN else State.RAIN)


func is_raining() -> bool:
	return state == State.RAIN


func _process(delta: float) -> void:
	var target := 1.0 if state == State.RAIN else 0.0
	if not is_equal_approx(rain_amount, target):
		rain_amount = move_toward(rain_amount, target, delta / maxf(transition_seconds, 0.01))
		if _day_night:
			_day_night.set_weather_dim(rain_amount)
	if _camera:
		global_position = _camera.global_position + Vector3(0.0, 8.0, 0.0)
	_cover_timer -= delta
	if _cover_timer <= 0.0:
		_cover_timer = COVER_CHECK_INTERVAL
		_update_cover()
	_rain.emitting = state == State.RAIN and not _covered


func _update_cover() -> void:
	if _camera == null:
		return
	var query := PhysicsRayQueryParameters3D.create(
		_camera.global_position + Vector3(0.0, 0.5, 0.0),
		_camera.global_position + Vector3(0.0, COVER_HEIGHT, 0.0))
	query.collision_mask = VoxelDefs.COLLISION_LAYER_WORLD
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	_covered = not hit.is_empty()
