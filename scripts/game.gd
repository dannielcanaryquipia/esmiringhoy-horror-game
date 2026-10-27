extends Node

enum Diff { EASY, NORMAL, NIGHTMARE }

var difficulty: int = Diff.NORMAL

var time_survived: float = 0.0
var times_hidden: int = 0
var closest_demon: float = 999.0
var matches_used: int = 0
var candles_lit: int = 0

func set_difficulty(d: int) -> void:
	difficulty = d

func difficulty_name() -> String:
	match difficulty:
		Diff.EASY:
			return "Easy"
		Diff.NIGHTMARE:
			return "Nightmare"
		_:
			return "Normal"

func tuning() -> Dictionary:
	match difficulty:
		Diff.EASY:
			return {"hunt": 3.6, "breath": 8.0, "batteries": 5}
		Diff.NIGHTMARE:
			return {"hunt": 4.5, "breath": 5.0, "batteries": 1}
		_:
			return {"hunt": 4.0, "breath": 6.0, "batteries": 3}

func reset_stats() -> void:
	time_survived = 0.0
	times_hidden = 0
	closest_demon = 999.0
	matches_used = 0
	candles_lit = 0

func note_close(dist: float) -> void:
	closest_demon = minf(closest_demon, dist)

func stats_lines() -> Array:
	var total_secs: int = int(time_survived)
	@warning_ignore("integer_division")
	var mins: int = total_secs / 60
	var secs: int = total_secs % 60
	var time_str: String = "%d:%02d" % [mins, secs]
	return [
		"Time survived: " + time_str,
		"Times hidden: " + str(times_hidden),
		"Closest it got: " + ("%.1f" % closest_demon) + " m",
		"Candles lit: " + str(candles_lit),
	]
