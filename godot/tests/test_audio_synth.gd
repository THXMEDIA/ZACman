extends SceneTree
## Headless test: res://scripts/audio_synth.gd (the Sfx autoload) — mainly
## the two new background-music loops (play_arcade_music / play_explorer_
## music, see the big header comment in audio_synth.gd for why these are
## original procedurally-synthesized tunes rather than downloaded audio).
## A bare `--script` run has no autoloads initialized (same reason
## test_leaderboard.gd does this), so this instantiates a fresh instance
## directly instead of referencing the `Sfx` global — _ready() only builds
## PCM buffers and child AudioStreamPlayers, neither of which needs the
## node to actually be inside a live SceneTree. Run with
##   godot --headless --path . --script res://tests/test_audio_synth.gd
## Exits with code 0 on success, 1 on any failure.

func _initialize() -> void:
	var failures := 0
	var checks := 0

	var sfx = load("res://scripts/audio_synth.gd").new()
	sfx._ready()

	# --- both music tracks built into real, non-empty looping WAV buffers ---
	for name_and_stream in [["arcade", sfx._arcade_music], ["explorer", sfx._explorer_music]]:
		var track_name: String = name_and_stream[0]
		var stream: AudioStreamWAV = name_and_stream[1]
		checks += 1
		if stream == null or stream.data.size() == 0:
			failures += 1
			print("FAIL %s music should render a non-empty PCM buffer" % track_name)
		checks += 1
		if stream != null and stream.loop_mode != AudioStreamWAV.LOOP_FORWARD:
			failures += 1
			print("FAIL %s music should loop seamlessly (LOOP_FORWARD)" % track_name)
		checks += 1
		if stream != null and stream.loop_end != stream.data.size() / 2:
			failures += 1
			print("FAIL %s music loop_end should cover the whole buffer" % track_name)

	# --- Tokyo scramble: the synthetic crossing tone (two short chirps) ---
	var chirps: Array = sfx.crossing_streams()
	checks += 1
	if chirps.size() != 2 or chirps[0] == null or chirps[0].data.size() == 0 or chirps[0].get_length() > 0.2 or chirps[1].get_length() > 0.2:
		failures += 1
		print("FAIL the crossing tone should be two short non-empty chirps")

	# --- play_*/stop_music()/music_state() track which track is playing ---
	checks += 1
	if sfx.music_state() != "":
		failures += 1
		print("FAIL music_state() should start empty, got '%s'" % sfx.music_state())

	sfx.play_arcade_music()
	checks += 1
	if sfx.music_state() != "arcade":
		failures += 1
		print("FAIL play_arcade_music() should set music_state() to 'arcade', got '%s'" % sfx.music_state())
	checks += 1
	if sfx._music_player.stream != sfx._arcade_music:
		failures += 1
		print("FAIL play_arcade_music() should assign the arcade stream to the music player")

	sfx.play_explorer_music()
	checks += 1
	if sfx.music_state() != "explorer":
		failures += 1
		print("FAIL play_explorer_music() should switch music_state() to 'explorer', got '%s'" % sfx.music_state())

	sfx.stop_all()
	checks += 1
	if sfx.music_state() != "":
		failures += 1
		print("FAIL stop_all() should also stop the background music")

	# --- condition music layer (spec 2.2): starts, ramps, ends -------------
	var layers := [["good", sfx._layer_good], ["bad", sfx._layer_bad]]
	for pair in layers:
		var st: AudioStreamWAV = pair[1]
		checks += 1
		if st == null or st.data.size() == 0 or st.loop_mode != AudioStreamWAV.LOOP_FORWARD:
			failures += 1
			print("FAIL %s layer should be a non-empty looping buffer" % pair[0])
		checks += 1
		if st != null and absf(st.get_length() - sfx._arcade_music.get_length()) > 0.01:
			failures += 1
			print("FAIL %s layer should be as long as the arcade loop (in sync), %f vs %f" % [pair[0], st.get_length(), sfx._arcade_music.get_length()])
	checks += 1
	if sfx._layer_good.data == sfx._layer_bad.data:
		failures += 1
		print("FAIL good and bad layers must differ")

	checks += 1
	if sfx.condition_layer_state() != "" or sfx.condition_layer_audible():
		failures += 1
		print("FAIL the layer should start silent")
	sfx.start_condition_layer(true)
	checks += 1
	if sfx.condition_layer_state() != "good" or sfx._layer_player.stream != sfx._layer_good or sfx.condition_layer_gain() != 0.0:
		failures += 1
		print("FAIL start_condition_layer(true) should start the good layer at gain 0 (fade-in)")
	sfx._update_layer(sfx.LAYER_FADE_IN_S * 0.5)
	checks += 1
	if absf(sfx.condition_layer_gain() - 0.5) > 0.01 or sfx._layer_player.volume_db >= sfx.LAYER_VOLUME_DB:
		failures += 1
		print("FAIL the fade-in should ramp the gain (half way after half the time), got %f / %f dB" % [sfx.condition_layer_gain(), sfx._layer_player.volume_db])
	sfx._update_layer(1.0)
	checks += 1
	if not is_equal_approx(sfx.condition_layer_gain(), 1.0) or not is_equal_approx(sfx._layer_player.volume_db, sfx.LAYER_VOLUME_DB):
		failures += 1
		print("FAIL after the fade-in the layer plays at LAYER_VOLUME_DB")
	sfx.start_condition_layer(false)
	checks += 1
	if sfx.condition_layer_state() != "bad" or sfx._layer_player.stream != sfx._layer_bad:
		failures += 1
		print("FAIL a bad condition swaps to the bad layer")
	sfx._update_layer(1.0)
	sfx.stop_condition_layer()
	checks += 1
	if sfx.condition_layer_state() != "" or not sfx.condition_layer_audible():
		failures += 1
		print("FAIL stop should fade out (state '' at once, still audible during the ramp)")
	sfx._update_layer(sfx.LAYER_FADE_OUT_S * 0.5)
	checks += 1
	if absf(sfx.condition_layer_gain() - 0.5) > 0.01:
		failures += 1
		print("FAIL the fade-out should ramp down, got %f" % sfx.condition_layer_gain())
	sfx._update_layer(1.0)
	checks += 1
	if sfx.condition_layer_audible() or sfx.condition_layer_gain() != 0.0 or sfx._layer_player.volume_db > sfx.LAYER_SILENT_DB + 0.01:
		failures += 1
		print("FAIL after the fade-out the layer is silent and ended")
	sfx.start_condition_layer(true)
	sfx._update_layer(1.0)
	sfx.stop_all()
	checks += 1
	if sfx.condition_layer_audible() or sfx.condition_layer_state() != "":
		failures += 1
		print("FAIL stop_all() cuts the layer at once")

	print("")
	if failures == 0:
		print("ALL %d AUDIO SYNTH CHECKS PASSED" % checks)
		quit(0)
	else:
		print("%d/%d AUDIO SYNTH CHECKS FAILED" % [failures, checks])
		quit(1)
