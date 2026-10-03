extends SceneTree
## Headless test: res://scripts/chat_vote.gd — the Twitch chat's vote on the
## white rabbit (spec 2.6): one vote per user in a sliding 60-s window, the
## latest vote counts, share = 60 % + 30 points × (gut − schlecht) / (gut +
## schlecht) clamped to 20–80 %, 60 % under 3 different voters. Run with
##   godot --headless --path . --script res://tests/test_chat_vote.gd
## Exits with code 0 on success, 1 on any failure.

const ChatVote := preload("res://scripts/chat_vote.gd")

var failures := 0
var checks := 0


func _check(name: String, cond: bool, detail := "") -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL %s %s" % [name, detail])


func _initialize() -> void:
	# --- the formula ----------------------------------------------------------
	_check("formula: 7 gut / 3 schlecht -> 72 %", is_equal_approx(ChatVote.share_for(7, 3), 0.72), str(ChatVote.share_for(7, 3)))
	_check("formula: tie -> 60 %", is_equal_approx(ChatVote.share_for(5, 5), 0.6))
	_check("formula: all gut -> capped at 80 %", is_equal_approx(ChatVote.share_for(10, 0), 0.8))
	_check("formula: all schlecht -> 30 % (the 20 % floor is never reached)", is_equal_approx(ChatVote.share_for(0, 10), 0.3))
	var in_bounds := true
	for g in 40:
		for b in 40:
			var p := ChatVote.share_for(g, b)
			if p < 0.2 - 1e-9 or p > 0.8 + 1e-9:
				in_bounds = false
	_check("formula: always within 20–80 %", in_bounds)
	_check("formula: under 3 voters the base 60 %", is_equal_approx(ChatVote.share_for(2, 0), 0.6) and is_equal_approx(ChatVote.share_for(0, 2), 0.6) and is_equal_approx(ChatVote.share_for(1, 1), 0.6))
	_check("formula: 3 voters already count", is_equal_approx(ChatVote.share_for(3, 0), 0.8) and is_equal_approx(ChatVote.share_for(2, 1), 0.7))
	_check("percent: 0.72 -> 72", ChatVote.percent(0.72) == 72 and ChatVote.percent(0.6) == 60)

	# --- one vote per user, the latest counts ----------------------------------
	var v = ChatVote.new()
	v.vote("alice", true, 0.0)
	v.vote("bob", true, 1.0)
	_check("min voters: 2 voters -> 60 %, not shifted", is_equal_approx(v.p_good(2.0), 0.6) and not v.shifted(2.0))
	v.vote("carol", true, 2.0)
	_check("3 different voters, all gut -> 80 %, shifted", is_equal_approx(v.p_good(3.0), 0.8) and v.shifted(3.0))
	for i in 10:
		v.vote("alice", true, 3.0 + i * 0.1)
	_check("spamming one user counts once", v.voters(5.0) == 3 and v.counts(5.0) == Vector2i(3, 0), str(v.counts(5.0)))
	v.vote("Alice", false, 5.0)
	_check("the latest vote of a user counts (case-insensitive name)", v.counts(5.0) == Vector2i(2, 1) and is_equal_approx(v.p_good(5.0), 0.7), str(v.counts(5.0)))
	v.vote("  ", true, 5.0)
	_check("empty user names are ignored", v.voters(5.0) == 3)

	# --- sliding 60-s window ----------------------------------------------------
	# bob voted at 1.0, carol at 2.0, alice (schlecht) at 5.0
	_check("window: all three still count at 60.9 s", v.voters(60.9) == 3)
	_check("window: bob's vote (1.0) has expired at 61.0", v.voters(61.0) == 2 and v.counts(61.0) == Vector2i(1, 1))
	_check("window: after expiry under 3 voters -> 60 % again", is_equal_approx(v.p_good(61.0), 0.6) and not v.shifted(61.0))
	v.vote("bob", true, 61.5)
	_check("window: a new vote re-enters", v.voters(61.5) == 3 and is_equal_approx(v.p_good(61.5), 0.7))
	# carol (2.0) expires at 62.0; alice's renewed vote (5.0) at 65.0; bob (61.5) stays
	_check("window: each vote expires 60 s after its own time", v.voters(61.9) == 3 and v.voters(62.0) == 2 and v.voters(64.9) == 2 and v.voters(65.0) == 1)
	_check("window: everything expired after a quiet minute", v.voters(200.0) == 0 and is_equal_approx(v.p_good(200.0), 0.6))

	# --- tie: enough voters but not shifted --------------------------------------
	var tie = ChatVote.new()
	for u in ["a", "b"]:
		tie.vote(u, true, 0.0)
	for u in ["c", "d"]:
		tie.vote(u, false, 0.0)
	_check("tie: 4 voters, 60 % -> not shifted (spec: share must differ from 60 %)", tie.voters(1.0) == 4 and not tie.shifted(1.0))
	tie.clear()
	_check("clear() drops every vote", tie.voters(1.0) == 0)

	print("")
	if failures == 0:
		print("ALL %d CHAT VOTE CHECKS PASSED" % checks)
		quit(0)
	else:
		print("%d/%d CHAT VOTE CHECKS FAILED" % [failures, checks])
		quit(1)
