extends SceneTree
## Headless test: res://scripts/chat_duel.gd — the chat duel of a Versus race
## (E17, docs/design/multiplayer.md 3): !gut helps the chat's own player,
## !schlecht sabotages the opponent, counted as shares per chat, both rabbits
## drawn from the same round generator. Run with
##   godot --headless --path . --script res://tests/test_chat_duel.gd
## Exits with code 0 on success, 1 on any failure.

const ChatDuel := preload("res://scripts/chat_duel.gd")
const ChatVote := preload("res://scripts/chat_vote.gd")
const Conditions := preload("res://scripts/conditions.gd")

var failures := 0
var checks := 0


func _check(name: String, cond: bool, detail := "") -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL %s %s" % [name, detail])


func _approx(a: float, b: float) -> bool:
	return absf(a - b) < 1e-6


func _votes(duel, side: int, good: int, bad: int, t: float = 0.0) -> void:
	var ch: String = duel.channels[side]
	for i in good:
		duel.on_command(ch, "g%d_%d" % [side, i], "gut", t)
	for i in bad:
		duel.on_command(ch, "b%d_%d" % [side, i], "schlecht", t)


func _initialize() -> void:
	# --- pure formulas ----------------------------------------------------------
	_check("shares: under 3 voters count as nothing", ChatDuel.shares_for(2, 0) == Vector2.ZERO)
	_check("shares: 3 gut / 1 schlecht -> (0.75, 0.25)", ChatDuel.shares_for(3, 1).is_equal_approx(Vector2(0.75, 0.25)))
	var full_help := Vector2(1, 0)
	var full_sab := Vector2(0, 1)
	var half := Vector2(0.5, 0.5)
	var none := Vector2.ZERO
	_check("both chats help -> 80 % each", _approx(ChatDuel.p_for(full_help, full_help), 0.8))
	_check("both chats sabotage -> 20 % each", _approx(ChatDuel.p_for(full_sab, full_sab), 0.2))
	_check("A helps, B sabotages -> A 60 % (help and sabotage cancel)", _approx(ChatDuel.p_for(full_help, full_sab), 0.6))
	_check("A helps, B sabotages -> B 60 % (B's chat did not help B)", _approx(ChatDuel.p_for(full_sab, full_help), 0.6))
	_check("A half/half, B full help -> A 72.5 %", _approx(ChatDuel.p_for(half, full_help), 0.725), str(ChatDuel.p_for(half, full_help)))
	_check("A half/half, B full help -> B 72.5 % (A sabotaged B by half)", _approx(ChatDuel.p_for(full_help, half), 0.725))
	_check("no votes at all -> 60 %", _approx(ChatDuel.p_for(none, none), 0.6))
	_check("help share 0.7, no sabotage -> 0.60 + 0.21 - 0.049 = 76.1 %", _approx(ChatDuel.p_for(Vector2(0.7, 0.3), none), 0.761))
	var bounded := true
	for i in 11:
		for j in 11:
			var p := ChatDuel.p_for(Vector2(i / 10.0, 1.0 - i / 10.0), Vector2(j / 10.0, 1.0 - j / 10.0))
			if p < 0.2 - 1e-9 or p > 0.8 + 1e-9:
				bounded = false
	_check("every combination stays within 20–80 %", bounded)
	var mono := true
	for i in 10:
		if ChatDuel.p_for(Vector2((i + 1) / 10.0, 0), none) < ChatDuel.p_for(Vector2(i / 10.0, 0), none) - 1e-9:
			mono = false
		if ChatDuel.p_for(none, Vector2(0, (i + 1) / 10.0)) > ChatDuel.p_for(none, Vector2(0, i / 10.0)) + 1e-9:
			mono = false
	_check("more help never lowers, more sabotage never raises the share", mono)

	# --- the duel object --------------------------------------------------------
	var duel = ChatDuel.new()
	duel.set_channels("#StreamerA", "streamer_b")
	_check("channels are normalized", duel.channels == ["streamera", "streamer_b"])
	_check("side_of_channel: A", duel.side_of_channel("#STREAMERA") == ChatDuel.SIDE_A)
	_check("side_of_channel: B", duel.side_of_channel("streamer_b") == ChatDuel.SIDE_B)
	_check("side_of_channel: a third channel is ignored", duel.side_of_channel("someone_else") == -1)
	_check("non-vote commands are ignored", not duel.on_command("streamera", "x", "power", 0.0))
	_check("votes from a third channel are ignored", not duel.on_command("other", "x", "gut", 0.0))

	_votes(duel, ChatDuel.SIDE_A, 6, 0)
	_votes(duel, ChatDuel.SIDE_B, 0, 4)
	duel.active = false
	_check("inactive duel (a chat missing) -> 60 % for both", _approx(duel.p_good(0, 1.0), 0.6) and _approx(duel.p_good(1, 1.0), 0.6))
	_check("inactive duel never shifts", not duel.shifted(0, 1.0) and not duel.shifted(1, 1.0))
	duel.active = true
	_check("A all help, B all sabotage -> A 60 %", _approx(duel.p_good(0, 1.0), 0.6), str(duel.p_good(0, 1.0)))
	_check("A all help, B all sabotage -> B 60 %", _approx(duel.p_good(1, 1.0), 0.6))
	_check("help and sabotage cancel: no shift for A", not duel.shifted(0, 1.0))
	_check("influence A: beides", duel.influence(0, 1.0) == "beides")
	_check("influence B: nothing (A's chat only helped A, B's chat only sabotaged A)", duel.influence(1, 1.0) == "")

	duel.clear()
	_votes(duel, ChatDuel.SIDE_A, 3, 0)
	_check("only A's chat helps -> A 80 %, shifted", _approx(duel.p_good(0, 1.0), 0.8) and duel.shifted(0, 1.0))
	_check("only A's chat helps -> B untouched 60 %", _approx(duel.p_good(1, 1.0), 0.6) and not duel.shifted(1, 1.0))
	_check("influence A: hilfe", duel.influence(0, 1.0) == "hilfe")

	duel.clear()
	_votes(duel, ChatDuel.SIDE_A, 0, 3)
	_check("A's chat sabotages -> B 20 %", _approx(duel.p_good(1, 1.0), 0.2))
	_check("A's chat sabotaging never hurts A", _approx(duel.p_good(0, 1.0), 0.6))
	_check("influence B: sabotage", duel.influence(1, 1.0) == "sabotage")

	# Normalization: a big chat does not outweigh a small one.
	duel.clear()
	_votes(duel, ChatDuel.SIDE_A, 3, 0) # small chat, all help
	_votes(duel, ChatDuel.SIDE_B, 0, 3000) # huge chat, all sabotage
	_check("3 helpers weigh as much as 3000 saboteurs (shares, not votes)", _approx(duel.p_good(0, 1.0), 0.6))

	# Votes expire with ChatVote's window.
	_check("votes expire after the window", _approx(duel.p_good(0, 1.0 + ChatVote.WINDOW_S), 0.6))

	# --- shared randomness ------------------------------------------------------
	var a := ChatDuel.round_rng(12345, 0)
	var b := ChatDuel.round_rng(12345, 0)
	_check("round_rng: both players get the same first number", a.randf() == b.randf())
	var c := ChatDuel.round_rng(12345, 1)
	var d := ChatDuel.round_rng(12345, 0)
	_check("round_rng: another round draws differently", c.randf() != d.randf())
	# Same generator + same share -> same condition for both; the higher share
	# can only ever turn bad into good.
	var never_worse := true
	var same_when_equal := true
	for r in 200:
		var cond_hi := Conditions.pick_condition(ChatDuel.round_rng(777, r), 0.75)
		var cond_lo := Conditions.pick_condition(ChatDuel.round_rng(777, r), 0.35)
		var g_hi: bool = Conditions.get_condition(cond_hi).is_good
		var g_lo: bool = Conditions.get_condition(cond_lo).is_good
		if g_lo and not g_hi:
			never_worse = false
		if Conditions.pick_condition(ChatDuel.round_rng(777, r), 0.6) != Conditions.pick_condition(ChatDuel.round_rng(777, r), 0.6):
			same_when_equal = false
	_check("same share -> both players get the same condition", same_when_equal)
	_check("a higher share never turns a good rabbit bad (shared u)", never_worse)

	# --- commit-reveal ----------------------------------------------------------
	var commit := ChatDuel.commit(987654)
	_check("commit is a SHA-256 hex", commit.length() == 64)
	_check("verify accepts the committed seed", ChatDuel.verify(987654, commit))
	_check("verify rejects another seed", not ChatDuel.verify(987655, commit))
	_check("match seed depends on both seeds", ChatDuel.match_seed(1, 2) != ChatDuel.match_seed(1, 3) and ChatDuel.match_seed(1, 2) != ChatDuel.match_seed(4, 2))
	_check("match seed is reproducible", ChatDuel.match_seed(11, 22) == ChatDuel.match_seed(11, 22))

	if failures == 0:
		print("test_chat_duel: all %d checks passed" % checks)
	else:
		print("test_chat_duel: %d of %d checks FAILED" % [failures, checks])
	quit(1 if failures > 0 else 0)
