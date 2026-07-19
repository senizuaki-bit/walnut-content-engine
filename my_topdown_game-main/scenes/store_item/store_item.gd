class_name StoreItem
extends Area2D

@export var common_glow: Color
@export var rare_glow: Color
@export var epic_glow: Color


@onready var glow: Sprite2D = %Glow
@onready var sprite: Sprite2D = %Sprite
@onready var price_label: Label = %PriceLabel
@onready var discription_panel: DiscriptionPanel = %DiscriptionPanel


var item_resource: ItemsResource
var can_buy_item: bool

var glow_color = {
	ItemsResource.RarityType.COMMON: common_glow,
	ItemsResource.RarityType.RARE: rare_glow,
	ItemsResource.RarityType.EPIC: epic_glow
}



func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and can_buy_item:
		buy_item()


func setup(data: ItemsResource) -> void:
	item_resource = data
	sprite.texture = item_resource.icon
	glow.self_modulate = glow_color[item_resource.rarity]
	price_label.text = str(item_resource.price)
	discription_panel.text = item_resource.discription


func buy_item() -> void:
	if not item_resource: return
	if Global.conis < item_resource.price: return
	match item_resource.item_id:
		"Potion":
			Global.player_ref.health_component.heal(item_resource.value)
		"Mana":
			Global.player_ref.current_mana += item_resource.value
		"Magic":
			Global.player_ref.player_resource.magic += item_resource.value
		"Speed":
			Global.player_ref.player_resource.move_speed += item_resource.value
	Global.conis -= item_resource.price
	queue_free()


func _on_body_entered(_body: Node2D) -> void:
	can_buy_item = true
	discription_panel.animate_show()


func _on_body_exited(_body: Node2D) -> void:
	can_buy_item = false
	discription_panel.hide()
