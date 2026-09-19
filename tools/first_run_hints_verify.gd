## Focused headless regression check for the gradual first-run HUD hints.
## Run: redot --headless --path . --script res://tools/first_run_hints_verify.gd
extends SceneTree

const FirstRunHintsScript := preload("res://game/first_run_hints.gd")

var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var completed := {}
	var presentation := {"allowed": true}
	var bindings := {"move": "Arrows", "inventory": "I", "jump": "J"}
	var hud := Control.new()
	root.add_child(hud)
	var hints := _make_hints(hud, completed, bindings, func() -> bool: return bool(presentation["allowed"]))

	# Movement starts alone and uses the current rebound movement labels.
	hints.tick(2.0, false, false, false)
	_expect(hints.active_hint() == FirstRunHintsScript.HINT_MOVEMENT, "movement should be the first cue")
	_expect(hints.hint_text() == "Move with Arrows", "movement cue must use the live move label")
	hints.tick(0.1, true, false, false)
	_expect(bool(completed.get(FirstRunHintsScript.HINT_MOVEMENT, false)), "movement action should complete its cue")

	# Targeting waits for a real target, freezes under a hidden HUD/modal, and
	# then progresses to inventory once it has been shown or used.
	hints.tick(2.0, false, false, false)
	_expect(hints.active_hint().is_empty(), "targeting should wait for a target")
	hints.tick(0.1, false, true, false)
	_expect(hints.active_hint() == FirstRunHintsScript.HINT_TARGETING, "targeting should appear at a target")
	presentation["allowed"] = false
	hints.tick(FirstRunHintsScript.HINT_DURATION + 1.0, false, true, false)
	_expect(not bool(completed.get(FirstRunHintsScript.HINT_TARGETING, false)), "hidden HUD must freeze hint completion")
	_expect(not hints.is_hint_visible(), "hidden HUD must hide the active cue")
	presentation["allowed"] = true
	hints.observe_target_action()
	_expect(bool(completed.get(FirstRunHintsScript.HINT_TARGETING, false)), "mining or placement should complete targeting")
	hints.tick(2.0, false, false, false)
	_expect(hints.active_hint() == FirstRunHintsScript.HINT_INVENTORY, "inventory should follow targeting")
	_expect(hints.hint_text() == "I opens your inventory", "inventory cue must use the live binding")
	hints.observe_inventory_opened()
	_expect(bool(completed.get(FirstRunHintsScript.HINT_INVENTORY, false)), "opening inventory should complete its cue")

	# Flight is only queued in Creative and its rebound jump label updates while
	# active, rather than keeping the label that was present at startup.
	hints.set_creative(true)
	hints.tick(2.0, false, false, false)
	_expect(hints.active_hint() == FirstRunHintsScript.HINT_FLY, "Creative should receive the flight cue")
	_expect(hints.hint_text() == "Double-tap J to toggle flight", "flight cue must use the live jump binding")
	bindings["jump"] = "K"
	hints.tick(0.1, false, false, false)
	_expect(hints.hint_text() == "Double-tap K to toggle flight", "active flight cue must refresh after a rebind")
	hints.tick(0.1, false, false, true)
	_expect(bool(completed.get(FirstRunHintsScript.HINT_FLY, false)), "toggling flight should complete its cue")

	# Persisted completions prevent a second session from replaying the sequence.
	var resumed := _make_hints(hud, completed, bindings, func() -> bool: return true)
	resumed.set_creative(true)
	resumed.tick(10.0, false, true, false)
	_expect(resumed.active_hint().is_empty(), "completed hints must not replay")

	var survival_completed := {
		FirstRunHintsScript.HINT_MOVEMENT: true,
		FirstRunHintsScript.HINT_TARGETING: true,
		FirstRunHintsScript.HINT_INVENTORY: true,
	}
	var survival := _make_hints(hud, survival_completed, bindings, func() -> bool: return true)
	survival.tick(10.0, false, true, false)
	_expect(survival.active_hint().is_empty(), "Survival must not show Creative flight guidance")

	if _failures == 0:
		print("FIRST RUN HINTS VERIFY: PASS")
		quit(0)
		return
	print("FIRST RUN HINTS VERIFY: FAIL (%d)" % _failures)
	quit(1)


func _make_hints(hud: Control, completed: Dictionary, bindings: Dictionary, can_present: Callable) -> Node:
	var hints := FirstRunHintsScript.new()
	hints.completion_provider = func(hint: String) -> bool: return bool(completed.get(hint, false))
	hints.completion_recorder = func(hint: String) -> void: completed[hint] = true
	hints.move_hint_provider = func() -> String: return String(bindings["move"])
	hints.key_label_provider = func(action: String) -> String: return String(bindings["jump"] if action == "jump" else bindings["inventory"])
	hints.presentation_allowed = can_present
	hints.text_scale_provider = func() -> float: return 1.0
	hints.initialize(hud, false)
	root.add_child(hints)
	return hints


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("FIRST RUN HINTS VERIFY: %s" % message)
