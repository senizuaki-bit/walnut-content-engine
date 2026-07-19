class_name ItemsResource
extends Resource

enum RarityType {
	COMMON,
	RARE,
	EPIC,
}

@export_group("Item Data")
@export var item_id: String
@export var item_name: String
@export var value: float
@export var price: float
@export var rarity: RarityType = RarityType.COMMON



@export_group("Item Visuais")
@export var icon: Texture
@export_multiline var discription: String
