class_name Motion
extends RefCounted

## Small tween vocabulary shared by every menu and HUD flourish.
## Rule of thumb: animate in, hide instantly — outro tweens race with
## tree-pause and scene changes, so nothing here delays closing.


## Scale-and-rise pop used when a modal panel appears. Awaits one frame so
## the freshly-shown control has a real size to pivot around.
static func pop_in(control: Control, duration: float = 0.24, rise: float = 16.0) -> void:
	if control == null or not is_instance_valid(control):
		return
	await control.get_tree().process_frame
	if not is_instance_valid(control) or not control.visible:
		return
	control.pivot_offset = control.size * 0.5
	control.scale = Vector2(0.965, 0.965)
	control.modulate.a = 0.0
	var tween := control.create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(control, "scale", Vector2.ONE, duration)
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(control, "modulate:a", 1.0, duration * 0.6)


## Fade the dim backdrop of a modal layer in.
static func dim_in(dim: ColorRect, duration: float = 0.16) -> void:
	if dim == null or not is_instance_valid(dim):
		return
	dim.modulate.a = 0.0
	var tween := dim.create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(dim, "modulate:a", 1.0, duration)


## Staggered entrance for a column of controls (menu buttons).
static func stagger_in(controls: Array, step: float = 0.055, duration: float = 0.26) -> void:
	for control in controls:
		if is_instance_valid(control) and control is Control:
			(control as Control).modulate.a = 0.0
	var tree: SceneTree = null
	for control in controls:
		if is_instance_valid(control) and control is Control and (control as Control).get_tree() != null:
			tree = (control as Control).get_tree()
			break
	if tree == null:
		return
	await tree.process_frame
	for index in controls.size():
		var candidate: Variant = controls[index]
		if candidate == null or not is_instance_valid(candidate) or not (candidate is Control):
			continue
		var control := candidate as Control
		if not control.visible:
			continue
		control.pivot_offset = control.size * 0.5
		control.scale = Vector2(0.985, 0.985)
		var tween := control.create_tween()
		tween.set_parallel(true)
		tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(control, "modulate:a", 1.0, duration).set_delay(step * index)
		tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tween.tween_property(control, "scale", Vector2.ONE, duration).set_delay(step * index)


## Quick scale pulse used for hotbar slot selection.
static func pulse(control: Control, peak: float = 1.08, duration: float = 0.16) -> void:
	if control == null or not is_instance_valid(control):
		return
	control.pivot_offset = control.size * 0.5
	var tween := control.create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(control, "scale", Vector2(peak, peak), duration * 0.4)
	tween.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(control, "scale", Vector2.ONE, duration * 0.6)


## Gentle fade used for status toasts.
static func fade_in(control: Control, duration: float = 0.18) -> void:
	if control == null or not is_instance_valid(control):
		return
	control.modulate.a = 0.0
	var tween := control.create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(control, "modulate:a", 1.0, duration)
