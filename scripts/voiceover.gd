extends Node
## Voiceover for AI lines (boss taunts, wingman tips, coach advice).
## Backend chain, picked per platform:
##   web     -> browser speechSynthesis via JavaScriptBridge
##   android -> DisplayServer TTS with an English voice lookup
##   desktop -> DisplayServer TTS where the OS provides it
##   fallback (any platform) -> pre-recorded clips in res://audio/vox/
##               (exact-line match, else a short cue) on AudioStreamPlayer
## Silent no-op only when no backend exists. Never blocks gameplay.
## NOTE: is_supported() reports live TTS only (web/native) and is pinned
## by the AI test; the clip fallback is transparent and deliberately not
## reflected there.

var enabled := true
## Introspection for tests/debug: backend used by the last speak().
## One of "web", "native", "clips", "none".
var last_backend := "none"
## Clip path used by the last speak() via the clips backend ("" otherwise).
var last_clip := ""

const TTS_STATE_PATH := "user://space_shooters_tts.cfg"
const VOX_DIR := "res://audio/vox/"
const VOX_CUE := "res://audio/vox_cue.wav"
const VOX_LANGS: Array[String] = ["en-US", "en"]
const VOICE_MAX_TRIES := 5
## Only utterances at least this long (estimated seconds) arm the silence
## probe; short lines can finish before the check and must never count
## against a healthy engine.
const PROBE_MIN_DURATION := 1.5

var _voice_id := ""
var _picked := false
var _voice_tries := 0
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
var _clip_player: AudioStreamPlayer


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
	_clip_player = AudioStreamPlayer.new()
	_clip_player.bus = "Master"
	_clip_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_clip_player)
	print("[voice] ready: native=%s (allowed=%s broken=%s feature=%s setting=%s) web=%s clips=%s enabled=%s" % [
		_use_native(), _native_allowed, _native_broken,
		DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH),
		bool(ProjectSettings.get_setting("audio/general/text_to_speech", false)),
		_web_tts_available(), _clips_available(), enabled])


func _save_tts_state() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("tts", "native_broken", _native_broken)
	cfg.set_value("tts", "native_allowed", _native_allowed)
	cfg.save(TTS_STATE_PATH)


func _use_native() -> bool:
	return _native_usable()


func _native_usable() -> bool:
	return _native_allowed and not _native_broken and DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH)


## Backend for the next speak(): "web", "native", "clips", or "none".
func get_backend() -> String:
	if OS.has_feature("web"):
		if _web_tts_available():
			return "web"
	elif OS.has_feature("android"):
		if _native_usable():
			return "native"
	elif _native_usable():
		return "native"
	if _clips_available():
		return "clips"
	return "none"


func _clips_available() -> bool:
	return ResourceLoader.exists(VOX_CUE)


func is_supported() -> bool:
	return _use_native() or _web_tts_available()


func speak(text: String, pitch: float = 1.0, rate: float = 1.0) -> void:
	if not enabled:
		return
	var clean := text.strip_edges()
	if clean == "":
		return
	var backend := get_backend()
	last_backend = backend
	match backend:
		"web":
			_speak_web(clean, pitch, rate)
		"native":
			_speak_native(clean, pitch, rate)
		"clips":
			_speak_clip(clean, rate)
		_:
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


func _speak_clip(text: String, rate: float) -> void:
	if _clip_player == null:
		return
	var clip := _clip_for_text(text)
	if clip == "":
		return
	var stream := load(clip) as AudioStream
	if stream == null:
		return
	last_clip = clip
	_clip_player.stop()
	_clip_player.stream = stream
	_clip_player.pitch_scale = clampf(rate, 0.5, 2.0)
	_clip_player.play()


## Exact-line recording when one was shipped, else the generic cue.
func _clip_for_text(text: String) -> String:
	var exact := VOX_DIR + clip_key(text) + ".wav"
	if ResourceLoader.exists(exact):
		return exact
	if ResourceLoader.exists(VOX_CUE):
		return VOX_CUE
	return ""


## Stable file key for a voice line (matches the clip generator).
static func clip_key(text: String) -> String:
	return "vox_" + text.md5_text()


## Rough speech time in seconds (~2.5 words/sec at rate 1.0).
static func estimate_duration(text: String, rate: float) -> float:
	var words := text.strip_edges().split(" ", false).size()
	return maxf(0.4, float(maxi(words, 1)) / 2.5 / clampf(rate, 0.5, 2.0))


## Best voice from an engine list: US English, then any English, then first.
static func choose_voice(voices: PackedStringArray) -> String:
	if voices.is_empty():
		return ""
	for v in voices:
		var lv := v.to_lower()
		if lv.contains("en-us") or lv.contains("en_us"):
			return v
	for v in voices:
		if v.to_lower().begins_with("en"):
			return v
	return voices[0]


func stop() -> void:
	if _spoke_native and _use_native():
		DisplayServer.tts_stop()
	_last_was_speak = false
	_utterance_seq += 1
	if _web_tts_available():
		_stop_web()
	if _clip_player != null:
		_clip_player.stop()


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
		_picked = false
		_voice_tries = 0
		_warned_no_backend = false
		_save_tts_state()
	return enabled


func _pick_voice() -> void:
	if _picked:
		return
	if not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		return # No engine: keep default "" and let the backend chain decide.
	_voice_tries += 1
	for lang in VOX_LANGS:
		var got := choose_voice(_lang_voices(lang))
		if got != "":
			_voice_id = got
			_picked = true
			return
	if _voice_tries >= VOICE_MAX_TRIES:
		# Engine unforthcoming (some never enumerate but still speak the
		# default voice): stop asking and use "" from here on.
		_picked = true


## Voice ids for a language. tts_get_voices_for_language is the Godot 4 API
## (verified on 4.7.2); the by_language spelling is probed first in case a
## build or future version provides it instead.
func _lang_voices(lang: String) -> PackedStringArray:
	if DisplayServer.has_method("tts_get_voices_by_language"):
		var alt: Variant = DisplayServer.call("tts_get_voices_by_language", lang)
		if typeof(alt) == TYPE_PACKED_STRING_ARRAY:
			return alt
	return DisplayServer.tts_get_voices_for_language(lang)


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
	if estimate_duration(_last_text, _last_rate) < PROBE_MIN_DURATION:
		return # Too short to prove anything; never counts against the engine.
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
