class_name Weapon
extends Node2D

@export var weapon_resource: WeaponResource
@export var shoot_sound: AudioStream

# 通用属性
@onready var pivot: Node2D = %Pivot
@onready var sprite: Sprite2D = %Sprite2D

func use_weapon() -> void:
	pass
