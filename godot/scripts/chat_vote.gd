extends RefCounted
## ChatVote — the Twitch chat's say over the white rabbit (spec 2.6, E8g).
##
## Viewers vote with !gut and !schlecht. One vote per user in a sliding
## 60-s window; a user's latest vote counts (it replaces their earlier one
## and restarts their 60 s). The rabbit reads the share at the moment it is
## picked up (Entscheidung Studio Head, 03.10.2026 review):
##
##   d          = (gut − schlecht) / (gut + schlecht)        (−1 … +1)
##   good share = 0.60 + 0.30·d − 0.10·d²,  clamped to 20–80 %;
##                under 3 different voters 60 %.
##
## The quadratic term makes the formula reach both ends: a unanimous
## !gut chat gives 80 %, a unanimous !schlecht chat 20 % (the old linear
## 60 % + 30 points × d could only go down to 30 %). Near a tie it still moves
## like the linear one (slope 0.30 at d = 0), so a small majority shifts a
## little and only a clear majority shifts a lot.
##
## Pure logic, no nodes and no clock of its own: the caller passes the time
## (Main uses its never-stopping real clock), so tests can drive it directly.

const WINDOW_S := 60.0
const MIN_VOTERS := 3
const P_BASE := 0.6
const SPREAD := 0.3
const CURVE := 0.1
const P_MIN := 0.2
const P_MAX := 0.8

var _votes := {} # user (lower case) -> {"good": bool, "t": float}


## Records `user`'s vote at time `t` (seconds). Replaces an earlier vote of
## the same user. Empty user names are ignored.
func vote(user: String, good: bool, t: float) -> void:
	var u := user.strip_edges().to_lower()
	if u == "":
		return
	_votes[u] = {"good": good, "t": t}


## Drops every vote older than the window (a vote cast at t0 counts while
## t - t0 < WINDOW_S).
func prune(t: float) -> void:
	for u in _votes.keys():
		if t - float(_votes[u].t) >= WINDOW_S:
			_votes.erase(u)


## Vector2i(good, bad) of the valid votes at time `t`.
func counts(t: float) -> Vector2i:
	prune(t)
	var out := Vector2i.ZERO
	for u in _votes:
		if _votes[u].good:
			out.x += 1
		else:
			out.y += 1
	return out


func voters(t: float) -> int:
	var c := counts(t)
	return c.x + c.y


## The good share for the rabbit at time `t`.
func p_good(t: float) -> float:
	var c := counts(t)
	return share_for(c.x, c.y)


## True when the chat moved the share away from the base (>= MIN_VOTERS and
## a share other than 60 %): the rabbit is then drawn with real randomness
## and the level counts on the "chat" board.
func shifted(t: float) -> bool:
	return voters(t) >= MIN_VOTERS and not is_equal_approx(p_good(t), P_BASE)


func clear() -> void:
	_votes.clear()


## The formula on its own (good / bad = numbers of voters).
static func share_for(good: int, bad: int) -> float:
	var n := good + bad
	if n < MIN_VOTERS:
		return P_BASE
	var d := float(good - bad) / float(n)
	return clampf(P_BASE + SPREAD * d - CURVE * d * d, P_MIN, P_MAX)


## "70 %" style percentage used by the HUD ("Kaninchen: 70 % gut").
static func percent(p: float) -> int:
	return roundi(p * 100.0)
