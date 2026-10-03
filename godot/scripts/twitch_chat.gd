extends Node
## TwitchChat — autoload singleton for optional, opt-in Twitch chat
## interaction. Connects anonymously (no OAuth/credentials needed — Twitch's
## IRC gateway accepts a throwaway "justinfanNNNNN" login for read-only
## access) to a streamer-chosen channel's chat, and turns "!command"
## messages into a `chat_command` signal that Main listens to for small,
## opt-in gameplay effects.
##
## Off by default and never auto-enabled: a serious/competitive speedrun
## should not have its outcome affected by chat unless the streamer turns
## this on themselves from the start screen (see hud.gd's Twitch toggle).
##
## The actual IRC socket (irc.chat.twitch.tv:6667, raw TCP) can't be reached
## from this development sandbox's egress allowlist, so the line/message
## parsing is split into pure static functions (parse_irc_line,
## parse_command) that a headless test can exercise directly against
## synthetic IRC lines without any real network access — see
## tests/test_twitch_chat.gd.

signal chat_command(user: String, command: String, args: String)
signal connection_state_changed(is_connected: bool)

const HOST := "irc.chat.twitch.tv"
const PORT := 6667
## Recognized viewer commands. Kept deliberately small, harmless, and
## reversible: nothing here can end a run or lock out player input.
const KNOWN_COMMANDS := ["power", "fruit"]

var enabled := false
var channel := ""

var _tcp: StreamPeerTCP
var _connected := false
var _registered := false
var _recv_buffer := ""


func connect_to_channel(channel_name: String) -> void:
	channel = channel_name.strip_edges().to_lower().trim_prefix("#")
	if channel == "":
		return
	_tcp = StreamPeerTCP.new()
	var err := _tcp.connect_to_host(HOST, PORT)
	if err != OK:
		_tcp = null
		return
	_registered = false
	_connected = false


func disconnect_chat() -> void:
	if _tcp != null:
		_tcp.disconnect_from_host()
	_tcp = null
	_registered = false
	if _connected:
		_connected = false
		connection_state_changed.emit(false)


func is_connected_to_chat() -> bool:
	return _connected


func _process(_delta: float) -> void:
	if not enabled or _tcp == null:
		return
	_tcp.poll()
	var status := _tcp.get_status()
	if status == StreamPeerTCP.STATUS_CONNECTED:
		if not _registered:
			_registered = true
			# Anonymous read-only login: any "justinfanNNNNN" nick is accepted
			# without a password by Twitch's IRC gateway.
			var anon_nick := "justinfan%d" % (100000 + (randi() % 900000))
			_tcp.put_data(("PASS blah\r\n").to_utf8_buffer())
			_tcp.put_data(("NICK %s\r\n" % anon_nick).to_utf8_buffer())
			_tcp.put_data(("JOIN #%s\r\n" % channel).to_utf8_buffer())
			_connected = true
			connection_state_changed.emit(true)
		var avail := _tcp.get_available_bytes()
		if avail > 0:
			var chunk := _tcp.get_utf8_string(avail)
			_recv_buffer += chunk
			var lines := _recv_buffer.split("\n")
			_recv_buffer = lines[lines.size() - 1]
			for i in range(lines.size() - 1):
				_handle_line(lines[i].strip_edges())
	elif status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE:
		if _connected:
			_connected = false
			connection_state_changed.emit(false)
		_tcp = null


func _handle_line(line: String) -> void:
	if line == "":
		return
	if line.begins_with("PING"):
		_tcp.put_data(("PONG :tmi.twitch.tv\r\n").to_utf8_buffer())
		return
	var parsed := parse_irc_line(line)
	if parsed.is_empty():
		return
	var cmd := parse_command(parsed.message)
	if cmd.is_empty():
		return
	chat_command.emit(parsed.user, cmd.command, cmd.args)


## Pure parser: a raw Twitch IRC line -> {user, channel, message}, or {} if
## it isn't a channel chat message (PRIVMSG). No network/state involved, so
## this is directly unit-testable.
## Example input:
##   :alice!alice@alice.tmi.twitch.tv PRIVMSG #zapmaniac :!power let's go
static func parse_irc_line(line: String) -> Dictionary:
	if not line.begins_with(":"):
		return {}
	var prefix_end := line.find(" ")
	if prefix_end == -1:
		return {}
	var prefix := line.substr(1, prefix_end - 1)
	var user := prefix.split("!")[0]
	var rest := line.substr(prefix_end + 1)
	if not rest.begins_with("PRIVMSG "):
		return {}
	rest = rest.substr("PRIVMSG ".length())
	var chan_end := rest.find(" :")
	if chan_end == -1:
		return {}
	var chan := rest.substr(0, chan_end).trim_prefix("#")
	var message := rest.substr(chan_end + 2)
	return {"user": user, "channel": chan, "message": message}


## Pure parser: a chat message body -> {command, args}, or {} if it isn't a
## recognized "!command" (unknown commands and plain chat are both ignored
## so chat can talk normally without spamming gameplay effects).
static func parse_command(message: String) -> Dictionary:
	var text := message.strip_edges()
	if not text.begins_with("!"):
		return {}
	var parts := text.substr(1).split(" ", false, 1)
	if parts.is_empty():
		return {}
	var cmd: String = parts[0].to_lower()
	if not KNOWN_COMMANDS.has(cmd):
		return {}
	var args := parts[1] if parts.size() > 1 else ""
	return {"command": cmd, "args": args}
