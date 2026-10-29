extends Node
## Procedural retro SFX + ambient music loop. No audio files needed.
## All sounds are synthesized into AudioStreamWAV at startup.

var muted: bool = false
var _players: Array[AudioStreamPlayer] = []
var _music_player: AudioStreamPlayer
var _streams: Dictionary = {}
var _idx: int = 0

const RATE := 22050


func _ready() -> void:
	add_to_group("audio")
	process_mode = Node.PROCESS_MODE_ALWAYS
	_streams["laser"] = _make_tone(880.0, 240.0, 0.09, 0.35, "square")
	_streams["enemy_laser"] = _make_tone(320.0, 140.0, 0.14, 0.28, "saw")
	_streams["explosion"] = _make_noise(0.45, 0.6, 900.0)
	_streams["big_explosion"] = _make_noise(1.1, 0.8, 420.0)
	_streams["powerup"] = _make_arpeggio([523.0, 659.0, 784.0, 1046.0], 0.07, 0.4)
	_streams["hit"] = _make_tone(200.0, 60.0, 0.25, 0.55, "saw")
	_streams["boss_warn"] = _make_tone(110.0, 440.0, 0.7, 0.5, "saw")
	_streams["click"] = _make_tone(660.0, 880.0, 0.06, 0.3, "square")
	_streams["shield"] = _make_tone(300.0, 900.0, 0.18, 0.4, "sine")
	_streams["bomb"] = _make_noise(0.8, 0.7, 600.0)
	_streams["dash"] = _make_tone(150.0, 700.0, 0.2, 0.3, "sine")
	_streams["taunt_1"] = _make_taunt(1)
	_streams["taunt_2"] = _make_taunt(2)
	_streams["taunt_3"] = _make_taunt(3)
	_streams["taunt_4"] = _make_taunt(4)
	_streams["taunt_5"] = _make_taunt(5)
	_streams["denied"] = _make_tone(180.0, 110.0, 0.16, 0.4, "square")
	for i in range(14):
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
	_music_player = AudioStreamPlayer.new()
	_music_player.volume_db = -16.0
	add_child(_music_player)
	_music_player.stream = _make_music_loop()
	_music_player.play()


func set_muted(m: bool) -> void:
	muted = m
	AudioServer.set_bus_mute(0, m)


func _play(name: String, pitch: float = 1.0, vol: float = 0.0) -> void:
	if muted or not _streams.has(name):
		return
	var p := _players[_idx]
	_idx = (_idx + 1) % _players.size()
	p.stream = _streams[name]
	p.pitch_scale = pitch * randf_range(0.94, 1.06)
	p.volume_db = vol
	p.play()


func play_laser() -> void:
	_play("laser", 1.0, -10.0)


func play_enemy_laser() -> void:
	_play("enemy_laser", 1.0, -14.0)


func play_explosion(big: bool = false) -> void:
	_play("big_explosion" if big else "explosion", 1.0, -6.0 if big else -8.0)


func play_powerup() -> void:
	_play("powerup", 1.0, -6.0)


func play_hit() -> void:
	_play("hit", 1.0, -4.0)


func play_boss_warn() -> void:
	_play("boss_warn", 1.0, -4.0)


func play_click() -> void:
	_play("click", 1.0, -8.0)


func play_shield() -> void:
	_play("shield", 1.0, -6.0)


func play_bomb() -> void:
	_play("bomb", 1.0, -2.0)


func play_dash() -> void:
	_play("dash", 1.0, -10.0)


func play_boss_taunt(boss_id: int) -> void:
	var key := "taunt_%d" % clampi(boss_id, 1, 5)
	_play(key, 1.0, -3.0)


func play_denied() -> void:
	_play("denied", 1.0, -6.0)


# --- synthesis helpers ---

func _pack(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		var v := clampf(samples[i], -1.0, 1.0)
		var s := int(v * 32767.0)
		if s < 0:
			s += 65536
		data[i * 2] = s & 0xFF
		data[i * 2 + 1] = (s >> 8) & 0xFF
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


func _osc(kind: String, phase: float) -> float:
	match kind:
		"square":
			return 1.0 if sin(phase) > 0.0 else -1.0
		"saw":
			return fmod(phase / TAU, 1.0) * 2.0 - 1.0
		_:
			return sin(phase)


func _make_tone(f0: float, f1: float, dur: float, vol: float, kind: String) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var phase := 0.0
	for i in range(n):
		var k := float(i) / float(maxi(1, n - 1))
		var f := lerpf(f0, f1, k)
		phase += TAU * f / RATE
		var env := (1.0 - k) * (1.0 - k)
		samples[i] = _osc(kind, phase) * vol * env
	return _pack(samples)


func _make_noise(dur: float, vol: float, cutoff_hint: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var smooth := 0.0
	var alpha := clampf(cutoff_hint / RATE, 0.02, 1.0)
	for i in range(n):
		var k := float(i) / float(maxi(1, n - 1))
		var env := (1.0 - k) * (1.0 - k)
		smooth = lerpf(smooth, randf_range(-1.0, 1.0), alpha)
		samples[i] = smooth * vol * env * 2.0
	return _pack(samples)


func _make_arpeggio(freqs: Array, note_dur: float, vol: float) -> AudioStreamWAV:
	var per := int(RATE * note_dur)
	var samples := PackedFloat32Array()
	samples.resize(per * freqs.size())
	for ni in range(freqs.size()):
		var phase := 0.0
		for i in range(per):
			var k := float(i) / float(maxi(1, per - 1))
			phase += TAU * float(freqs[ni]) / RATE
			samples[ni * per + i] = sin(phase) * vol * (1.0 - k * 0.6)
	return _pack(samples)


func _make_music_loop() -> AudioStreamWAV:
	# Dark 8s synth loop: bass pulse + minor arpeggio. Loops seamlessly.
	var dur := 8.0
	var n := int(RATE * dur)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var bass := [55.0, 55.0, 65.4, 49.0] # A A C G
	var arp := [220.0, 261.6, 329.6, 261.6, 246.9, 261.6, 329.6, 392.0]
	for i in range(n):
		var t := float(i) / RATE
		var bar := int(t / 2.0) % 4
		var bi := int(t * 4.0) % 8
		var bass_ph: float = TAU * float(bass[bar]) * t
		var arp_ph: float = TAU * float(arp[bi]) * t
		var pulse := 0.5 + 0.5 * sin(TAU * 2.0 * t)
		var v := sin(bass_ph) * 0.28 * pulse + _osc("square", arp_ph) * 0.06
		# Fade last 50ms into first sample for a clean loop.
		var tail := 1.0
		if t > dur - 0.05:
			tail = (dur - t) / 0.05
		samples[i] = v * tail
	var w := _pack(samples)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w


# --- boss taunts: layered procedural stings, one personality per boss ---

func _new_buffer(dur: float) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	samples.resize(int(RATE * dur))
	return samples


func _add_tone(buf: PackedFloat32Array, f0: float, f1: float, vol: float, kind: String, start: float, dur: float, am_rate: float = 0.0, am_depth: float = 0.0, vibrato_rate: float = 0.0, vibrato_depth: float = 0.0) -> void:
	var s0 := int(start * RATE)
	var n := int(dur * RATE)
	var phase := 0.0
	for i in range(n):
		var idx := s0 + i
		if idx < 0 or idx >= buf.size():
			continue
		var k := float(i) / float(maxi(1, n - 1))
		var f := lerpf(f0, f1, k)
		if vibrato_rate > 0.0:
			f *= 1.0 + sin(TAU * vibrato_rate * float(i) / RATE) * vibrato_depth
		phase += TAU * f / RATE
		var env := sin(PI * clampf(k, 0.0, 1.0))
		env = env * env
		var am := 1.0
		if am_rate > 0.0:
			am = 1.0 - am_depth * 0.5 * (1.0 + sin(TAU * am_rate * float(i) / RATE))
		buf[idx] += _osc(kind, phase) * vol * env * am


func _add_noise(buf: PackedFloat32Array, vol: float, start: float, dur: float, alpha0: float, alpha1: float) -> void:
	var s0 := int(start * RATE)
	var n := int(dur * RATE)
	var smooth := 0.0
	for i in range(n):
		var idx := s0 + i
		if idx < 0 or idx >= buf.size():
			continue
		var k := float(i) / float(maxi(1, n - 1))
		var alpha := lerpf(alpha0, alpha1, k)
		smooth = lerpf(smooth, randf_range(-1.0, 1.0), alpha)
		var env := sin(PI * clampf(k, 0.0, 1.0))
		buf[idx] += smooth * vol * env * 2.0


func _make_taunt(boss_id: int) -> AudioStreamWAV:
	var durs := [0.0, 1.7, 2.0, 1.6, 2.2, 2.6]
	var buf := _new_buffer(float(durs[clampi(boss_id, 1, 5)]))
	match boss_id:
		1: # VEX WARDEN - war horn blast + battle-drum hit.
			_add_tone(buf, 98.0, 98.0, 0.5, "saw", 0.0, 1.2)
			_add_tone(buf, 147.0, 146.0, 0.35, "saw", 0.05, 1.1)
			_add_tone(buf, 49.0, 49.0, 0.5, "sine", 0.0, 1.2)
			_add_tone(buf, 196.0, 98.0, 0.4, "square", 0.9, 0.5)
			_add_noise(buf, 0.7, 0.9, 0.7, 0.5, 0.08)
		2: # NEBULA TWINS - eerie detuned wail.
			_add_tone(buf, 620.0, 615.0, 0.35, "sine", 0.0, 2.0, 0.0, 0.0, 5.5, 0.03)
			_add_tone(buf, 655.0, 648.0, 0.35, "sine", 0.0, 2.0, 0.0, 0.0, 5.5, 0.03)
			_add_tone(buf, 930.0, 880.0, 0.2, "sine", 0.3, 1.4)
			_add_noise(buf, 0.15, 0.0, 2.0, 0.9, 0.9)
		3: # CHROMA HYDRA - triple roar pulses + hiss.
			for hit in range(3):
				var st := float(hit) * 0.5
				_add_tone(buf, 70.0, 55.0, 0.55, "square", st, 0.45)
				_add_tone(buf, 140.0, 110.0, 0.3, "saw", st, 0.45)
				_add_noise(buf, 0.5, st, 0.45, 0.3, 0.1)
			_add_noise(buf, 0.2, 0.0, 1.6, 0.95, 0.95)
		4: # VOID REAPER - dark whisper swell + chattering menace.
			_add_noise(buf, 0.5, 0.0, 2.0, 0.05, 0.9)
			_add_tone(buf, 1200.0, 300.0, 0.18, "sine", 0.2, 1.6)
			_add_tone(buf, 60.0, 45.0, 0.5, "sine", 0.4, 1.6)
			_add_tone(buf, 300.0, 150.0, 0.25, "square", 1.1, 0.9, 11.0, 0.8)
		_: # STAR EATER PRIME - apocalyptic chord + sub drop.
			_add_tone(buf, 55.0, 55.0, 0.4, "saw", 0.0, 2.2)
			_add_tone(buf, 82.5, 82.5, 0.3, "saw", 0.0, 2.2)
			_add_tone(buf, 110.0, 110.0, 0.28, "saw", 0.0, 2.2)
			_add_tone(buf, 165.0, 164.0, 0.22, "saw", 0.0, 2.2)
			_add_tone(buf, 440.0, 110.0, 0.3, "square", 0.0, 1.0, 7.0, 0.9)
			_add_tone(buf, 80.0, 30.0, 0.6, "sine", 0.8, 1.6)
			_add_noise(buf, 0.8, 0.8, 1.8, 0.4, 0.05)
	return _pack(buf)
