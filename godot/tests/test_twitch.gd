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
	var ok_line := ":alice!alice@alice.tmi.twitch.tv PRIVMSG #zacman :!power let's go"
	var parsed: Dictionary = twitch.parse_irc_line(ok_line)
	if parsed.get("user") != "alice" or parsed.get("channel") != "zacman" or parsed.get("message") != "!power let's go":
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

	checks += 1
	var no_user_line := ":bob!bob@bob.tmi.twitch.tv PRIVMSG #zacman :just chatting, no command here"
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
	]
	for msg in rejected_cases:
		checks += 1
		if not twitch.parse_command(msg).is_empty():
			failures += 1
			print("FAIL parse_command(%s) should have been rejected" % msg)

	# --- KNOWN_COMMANDS sanity: every command Main actually handles must be
	# whitelisted here, and vice versa, so the two can't silently drift.
	checks += 1
	var main_handled := ["power", "fruit"]
	var known: Array = twitch.KNOWN_COMMANDS
	var same := known.size() == main_handled.size()
	if same:
		for c in main_handled:
			if not known.has(c):
				same = false
	if not same:
		failures += 1
		print("FAIL KNOWN_COMMANDS %s does not match the commands Main handles %s" % [known, main_handled])

	print("")
	if failures == 0:
		print("ALL %d TWITCH PARSER CHECKS PASSED" % checks)
		quit(0)
	else:
		print("%d/%d TWITCH PARSER CHECKS FAILED" % [failures, checks])
		quit(1)
