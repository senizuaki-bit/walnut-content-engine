extends CanvasLayer

@onready var sprite: Sprite2D = %Sprite


func _ready() -> void:
	_sync_cursor_mode()


func _process(_delta: float) -> void:
	if sprite.visible:
		sprite.position = get_viewport().get_mouse_position()


func _on_sprite_texture_changed() -> void:
	_sync_cursor_mode()


func _sync_cursor_mode() -> void:
	# 只有确实存在自定义光标贴图时才隐藏系统鼠标。
	# 数据花园没有配置自定义贴图，因此始终保留可见的系统指针。
	var has_custom_cursor := sprite.texture != null
	sprite.visible = has_custom_cursor
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN if has_custom_cursor else Input.MOUSE_MODE_VISIBLE)
