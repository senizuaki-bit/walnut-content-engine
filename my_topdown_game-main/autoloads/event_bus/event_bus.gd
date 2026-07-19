extends Node

var player = PlayerSignal.new()
var rooms = RoomsSignal.new()
var enemy = EnemySignal.new()
var shop = ShopSignal.new()


func _ready() -> void:
	# 让信号节点进入场景树，由 EventBus 在退出时统一释放。
	# 原实现只 new() 不挂树，会在每次关闭游戏时留下 4 个孤儿节点。
	add_child(player)
	add_child(rooms)
	add_child(enemy)
	add_child(shop)
