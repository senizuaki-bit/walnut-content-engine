class_name WeaponController
extends Node2D

var current_weapon: Weapon ## 当前武器
var target_position: Vector2  ## 发射位置


func equip_weapon(weapon_resource: WeaponResource) -> void:
	var weapon_instance := Global.weapons_scene[weapon_resource.weapon_id].instantiate()
	add_child(weapon_instance)
	current_weapon = weapon_instance
	current_weapon.position.y = -8
	current_weapon.weapon_resource = weapon_resource

func rotate_weapon() -> void:
	if not current_weapon: return
	current_weapon.pivot.look_at(target_position)
