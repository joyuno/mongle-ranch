# GitHub activity sync — "간식 배달부". Username-only, unauthenticated, and
# strictly non-blocking: every failure falls back to cache and the game is
# fully playable without it.
#
# Security posture (docs/RISKS.md):
#   * NO token input, NO OAuth — public GET /users/{u}/events only
#   * ETag conditional requests (304 doesn't count against the 60/h limit)
#   * poll at most every SYNC_INTERVAL_SEC, exponential backoff on 403/429
#   * runtime never calls any image-generation endpoint

extends Node

signal sync_started
signal snacks_arrived(granted: int, commits: int)
signal sync_failed(reason: String)

const API_BASE := "https://api.github.com"
const CACHE_PATH := "user://github_cache.json"
const SYNC_INTERVAL_SEC: float = 600.0   # 10 min minimum between live calls
const USER_AGENT := "mongle-ranch/0.1 (Godot; study game; no auth)"

var _http: HTTPRequest
var _busy := false
var _last_sync_unix: float = 0.0
var _backoff_until_unix: float = 0.0
var _etag := ""


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
	_load_cache()


# Called by the ranch screen on entry. Silently does nothing when disabled,
# too soon, backing off, or already running.
func sync() -> void:
	var username := ProgressStore.get_github_username()
	if username.is_empty() or _busy:
		return
	var now := Time.get_unix_time_from_system()
	if now < _backoff_until_unix or now - _last_sync_unix < SYNC_INTERVAL_SEC:
		return
	_busy = true
	sync_started.emit()
	var headers := PackedStringArray([
		"User-Agent: %s" % USER_AGENT,
		"Accept: application/vnd.github+json",
	])
	if not _etag.is_empty():
		headers.append("If-None-Match: %s" % _etag)
	var url := "%s/users/%s/events?per_page=100" % [API_BASE, username.uri_encode()]
	var err := _http.request(url, headers)
	if err != OK:
		_busy = false
		sync_failed.emit("request_error_%d" % err)


func _on_request_completed(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	_busy = false
	_last_sync_unix = Time.get_unix_time_from_system()
	if result != HTTPRequest.RESULT_SUCCESS:
		sync_failed.emit("transport_%d" % result)
		return
	if code == 304:
		return  # nothing new — free request, no rate-limit cost
	if code == 403 or code == 429:
		# Respect X-RateLimit-Reset when present, else back off 30 min.
		var reset := 0.0
		for h in headers:
			if h.to_lower().begins_with("x-ratelimit-reset:"):
				reset = float(h.get_slice(":", 1).strip_edges())
		_backoff_until_unix = reset if reset > 0.0 else Time.get_unix_time_from_system() + 1800.0
		sync_failed.emit("rate_limited")
		return
	if code != 200:
		sync_failed.emit("http_%d" % code)
		return
	for h in headers:
		if h.to_lower().begins_with("etag:"):
			_etag = h.substr(5).strip_edges()
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_ARRAY:
		sync_failed.emit("bad_payload")
		return
	_save_cache(parsed)
	_credit_events(parsed)


func _credit_events(events: Array) -> void:
	var counted := GithubSnacks.count_new_commits(events, ProgressStore.get_github_last_event_id())
	var commits := int(counted.get("commits", 0))
	var granted := ProgressStore.grant_snacks(commits, String(counted.get("latest_id", "")))
	if commits > 0:
		snacks_arrived.emit(granted, commits)


func _save_cache(events: Array) -> void:
	var f := FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"etag": _etag,
		"savedAt": Time.get_unix_time_from_system(),
		"events": events,
	}))
	f.close()


func _load_cache() -> void:
	if not FileAccess.file_exists(CACHE_PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CACHE_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	_etag = String(parsed.get("etag", ""))
