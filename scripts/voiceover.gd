extends Node
## Voiceover for AI lines (boss taunts, wingman tips, coach advice) using
## Godot's built-in text-to-speech. Silent no-op where TTS is unsupported
## (e.g. headless), and never blocks gameplay.

var enabled := true

var _voice_id := ""
var _picked := false


func is_supported() -> bool:
	return DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH)


func speak(text: String, pitch: float = 1.0, rate: float = 1.0) -> void:
	if not enabled or not is_supported():
		return
	var clean := text.strip_edges()
	if clean == "":
		return
	_pick_voice()
	DisplayServer.tts_stop()
	DisplayServer.tts_speak(clean, _voice_id, 90, pitch, rate)


func stop() -> void:
	if is_supported():
		DisplayServer.tts_stop()


func toggle() -> bool:
	enabled = not enabled
	if not enabled:
		stop()
	return enabled


func _pick_voice() -> void:
	if _picked:
		return
	_picked = true
	var voices: PackedStringArray = DisplayServer.tts_get_voices_for_language("en")
	if not voices.is_empty():
		_voice_id = voices[0]
