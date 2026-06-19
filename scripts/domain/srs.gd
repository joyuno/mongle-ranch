# Spaced Repetition System — simplified Anki SM-2.
# Ported from shared/constants/srs.ts. ISO 8601 timestamps for interop with the
# Electron version's progress.json (cross-engine save migration possible).

class_name SRS
extends RefCounted

# Days until next review per stage. Index 0 = first wrong answer.
const SRS_INTERVAL_DAYS: Array[int] = [1, 3, 7, 14, 30, 90]
const SRS_GRADUATE_LEVEL: int = 6  # == SRS_INTERVAL_DAYS.size()


static func initial_next_review_at(now_unix: float = 0.0) -> String:
	if now_unix <= 0.0:
		now_unix = Time.get_unix_time_from_system()
	return _add_days_iso(now_unix, SRS_INTERVAL_DAYS[0])


# Returns { "review_level": int, "next_review_at": String } on next review,
# or {} (empty Dictionary) when the entry graduates from the wrong-note set.
static func grade_review(current_level: int, correct: bool, now_unix: float = 0.0) -> Dictionary:
	if now_unix <= 0.0:
		now_unix = Time.get_unix_time_from_system()
	if correct:
		var next_level := current_level + 1
		if next_level >= SRS_GRADUATE_LEVEL:
			return {}
		var days := SRS_INTERVAL_DAYS[next_level] if next_level < SRS_INTERVAL_DAYS.size() else 90
		return { "review_level": next_level, "next_review_at": _add_days_iso(now_unix, days) }
	# Wrong → reset to stage 0, 1 day later.
	return { "review_level": 0, "next_review_at": _add_days_iso(now_unix, SRS_INTERVAL_DAYS[0]) }


# Missing timestamp counts as due (legacy entries from before SRS was wired in).
static func is_due(next_review_at: String, now_unix: float = 0.0) -> bool:
	if next_review_at.is_empty():
		return true
	if now_unix <= 0.0:
		now_unix = Time.get_unix_time_from_system()
	var due_unix := Time.get_unix_time_from_datetime_string(next_review_at)
	return due_unix <= now_unix


# Korean-localized "due in" label used in the Home review card.
static func format_due_in(next_review_at: String, now_unix: float = 0.0) -> String:
	if next_review_at.is_empty():
		return "지금"
	if now_unix <= 0.0:
		now_unix = Time.get_unix_time_from_system()
	var due_unix := Time.get_unix_time_from_datetime_string(next_review_at)
	var diff_sec := due_unix - now_unix
	if diff_sec <= 0:
		return "지금"
	var hr := int(diff_sec / 3600.0)
	if hr < 1:
		return "1시간 안"
	if hr < 24:
		return "%d시간 후" % hr
	var day := int(hr / 24.0)
	return "%d일 후" % day


static func _add_days_iso(now_unix: float, days: int) -> String:
	var future := now_unix + days * 86400.0
	return Time.get_datetime_string_from_unix_time(int(future), true)
