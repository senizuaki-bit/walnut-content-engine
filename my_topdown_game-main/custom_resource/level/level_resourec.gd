class_name LevelResource
extends Resource

@export_group("Level Resource") ## 关卡资源
@export var num_sub_levels := 4 ## 子层级
@export var num_rooms := 5 ## 房间数量

@export_group("Room Resource") ## 房间数据
@export var min_enemies_per_room := 5 ## 房间最大敌人
@export var max_enemies_per_room := 10 ## 房间最小敌人
@export var min_props_per_room := 3 ## 房间最小道具
@export var max_props_per_room := 6 ## 房间最大道具
@export var room_size := Vector2i(384, 384) ## 房间大小
@export var room_scene: PackedScene ## 房间场景

@export_group("Corridor Resource") ## 过道数据
@export var corridor_size:= Vector2i(192, 192) ## 过道大小
@export var h_corridor: PackedScene ## 横向过道
@export var v_corridor: PackedScene ## 纵向过道

@export_group("Other Scene") ## 其他场景
@export var props: Array[PackedScene] ## 道具场景
@export var enemy_scenes: Array[PackedScene] ## 敌人场景
@export var store_resource: Array[LevelStoreResource] ## 商店资源

func get_random_store_item() -> ItemsResource:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var weights: PackedFloat32Array = []
	for item in store_resource:
		weights.append(item.item_prob)
	var index = rng.rand_weighted(weights)
	return store_resource[index].item_resource
