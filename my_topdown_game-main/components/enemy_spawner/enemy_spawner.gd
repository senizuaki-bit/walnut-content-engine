class_name EnemySpawner
extends Node

@export var arena: Arena

var enemies: Array[Enemy] = []
var amount: int
var enemies_killed := 0


func _ready() -> void:
	EventBus.enemy.on_enemy_die.connect(_on_enemy_die)


func spawn_enemies(level_resource: LevelResource, room: LevelRoom) -> void:
	if level_resource.enemy_scenes.is_empty(): return
	await get_tree().create_timer(0.8).timeout
	amount = randi_range(level_resource.min_enemies_per_room, level_resource.max_enemies_per_room)
	for i in amount:
		var spawn_global_positons = room.to_global(room.get_free_spawn_position())
		var marker_instance: SpawnMarker = Global.SPAWN_MARKER.instantiate() as SpawnMarker
		get_parent().add_child(marker_instance)
		marker_instance.global_position = spawn_global_positons
		await marker_instance.animation_player.animation_finished
		var enemy_instance: Enemy = level_resource.enemy_scenes.pick_random().instantiate() as Enemy
		enemies.append(enemy_instance)
		get_parent().add_child(enemy_instance)
		enemy_instance.global_position = spawn_global_positons
		enemy_instance.parent_room = arena.current_room


func _on_enemy_die() -> void:
	enemies_killed += 1
	if enemies_killed >= amount:
		enemies.clear()
		enemies_killed = 0
		EventBus.rooms.emit_on_room_cleared()
