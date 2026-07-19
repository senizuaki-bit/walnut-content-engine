class_name WeaponResource
extends Resource

## 武器数据
@export_group("Weapons Data")
@export var weapon_id: String ## 武器id
@export var weapon_name: String ## 武器名称
@export var demage: float  ## 武器伤害
@export var cooldown: float ## 冷却时间
@export var mana_cons: float ## 法力消耗
@export var spread: float ## 散布值
@export var bullet_speed: float ## 射速


## 武器视觉
@export_group("Weapons Visuais")
@export var icon: Texture2D ## 武器图标
@export var bullte_scene: PackedScene ## 子弹场景
@export_multiline var description: String ## 武器描述
