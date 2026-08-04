extends Node

const SourceStage := preload("res://scenes/demo/loop_oasis/multi_scene/source_room_stage.gd")

var stage: SourceRoomStage
var clear_events := 0
var portal_events := 0


func _ready() -> void:
	if "--source-room-stage-test" not in OS.get_cmdline_user_args():
		return
	call_deferred("_run")


func _run() -> void:
	stage = SourceStage.new() as SourceRoomStage
	add_child(stage)
	await stage.build({
		"stage_id": "automated_stage",
		"title": "自动化实体房间",
		"capture_mode": true,
		"auto_reward_on_clear": false,
	})
	stage.room_cleared.connect(func() -> void: clear_events += 1)
	stage.portal_entered.connect(func() -> void: portal_events += 1)

	if not _require(is_instance_valid(stage.level_room), "ROOM_INSTANCE_MISSING"):
		return
	if not _require(is_instance_valid(stage.player), "PLAYER_INSTANCE_MISSING"):
		return
	if not _require(is_instance_valid(stage.player.weapon_controller.current_weapon), "WEAPON_INSTANCE_MISSING"):
		return
	if not _require(stage.room_sealed, "ROOM_NOT_SEALED"):
		return

	await stage.spawn_wave(3, 2.0)
	if not _require(stage.enemies_spawned == 3 and stage.enemies.size() == 3, "SPAWN_COUNT_MISMATCH"):
		return
	if not _require(not stage.reward_ready and not stage.portal_ready, "EARLY_REWARD_OR_PORTAL"):
		return
	print("SOURCE_ROOM_STAGE_SPAWN_OK")

	stage.use_loop_pulse()
	if not _require(stage.pulse_uses == 1 and stage.enemies.size() == 3, "PULSE_SHOULD_NOT_SKIP_SHOOTING"):
		return
	for _shot in range(3):
		stage.player.weapon_controller.current_weapon.use_weapon()
	await get_tree().process_frame
	await get_tree().process_frame
	if not _require(stage.shots_fired == 3, "PLAYER_SHOT_OBSERVER_MISMATCH"):
		return

	var last_enemy: Enemy = stage.enemies.back()
	for enemy in stage.enemies.duplicate():
		if is_instance_valid(enemy):
			enemy.health_component.take_damage(1.0)
	if is_instance_valid(last_enemy):
		last_enemy.health_component.take_damage(1.0)
	await get_tree().process_frame
	if not _require(stage.enemies_defeated == 3 and stage.enemies.is_empty(), "EXACT_KILL_COUNT_MISMATCH"):
		return
	if not _require(clear_events == 1, "CLEAR_EVENT_NOT_IDEMPOTENT"):
		return
	if not _require(stage.room_sealed and not stage.reward_ready, "CONTRACT_BYPASS_OPENED_ROOM"):
		return
	print("SOURCE_ROOM_STAGE_EXACT_KILL_OK")

	stage.complete_noncombat_room(false)
	stage.complete_noncombat_room(false)
	if not _require(not stage.room_sealed and stage.reward_ready, "VALIDATED_ROOM_DID_NOT_OPEN"):
		return
	if not _require(is_instance_valid(stage.chest) and not stage.portal_ready, "CHEST_PORTAL_SEQUENCE_INVALID"):
		return
	if not _require(clear_events == 1, "COMPLETION_DUPLICATED_CLEAR_EVENT"):
		return
	print("SOURCE_ROOM_STAGE_GATE_REWARD_OK")

	stage.teleport_player(stage.chest.global_position + Vector2(52, 0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	stage.teleport_player(stage.chest.global_position)
	for _frame in range(6):
		await get_tree().physics_frame
	if not _require(stage.chest_was_opened and stage.portal_ready and is_instance_valid(stage.portal), "PHYSICAL_CHEST_DID_NOT_REVEAL_PORTAL"):
		return

	stage.teleport_player(stage.portal.global_position)
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not _require(portal_events == 1, "PHYSICAL_PORTAL_EVENT_MISMATCH"):
		return
	print("SOURCE_ROOM_STAGE_PORTAL_OK")
	print("SOURCE_ROOM_STAGE_E2E_OK")
	# Source enemy hit/death effects own short SceneTreeTimers (the longest is
	# one second). Let those one-shot effects finish before the headless test
	# tears down the SceneTree, otherwise Godot reports false-positive timer
	# leaks even though normal gameplay keeps running long enough to resolve them.
	await get_tree().create_timer(1.25).timeout
	for child in get_tree().root.get_children():
		if child is Bullet or child is GPUParticles2D:
			child.queue_free()
	stage.queue_free()
	for _frame in range(3):
		await get_tree().process_frame
	get_tree().quit(0)


func _require(condition: bool, code: String) -> bool:
	if condition:
		return true
	push_error("SOURCE_ROOM_STAGE_TEST_FAIL [%s]" % code)
	get_tree().quit(2)
	return false
