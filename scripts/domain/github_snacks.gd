# GitHub activity → snack conversion — pure parsing over the public events
# payload. Network/caching lives in the GithubSync autoload; this module only
# turns a parsed JSON array into numbers so it stays headless-testable.
#
# Design source: docs/GAME_DESIGN.md §3 — "간식 배달부":
#   * unauthenticated GET /users/{u}/events (no token, ever)
#   * 1 commit = 1 snack, capped at 10 snacks per day
#   * incremental: only events newer than the last seen event id count

class_name GithubSnacks
extends RefCounted

const DAILY_SNACK_CAP: int = 10


# events: Array of GitHub event Dictionaries (newest first, as the API returns).
# last_seen_id: the newest event id already credited ("" on first sync).
# Returns { "commits": int, "latest_id": String }.
static func count_new_commits(events: Array, last_seen_id: String) -> Dictionary:
	var commits := 0
	var latest_id := last_seen_id
	for i in events.size():
		var ev = events[i]
		if typeof(ev) != TYPE_DICTIONARY:
			continue
		var ev_id := String(ev.get("id", ""))
		if i == 0 and not ev_id.is_empty():
			latest_id = ev_id
		if not last_seen_id.is_empty() and ev_id == last_seen_id:
			break
		if String(ev.get("type", "")) == "PushEvent":
			var payload = ev.get("payload", {})
			if typeof(payload) == TYPE_DICTIONARY:
				commits += maxi(0, int(payload.get("distinct_size", 0)))
	return { "commits": commits, "latest_id": latest_id }


# Snacks actually grantable given how many were already granted today.
static func snacks_to_grant(commits: int, granted_today: int) -> int:
	return clampi(DAILY_SNACK_CAP - granted_today, 0, commits)
