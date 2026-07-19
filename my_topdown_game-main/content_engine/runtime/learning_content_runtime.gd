class_name LearningContentRuntime
extends RefCounted

## 内容引擎运行内核。
##
## 它只解释受限的 Sequence / Repeat / Action IR，不执行任意脚本。
## 世界皮肤、动作绑定、目标数量与诊断规则全部来自编译后的内容包。

var manifest: Dictionary = {}
var max_execution_steps := 100
var manifest_path := ""


func load_manifest(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "content_manifest_not_found", "path": path}
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return {"ok": false, "error": "content_manifest_open_failed", "path": path}
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return {"ok": false, "error": "content_manifest_invalid_json", "path": path}
	manifest = parsed
	manifest_path = path
	max_execution_steps = int(manifest.get("program_semantics", {}).get("max_execution_steps", 100))
	if manifest.get("world_skins", []).size() < 2:
		return {"ok": false, "error": "content_manifest_requires_two_skins", "path": path}
	return {
		"ok": true,
		"unit_id": str(manifest.get("unit_id", "")),
		"version": str(manifest.get("version", "")),
		"content_hash": str(manifest.get("content_hash", "")),
	}


func metadata() -> Dictionary:
	return {
		"unit_id": str(manifest.get("unit_id", "")),
		"version": str(manifest.get("version", "")),
		"content_hash": str(manifest.get("content_hash", "")),
		"event_schema_version": str(manifest.get("evidence", {}).get("event_schema_version", "1.0.0")),
	}


func get_skin_target_count(skin_id: String, fallback: int) -> int:
	var skin := _find_skin(skin_id)
	return int(skin.get("target_count", fallback)) if not skin.is_empty() else fallback


func get_skin_action_id(skin_id: String, fallback: String) -> String:
	var skin := _find_skin(skin_id)
	return str(skin.get("action_id", fallback)) if not skin.is_empty() else fallback


func get_main_skin_id(fallback: String) -> String:
	return str(manifest.get("world", {}).get("main_skin_id", fallback))


func get_transfer_skin_id(fallback: String) -> String:
	return str(manifest.get("world", {}).get("transfer_skin_id", fallback))


func get_skin_display(skin_id: String, fallback: Dictionary = {}) -> Dictionary:
	var skin := _find_skin(skin_id)
	if skin.is_empty():
		return fallback.duplicate(true)
	var display = skin.get("display", {})
	return display.duplicate(true) if display is Dictionary else fallback.duplicate(true)


func get_transfer_variant(variant_id: String) -> Dictionary:
	if variant_id.is_empty():
		return {}
	for variant in manifest.get("transfer_variants", []):
		if variant is Dictionary and str(variant.get("variant_id", "")) == variant_id:
			return variant.duplicate(true)
	return {}


func resolve_asset_path(asset_ref: String) -> String:
	var value := asset_ref.strip_edges()
	if value.is_empty() or value.begins_with("res://") or value.begins_with("user://") or value.is_absolute_path():
		return value
	return manifest_path.get_base_dir().path_join(value).simplify_path()


func load_skin_texture(skin_id: String, asset_key: String, fallback_path: String = "") -> Texture2D:
	var skin := _find_skin(skin_id)
	var asset_ref := str(skin.get("assets", {}).get(asset_key, "")) if not skin.is_empty() else ""
	var resolved := resolve_asset_path(asset_ref)
	if not resolved.is_empty() and FileAccess.file_exists(resolved):
		var integrity_key := "%s/%s" % [skin_id, asset_key]
		var expected_hash := str(manifest.get("asset_integrity", {}).get(integrity_key, {}).get("sha256", ""))
		if not expected_hash.is_empty() and FileAccess.get_sha256(resolved) != expected_hash:
			push_error("CONTENT_ASSET_HASH_MISMATCH: %s" % integrity_key)
		else:
			var image := Image.load_from_file(resolved)
			if image and not image.is_empty():
				return ImageTexture.create_from_image(image)
	if fallback_path.is_empty():
		return null
	return load(fallback_path) as Texture2D


func make_repeat_program(action_id: String, count: int, node_prefix: String = "program") -> Dictionary:
	return {
		"type": "Sequence",
		"node_id": "%s_sequence" % node_prefix,
		"children": [
			{
				"type": "Repeat",
				"node_id": "%s_repeat" % node_prefix,
				"count": count,
				"body": {
					"type": "Action",
					"node_id": "%s_action" % node_prefix,
					"action_id": action_id,
				},
			},
		],
	}


func execute(program: Dictionary, skin_id: String, target_count_override: int = -1) -> Dictionary:
	var skin := _find_skin(skin_id)
	if skin.is_empty():
		return _invalid_result("UNKNOWN_SKIN", "unknown_skin:%s" % skin_id)
	if target_count_override >= 2:
		skin = skin.duplicate(true)
		skin.target_count = target_count_override

	var entities: Array = []
	for index in range(int(skin.get("target_count", 0))):
		entities.append({
			"id": "%s_%d" % [str(skin.get("entity_type", "target")), index],
			"index": index,
			"state": str(skin.get("initial_state", "pending")),
		})

	var result := {
		"skin_id": skin_id,
		"template_id": str(skin.get("template_id", "")),
		"program": program.duplicate(true),
		"world_state": {"entities": entities},
		"trace": [],
		"errors": [],
		"execution_steps": 0,
		"no_target_actions": 0,
		"step_limit_exceeded": false,
		"goal_met": false,
		"completed_targets": 0,
		"diagnosis": {},
	}

	_validate_node(program, result)
	if result.errors.is_empty():
		var context := {"iteration": -1, "skin": skin}
		_execute_node(program, context, result)

	var completed_state := str(skin.get("completed_state", "complete"))
	var completed := 0
	for entity in result.world_state.entities:
		if str(entity.get("state", "")) == completed_state:
			completed += 1
	result.completed_targets = completed
	result.goal_met = completed == entities.size()
	result.diagnosis = _diagnose(program, skin, result)
	return result


func trace_summary(result: Dictionary) -> Dictionary:
	return {
		"diagnosis_id": str(result.get("diagnosis", {}).get("id", "NOT_RUN")),
		"execution_steps": int(result.get("execution_steps", 0)),
		"completed_targets": int(result.get("completed_targets", 0)),
		"no_target_actions": int(result.get("no_target_actions", 0)),
		"goal_met": bool(result.get("goal_met", false)),
	}


func _find_skin(skin_id: String) -> Dictionary:
	for candidate in manifest.get("world_skins", []):
		if str(candidate.get("skin_id", "")) == skin_id:
			return candidate
	return {}


func _find_action(action_id: String) -> Dictionary:
	for candidate in manifest.get("world_actions", []):
		if str(candidate.get("action_id", "")) == action_id:
			return candidate
	return {}


func _validate_node(node: Dictionary, result: Dictionary) -> void:
	var node_type := str(node.get("type", ""))
	var allowed: Array = manifest.get("program_semantics", {}).get("allowed_nodes", [])
	if node_type not in allowed:
		result.errors.append("unsupported_node:%s" % node_type)
		return
	match node_type:
		"Sequence":
			for child in node.get("children", []):
				if child is Dictionary:
					_validate_node(child, result)
				else:
					result.errors.append("invalid_sequence_child")
		"Repeat":
			if int(node.get("count", -1)) < 0:
				result.errors.append("invalid_repeat_count")
			var body = node.get("body", {})
			if body is Dictionary and not body.is_empty():
				_validate_node(body, result)
		"Action":
			if str(node.get("action_id", "")).is_empty():
				result.errors.append("missing_action_id")


func _execute_node(node: Dictionary, context: Dictionary, result: Dictionary) -> void:
	if result.step_limit_exceeded:
		return
	if int(result.execution_steps) >= max_execution_steps:
		result.step_limit_exceeded = true
		_trace(result, node, "step_limit_exceeded", context)
		return
	result.execution_steps = int(result.execution_steps) + 1
	var node_type := str(node.get("type", ""))
	match node_type:
		"Sequence":
			_trace(result, node, "sequence_entered", context)
			for child in node.get("children", []):
				_execute_node(child, context, result)
				if result.step_limit_exceeded:
					break
			_trace(result, node, "sequence_finished", context)
		"Repeat":
			var count := int(node.get("count", 0))
			_trace(result, node, "repeat_entered", context, {"repeat_count": count})
			var body: Dictionary = node.get("body", {})
			for iteration in range(count):
				context.iteration = iteration
				_trace(result, node, "repeat_iteration_started", context, {"iteration": iteration})
				_execute_node(body, context, result)
				if result.step_limit_exceeded:
					break
			_trace(result, node, "repeat_finished", context, {"repeat_count": count})
		"Action":
			_execute_action(node, context, result)


func _execute_action(node: Dictionary, context: Dictionary, result: Dictionary) -> void:
	var action_id := str(node.get("action_id", ""))
	var action := _find_action(action_id)
	var skin: Dictionary = context.skin
	if action.is_empty() or action_id != str(skin.get("action_id", "")):
		result.errors.append("wrong_action:%s" % action_id)
		_trace(result, node, "action_rejected", context, {"action_id": action_id})
		return

	var from_state := str(action.get("from_state", "pending"))
	var to_state := str(action.get("to_state", "complete"))
	var target: Dictionary = {}
	for entity in result.world_state.entities:
		if str(entity.get("state", "")) == from_state:
			target = entity
			break

	if target.is_empty():
		result.no_target_actions = int(result.no_target_actions) + 1
		_trace(result, node, "action_no_target", context, {
			"action_id": action_id,
			"feedback": str(action.get("no_target_feedback", "")),
		})
		return

	var before_state := str(target.get("state", ""))
	target.state = to_state
	_trace(result, node, "action_effect_applied", context, {
		"action_id": action_id,
		"target_id": str(target.get("id", "")),
		"target_index": int(target.get("index", -1)),
		"before_state": before_state,
		"after_state": to_state,
	})


func _trace(result: Dictionary, node: Dictionary, event_name: String, context: Dictionary, extra: Dictionary = {}) -> void:
	var event := {
		"trace_index": result.trace.size(),
		"event_name": event_name,
		"node_id": str(node.get("node_id", "")),
		"node_type": str(node.get("type", "")),
		"iteration": int(context.get("iteration", -1)),
	}
	for key in extra:
		event[key] = extra[key]
	result.trace.append(event)


func _diagnose(program: Dictionary, skin: Dictionary, result: Dictionary) -> Dictionary:
	if result.step_limit_exceeded:
		return {"id": "STEP_LIMIT_EXCEEDED", "mastery": false}
	if not result.errors.is_empty():
		if result.errors.any(func(value): return str(value).begins_with("wrong_action:")):
			return {"id": "WRONG_ACTION", "mastery": false}
		return {"id": "INVALID_PROGRAM", "mastery": false, "errors": result.errors.duplicate()}
	if not _program_contains_node(program, "Repeat"):
		return {"id": "MISSING_REPEAT", "mastery": false}
	if _repeat_body_empty(program):
		return {"id": "EMPTY_LOOP_BODY", "mastery": false}
	if int(result.no_target_actions) > 0:
		return {"id": "COUNT_TOO_LARGE", "mastery": false}
	if int(result.completed_targets) < int(skin.get("target_count", 0)):
		return {"id": "COUNT_TOO_SMALL", "mastery": false}
	if bool(result.goal_met):
		return {"id": "SUCCESS", "mastery": true}
	return {"id": "INCOMPLETE", "mastery": false}


func _program_contains_node(node: Dictionary, wanted_type: String) -> bool:
	if str(node.get("type", "")) == wanted_type:
		return true
	if str(node.get("type", "")) == "Sequence":
		for child in node.get("children", []):
			if child is Dictionary and _program_contains_node(child, wanted_type):
				return true
	elif str(node.get("type", "")) == "Repeat":
		var body = node.get("body", {})
		if body is Dictionary and _program_contains_node(body, wanted_type):
			return true
	return false


func _repeat_body_empty(node: Dictionary) -> bool:
	if str(node.get("type", "")) == "Repeat":
		var body = node.get("body", {})
		return not body is Dictionary or body.is_empty()
	if str(node.get("type", "")) == "Sequence":
		for child in node.get("children", []):
			if child is Dictionary and _repeat_body_empty(child):
				return true
	return false


func _invalid_result(diagnosis_id: String, error: String) -> Dictionary:
	return {
		"trace": [],
		"errors": [error],
		"execution_steps": 0,
		"no_target_actions": 0,
		"goal_met": false,
		"completed_targets": 0,
		"world_state": {"entities": []},
		"diagnosis": {"id": diagnosis_id, "mastery": false},
	}
