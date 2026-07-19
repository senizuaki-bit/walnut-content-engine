class_name Player
extends CharacterBody2D

@export var player_resource: PlayerResource ## 玩家资源

@onready var visuais: Node2D = %Visuais ## 玩家视觉
@onready var player_animated_sprite: AnimatedSprite2D = %PlayerAnimatedSprite ## 玩家动画
@onready var health_component: HealthComponent = %HealthComponent
@onready var weapon_controller: WeaponController = %WeaponController

var can_move: bool = true ## 移动判断
var movement: Vector2 ## 移动
var direction: Vector2 ## 移动向量
var coolfown: float
var current_mana:float

func _ready() -> void:
	current_mana = player_resource.magic
	health_component.init_health(player_resource.max_hp)
	

func _process(delta: float) -> void:
	weapon_controller.target_position = get_global_mouse_position()
	weapon_controller.rotate_weapon()
	coolfown -= delta
	if Input.is_action_pressed("shoot") and current_mana > weapon_controller.current_weapon.weapon_resource.mana_cons:
		if coolfown <= 0:
			weapon_controller.current_weapon.use_weapon()
			coolfown = weapon_controller.current_weapon.weapon_resource.cooldown
			use_mana(weapon_controller.current_weapon.weapon_resource.mana_cons)


func _physics_process(_delta: float) -> void:
	if not can_move: return
	direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	rotate_player()
	if direction != Vector2.ZERO:
		movement = direction * player_resource.move_speed
		player_animated_sprite.play("move")
	else :
		movement = Vector2.ZERO
		player_animated_sprite.play("idle")
	velocity = movement
	move_and_slide()


func rotate_player() -> void:
	if direction != Vector2.ZERO:
		if direction == Vector2.LEFT:
			visuais.scale = Vector2(-1, 1)
		else :
			visuais.scale = Vector2(1, 1)


func use_mana(value: float) -> void:
	if current_mana < value: return
	current_mana -= value


func _on_health_component_on_unit_damaged(_amount: float) -> void:
	# 套个娃 防止event_bus过大
	EventBus.player.emit_player_health_updated(health_component.current_health, health_component.max_health)


func _on_health_component_on_unit_dead() -> void:
	queue_free()


func _on_health_component_on_unit_healed(_amount: float) -> void:
	EventBus.player.emit_player_health_updated(health_component.current_health, health_component.max_health)
