class_name MainMenu
extends Control

const CHARACTER_SELECTION = "res://scenes/ui/character_selection/character_selection.tscn"

const BusType: Dictionary = {
	"MUSIC": "Music",
	"SFX": "SFX"
} 

const MAIN_TWEEN_TIME = 0.2 ## 主窗口补间时长
const SETTINGS_TWEEN_TIME = 0.3 ## 设置窗口补间时长

@export var meun_cursor: Texture2D
@export var music_stream: AudioStream
@export var hover_stream: AudioStream
@export var sound_stream: AudioStream

@onready var main_buttons: Control = %MainButtons ## 主窗口按钮组
@onready var settings_buttons: Control = %SettingsButtons ## 设置按钮组

@onready var music_label: Label = %MusicLabel ## 音乐label
@onready var sfx_label: Label = %SFXLabel ## 音效label
@onready var window_label: Label = %WindowLabel ## 窗口label


var main_buttons_position: Vector2
var settings_buttons_position_x: float


func _ready() -> void:
	# 国际化配置
	TranslationServer.set_locale("zh")
	Cursor.sprite.texture = meun_cursor
	update_audio_bus(BusType.MUSIC, music_label, Global.settings.music)
	update_audio_bus(BusType.SFX, sfx_label, Global.settings.sfx)
	update_fullscreen(Global.settings.fullscreen)
	
	main_buttons_position = main_buttons.position
	settings_buttons_position_x = settings_buttons.position.x
	
	# 播放背景音乐
	MusicPlayer.play(music_stream)


func update_audio_bus(bus_name: String, label: Label, is_on: bool) -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index(bus_name), is_on)
	var key_name = tr("KEY_MUSIC") if bus_name == BusType.MUSIC else tr("KEY_SFX")
	var key_value = tr("KEY_ON") if is_on else tr("KEY_OFF")
	label.text = key_name + ": " + key_value
	

func update_fullscreen(is_on: bool) -> void:
	var mode = DisplayServer.WINDOW_MODE_FULLSCREEN if is_on else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)
	var key_value = tr("KEY_ON") if is_on else tr("KEY_OFF")
	window_label.text = tr("KEY_WINDOW") + ": " + key_value


func _on_play_button_pressed() -> void:
	Transition.transition_to(CHARACTER_SELECTION)
	SFXPlayer.play(sound_stream)


func _on_settings_button_pressed() -> void:
	SFXPlayer.play(sound_stream)
	var viewport_y := get_viewport_rect().size.y
	var tween := create_tween()
	tween.tween_property(main_buttons, "global_position:y", viewport_y, MAIN_TWEEN_TIME)
	tween.tween_interval(0.1)
	tween.tween_property(settings_buttons, "global_position:x", main_buttons_position.x, SETTINGS_TWEEN_TIME)


func _on_quit_button_pressed() -> void:
	SFXPlayer.play(sound_stream)
	Global.save_date()
	get_tree().quit()


func _on_music_button_pressed() -> void:
	SFXPlayer.play(sound_stream)
	Global.settings.music = not Global.settings.music
	update_audio_bus(BusType.MUSIC, music_label, Global.settings.music)


func _on_sfx_button_pressed() -> void:
	SFXPlayer.play(sound_stream)
	Global.settings.sfx = not Global.settings.sfx
	update_audio_bus(BusType.SFX, sfx_label, Global.settings.sfx)


func _on_window_button_pressed() -> void:
	SFXPlayer.play(sound_stream)
	Global.settings.fullscreen = not Global.settings.fullscreen
	update_fullscreen(Global.settings.fullscreen)


func _on_back_button_pressed() -> void:
	SFXPlayer.play(sound_stream)
	var tween := create_tween()
	tween.tween_property(settings_buttons, "global_position:x", settings_buttons_position_x, SETTINGS_TWEEN_TIME)
	tween.tween_interval(0.1)
	tween.tween_property(main_buttons, "global_position:y", main_buttons_position.y, MAIN_TWEEN_TIME)


func _on_button_mouse_entered() -> void:
	SFXPlayer.play(hover_stream)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		Global.save_date()
