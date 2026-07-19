class_name ShopSignal
extends Node

signal on_coin_picked

func emit_on_coin_picked() -> void:
	on_coin_picked.emit()
