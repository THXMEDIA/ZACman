extends Node
## Sfx — autoload singleton providing fully synthesized sound effects
## (oscillator + envelope, rendered to short PCM buffers at load time).
## No sample/asset files anywhere — mirrors the Web Audio synthesis approach
## used in the browser prototype (web/index.html's Audio_ module), so the
## Godot build carries the same "no ripped audio" property.

const SAMPLE_RATE := 44100

var _munch_toggle := false
var _players: Array[AudioStreamPlayer] = []
var _siren_player: AudioStreamPlayer
var _siren_normal: AudioStreamWAV
var _siren_frightened: AudioStreamWAV
var _siren_state := "" # "", "normal", "frightened"

var _munch_a: AudioStreamWAV
var _munch_b: AudioStreamWAV
var _power: AudioStreamWAV
var _eat_1: AudioStreamWAV
var _eat_2: AudioStreamWAV
var _eat_3: AudioStreamWAV
var _death: AudioStreamWAV
var _fruit_1: AudioStreamWAV
var _fruit_2: AudioStreamWAV
var _clear_notes: Array[AudioStreamWAV] = []


func _ready() -> void:
	_munch_a = _tone(260.0, 0.07, "triangle", 0.5)
	_munch_b = _tone(330.0, 0.07, "triangle", 0.5)
	_power = _sweep(120.0, 520.0, 0.45, "sawtooth", 0.5)
	_eat_1 = _tone(180.0, 0.06, "square", 0.55)
	_eat_2 = _tone(520.0, 0.12, "square", 0.55)
	_eat_3 = _tone(880.0, 0.16, "square", 0.55)
	_death = _sweep(420.0, 40.0, 1.15, "sawtooth", 0.55)
	_fruit_1 = _tone(700.0, 0.08, "sine", 0.45)
	_fruit_2 = _tone(1000.0, 0.1, "sine", 0.45)
	for f in [523.0, 659.0, 784.0, 1047.0]:
		_clear_notes.append(_tone(f, 0.22, "square", 0.5))
	_siren_normal = _siren_loop(90.0, 25.0, 3.2, 0.16)
	_siren_frightened = _siren_loop(220.0, 40.0, 9.0, 0.2)

	for i in range(8):
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)

	_siren_player = AudioStreamPlayer.new()
	_siren_player.bus = "Master"
	_siren_player.volume_db = -14.0
	add_child(_siren_player)


func _free_player() -> AudioStreamPlayer:
	for p in _players:
		if not p.playing:
			return p
	return _players[0]


func _play(stream: AudioStreamWAV, delay := 0.0) -> void:
	if delay <= 0.0:
		var p := _free_player()
		p.stream = stream
		p.play()
	else:
		await get_tree().create_timer(delay).timeout
		var p2 := _free_player()
		p2.stream = stream
		p2.play()


func munch() -> void:
	_munch_toggle = not _munch_toggle
	_play(_munch_b if _munch_toggle else _munch_a)


func power() -> void:
	_play(_power)


func eat_enemy() -> void:
	_play(_eat_1)
	_play(_eat_2, 0.06)
	_play(_eat_3, 0.12)


func death() -> void:
	_play(_death)


func fruit() -> void:
	_play(_fruit_1)
	_play(_fruit_2, 0.07)


func level_clear() -> void:
	for i in _clear_notes.size():
		_play(_clear_notes[i], i * 0.13)


func set_siren(active: bool, frightened: bool) -> void:
	var wanted := "" if not active else ("frightened" if frightened else "normal")
	if wanted == _siren_state:
		return
	_siren_state = wanted
	if wanted == "":
		_siren_player.stop()
		return
	_siren_player.stream = _siren_frightened if wanted == "frightened" else _siren_normal
	_siren_player.play()


func stop_all() -> void:
	set_siren(false, false)


func siren_state() -> String:
	return _siren_state


## ---------------- synthesis helpers ----------------

func _waveform_sample(waveform: String, phase: float) -> float:
	var p := fmod(phase, 1.0)
	match waveform:
		"sine":
			return sin(p * TAU)
		"square":
			return 1.0 if p < 0.5 else -1.0
		"sawtooth":
			return 2.0 * p - 1.0
		"triangle":
			return 1.0 - 4.0 * absf(p - 0.5)
		_:
			return sin(p * TAU)


func _tone(freq: float, duration: float, waveform: String, volume: float) -> AudioStreamWAV:
	return _sweep(freq, freq, duration, waveform, volume)


func _sweep(freq_start: float, freq_end: float, duration: float, waveform: String, volume: float) -> AudioStreamWAV:
	var frame_count := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(frame_count * 2)
	var phase := 0.0
	var attack := mini(frame_count, int(SAMPLE_RATE * 0.012))
	for i in frame_count:
		var t := float(i) / float(frame_count)
		# exponential-ish frequency glide, same shape as the web version's ramps
		var freq: float = lerpf(freq_start, freq_end, t)
		phase += freq / SAMPLE_RATE
		var s := _waveform_sample(waveform, phase) * volume
		# envelope: quick attack, exponential-ish decay to silence
		var env: float
		if i < attack:
			env = float(i) / float(max(attack, 1))
		else:
			var rel := float(i - attack) / float(max(frame_count - attack, 1))
			env = pow(1.0 - rel, 2.2)
		var sample := s * env
		var v := int(clampf(sample, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream


func _siren_loop(freq_base: float, freq_spread: float, cycles_per_sec: float, volume: float) -> AudioStreamWAV:
	var duration := 1.0
	var frame_count := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(frame_count * 2)
	var phase := 0.0
	for i in frame_count:
		var t := float(i) / float(SAMPLE_RATE)
		var freq: float = freq_base + sin(t * cycles_per_sec * TAU) * freq_spread
		phase += freq / SAMPLE_RATE
		var s := _waveform_sample("triangle", phase) * volume
		var v := int(clampf(s, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = frame_count
	stream.data = data
	return stream
