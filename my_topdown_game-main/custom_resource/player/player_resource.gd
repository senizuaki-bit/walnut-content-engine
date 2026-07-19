class_name PlayerResource
extends Resource

## 玩家数据
@export_group("Player Data")
@export var player_id: String ## 玩家id
@export var Player_name: String ## 玩家名字
@export var max_hp := 5.0 ## 最大血量
@export var max_magic := 10.0 ## 最大法力
@export var move_speed := 200.0 ## 移动速度
@export var magic := 5.0 ## 法力值

## 玩家视觉
@export_group("palyer Visuais")
@export var icon: Texture2D ## 玩家图标
