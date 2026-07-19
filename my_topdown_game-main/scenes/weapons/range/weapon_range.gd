class_name WeaponRange
extends Weapon

const TILT_RANGE = 90 ## 武器翻转角度

@onready var fire_position: Marker2D = %FirePosition

var direction: Vector2
var coolfown: float

func _ready() -> void:
	sprite.texture = weapon_resource.icon


func _process(_delta: float) -> void:
	rotate_weapon()


func use_weapon() -> void:
	var bullet_instance: Bullet = weapon_resource.bullte_scene.instantiate() as Bullet
	get_tree().root.add_child(bullet_instance)
	bullet_instance.setup(weapon_resource)
	bullet_instance.global_position = fire_position.global_position
	bullet_instance.global_rotation = pivot.global_rotation + deg_to_rad(randf_range(-weapon_resource.spread, weapon_resource.spread))



func rotate_weapon() -> void:
	direction = get_global_mouse_position() - global_position
	# sprite引用在继承类
	sprite.flip_v = direction.x < 0
