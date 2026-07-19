class_name WeaponMelee
extends Weapon

@onready var cooldown: Timer = %Cooldown
@onready var slash: GPUParticles2D = %SlashParticle
@onready var animation_player: AnimationPlayer = %AnimationPlayer

var can_use: bool = true
var entitits: Array[Node2D]

func _ready() -> void:
	cooldown.wait_time = weapon_resource.cooldown


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("shoot"):
		use_weapon()


func use_weapon() -> void:
	if not can_use: return
	can_use = false
	cooldown.start()
	SFXPlayer.play(shoot_sound)
	animation_player.play("melee/slash")
	for enemy: Node2D in entitits:
		Global.create_demage_text(weapon_resource.demage, enemy.global_position)
	slash.global_rotation = pivot.global_rotation
	slash.emitting = true
	print(entitits)


func _on_cooldown_timeout() -> void:
	can_use = true
	animation_player.play("melee/idle")


func _on_hitbox_body_entered(body: Node2D) -> void:
	if not is_instance_valid(body): return # 检查当前节点是否有效
	entitits.append(body)

func _on_hitbox_body_exited(body: Node2D) -> void:
	if not is_instance_valid(body): return # 检查当前节点是否有效
	entitits.erase(body)
