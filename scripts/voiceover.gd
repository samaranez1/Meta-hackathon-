extends Node
## Voiceover for AI lines (boss taunts, wingman tips, coach advice) using
## Godot's built-in text-to-speech, plus browser speechSynthesis on web
## exports where DisplayServer TTS is unsupported. Silent no-op where
## neither is available (e.g. headless), and never blocks gameplay.

var enabled := true

const TTS_STATE_PATH := "user://space_shooters_tts.cfg"

var _voice_id := ""
var _picked := false
var _web_tts := -1 # -1 unknown, 0 no, 1 yes
# Native TTS (notably Android) errors if tts_stop() runs before the engine
# has initialized via the first tts_speak(), so only stop after speaking.
var _spoke_native := false
# Android offers no silent TTS-readiness probe and devices without an engine
# never initialize, so the first speak attempt doubles as the probe: if the
# engine is still silent 0.6 s later, native TTS is disabled and remembered
# (see _arm_android_probe). Healthy devices speak from the first run.
var _native_broken := false
var _native_allowed := true
var _last_was_speak := false
var _utterance_seq := 0
var _probe_pending := false
var _probe_confirmed := false
var _probe_strikes := 0
var _warned_no_backend := false
# Last native utterance, so the probe can retry it once when the first
# attempt is eaten by async engine init (see _on_probe_timeout).
var _last_text := ""
var _last_pitch := 1.0
var _last_rate := 1.0


func _ready() -> void:
	_native_allowed = true
	_native_broken = false
	var cfg := ConfigFile.new()
	if cfg.load(TTS_STATE_PATH) == OK:
		_native_broken = bool(cfg.get_value("tts", "native_broken", false))
		# Only a probe-confirmed broken engine stays off. In particular this
		# migrates installs saved by the old Android-default-off build, which
		# persisted native_allowed=false with native_broken=false.
		_native_allowed = not _native_broken
	print("[voice] ready: native=%s (allowed=%s broken=%s feature=%s setting=%s) web=%s enabled=%s" % [
		_use_native(), _native_allowed, _native_broken,
		DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH),
		bool(ProjectSettings.get_setting("audio/general/text_to_speech", false)),
		_web_tts_available(), enabled])


func _save_tts_state() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("tts", "native_broken", _native_broken)
	cfg.set_value("tts", "native_allowed", _native_allowed)
	cfg.save(TTS_STATE_PATH)


func _use_native() -> bool:
	return _native_allowed and not _native_broken and DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH)


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
		# another chance; clears any persisted broken flag.
		_native_allowed = true
		_native_broken = false
		_probe_confirmed = false
		_probe_pending = false
		_probe_strikes = 0
		_spoke_native = false
		_warned_no_backend = false
		_save_tts_state()
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
	# Confirmation that native speech actually started. Healthy engines are
	# still speaking our seconds-long lines 0.6 s later; silent ones get one
	# automatic retry (first utterance can be eaten by async engine init)
	# before native TTS is disabled and remembered instead of erroring on
	# every line. See _on_probe_timeout.
	if not OS.has_feature("android"):
		return
	if _probe_pending or _probe_confirmed or _native_broken:
		return
	_probe_pending = true
	get_tree().create_timer(0.6).timeout.connect(_on_probe_timeout.bind(_utterance_seq))


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
	# Silent. The first utterance after install can be eaten while the engine
	# binds asynchronously ("not bound to TTS engine"), so retry the same
	# line once - by then init has completed on healthy devices. Only two
	# silent checks in a row disable native TTS.
	_probe_strikes += 1
	if _probe_strikes >= 2 or _last_text == "":
		_probe_strikes = 0
		_native_broken = true
		_native_allowed = false
		_save_tts_state()
		print("[voice] native TTS silent twice; voiceover disabled (VOX toggle retries)")
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
