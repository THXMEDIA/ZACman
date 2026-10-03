extends Node
## Sfx — autoload singleton providing fully synthesized sound effects
## (oscillator + envelope, rendered to short PCM buffers at load time).
## No sample/asset files anywhere — mirrors the Web Audio synthesis approach
## used in the browser prototype (web/index.html's Audio_ module), so the
## Godot build carries the same "no ripped audio" property.
##
## Background music (play_arcade_music / play_explorer_music below) follows
## that same principle: rather than sourcing and embedding a "frei
## verfügbare" (freely licensed) audio file — which this project's audio
## layer has deliberately never done, and which the sandbox this was built
## in can't reliably download from third-party sites anyway — both tracks
## are original tunes composed as note sequences and rendered the same way
## as every sound effect above: oscillators (_waveform_sample), envelopes,
## and a looping AudioStreamWAV (see _siren_loop, the existing precedent for
## a looping synthesized buffer). _compose_loop generalizes that from "one
## repeating tone" to "several voices playing a short note sequence".

const SAMPLE_RATE := 44100
## Condition music layer (spec 2.2: "Musikschicht für die Dauer"): an extra
## loop on top of the arcade track while a rabbit condition runs — bright
## arpeggios for a good one, a detuned low pulse for a bad one. Same length
## and tempo as the arcade loop (32 eighths at 0.15 s), started in sync with
## it, faded in and out with a volume ramp (never a hard cut).
const LAYER_FADE_IN_S := 0.6
const LAYER_FADE_OUT_S := 0.9
const LAYER_VOLUME_DB := -10.0
const LAYER_SILENT_DB := -60.0

var _munch_toggle := false
var _players: Array[AudioStreamPlayer] = []
var _siren_player: AudioStreamPlayer
var _siren_normal: AudioStreamWAV
var _siren_frightened: AudioStreamWAV
var _siren_state := "" # "", "normal", "frightened"

var _music_player: AudioStreamPlayer
var _arcade_music: AudioStreamWAV
var _explorer_music: AudioStreamWAV
var _music_state := "" # "", "arcade", "explorer"

var _layer_player: AudioStreamPlayer
var _layer_good: AudioStreamWAV
var _layer_bad: AudioStreamWAV
var _layer_state := "" # "", "good", "bad" — what is wanted right now
var _layer_gain := 0.0 # 0..1, ramps towards _layer_target
var _layer_target := 0.0

var _munch_a: AudioStreamWAV
var _munch_b: AudioStreamWAV
var _power: AudioStreamWAV
var _eat_1: AudioStreamWAV
var _eat_2: AudioStreamWAV
var _eat_3: AudioStreamWAV
var _death: AudioStreamWAV
## White rabbit (spec 2.2): good conditions rise, bad ones fall detuned;
## countdown ticks in the last 3 s; a slow clock tick for the Taschenuhr.
var _rabbit_good: Array[AudioStreamWAV] = []
var _rabbit_bad_a: AudioStreamWAV
var _rabbit_bad_b: AudioStreamWAV
var _condition_tick: AudioStreamWAV
var _condition_end: AudioStreamWAV
var _clock_tick: AudioStreamWAV
var _fruit_1: AudioStreamWAV
var _fruit_2: AudioStreamWAV
var _clear_notes: Array[AudioStreamWAV] = []
## Tokyo scramble: the pedestrian-crossing tone (a synthetic bird-like
## chirp, two short rising sine glides) announcing "All Walk".
var _crossing_a: AudioStreamWAV
var _crossing_b: AudioStreamWAV


func _ready() -> void:
	_munch_a = _tone(260.0, 0.07, "triangle", 0.5)
	_munch_b = _tone(330.0, 0.07, "triangle", 0.5)
	_power = _sweep(120.0, 520.0, 0.45, "sawtooth", 0.5)
	_eat_1 = _tone(180.0, 0.06, "square", 0.55)
	_eat_2 = _tone(520.0, 0.12, "square", 0.55)
	_eat_3 = _tone(880.0, 0.16, "square", 0.55)
	_death = _sweep(420.0, 40.0, 1.15, "sawtooth", 0.55)
	# Rabbit: a good condition is a bright rising triad (C-E-G-C), a bad one
	# two slightly detuned falling square sweeps (the beat between them is
	# the "verstimmt" part) — audible as good/bad before reading the card.
	for f in [523.0, 659.0, 784.0, 1047.0]:
		_rabbit_good.append(_tone(f, 0.11, "triangle", 0.45))
	_rabbit_bad_a = _sweep(620.0, 150.0, 0.6, "square", 0.32)
	_rabbit_bad_b = _sweep(641.0, 158.0, 0.6, "square", 0.32)
	_condition_tick = _tone(1320.0, 0.05, "square", 0.32)
	_condition_end = _sweep(300.0, 600.0, 0.22, "triangle", 0.4)
	_clock_tick = _tone(1800.0, 0.025, "triangle", 0.28)
	_fruit_1 = _tone(700.0, 0.08, "sine", 0.45)
	_fruit_2 = _tone(1000.0, 0.1, "sine", 0.45)
	for f in [523.0, 659.0, 784.0, 1047.0]:
		_clear_notes.append(_tone(f, 0.22, "square", 0.5))
	_crossing_a = _sweep(2350.0, 3050.0, 0.08, "sine", 0.3)
	_crossing_b = _sweep(2050.0, 2650.0, 0.1, "sine", 0.26)
	_siren_normal = _siren_loop(90.0, 25.0, 3.2, 0.16)
	_siren_frightened = _siren_loop(220.0, 40.0, 9.0, 0.2)
	_arcade_music = _build_arcade_music()
	_explorer_music = _build_explorer_music()
	_layer_good = _build_layer_good()
	_layer_bad = _build_layer_bad()

	for i in range(8):
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)

	_siren_player = AudioStreamPlayer.new()
	_siren_player.bus = "Master"
	_siren_player.volume_db = -14.0
	add_child(_siren_player)

	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Master"
	_music_player.volume_db = -9.0
	add_child(_music_player)

	_layer_player = AudioStreamPlayer.new()
	_layer_player.bus = "Master"
	_layer_player.volume_db = LAYER_SILENT_DB
	add_child(_layer_player)


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


func rabbit_good() -> void:
	for i in _rabbit_good.size():
		_play(_rabbit_good[i], i * 0.07)


func rabbit_bad() -> void:
	_play(_rabbit_bad_a)
	_play(_rabbit_bad_b)


## One countdown tick (the last 3 s of a condition).
func condition_tick() -> void:
	_play(_condition_tick)


func condition_end() -> void:
	_play(_condition_end)


## The Taschenuhr's slow ticking (once per second).
func clock_tick() -> void:
	_play(_clock_tick)


func eat_enemy() -> void:
	_play(_eat_1)
	_play(_eat_2, 0.06)
	_play(_eat_3, 0.12)


func death() -> void:
	_play(_death)


func fruit() -> void:
	_play(_fruit_1)
	_play(_fruit_2, 0.07)


## "All Walk" at the Tokyo scramble: three chirp pairs ("pi-yo") over ~1.5 s.
func crossing_signal() -> void:
	for k in 3:
		_play(_crossing_a, k * 0.5)
		_play(_crossing_b, k * 0.5 + 0.16)


## The streams of the crossing tone (tests check they exist and are short).
func crossing_streams() -> Array:
	return [_crossing_a, _crossing_b]


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


## Original, procedurally-synthesized "arcade Pac-Man style" loop — bouncy
## square-wave lead + bass + an offbeat click, the coin-op chiptune spirit
## the normal/Matrix run asked for (see the header comment for why this is
## synthesized rather than a downloaded track). Call at the start of a
## normal run (Main.begin_game).
func play_arcade_music() -> void:
	_set_music("arcade", _arcade_music)


## Original, procedurally-synthesized downtempo/lounge loop for the Explorer
## (Manhattan) level — warm held chords, a laid-back sine bass and a soft
## brushed-shaker pulse, aiming for the mellow, jazzy Roudoudou / Air / The
## Herbaliser feel the Explorer run asked for. Call at the start of an
## Explorer run (Main.begin_manhattan_game).
func play_explorer_music() -> void:
	_set_music("explorer", _explorer_music)


func stop_music() -> void:
	_set_music("", null)


func _set_music(wanted: String, stream: AudioStreamWAV) -> void:
	if wanted == _music_state:
		return
	_music_state = wanted
	if wanted == "":
		_music_player.stop()
		return
	_music_player.stream = stream
	_music_player.play()


func music_state() -> String:
	return _music_state


func stop_all() -> void:
	set_siren(false, false)
	stop_music()
	stop_condition_layer(true)


## ---------------- condition music layer ----------------

## Starts the layer of a good (true) or bad (false) condition with a fade-in.
## A running layer of the other kind is swapped (a new rabbit replaces the
## condition, spec 2.2). In sync with the arcade loop when that is playing.
func start_condition_layer(good: bool) -> void:
	var wanted := "good" if good else "bad"
	var stream: AudioStreamWAV = _layer_good if good else _layer_bad
	_layer_target = 1.0
	if _layer_state == wanted and _layer_player.stream == stream:
		return
	_layer_state = wanted
	_layer_player.stream = stream
	_layer_gain = 0.0
	_apply_layer_volume()
	var from := 0.0
	if _music_state == "arcade" and _music_player.playing:
		from = fmod(_music_player.get_playback_position(), stream.get_length())
	if _layer_player.is_inside_tree():
		_layer_player.play(from)


## Fades the layer out (`immediate`: cut at once, e.g. game over / stop_all).
func stop_condition_layer(immediate: bool = false) -> void:
	_layer_state = ""
	_layer_target = 0.0
	if immediate:
		_layer_gain = 0.0
		_apply_layer_volume()
		_layer_player.stop()


## "", "good" or "bad" — the layer that is wanted (a fading-out layer already
## reports "").
func condition_layer_state() -> String:
	return _layer_state


## Current loudness of the layer, 0..1 (follows the ramp).
func condition_layer_gain() -> float:
	return _layer_gain


## True while the layer still sounds (also during its fade-out).
func condition_layer_audible() -> bool:
	return _layer_gain > 0.0 or _layer_target > 0.0


func _process(delta: float) -> void:
	_update_layer(delta)


## The volume ramp: linear in gain, LAYER_FADE_IN_S up, LAYER_FADE_OUT_S
## down; at 0 the player stops.
func _update_layer(delta: float) -> void:
	if is_equal_approx(_layer_gain, _layer_target):
		return
	if _layer_target > _layer_gain:
		_layer_gain = minf(_layer_target, _layer_gain + delta / LAYER_FADE_IN_S)
	else:
		_layer_gain = maxf(_layer_target, _layer_gain - delta / LAYER_FADE_OUT_S)
	_apply_layer_volume()
	if _layer_gain <= 0.0 and _layer_target <= 0.0:
		_layer_player.stop()


func _apply_layer_volume() -> void:
	if _layer_gain <= 0.001:
		_layer_player.volume_db = LAYER_SILENT_DB
	else:
		_layer_player.volume_db = maxf(LAYER_VOLUME_DB + linear_to_db(_layer_gain), LAYER_SILENT_DB)


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
		"noise":
			# Unpitched texture for the explorer track's soft shaker — phase
			# is unused, each call is an independent random sample.
			return randf_range(-1.0, 1.0)
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


## ---------------- music composer (background loops) ----------------
##
## A "voice" is {waveform: String, volume: float, steps: Array, gate?: float,
## attack?: float, release_pow?: float}. Each step is {freqs: Array[float],
## beats: float} — beats is a multiple of `beat_dur` seconds, and an empty
## freqs array is a rest. A step with more than one freq plays as a chord
## (each note's own oscillator, summed and loudness-compensated by chord
## size). All voices in one call share the same beat_dur and are expected to
## sum to the same total beat count, so the render tiles as one seamless
## loop (same LOOP_FORWARD technique as _siren_loop above).
func _compose_loop(voices: Array, beat_dur: float) -> AudioStreamWAV:
	var total_beats := 0.0
	for voice in voices:
		var vb := 0.0
		for step in voice.steps:
			vb += step.beats
		total_beats = maxf(total_beats, vb)
	var frame_count := int(SAMPLE_RATE * total_beats * beat_dur)
	var mix := PackedFloat32Array()
	mix.resize(frame_count)

	for voice in voices:
		var waveform: String = voice.waveform
		var gate: float = voice.get("gate", 0.9)
		var attack_s: float = voice.get("attack", 0.008)
		var release_pow: float = voice.get("release_pow", 1.8)
		var frame := 0
		for step in voice.steps:
			var step_frames := int(SAMPLE_RATE * step.beats * beat_dur)
			var freqs: Array = step.freqs
			if freqs.is_empty() or step_frames <= 0:
				frame += step_frames
				continue
			var note_frames := int(step_frames * gate)
			var attack := mini(note_frames, int(SAMPLE_RATE * attack_s))
			var per_note_vol: float = voice.volume / sqrt(float(freqs.size()))
			for f in freqs:
				if f <= 0.0:
					continue
				var phase := 0.0
				for i in step_frames:
					if i >= note_frames:
						break
					var idx := frame + i
					if idx >= frame_count:
						break
					phase += f / SAMPLE_RATE
					var s := _waveform_sample(waveform, phase) * per_note_vol
					var env: float
					if i < attack:
						env = float(i) / float(max(attack, 1))
					else:
						var rel := float(i - attack) / float(max(note_frames - attack, 1))
						env = pow(1.0 - clampf(rel, 0.0, 1.0), release_pow)
					mix[idx] += s * env
			frame += step_frames

	var data := PackedByteArray()
	data.resize(frame_count * 2)
	for i in frame_count:
		var v := int(clampf(mix[i], -1.0, 1.0) * 32767.0)
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


## Tiny helper: one single-note (or rest, freq<=0) step.
func _step(freq: float, beats: float) -> Dictionary:
	return {"freqs": ([] if freq <= 0.0 else [freq]), "beats": beats}


## Tiny helper: one chord step.
func _chord_step(freqs: Array, beats: float) -> Dictionary:
	return {"freqs": freqs, "beats": beats}


## "Arcade Pac-Man style" loop: a bouncy square-wave lead over a triangle
## bass with a light offbeat click, in a coin-op chiptune spirit — an
## eighth-note pulse at a brisk tempo, the way the genre's own melodies
## bounce around a I–vi–IV–V-ish progression in short repeating phrases.
func _build_arcade_music() -> AudioStreamWAV:
	var eighth := 0.15 # seconds per eighth-note step — a brisk ~200bpm feel

	# Notes used below (Hz, equal temperament).
	var C6 := 1046.50
	var B5 := 987.77
	var A5 := 880.00
	var G5 := 783.99
	var F5 := 698.46
	var E5 := 659.25
	var D5 := 587.33
	var C5 := 523.25
	var B4 := 493.88
	var A4 := 440.00
	var G4 := 392.00
	var C3 := 130.81
	var E3 := 164.81
	var F3 := 174.61
	var G3 := 196.00
	var A2 := 110.00

	var lead_freqs := [
		C5, E5, G5, E5, D5, F5, A5, F5, C5, E5, G5, C6, B5, G5, E5, D5,
		G4, B4, D5, B4, C5, E5, G5, E5, A4, C5, E5, A5, G5, E5, C5, 0.0,
	]
	var lead_steps := []
	for f in lead_freqs:
		lead_steps.append(_step(f, 1.0))

	var bass_freqs := [C3, C3, A2, A2, F3, F3, G3, G3, E3, E3, C3, C3, F3, F3, G3, G3]
	var bass_steps := []
	for f in bass_freqs:
		bass_steps.append(_step(f, 2.0))

	var hat_steps := []
	for i in 32:
		hat_steps.append(_step(1800.0 if i % 2 == 1 else 0.0, 1.0))

	var voices := [
		{"waveform": "square", "volume": 0.32, "gate": 0.72, "attack": 0.003, "release_pow": 1.4, "steps": lead_steps},
		{"waveform": "triangle", "volume": 0.28, "gate": 0.85, "attack": 0.005, "release_pow": 1.6, "steps": bass_steps},
		{"waveform": "square", "volume": 0.10, "gate": 0.25, "attack": 0.001, "release_pow": 3.0, "steps": hat_steps},
	]
	return _compose_loop(voices, eighth)


## Good-condition layer: a light, rising sine/triangle arpeggio two octaves
## above the arcade chords (C – Am – F – G – Em – C – F – G, one chord per
## four eighths, exactly the arcade loop's harmony), plus a soft high
## shimmer on the off-beats — "the maze opens up".
func _build_layer_good() -> AudioStreamWAV:
	var eighth := 0.15
	var chords := [
		[1046.50, 1318.51, 1567.98, 2093.00], # C
		[880.00, 1046.50, 1318.51, 1760.00],  # Am
		[698.46, 880.00, 1046.50, 1396.91],   # F
		[783.99, 987.77, 1174.66, 1567.98],   # G
		[659.25, 783.99, 987.77, 1318.51],    # Em
		[1046.50, 1318.51, 1567.98, 2093.00], # C
		[698.46, 880.00, 1046.50, 1396.91],   # F
		[783.99, 987.77, 1174.66, 1567.98],   # G
	]
	var arp_steps := []
	for ch in chords:
		for f in ch:
			arp_steps.append(_step(f, 1.0))
	var shimmer_steps := []
	for i in 32:
		shimmer_steps.append(_step(3135.96 if i % 4 == 2 else 0.0, 1.0))
	var voices := [
		{"waveform": "triangle", "volume": 0.26, "gate": 0.6, "attack": 0.004, "release_pow": 2.0, "steps": arp_steps},
		{"waveform": "sine", "volume": 0.08, "gate": 0.5, "attack": 0.002, "release_pow": 3.0, "steps": shimmer_steps},
	]
	return _compose_loop(voices, eighth)


## Bad-condition layer: a low square pulse on the tritone of the arcade
## bass (F#), doubled by a slightly detuned sawtooth (the beat between them
## is the "verstimmt" part), plus a falling minor-second sting every bar —
## uneasy, but quieter than the lead so the game sounds stay readable.
func _build_layer_bad() -> AudioStreamWAV:
	var eighth := 0.15
	var pulse_steps := []
	var detune_steps := []
	for i in 32:
		var low := 92.50 if (i / 8) % 2 == 0 else 87.31 # F#2 / F2
		pulse_steps.append(_step(low if i % 2 == 0 else 0.0, 1.0))
		detune_steps.append(_step(low * 1.013 if i % 2 == 0 else 0.0, 1.0))
	var sting_steps := []
	for bar in 4:
		sting_steps.append(_step(466.16, 1.0)) # Bb4
		sting_steps.append(_step(440.00, 1.0)) # A4
		sting_steps.append(_step(0.0, 6.0))
	var voices := [
		{"waveform": "square", "volume": 0.20, "gate": 0.7, "attack": 0.004, "release_pow": 1.6, "steps": pulse_steps},
		{"waveform": "sawtooth", "volume": 0.14, "gate": 0.7, "attack": 0.004, "release_pow": 1.6, "steps": detune_steps},
		{"waveform": "square", "volume": 0.10, "gate": 0.85, "attack": 0.01, "release_pow": 1.2, "steps": sting_steps},
	]
	return _compose_loop(voices, eighth)


## Explorer (Manhattan) loop: warm held triangle-wave chords, a laid-back
## sine bass and a soft brushed-noise shaker pulse — aiming for the mellow,
## jazzy downtempo/lounge feel of Roudoudou, Air and The Herbaliser rather
## than anything arcade-y, at a slow, relaxed quarter-note tempo.
func _build_explorer_music() -> AudioStreamWAV:
	var quarter := 0.714 # ~84bpm — a laid-back downtempo pulse

	# Four bar-pair chords: Fmaj7 - Dm9(no5) - Gm7 - Cmaj7, each held 8 beats.
	var chord_fmaj7 := [174.61, 220.00, 261.63, 329.63] # F3 A3 C4 E4
	var chord_dm9 := [146.83, 174.61, 220.00, 261.63]   # D3 F3 A3 C4
	var chord_gm7 := [196.00, 233.08, 293.66, 349.23]   # G3 Bb3 D4 F4
	var chord_cmaj7 := [130.81, 164.81, 196.00, 246.94] # C3 E3 G3 B3

	var chord_steps := [
		_chord_step(chord_fmaj7, 8.0),
		_chord_step(chord_dm9, 8.0),
		_chord_step(chord_gm7, 8.0),
		_chord_step(chord_cmaj7, 8.0),
	]

	# Root-then-fifth walking bass, one pair of half-notes per chord.
	var bass_pairs := [
		[87.31, 130.81],  # F2, C3
		[73.42, 110.00],  # D2, A2
		[98.00, 146.83],  # G2, D3
		[65.41, 98.00],   # C2, G2
	]
	var bass_steps := []
	for pair in bass_pairs:
		bass_steps.append(_step(pair[0], 4.0))
		bass_steps.append(_step(pair[1], 4.0))

	# A soft shuffle shaker: three soft hits then a rest, on repeat — the
	# brushed, laid-back groove this trip-hop/downtempo style leans on.
	var shaker_steps := []
	for i in 32:
		shaker_steps.append(_step(1.0 if i % 4 != 3 else 0.0, 1.0))

	var voices := [
		{"waveform": "triangle", "volume": 0.24, "gate": 0.92, "attack": 0.12, "release_pow": 1.2, "steps": chord_steps},
		{"waveform": "sine", "volume": 0.30, "gate": 0.8, "attack": 0.02, "release_pow": 1.5, "steps": bass_steps},
		{"waveform": "noise", "volume": 0.055, "gate": 0.4, "attack": 0.001, "release_pow": 2.5, "steps": shaker_steps},
	]
	return _compose_loop(voices, quarter)
