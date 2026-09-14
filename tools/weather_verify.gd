## Headless check for the weather ambience: biome classification, biome-aware
## snow/mist particle fields, lightning scheduling, the lightning flash on
## DayNightCycle, and the wind-sway shader/global wiring. Run:
##   redot --headless --path . --script res://tools/weather_verify.gd
extends SceneTree

const WeatherSystemScript = preload("res://world/weather_system.gd")
const DayNightScript = preload("res://world/day_night_cycle.gd")

var _failures := 0


func _initialize() -> void:
	process_frame.connect(_verify, CONNECT_ONE_SHOT)


func _verify() -> void:
	_check_biome_classification()
	_check_particles()
	_check_lightning_schedule()
	_check_lightning_flash()
	_check_wind_wiring()
	if _failures == 0:
		print("WEATHER VERIFY: PASS")
		quit(0)
		return
	print("WEATHER VERIFY: FAIL (%d)" % _failures)
	quit(1)


func _check_biome_classification() -> void:
	for biome in [BiomeCatalog.SNOW, BiomeCatalog.TAIGA, BiomeCatalog.HIGHLANDS, BiomeCatalog.FROZEN_OCEAN]:
		_expect(BiomeCatalog.is_cold_biome(biome), "biome %d should classify cold" % biome)
	for biome in [BiomeCatalog.PLAINS, BiomeCatalog.FOREST, BiomeCatalog.DESERT, BiomeCatalog.JUNGLE, BiomeCatalog.SWAMP]:
		_expect(not BiomeCatalog.is_cold_biome(biome), "biome %d should not classify cold" % biome)
	_expect(BiomeCatalog.is_wetland_biome(BiomeCatalog.SWAMP), "swamp should classify wetland")
	_expect(not BiomeCatalog.is_wetland_biome(BiomeCatalog.PLAINS), "plains should not classify wetland")
	_expect(WeatherSystemScript.precipitation_for_biome(BiomeCatalog.SNOW) == WeatherSystemScript.Precipitation.SNOW,
		"cold biome should precipitate snow")
	_expect(WeatherSystemScript.precipitation_for_biome(BiomeCatalog.PLAINS) == WeatherSystemScript.Precipitation.RAIN,
		"warm biome should precipitate rain")


func _check_particles() -> void:
	var weather := WeatherSystemScript.new()
	weather.name = "WeatherVerify"
	get_root().add_child(weather)
	_expect(weather._rain is GPUParticles3D, "rain particle field missing")
	_expect(weather._snow is GPUParticles3D, "snow particle field missing")
	_expect(weather._mist is GPUParticles3D, "mist particle field missing")
	_expect(weather.get_precipitation() == WeatherSystemScript.Precipitation.NONE, "clear sky should report no precipitation")

	weather._cold = true
	weather._wetland = false
	weather._update_particles()
	_expect(weather._snow.emitting, "snow field should emit in a cold biome")
	_expect(not weather._rain.emitting, "rain field should stay off in a cold biome")

	weather._cold = false
	weather._wetland = true
	weather._update_particles()
	_expect(weather._mist.emitting, "mist field should emit in a wetland biome")
	_expect(not weather._snow.emitting, "snow field should stop outside a cold biome")

	weather.free()


func _check_lightning_schedule() -> void:
	var weather := WeatherSystemScript.new()
	weather.name = "LightningVerify"
	get_root().add_child(weather)
	var strikes: Array = []
	weather.lightning.connect(func(strength: float) -> void: strikes.append(strength))
	weather.set_state(WeatherSystemScript.State.RAIN)
	weather.rain_amount = 1.0
	weather._covered = false
	weather._cold = false
	weather._lightning_timer = -1.0
	weather._update_lightning(0.0)
	weather._lightning_timer = 0.05
	weather._update_lightning(0.1)
	_expect(strikes.size() == 1, "rain storm should schedule a lightning strike")
	if strikes.size() == 1:
		_expect(float(strikes[0]) > 0.0 and float(strikes[0]) <= 1.0, "strike strength should be normalized")

	# Cold (snow) storms and covered cameras must not strike.
	strikes.clear()
	weather._cold = true
	weather._lightning_timer = 0.05
	weather._update_lightning(0.1)
	_expect(strikes.is_empty(), "snow storms should not trigger lightning")
	strikes.clear()
	weather._cold = false
	weather._covered = true
	weather._lightning_timer = 0.05
	weather._update_lightning(0.1)
	_expect(strikes.is_empty(), "a covered camera should not trigger lightning")
	weather.free()


func _check_lightning_flash() -> void:
	var day: Node = DayNightScript.new()
	day.trigger_lightning(0.8)
	_expect(float(day.lightning_flash) >= 0.79, "trigger_lightning should raise the flash")
	day._process(0.1)
	_expect(float(day.lightning_flash) < 0.8, "the lightning flash should decay")
	day.set_wind_strength(0.0)
	_expect(is_equal_approx(float(day.wind_strength), 0.0), "set_wind_strength should clamp to zero")
	day.set_wind_strength(0.7)
	_expect(is_equal_approx(float(day.wind_strength), 0.7), "set_wind_strength should store the value")
	day.free()


func _check_wind_wiring() -> void:
	var shader_file := FileAccess.open("res://world/block.gdshader", FileAccess.READ)
	_expect(shader_file != null, "block.gdshader should be readable")
	if shader_file != null:
		var text := shader_file.get_as_text()
		_expect("global uniform float wind_strength" in text, "block.gdshader should declare the wind_strength global")
		_expect("COLOR.a" in text, "block.gdshader should read the per-vertex wind weight from COLOR.a")
	var globals: Variant = ProjectSettings.get_setting("shader_globals/wind_strength", null)
	_expect(typeof(globals) == TYPE_DICTIONARY and (globals as Dictionary).has("value"),
		"project.godot should register the wind_strength shader global")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("weather_verify: %s" % message)
