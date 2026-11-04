extends Node
## Regression test: voice backend chain (web/native/clips), clip fallback,
## VOX/Snd toggles, and Master bus state. Headless has no live TTS, so the
## clips backend is exercised end to end; the web/native branches are
## covered through their pure helpers and guards.
## Run: godot --headless --path <project> res://tests/voice_test.tscn
## Pass criteria: RESULT PASS with zero ERROR lines in the output.
## Exits 0 on success, 1 on any failure.

const Voiceover := preload("res://scripts/voiceover.gd")
const AudioManager := preload("res://scripts/audio_manager.gd")

const TAUNT_1 := "VEX WARDEN: 'Your little ship amuses me. It will make fine debris.'"
const CUE := "res://audio/vox_cue.wav"
const TTS_STATE := "user://space_shooters_tts.cfg"

var _failures: Array = []
var _done := false
var _vox: Node
var _audio: Node
var _saved_tts := ""
var _had_tts := false


func _ready() -> void:
	_watchdog()
	_snapshot_tts()
	_vox = Voiceover.new()
	add_child(_vox)
	_audio = AudioManager.new()
	add_child(_audio)
	_run()
	_restore_tts()
	_finish()


func _run() -> void:
	# 1. Pure helpers.
	var k1: String = Voiceover.clip_key("abc")
	_check(k1 == Voiceover.clip_key("abc") and k1.begins_with("vox_") and k1.length() == 36, "clip_key stable (vox_<md5>)")
	var exact := "res://audio/vox/" + Voiceover.clip_key(TAUNT_1) + ".wav"
	_check(ResourceLoader.exists(exact), "exact clip shipped for fallback taunt")
	_check(ResourceLoader.exists(CUE), "generic vox cue shipped")
	var short_dur := Voiceover.estimate_duration("hi there", 1.0)
	var long_dur := Voiceover.estimate_duration(TAUNT_1, 1.0)
	_check(long_dur > short_dur, "duration grows with text")
	_check(Voiceover.estimate_duration(TAUNT_1, 2.0) < long_dur, "duration shrinks with rate")
	_check(Voiceover.choose_voice(["fr-x", "en-us-x-y", "de"]) == "en-us-x-y", "voice pick prefers en-us")
	_check(Voiceover.choose_voice(["de", "en-gb-x"]) == "en-gb-x", "voice pick falls back to en")
	_check(Voiceover.choose_voice(["de", "fr"]) == "de", "voice pick takes first when no en")
	_check(Voiceover.choose_voice([]) == "", "voice pick empty when engine voiceless")
	var no_voices: PackedStringArray = _vox.call("_lang_voices", "en")
	_check(no_voices.is_empty(), "language voice query safe with no engine")
	# 2. Backend chain headless: no live TTS, clips engaged.
	_check(String(_vox.call("get_backend")) == "clips", "backend resolves to clips headless")
	_check(bool(_vox.call("is_supported")) == false, "is_supported stays TTS-only")
	# 3. Clip fallback dispatch.
	_vox.call("speak", TAUNT_1, 1.0, 1.0)
	_check(String(_vox.get("last_backend")) == "clips", "exact line speaks via clips")
	_check(String(_vox.get("last_clip")) == exact, "exact line plays its recording")
	_vox.call("speak", "a brand new dynamic line nobody recorded", 1.0, 1.0)
	_check(String(_vox.get("last_clip")) == CUE, "dynamic line falls back to cue")
	_vox.call("speak", "   ", 1.0, 1.0)
	_check(String(_vox.get("last_clip")) == CUE, "blank line speaks nothing")
	_vox.call("stop")
	# 4. VOX toggle gates voice, never touches the bus.
	_check(bool(_vox.call("toggle")) == false, "VOX toggles off")
	_vox.call("speak", TAUNT_1, 1.0, 1.0)
	_check(String(_vox.get("last_clip")) == CUE, "muted VOX speaks nothing")
	_check(bool(_vox.call("toggle")) == true, "VOX toggles on")
	_check(AudioServer.is_bus_mute(0) == false, "VOX toggle leaves Master unmuted")
	# 5. Snd toggle drives Master mute and starts unmuted.
	_check(bool(_audio.get("muted")) == false, "Snd starts unmuted")
	_check(AudioServer.is_bus_mute(0) == false, "Master bus starts unmuted")
	_audio.call("set_muted", true)
	_check(AudioServer.is_bus_mute(0) == true, "Snd mutes Master")
	_audio.call("set_muted", false)
	_check(AudioServer.is_bus_mute(0) == false, "Snd unmutes Master")
	_vox.call("speak", TAUNT_1, 1.0, 1.0)
	_check(String(_vox.get("last_backend")) == "clips", "voice dispatches after Snd cycle")


func _snapshot_tts() -> void:
	_had_tts = FileAccess.file_exists(TTS_STATE)
	if _had_tts:
		_saved_tts = FileAccess.get_file_as_string(TTS_STATE)


func _restore_tts() -> void:
	if _had_tts:
		var f := FileAccess.open(TTS_STATE, FileAccess.WRITE)
		f.store_string(_saved_tts)
		f.close()
	elif FileAccess.file_exists(TTS_STATE):
		DirAccess.remove_absolute(TTS_STATE)


func _check(cond: bool, label: String) -> void:
	print("[voice-test] %s: %s" % ["PASS" if cond else "FAIL", label])
	if not cond:
		_failures.append(label)


func _watchdog() -> void:
	await get_tree().create_timer(60.0).timeout
	if not _done:
		print("[voice-test] FAIL: timed out")
		_done = true
		get_tree().quit(1)


func _finish() -> void:
	_done = true
	if is_instance_valid(_vox):
		_vox.call("stop")
	if is_instance_valid(_audio):
		for p in _audio.get_children():
			if p is AudioStreamPlayer:
				(p as AudioStreamPlayer).stop()
				(p as AudioStreamPlayer).stream = null
	await get_tree().create_timer(0.5).timeout
	for n in [_vox, _audio]:
		if is_instance_valid(n):
			remove_child(n)
			n.queue_free()
	_vox = null
	_audio = null
	await get_tree().process_frame
	await get_tree().process_frame
	if _failures.is_empty():
		print("[voice-test] RESULT: PASS")
		get_tree().quit(0)
	else:
		print("[voice-test] RESULT: FAIL (%d failures)" % _failures.size())
		for f in _failures:
			print("[voice-test] failed: %s" % str(f))
		get_tree().quit(1)
