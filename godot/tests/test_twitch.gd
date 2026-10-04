extends SceneTree
## Headless test: res://scripts/twitch_chat.gd's pure parsing functions
## (parse_irc_line, parse_command). The actual IRC socket
## (irc.chat.twitch.tv:6667) isn't reachable from this sandbox's network
## allowlist, so this exercises the parser directly against synthetic IRC
## lines instead — the same split-network-from-logic approach used for the
## Manhattan maze (see manhattan_maze.gd's header comment). Run with
##   godot --headless --path . --script res://tests/test_twitch.gd
## Exits with code 0 on success, 1 on any failure.

func _initialize() -> void:
	var twitch = load("res://scripts/twitch_chat.gd")
	var failures := 0
	var checks := 0

	# --- parse_irc_line -------------------------------------------------
	checks += 1
	var ok_line := ":alice!alice@alice.tmi.twitch.tv PRIVMSG #zapmaniac :!power let's go"
	var parsed: Dictionary = twitch.parse_irc_line(ok_line)
	if parsed.get("user") != "alice" or parsed.get("channel") != "zapmaniac" or parsed.get("message") != "!power let's go":
		failures += 1
		print("FAIL parse_irc_line PRIVMSG: %s" % [parsed])

	checks += 1
	var ping_line := "PING :tmi.twitch.tv"
	if not twitch.parse_irc_line(ping_line).is_empty():
		failures += 1
		print("FAIL parse_irc_line should ignore PING (handled separately, not as a chat message)")

	checks += 1
	var join_notice := ":tmi.twitch.tv 001 justinfan12345 :Welcome, GLHF!"
	if not twitch.parse_irc_line(join_notice).is_empty():
		failures += 1
		print("FAIL parse_irc_line should ignore non-PRIVMSG server notices")

	checks += 1
	if not twitch.parse_irc_line("not even a colon-prefixed line").is_empty():
		failures += 1
		print("FAIL parse_irc_line should reject lines without a ':' prefix")

	# a vote as a full IRC line, end to end through both parsers
	checks += 1
	var vote_line: Dictionary = twitch.parse_irc_line(":Carol!carol@carol.tmi.twitch.tv PRIVMSG #zapmaniac :!schlecht")
	var vote_cmd: Dictionary = twitch.parse_command(vote_line.get("message", ""))
	if vote_line.get("user") != "Carol" or vote_cmd.get("command") != "schlecht":
		failures += 1
		print("FAIL a !schlecht line should parse to user Carol, command schlecht: %s %s" % [vote_line, vote_cmd])

	checks += 1
	var no_user_line := ":bob!bob@bob.tmi.twitch.tv PRIVMSG #zapmaniac :just chatting, no command here"
	var parsed2: Dictionary = twitch.parse_irc_line(no_user_line)
	if parsed2.get("message") != "just chatting, no command here":
		failures += 1
		print("FAIL parse_irc_line plain chat message: %s" % [parsed2])

	# --- parse_command ----------------------------------------------------
	var cmd_cases := [
		["!power", {"command": "power", "args": ""}],
		["!power now please", {"command": "power", "args": "now please"}],
		["!FRUIT", {"command": "fruit", "args": ""}],
		["  !fruit  ", {"command": "fruit", "args": ""}],
		["!gut", {"command": "gut", "args": ""}],
		["!schlecht", {"command": "schlecht", "args": ""}],
		["!GUT bitte Matrix", {"command": "gut", "args": "bitte Matrix"}],
		["  !Schlecht  ", {"command": "schlecht", "args": ""}],
	]
	for c in cmd_cases:
		checks += 1
		var got: Dictionary = twitch.parse_command(c[0])
		var want: Dictionary = c[1]
		if got.get("command", "") != want.command or got.get("args", "") != want.args:
			failures += 1
			print("FAIL parse_command(%s) = %s, expected %s" % [c[0], got, want])

	var rejected_cases := [
		"hello there",           # not a command at all
		"!unknowncommand",       # not in KNOWN_COMMANDS
		"!",                     # empty command
		"power",                 # missing the leading '!'
		"gut",                   # a vote needs the '!' too
		"!gutschlecht",          # not a command
	]
	for msg in rejected_cases:
		checks += 1
		if not twitch.parse_command(msg).is_empty():
			failures += 1
			print("FAIL parse_command(%s) should have been rejected" % msg)

	# --- KNOWN_COMMANDS sanity: every command Main actually handles must be
	# whitelisted here, and vice versa, so the two can't silently drift.
	checks += 1
	var main_handled := ["power", "fruit", "gut", "schlecht"]
	var known: Array = twitch.KNOWN_COMMANDS
	var same := known.size() == main_handled.size()
	if same:
		for c in main_handled:
			if not known.has(c):
				same = false
	if not same:
		failures += 1
		print("FAIL KNOWN_COMMANDS %s does not match the commands Main handles %s" % [known, main_handled])

	# --- extra channels (Versus, E17): only the primary channel drives
	# chat_command; every channel arrives on channel_command ---------------
	var tw = twitch.new()
	tw.channel = "streamera"
	var primary := []
	var all := []
	tw.chat_command.connect(func(u, c, a): primary.append([u, c]))
	tw.channel_command.connect(func(ch, u, c, a): all.append([ch, u, c]))
	tw.join_extra("#StreamerB")
	tw.join_extra("streamera") # the primary channel is never an extra
	tw.join_extra("")
	checks += 1
	if tw.extra_channels != ["streamerb"]:
		failures += 1
		print("FAIL join_extra: %s" % [tw.extra_channels])
	tw.inject_line(":viewer1!v@v.tmi.twitch.tv PRIVMSG #streamera :!gut")
	tw.inject_line(":viewer2!v@v.tmi.twitch.tv PRIVMSG #streamerb :!schlecht")
	tw.inject_line(":viewer3!v@v.tmi.twitch.tv PRIVMSG #streamerb :!power")
	tw.inject_line("PING :tmi.twitch.tv") # no socket: must not crash
	checks += 1
	if primary != [["viewer1", "gut"]]:
		failures += 1
		print("FAIL chat_command must only carry the primary channel: %s" % [primary])
	checks += 1
	if all != [["streamera", "viewer1", "gut"], ["streamerb", "viewer2", "schlecht"], ["streamerb", "viewer3", "power"]]:
		failures += 1
		print("FAIL channel_command must carry every channel: %s" % [all])
	tw.leave_extras()
	checks += 1
	if not tw.extra_channels.is_empty():
		failures += 1
		print("FAIL leave_extras")
	tw.free()

	print("")
	if failures == 0:
		print("ALL %d TWITCH PARSER CHECKS PASSED" % checks)
		quit(0)
	else:
		print("%d/%d TWITCH PARSER CHECKS FAILED" % [failures, checks])
		quit(1)
