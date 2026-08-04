class_name LoopPlayableScene
extends Node2D

## Shared interface for every top-level playable location.
##
## Scenes may animate, render and collect input however they need, but they are
## not allowed to mutate progression directly. They submit deterministic world
## evidence through this interface and receive an explicit result.

signal evidence_accepted(contract_id: String, result: Dictionary)
signal contract_failed(contract_id: String, error: String)
signal navigation_failed(scene_id: String, error: String)

var last_contract_result: Dictionary = {}
var last_contract_error := ""


func collect_completion_evidence() -> Dictionary:
	push_error("%s must implement collect_completion_evidence()" % get_script().resource_path)
	return {}


func submit_world_evidence(contract_id: String, evidence: Dictionary) -> Dictionary:
	var result: Dictionary = LoopRunState.submit_scene_evidence(contract_id, evidence)
	return _handle_contract_result(contract_id, result)


func submit_home_evidence(contract_id: String, evidence: Dictionary) -> Dictionary:
	var result: Dictionary = LoopRunState.commit_home_activity(contract_id, evidence)
	return _handle_contract_result(contract_id, result)


func navigate_to(scene_id: String) -> Dictionary:
	var result: Dictionary = SceneFlow.go(scene_id)
	if not bool(result.get("ok", false)):
		var error := str(result.get("error", "unknown_navigation_error"))
		push_error("SCENE_NAVIGATION_FAILED [%s]: %s" % [scene_id, error])
		navigation_failed.emit(scene_id, error)
	return result


func require_contract(result: Dictionary, context: String) -> bool:
	if bool(result.get("ok", false)):
		return true
	var error := str(result.get("error", "unknown_contract_error"))
	push_error("SCENE_CONTRACT_REQUIRED [%s]: %s" % [context, error])
	return false


func _handle_contract_result(contract_id: String, result: Dictionary) -> Dictionary:
	last_contract_result = result.duplicate(true)
	if bool(result.get("ok", false)):
		last_contract_error = ""
		evidence_accepted.emit(contract_id, result)
		return result
	last_contract_error = str(result.get("error", "unknown_contract_error"))
	push_error("SCENE_CONTRACT_REJECTED [%s]: %s" % [contract_id, last_contract_error])
	contract_failed.emit(contract_id, last_contract_error)
	return result
