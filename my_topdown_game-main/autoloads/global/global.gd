extends Node

var save_setting_path := "user://settings.json"

const EXPLOSION_EFFECT = preload("uid://jmfg8wkw46yc")
const DAMAGE_TEXT = preload("uid://c0tpbghu8sfq7")
const SPAWN_MARKER = preload("uid://brmmx1ct7w4dh")
const DEAD_PARTICLE = preload("uid://cyxp6ptyt13ew")
const Hit_MATERIAL = preload("uid://bj4juvthkrjdh")
const BLOOD_EFFECT = preload("uid://dgvlwej56mhl6")
const TREASURE_BOX = preload("uid://ccw60j2l4l7wn")
const STORE_ITEM_BASE = preload("uid://cfms4bi4sivvp")
const PROTAL = preload("uid://d4f8air3sd4qg")

## 配置字典
var settings: Dictionary = {
	"music": true,
	"sfx": true,
	"fullscreen": false
}


## 角色场景
var player_scene: Dictionary[String, PackedScene] = {
	"Dog": preload("uid://rpd0au1i8457"),
	"Cat": preload("uid://dwhg4i6g6boml"),
	"Bunny": preload("uid://sbtvw5u0mwws"),
	"Mouse": preload("uid://dji0x6mq1dshp")
}


var weapons_scene: Dictionary[String, PackedScene] = {
	"Uzi": preload("uid://br5gwb7lsuxv7"),
	"Pistol": preload("uid://23bdolwaskmn"),
	"Rifles": preload("uid://b7u68q5ek6isv"),
	"Shotgun": preload("uid://bd853itgqoqts"),
	"Sniper": preload("uid://bhvdhklwqft3s"),
	"MachineGun": preload("uid://bc8duq2j4gc2g"),
	"SubmachineGun": preload("uid://luu61ow810kq"),
	"Sword": preload("uid://cp2qhf42hkeja"),
	"Axe": preload("uid://drdalhkurttxy")
}

var player_ref: Player
var conis: float
var selected_player: PlayerResource
var selected_weapon: WeaponResource


func _ready() -> void:
	load_date()


func create_explosion(position:Vector2) -> void:
	var explosion_instance: ExplosionEffect = EXPLOSION_EFFECT.instantiate()
	get_tree().root.add_child(explosion_instance)
	explosion_instance.position = position


func create_demage_text(damage: float, position:Vector2) -> void:
	var random_position = randf_range(0, TAU)
	var damage_text_instance: DamageText = DAMAGE_TEXT.instantiate()
	get_tree().root.add_child(damage_text_instance)
	damage_text_instance.damgea = damage
	damage_text_instance.global_position = position + Vector2.RIGHT.rotated(random_position) * 20 
	var blood_instance: BloodEffect = BLOOD_EFFECT.instantiate()
	get_tree().root.add_child(blood_instance)
	blood_instance.global_position = position

func create_dead_particle(texture: Texture, position: Vector2) -> void:
	var particle_instance: GPUParticles2D = DEAD_PARTICLE.instantiate()
	get_tree().root.add_child(particle_instance)
	particle_instance.texture = texture
	particle_instance.global_position = position
	particle_instance.emitting = true


func get_player_scene() -> PackedScene:
	return player_scene[selected_player.player_id]

func get_weapons_scene() -> PackedScene:
	return weapons_scene[selected_weapon.weapon_id]

## 保存配置
func save_date() -> void:
	var data =  settings.duplicate() # 对数据进行拷贝
	var file = FileAccess.open(save_setting_path, FileAccess.WRITE) # 打开文件设置写入操作
	file.store_string(JSON.stringify(data)) # 转成String保存
	file.close() # 关闭文件


## 读取文件
func load_date() -> void:
	if not FileAccess.file_exists(save_setting_path): return # 检查是否存在配置文件
	var file = FileAccess.open(save_setting_path, FileAccess.READ) # 打开文件设置读取操作
	var data = JSON.parse_string(file.get_as_text()) # 读取文件并转成JSON格式
	file.close() # 关闭文件
	settings = data # 获取输出保存至设置
	
