extends Node
## Voiceover for AI lines (boss taunts, wingman tips, coach advice) using
## Godot's built-in text-to-speech, plus browser speechSynthesis on web
## exports. Silent no-op where neither is available, never blocks gameplay.
##
## Changes vs previous version:
##  - Native "broken" state is NOT saved to disk anymore. It lasts only for
##    the current session, so a one-time failed probe can't silence Android
##    forever. Any old saved flag file is deleted on startup.
##  - Probe confirms speech via the TTS_UTTERANCE_STARTED callback (reliable)
##    and only falls back to tts_is_speaking().
##  - Probe waits 1.5 s (engine binds asynchronously on first use).
##  - Logs the project setting / feature so you can see why TTS is off.
##  - Requires Project Settings > audio/general/text_to_speech = ON.

var enabled := true

const OLD_TTS_STATE_PATH := "user://space_shooters_tts.cfg"
const PROBE_DELAY := 1.5

var _voice_id := ""
var _picked := false
var _web_tts := -1 # -1 unknown, 0 no, 1 yes
# Native TTS (notably Android) errors if tts_stop() runs before the engine
# has initialized via the first tts_speak(), so only stop after speaking.
var _spoke_native := false
var _native_broken := false # session-only, never saved
var _last_was_speak := false
var _utterance_seq := 0
var _probe_pending := false
var _probe_confirmed := false
var _probe_strikes := 0
var _warned_no_backend := false
var _last_text := ""
var _last_pitch := 1.0
var _last_rate := 1.0


func _ready() -> void:
	# Remove the stale persisted flag from older builds.
	if FileAccess.file_exists(OLD_TTS_STATE_PATH):
		DirAccess.remove_absolute(OLD_TTS_STATE_PATH)
	_native_broken = false

	var feature := DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH)
	var setting := bool(ProjectSettings.get_setting("audio/general/text_to_speech", false))
	if feature:
		DisplayServer.tts_set_utterance_callback(
			DisplayServer.TTS_UTTERANCE_STARTED, Callable(self, "_on_tts_started"))
	print("[voice] ready: native=%s (broken=%s feature=%s setting=%s) web=%s enabled=%s" % [
		_use_native(), _native_broken, feature, setting,
		_web_tts_available(), enabled])
	if OS.has_feature("android") and not (feature and setting):
		print("[voice] WARNING: enable Project Settings > Audio > General > Text To Speech")


func _on_tts_started(_utterance_id: int) -> void:
	_probe_confirmed = true
	_probe_strikes = 0


func _use_native() -> bool:
	return not _native_broken and DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH)


func is_supported() -> bool:
	return _use_native() or _web_tts_available()


func speak(text: String, pitch: float = 1.0, rate: float = 1.0) -> void:
	if not enabled:
		return
	var clean := text.strip_edges()
	if clean == "":
		return
	if _use_native():
		_speak_native(clean, pitch, rate)
	elif _web_tts_available():
		_speak_web(clean, pitch, rate)
	else:
		if not _warned_no_backend:
			_warned_no_backend = true
			print("[voice] no TTS backend available; voiceover silent")


func _speak_native(clean: String, pitch: float, rate: float) -> void:
	_pick_voice()
	if _spoke_native:
		DisplayServer.tts_stop()
	DisplayServer.tts_speak(clean, _voice_id, 90, pitch, rate)
	_spoke_native = true
	_last_was_speak = true
	_last_text = clean
	_last_pitch = pitch
	_last_rate = rate
	_utterance_seq += 1
	_arm_android_probe()


func stop() -> void:
	if _spoke_native and _use_native():
		DisplayServer.tts_stop()
	_last_was_speak = false
	_utterance_seq += 1
	if _web_tts_available():
		_stop_web()


func toggle() -> bool:
	enabled = not enabled
	if not enabled:
		stop()
	else:
		# Re-arm native detection so a fixed engine (or a user retry) gets
		# another chance.
		_native_broken = false
		_probe_confirmed = false
		_probe_pending = false
		_probe_strikes = 0
		_spoke_native = false
		_warned_no_backend = false
	return enabled


func _pick_voice() -> void:
	if _picked:
		return
	_picked = true
	if OS.has_feature("android"):
		return # Default voice: get_voices() pre-init errors and can stall.
	var voices: PackedStringArray = DisplayServer.tts_get_voices_for_language("en")
	if not voices.is_empty():
		_voice_id = voices[0]


func _arm_android_probe() -> void:
	if not OS.has_feature("android"):
		return
	if _probe_pending or _probe_confirmed or _native_broken:
		return
	_probe_pending = true
	get_tree().create_timer(PROBE_DELAY).timeout.connect(_on_probe_timeout.bind(_utterance_seq))


func _on_probe_timeout(seq: int) -> void:
	_probe_pending = false
	if _probe_confirmed or _native_broken:
		return
	if seq != _utterance_seq or not _last_was_speak:
		if _last_was_speak:
			_arm_android_probe()
		return
	if DisplayServer.tts_is_speaking():
		_probe_confirmed = true
		_probe_strikes = 0
		return
	# Silent. The first utterance after launch can be eaten while the engine
	# binds asynchronously, so retry the same line once.
	_probe_strikes += 1
	if _probe_strikes >= 2 or _last_text == "":
		_probe_strikes = 0
		_native_broken = true # this session only; next launch tries again
		print("[voice] native TTS silent twice; off for this session (VOX toggle retries)")
	else:
		print("[voice] speech not detected, retrying once (strike %d)" % _probe_strikes)
		_speak_native(_last_text, _last_pitch, _last_rate)


func _web_tts_available() -> bool:
	if _web_tts != -1:
		return _web_tts == 1
	_web_tts = 0
	if not OS.has_feature("web"):
		return false
	if not Engine.has_singleton("JavaScriptBridge"):
		return false
	var js: Object = Engine.get_singleton("JavaScriptBridge")
	if js == null or not js.has_method("eval"):
		return false
	var v: Variant = js.call("eval", "typeof speechSynthesis !== 'undefined';", true)
	if typeof(v) == TYPE_BOOL and bool(v):
		_web_tts = 1
		return true
	if typeof(v) == TYPE_STRING and (v as String).strip_edges() == "true":
		_web_tts = 1
		return true
	return false


func _speak_web(text: String, pitch: float, rate: float) -> void:
	if not Engine.has_singleton("JavaScriptBridge"):
		return
	var js: Object = Engine.get_singleton("JavaScriptBridge")
	if js == null or not js.has_method("eval"):
		return
	var p := clampf(pitch, 0.0, 2.0)
	var r := clampf(rate, 0.5, 2.0)
	var quoted := JSON.stringify(text)
	var code := "try{speechSynthesis.resume();speechSynthesis.cancel();var u=new SpeechSynthesisUtterance(%s);u.pitch=%.3f;u.rate=%.3f;u.lang='en-US';speechSynthesis.speak(u);}catch(e){}" % [quoted, p, r]
	js.call("eval", code, true)


func _stop_web() -> void:
	if not Engine.has_singleton("JavaScriptBridge"):
		return
	var js: Object = Engine.get_singleton("JavaScriptBridge")
	if js == null or not js.has_method("eval"):
		return
	js.call("eval", "try{speechSynthesis.cancel();}catch(e){}", true)
