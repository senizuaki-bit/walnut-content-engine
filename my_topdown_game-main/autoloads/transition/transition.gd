extends Node

const START_PROGRESS := 0.0  ## 结束材质动画进度
const END_PROGRESS := 1.0  ## 结束材质动画进度
const EFFECT_TWEEN_TIME = 1.0 ## 过渡动画时间

@onready var effect: ColorRect = %Effect

func transition_to(scene_path: String) -> void:
	var tween := create_tween()
	tween.tween_property(effect.material, "shader_parameter/progress", END_PROGRESS, EFFECT_TWEEN_TIME)
	tween.finished.connect(_on_ransition_to_scene.bind(scene_path))


func _on_ransition_to_scene(scene_path: String) -> void:
	if not scene_path: return
	get_tree().change_scene_to_file(scene_path)
	var tween := create_tween()
	tween.tween_property(effect.material, "shader_parameter/progress", START_PROGRESS, EFFECT_TWEEN_TIME)


func show_transition_in() -> Tween:
	var tween := create_tween().set_trans(Tween.TRANS_SINE)
	tween.tween_property(effect.material, "shader_parameter/progress", END_PROGRESS, EFFECT_TWEEN_TIME)
	return tween


func show_transition_out() -> Tween:
	var tween := create_tween().set_trans(Tween.TRANS_SINE)
	tween.tween_property(effect.material, "shader_parameter/progress", START_PROGRESS, EFFECT_TWEEN_TIME)
	return tween
