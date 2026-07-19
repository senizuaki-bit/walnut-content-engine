extends Node

## 音频播放器
func play(audio: AudioStream, single = false) -> void:
	if not audio: return # 如果没有音频流，直接返回
	if single: stop() # 如果是单例播放，先停止所有音频
	for player: AudioStreamPlayer in get_children():
		player.stream = audio # 设置音频流
		player.play() # 播放音频
		return

## 停止所有音频播放
func stop() -> void:
	for player: AudioStreamPlayer in get_children(): # 遍历所有音频流播放器
		player.stop() # 停止播放
