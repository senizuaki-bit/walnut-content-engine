class_name PlayerSignal
extends Node

## 玩家生命更新信号
signal on_player_health_updated(current_health: float, max_health: float)

func emit_player_health_updated(current_health: float, max_health: float) -> void:
	on_player_health_updated.emit(current_health, max_health)
