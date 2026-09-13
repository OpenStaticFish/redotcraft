# Redot MCP issues

Observed with Redot Engine 26.2-stable on 2026-09-13. The MCP server is launched
from `.opencode/opencode.jsonc` with the installed `redot --headless --mcp-server`
and this project as its `--path`.

## Scene script resources cannot be assigned

**Status:** Reproducible capability gap or serialization bug in
`redot_scene_action.set_prop`.

The tool can create a scene and set ordinary JSON-compatible properties, but it
does not convert a resource path into the typed `Script` resource required by a
node's `script` property.

Reproduction:

1. Create a scene with a `Node` root using `redot_scene_action.create`.
2. Call `redot_scene_action.set_prop` for node `.`, property `script`, and value
   `"res://tools/player_target_verify.gd"`.
3. Inspect the generated `.tscn`.

Actual output:

```ini
[node name="PlayerTargetVerify" type="Node"]
script = "res://tools/player_target_verify.gd"
```

Passing `{ "path": "res://tools/player_target_verify.gd" }` instead produces a
literal dictionary:

```ini
script = {
"path": "res://tools/player_target_verify.gd"
}
```

Neither form attaches or executes the script. The required scene representation
is a typed external resource:

```ini
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tools/player_target_verify.gd" id="1_target"]

[node name="PlayerTargetVerify" type="Node"]
script = ExtResource("1_target")
```

Expected behavior: the scene tool should accept a resource-path value for typed
resource properties and create/reuse the corresponding `ExtResource` entry.

Current workaround: make the minimal `.tscn` correction manually, then inspect
the diff. This conflicts with the preferred project rule to make all scene edits
through `redot_scene_action`, so it should remain an explicit exception.

## Runtime class cache does not refresh

**Status:** Reproducible within the same MCP session; likely a cache-refresh
limitation.

After adding `class_name PlayerTargetVerify` and successfully running an editor
scan, `redot_scene_action.create` still returned:

```text
Error: Unknown node type: PlayerTargetVerify
```

The MCP server process was started before the class was added. Restarting
OpenCode/MCP is the known way to refresh that process, but there is no exposed
MCP action to rescan global script classes in place.

Expected behavior: scene creation should either refresh registered script
classes or expose a class-rescan/reload operation.

## Intermittent request timeouts

**Status:** Intermittent reliability issue, separate from the serialization gap.

During the same session, `redot_project_config.run`,
`redot_project_config.output`, `redot_game_control.capture`, and
`redot_scene_action` returned MCP error `-32001: Request timed out`. Later,
`get_info` and scene inspection worked again without project changes.

This does not establish one root cause, but it shows that a timeout alone should
not be treated as evidence of invalid project data. Check for a running game or
stalled MCP process and retry/restart the MCP session.

## Not MCP issues

- A Redot `--script` custom `SceneTree` does not initialize project autoload
  identifiers early enough to compile `player/player.gd` in this test setup.
  Running the check as a normal project scene resolves it.
- `RefCounted.free()` is invalid. The target-test cleanup error encountered after
  the scene workaround was a harness bug, not an MCP problem.
