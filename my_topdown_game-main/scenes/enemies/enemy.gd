class_name Enemy
extends CharacterBody2D

enum EnemyStates{
	FINDING_DESTINATION,
	MOVING,
	ATTACKING
}

@export_enum("Chase", "Weapon") var enemy_type := "Chase"
@export var hurt_sound: AudioStream
@export var icon_particle: Texture
@export var max_health := 5.0
@export var collision_damage := 2.0
@export var chase_speed := 60.0
@export var move_speed := 40.0
@export var weapon: WeaponResource

@onready var player_detector: Area2D = %PlayerDetector
@onready var animated_sprite: AnimatedSprite2D = %AnimatedSprite
@onready var health_bar: ProgressBar = %HealthBar
@onready var health_component: HealthComponent = %HealthComponent
@onready var enemy_detector: Area2D = %EnemyDetector
@onready var weapon_controller: WeaponController = %WeaponController


var can_move: bool = true
var is_killed: bool = false
var cooldown: float
var parent_room: LevelRoom
var enemy_state: EnemyStates
var move_destionation: Vector2


func _ready() -> void:
	health_bar.value = 1
	health_component.init_health(max_health)
	if not weapon: return
	weapon_controller.equip_weapon(weapon)


func _process(delta: float) -> void:
	if not Global.player_ref: return
	rotate_enemy()
	if enemy_state == EnemyStates.ATTACKING:
		manage_weapon(delta)


func _physics_process(_delta: float) -> void:
	if not Global.player_ref ||  not can_move: return
	match enemy_type:
		"Chase":
			run_enemy_chase()
		"Weapon":
			run_enemy_Weapon()


func run_enemy_chase() -> void:
	var direction = global_position.direction_to(Global.player_ref.global_position)
	for enemy in enemy_detector.get_overlapping_bodies():
		if enemy != self and enemy.is_inside_tree():
			var vector = global_position - enemy.global_position
			direction = 30 * vector.normalized() / vector.length()
	velocity = direction * chase_speed
	move_and_slide()


func run_enemy_Weapon() -> void:
	match enemy_state:
		EnemyStates.FINDING_DESTINATION:
			var local_position = parent_room.get_free_spawn_position()
			move_destionation = parent_room.to_global(local_position)
			enemy_state = EnemyStates.MOVING
		EnemyStates.MOVING:
			var direction = global_position.direction_to(move_destionation)
			velocity = direction * move_speed
			move_and_slide()
			if global_position.distance_to(move_destionation) < 2.0:
				velocity = Vector2.ZERO
				enemy_state = EnemyStates.ATTACKING
		EnemyStates.ATTACKING:
			velocity = Vector2.ZERO
			move_and_slide()
			await get_tree().create_timer(1.0).timeout
			enemy_state = EnemyStates.FINDING_DESTINATION


func rotate_enemy() -> void:
	if global_position.x > Global.player_ref.global_position.x:
		animated_sprite.flip_h = true
	elif  global_position.x < Global.player_ref.global_position.x:
		animated_sprite.flip_h = false


func enemy_daed() -> void:
	if is_killed: return
	is_killed = true
	Global.create_dead_particle(icon_particle, global_position)
	EventBus.enemy.emit_on_enemy_die()
	queue_free()


func manage_weapon(delta: float) -> void:
	if not weapon or not weapon_controller: return
	weapon_controller.target_position = Global.player_ref.global_position
	weapon_controller.rotate_weapon()
	cooldown -= delta
	if cooldown <= 0:
		weapon_controller.current_weapon.use_weapon()
		cooldown = weapon_controller.current_weapon.weapon_resource.cooldown


func _on_player_detector_body_entered(body: Node2D) -> void:
	body.health_component.take_damage(collision_damage)


func _on_health_component_on_unit_damaged(_amount: float) -> void:
	health_bar.value = health_component.current_health / max_health
	animated_sprite.material = Global.Hit_MATERIAL
	animated_sprite.play("hurt")
	await get_tree().create_timer(0.15).timeout
	animated_sprite.play("move")
	animated_sprite.material = null


func _on_health_component_on_unit_dead() -> void:
	enemy_daed()
