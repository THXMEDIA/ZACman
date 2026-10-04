extends RefCounted
## ChatDuel — the two Twitch chats of a Versus race ("Gegenwind", E17,
## docs/design/multiplayer.md 3).
##
## Each player has their own chat. In a chat, !gut helps THAT chat's player
## (their next rabbit should be good), !schlecht sabotages the OPPONENT (their
## next rabbit should be bad). Every chat is counted as shares, never as
## absolute votes, so 3 voters in a small chat weigh as much as 3,000 in a big
## one:
##
##   h_X = gut_X / n_X,  s_X = schlecht_X / n_X   (both 0 under 3 voters)
##   d_A = h_A − s_B,    d_B = h_B − s_A           (−1 … +1)
##   p_A = 0.60 + 0.30·d_A − 0.10·d_A²,  clamped to 20–80 %  (ChatVote.share_for's curve)
##
## Both players draw their rabbit with the SAME generator per round
## (round_rng: match seed + round), so the first number u is the same for
## both; whoever has the higher p gets the good condition when u falls in
## between — "which player gets a good or a bad rabbit next" (E17a).
##
## A raid can not hurt its own streamer: every command in chat X only ever
## works FOR player X. The duel only runs while BOTH chats are connected
## (`active`); otherwise both rabbits are drawn as without chat (60 %).
##
## Pure logic like ChatVote: no nodes, the caller passes the time.

const ChatVoteScript := preload("res://scripts/chat_vote.gd")

## Player sides of a match: the host is A, the client B.
const SIDE_A := 0
const SIDE_B := 1

## The two chats, one ChatVote each (same window and one-vote rule as solo).
var votes: Array = [ChatVoteScript.new(), ChatVoteScript.new()]
## Channel name (lower case, no '#') of each side's chat; "" = no chat.
var channels: Array = ["", ""]
## Both chats connected: only then does the duel shift anything.
var active := false


func set_channels(channel_a: String, channel_b: String) -> void:
	channels = [_norm(channel_a), _norm(channel_b)]
	clear()


func clear() -> void:
	for v in votes:
		v.clear()


## Side whose chat `channel` is, or -1 if it is none of the two.
func side_of_channel(channel: String) -> int:
	var c := _norm(channel)
	if c == "":
		return -1
	if c == channels[SIDE_A]:
		return SIDE_A
	if c == channels[SIDE_B]:
		return SIDE_B
	return -1


## A chat command from `channel`. Only !gut and !schlecht count; returns true
## when it was a vote of one of the two chats.
func on_command(channel: String, user: String, command: String, t: float) -> bool:
	if command != "gut" and command != "schlecht":
		return false
	var side := side_of_channel(channel)
	if side < 0:
		return false
	votes[side].vote(user, command == "gut", t)
	return true


## Vector2(h, s): help and sabotage share of `side`'s chat at time `t`
## (0, 0 under ChatVote.MIN_VOTERS voters).
func shares(side: int, t: float) -> Vector2:
	var c: Vector2i = votes[side].counts(t)
	return shares_for(c.x, c.y)


## Raw counts of `side`'s chat (Vector2i(gut, schlecht)) — what the two
## clients compare when a rabbit is drawn.
func counts(side: int, t: float) -> Vector2i:
	return votes[side].counts(t)


## Good share of `side`'s next rabbit at time `t`; 60 % while the duel is off.
func p_good(side: int, t: float) -> float:
	if not active:
		return ChatVoteScript.P_BASE
	return p_for(shares(side, t), shares(1 - side, t))


## True when the chats moved `side`'s share away from the base: the round then
## counts on the "chat" board for that player (help or sabotage alike).
func shifted(side: int, t: float) -> bool:
	return active and not is_equal_approx(p_good(side, t), ChatVoteScript.P_BASE)


## How the chats touched `side` right now: "" (not at all), "hilfe",
## "sabotage" or "beides" — stored with the board entry (E17, design 4).
func influence(side: int, t: float) -> String:
	if not active:
		return ""
	var help := shares(side, t).x > 0.0
	var sabotage := shares(1 - side, t).y > 0.0
	if help and sabotage:
		return "beides"
	if help:
		return "hilfe"
	if sabotage:
		return "sabotage"
	return ""


## ---- pure formulas --------------------------------------------------------

## Vector2(h, s) for a chat with `good` !gut and `bad` !schlecht voters.
static func shares_for(good: int, bad: int) -> Vector2:
	var n := good + bad
	if n < ChatVoteScript.MIN_VOTERS:
		return Vector2.ZERO
	return Vector2(float(good) / float(n), float(bad) / float(n))


## Good share for a player whose own chat has shares `own` and whose
## opponent's chat has shares `opp` (both Vector2(h, s)).
static func p_for(own: Vector2, opp: Vector2) -> float:
	var d := clampf(own.x - opp.y, -1.0, 1.0)
	return clampf(ChatVoteScript.P_BASE + ChatVoteScript.SPREAD * d - ChatVoteScript.CURVE * d * d, ChatVoteScript.P_MIN, ChatVoteScript.P_MAX)


## The match seed both clients agree on: derived from both players' secret
## seeds (exchanged by commit-reveal, see commit()), so neither side can pick it.
static func match_seed(seed_a: int, seed_b: int) -> int:
	return hash("zapmaniac-match|%d|%d" % [seed_a, seed_b])


## The rabbit generator of `round` (0, 1, 2 …) in a match: identical for both
## players, so they share the first number u (good/bad) and the weighting
## draw that follows.
static func round_rng(seed: int, round: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("zapmaniac-round|%d|%d" % [seed, round])
	return rng


## Commit of a secret seed (sent before the seed itself): SHA-256 hex.
static func commit(seed: int) -> String:
	return ("zapmaniac-commit|%d" % seed).sha256_text()


static func verify(seed: int, commit_hex: String) -> bool:
	return commit(seed) == commit_hex


static func _norm(channel: String) -> String:
	return channel.strip_edges().to_lower().trim_prefix("#")
