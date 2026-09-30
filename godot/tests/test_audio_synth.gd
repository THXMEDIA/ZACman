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

	print("")
	if failures == 0:
		print("ALL %d AUDIO SYNTH CHECKS PASSED" % checks)
		quit(0)
	else:
		print("%d/%d AUDIO SYNTH CHECKS FAILED" % [failures, checks])
		quit(1)
