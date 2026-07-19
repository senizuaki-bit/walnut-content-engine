class_name CharacterSelection
extends Control

const ARENA_PATH := "res://scenes/arena/arena.tscn"
const MAIN_MENU_PATH := "res://scenes/ui/main_menu/main_menu.tscn"
const PLAYER_CARD_SCENE = preload("uid://dgc8bf1w5ksd2")
const WEAPON_CARD_SCENE = preload("uid://b0bypmafxdd7o")

@export var selection_cursor: Texture2D
@export var sound_stream: AudioStream
@export var hover_stream: AudioStream
@export var players: Array[PlayerResource]
@export var weapons: Array[WeaponResource]

@onready var player_container: HBoxContainer = %PlayerContainer
@onready var weapon_container: HBoxContainer = %WeaponContainer


func _ready() -> void:
	Cursor.sprite.texture = selection_cursor
	clear_selection_items()
	load_selection_items()

## 清理初始化选项
func clear_selection_items() -> void:
	for item: Node in player_container.get_children():
		item.queue_free()
	for item: Node in weapon_container.get_children():
		item.queue_free()


## 加载选择项
func load_selection_items() -> void:
	for player_resource: PlayerResource in players:
		var player_card_instance := PLAYER_CARD_SCENE.instantiate() as PlayerCard
		player_container.add_child(player_card_instance)
		player_card_instance.pressed.connect(_on_player_card_pressed.bind(player_resource, player_card_instance))
		player_card_instance.player_resource = player_resource
	
	for weapon_resource: WeaponResource in weapons:
		var weapon_card_instance := WEAPON_CARD_SCENE.instantiate() as WeaponCard
		weapon_container.add_child(weapon_card_instance)
		weapon_card_instance.pressed.connect(_on_weapon_card_pressed.bind(weapon_resource, weapon_card_instance))
		weapon_card_instance.weapon_resource = weapon_resource



func _on_player_card_pressed(player_resource: PlayerResource, selected_card: PlayerCard) -> void:
	SFXPlayer.play(sound_stream)
	for card: PlayerCard in player_container.get_children():
		card.selector.hide()
	selected_card.selector.show()
	Global.selected_player = player_resource


func _on_weapon_card_pressed(weapon_resource: WeaponResource, selected_card: WeaponCard) -> void:
	SFXPlayer.play(sound_stream)
	for card: WeaponCard in weapon_container.get_children():
		card.selector.hide()
	selected_card.selector.show()
	Global.selected_weapon = weapon_resource


func _on_play_button_pressed() -> void:
	if not Global.selected_player or not Global.selected_weapon: return
	Transition.transition_to(ARENA_PATH)
	SFXPlayer.play(sound_stream)


func _on_back_button_pressed() -> void:
	Transition.transition_to(MAIN_MENU_PATH)
	SFXPlayer.play(sound_stream)


func _on_button_mouse_entered() -> void:
	SFXPlayer.play(hover_stream)
