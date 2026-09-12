class_name DayNightCycle
extends Node

## Rotates the sun and grades sky, ambient light, fog, glow, and clouds through
## a 24-hour cycle. The custom sky shader derives stars and the moon phase from
## the sun direction; glowstone lights take over after dark.

const SUNRISE_HOUR := 6.0

const SUN_MAX_ENERGY := 1.15
const FILL_MAX_ENERGY := 0.12
const SUN_NOON_COLOR := Color(1.0, 0.96, 0.86)
const SUN_HORIZON_COLOR := Color(1.0, 0.5, 0.22)
const AMBIENT_DAY_COLOR := Color(0.72, 0.85, 0.97)
const AMBIENT_NIGHT_COLOR := Color(0.2, 0.27, 0.45)
const AMBIENT_DAY_ENERGY := 0.4
const AMBIENT_NIGHT_ENERGY := 0.15
const MOON_MAX_ENERGY := 0.22
const MOON_COLOR := Color(0.72, 0.81, 1.0)
const LUNAR_CYCLE_DAYS := 8.0
const FOG_DAY_COLOR := Color(0.66, 0.8, 0.98)
const FOG_NIGHT_COLOR := Color(0.03, 0.05, 0.11)
const CLOUD_DAY_TINT := Color.WHITE
const CLOUD_NIGHT_TINT := Color(0.1, 0.13, 0.22)
const SUN_YAW := -35.0
const SKY_TOP_DAY := Color(0.29, 0.53, 1.0)
const SKY_TOP_NIGHT := Color(0.015, 0.02, 0.06)
const SKY_HORIZON_DAY := Color(0.6, 0.78, 1.0)
const SKY_HORIZON_NIGHT := Color(0.04, 0.05, 0.1)
const SKY_HORIZON_SUNSET := Color(1.0, 0.45, 0.2)
const GROUND_HORIZON_DAY := Color(0.55, 0.72, 0.95)
const GROUND_HORIZON_NIGHT := Color(0.03, 0.04, 0.08)
const GROUND_HORIZON_SUNSET := Color(0.55, 0.3, 0.2)
const GROUND_BOTTOM_DAY := Color(0.35, 0.52, 0.82)
const GROUND_BOTTOM_NIGHT := Color(0.01, 0.015, 0.04)
const GLOW_THRESHOLD_DAY := 1.15
const GLOW_THRESHOLD_NIGHT := 1.05
const NIGHT_SATURATION := 0.78
const NIGHT_CONTRAST := 0.96
const RAIN_CLOUD_DAY := Color(0.3, 0.33, 0.4)
const RAIN_CLOUD_NIGHT := Color(0.07, 0.08, 0.11)
const RAIN_SKY_TOP_DAY := Color(0.27, 0.3, 0.37)
const RAIN_SKY_TOP_NIGHT := Color(0.035, 0.04, 0.062)
const RAIN_SKY_HORIZON_DAY := Color(0.42, 0.45, 0.52)
const RAIN_SKY_HORIZON_NIGHT := Color(0.05, 0.06, 0.09)
const RAIN_GROUND_HORIZON_DAY := Color(0.3, 0.33, 0.4)
const RAIN_GROUND_HORIZON_NIGHT := Color(0.035, 0.045, 0.07)
const RAIN_GROUND_BOTTOM_DAY := Color(0.16, 0.18, 0.24)
const RAIN_GROUND_BOTTOM_NIGHT := Color(0.02, 0.025, 0.045)
const RAIN_FOG_DAY := Color(0.42, 0.45, 0.52)
const RAIN_FOG_NIGHT := Color(0.045, 0.055, 0.085)
const RAIN_FOG_ADD := 0.01
const RAIN_SUN_FACTOR := 0.4
const RAIN_AMBIENT_FACTOR := 0.7

@export var sun_path := NodePath("../Sun")
@export var fill_light_path := NodePath("../SkyFill")
@export var moon_path := NodePath("../Moon")
@export var world_environment_path := NodePath("../WorldEnvironment")
@export var clouds_path := NodePath("../Clouds")
@export var auto_advance := true
@export var day_length_seconds := 1200.0
@export_range(0.0, 24.0, 0.1) var start_hour := 8.0

@onready var _sun: DirectionalLight3D = get_node_or_null(sun_path) as DirectionalLight3D
@onready var _fill_light: DirectionalLight3D = get_node_or_null(fill_light_path) as DirectionalLight3D
@onready var _moon: DirectionalLight3D = get_node_or_null(moon_path) as DirectionalLight3D
@onready var _world_environment: WorldEnvironment = get_node_or_null(world_environment_path) as WorldEnvironment
@onready var _clouds: CloudField = get_node_or_null(clouds_path) as CloudField

var time_hours := 0.0
var weather_dim := 0.0
var base_fog_density := 0.006
var base_saturation := 1.08
var base_contrast := 1.04
var _sky_material: ShaderMaterial
var _moon_phase := 0.5


func _ready() -> void:
	if _world_environment and _world_environment.environment:
		var sky := _world_environment.environment.sky
		if sky and sky.sky_material is ShaderMaterial:
			_sky_material = sky.sky_material
	time_hours = start_hour
	_apply()


func _process(delta: float) -> void:
	if auto_advance and day_length_seconds > 0.0:
		var step := minf(delta, 0.25)
		time_hours = fposmod(time_hours + step * 24.0 / day_length_seconds, 24.0)
		_moon_phase = fposmod(_moon_phase + step / day_length_seconds / LUNAR_CYCLE_DAYS, 1.0)
	_apply()


func set_time(hours: float) -> void:
	time_hours = fposmod(hours, 24.0)
	_apply()


func set_weather_dim(value: float) -> void:
	weather_dim = clampf(value, 0.0, 1.0)


func get_clock_text() -> String:
	var hours := int(time_hours)
	var minutes := int((time_hours - float(hours)) * 60.0)
	return "%02d:%02d" % [hours, minutes]


func _apply() -> void:
	if _sun == null or _world_environment == null or _world_environment.environment == null:
		return
	var elevation := (time_hours - SUNRISE_HOUR) / 24.0 * 360.0
	_sun.rotation_degrees = Vector3(-elevation, SUN_YAW, 0.0)
	var sun_height := sin(deg_to_rad(elevation))
	var day_factor := smoothstep(-0.08, 0.18, sun_height)
	var horizon_factor := clampf(1.0 - absf(sun_height) / 0.35, 0.0, 1.0)
	var weather_factor := lerpf(1.0, RAIN_SUN_FACTOR, weather_dim)
	_sun.light_energy = SUN_MAX_ENERGY * day_factor * weather_factor
	_sun.light_color = SUN_NOON_COLOR.lerp(SUN_HORIZON_COLOR, horizon_factor)
	if _fill_light:
		_fill_light.light_energy = FILL_MAX_ENERGY * day_factor * weather_factor
	if _moon:
		_moon.rotation_degrees = Vector3(-(elevation + 180.0), SUN_YAW, 0.0)
		_moon.light_energy = MOON_MAX_ENERGY * (1.0 - day_factor) * weather_factor
		_moon.light_color = MOON_COLOR
	var environment := _world_environment.environment
	var night_amount := 1.0 - day_factor
	environment.ambient_light_color = AMBIENT_DAY_COLOR.lerp(AMBIENT_NIGHT_COLOR, night_amount)
	environment.ambient_light_energy = lerpf(AMBIENT_NIGHT_ENERGY, AMBIENT_DAY_ENERGY, day_factor) * lerpf(1.0, RAIN_AMBIENT_FACTOR, weather_dim)
	environment.fog_light_color = FOG_DAY_COLOR.lerp(FOG_NIGHT_COLOR, night_amount).lerp(RAIN_FOG_NIGHT.lerp(RAIN_FOG_DAY, day_factor), weather_dim)
	environment.fog_density = base_fog_density + RAIN_FOG_ADD * weather_dim
	environment.glow_hdr_threshold = lerpf(GLOW_THRESHOLD_NIGHT, GLOW_THRESHOLD_DAY, day_factor)
	environment.adjustment_enabled = true
	environment.adjustment_saturation = base_saturation * lerpf(NIGHT_SATURATION, 1.0, day_factor)
	environment.adjustment_contrast = base_contrast * lerpf(NIGHT_CONTRAST, 1.0, day_factor)
	if _clouds:
		var cloud_tint := CLOUD_DAY_TINT.lerp(CLOUD_NIGHT_TINT, night_amount)
		_clouds.set_sky_tint(cloud_tint.lerp(RAIN_CLOUD_NIGHT.lerp(RAIN_CLOUD_DAY, day_factor), weather_dim))
	if _sky_material:
		var star_intensity := (1.0 - smoothstep(-0.25, 0.0, sun_height)) * (1.0 - weather_dim)
		var sky_top := SKY_TOP_DAY.lerp(SKY_TOP_NIGHT, night_amount).lerp(RAIN_SKY_TOP_NIGHT.lerp(RAIN_SKY_TOP_DAY, day_factor), weather_dim)
		var sky_horizon := SKY_HORIZON_DAY.lerp(SKY_HORIZON_NIGHT, night_amount).lerp(SKY_HORIZON_SUNSET, horizon_factor).lerp(RAIN_SKY_HORIZON_NIGHT.lerp(RAIN_SKY_HORIZON_DAY, day_factor), weather_dim)
		var ground_horizon := GROUND_HORIZON_DAY.lerp(GROUND_HORIZON_NIGHT, night_amount).lerp(GROUND_HORIZON_SUNSET, horizon_factor).lerp(RAIN_GROUND_HORIZON_NIGHT.lerp(RAIN_GROUND_HORIZON_DAY, day_factor), weather_dim)
		var ground_bottom := GROUND_BOTTOM_DAY.lerp(GROUND_BOTTOM_NIGHT, night_amount).lerp(RAIN_GROUND_BOTTOM_NIGHT.lerp(RAIN_GROUND_BOTTOM_DAY, day_factor), weather_dim)
		_sky_material.set_shader_parameter("sky_top_color", sky_top)
		_sky_material.set_shader_parameter("sky_horizon_color", sky_horizon)
		_sky_material.set_shader_parameter("ground_horizon_color", ground_horizon)
		_sky_material.set_shader_parameter("ground_bottom_color", ground_bottom)
		_sky_material.set_shader_parameter("star_intensity", star_intensity)
		_sky_material.set_shader_parameter("moon_phase", _moon_phase)
