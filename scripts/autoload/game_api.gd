# Boundary to the local study_game_server coding API. Never calls Judge0 or
# Piston directly — the server is the only thing that executes submitted
# code. The session access token lives only in this autoload's memory; it is
# never written to ProgressStore or progress.json (docs/RISKS.md — the quiz
# game's save file must stay free of auth material).
#
# One request is in flight at a time. A second call while busy fails fast
# with request_failed(operation, "request_in_flight") instead of queuing,
# so UI code never needs to reason about overlapping responses.

extends Node

signal session_ready(user: Dictionary)
signal problems_loaded(problems: Array)
signal problem_loaded(problem: Dictionary)
signal public_run_completed(result: Dictionary)
signal submission_completed(result: Dictionary)
signal request_failed(operation: String, code: String)

const DEFAULT_BASE_URL := "http://127.0.0.1:8000"
const REQUEST_TIMEOUT_SECONDS := 15.0
const DEVICE_ID_PATH := "user://coding_device_id.txt"
const DEVICE_ID_PATH_TMP := "user://coding_device_id.txt.tmp"

var _http: HTTPRequest
var _busy := false
var _current_operation := ""
var _base_url := DEFAULT_BASE_URL
var _access_token := ""
var _wallet_coins := 0


func _ready() -> void:
	var override_url := OS.get_environment("GAME_API_URL")
	if not override_url.is_empty():
		_base_url = override_url
	_http = HTTPRequest.new()
	_http.timeout = REQUEST_TIMEOUT_SECONDS
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)


func wallet_coins() -> int:
	return _wallet_coins


# Test-only seam: GAME_API_URL is read once at _ready(), before an ephemeral
# test server's port is known. Production/device code should use the env var.
func set_base_url(url: String) -> void:
	_base_url = url


func has_session() -> bool:
	return not _access_token.is_empty()


func bootstrap_guest() -> void:
	if _busy:
		request_failed.emit("bootstrap_guest", "request_in_flight")
		return
	_start("bootstrap_guest", "POST", "/v1/dev/sessions",
		{ "device_id": _device_id() }, false)


func fetch_problems() -> void:
	if _busy:
		request_failed.emit("fetch_problems", "request_in_flight")
		return
	_start("fetch_problems", "GET", "/v1/problems", null, true)


func fetch_problem(slug: String) -> void:
	if _busy:
		request_failed.emit("fetch_problem", "request_in_flight")
		return
	_start("fetch_problem", "GET", "/v1/problems/%s" % slug.uri_encode(), null, true)


func run_public_tests(problem_slug: String, source_code: String) -> void:
	if _busy:
		request_failed.emit("run_public_tests", "request_in_flight")
		return
	var body := {
		"problem_slug": problem_slug,
		"language": "python",
		"source_code": source_code,
		"idempotency_key": Crypto.new().generate_random_bytes(16).hex_encode(),
	}
	_start("run_public_tests", "POST", "/v1/runs", body, true)


func submit_code(problem_slug: String, source_code: String, idempotency_key: String) -> void:
	if _busy:
		request_failed.emit("submit_code", "request_in_flight")
		return
	if idempotency_key.is_empty():
		request_failed.emit("submit_code", "missing_idempotency_key")
		return
	var body := {
		"problem_slug": problem_slug,
		"language": "python",
		"source_code": source_code,
		"idempotency_key": idempotency_key,
	}
	_start("submit_code", "POST", "/v1/submissions", body, true)


# -----------------------------------------------------------------------------
# Transport
# -----------------------------------------------------------------------------
func _start(operation: String, method: String, path: String, body, requires_auth: bool) -> void:
	if requires_auth and _access_token.is_empty():
		request_failed.emit(operation, "not_authenticated")
		return
	var headers := PackedStringArray(["Content-Type: application/json"])
	if requires_auth:
		headers.append("Authorization: Bearer %s" % _access_token)
	var method_const := HTTPClient.METHOD_GET if method == "GET" else HTTPClient.METHOD_POST
	var body_str := "" if body == null else JSON.stringify(body)
	_busy = true
	_current_operation = operation
	var err := _http.request(_base_url + path, headers, method_const, body_str)
	if err != OK:
		_busy = false
		_current_operation = ""
		request_failed.emit(operation, "request_error_%d" % err)


func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var operation := _current_operation
	_busy = false
	_current_operation = ""
	if operation.is_empty():
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		request_failed.emit(operation, "transport_error")
		return
	if code == 202:
		request_failed.emit(operation, "running")
		return
	if code == 429:
		request_failed.emit(operation, "rate_limited")
		return
	if code == 503:
		request_failed.emit(operation, "retryable")
		return
	if code < 200 or code >= 300:
		request_failed.emit(operation, "http_%d" % code)
		return

	var parsed = JSON.parse_string(body.get_string_from_utf8())
	match operation:
		"bootstrap_guest":
			_finish_session(operation, parsed)
		"fetch_problems":
			_finish_problem_list(operation, parsed)
		"fetch_problem":
			_finish_problem(operation, parsed)
		"run_public_tests":
			_finish_run(operation, parsed)
		"submit_code":
			_finish_submission(operation, parsed)


func _finish_session(operation: String, parsed) -> void:
	var normalized := ApiResponse.parse_session(parsed)
	if not normalized["ok"]:
		request_failed.emit(operation, normalized["error"])
		return
	_access_token = normalized["value"]["access_token"]
	session_ready.emit(normalized["value"]["user"])


func _finish_problem_list(operation: String, parsed) -> void:
	var normalized := ApiResponse.parse_problem_list(parsed)
	if not normalized["ok"]:
		request_failed.emit(operation, normalized["error"])
		return
	problems_loaded.emit(normalized["value"])


func _finish_problem(operation: String, parsed) -> void:
	var normalized := ApiResponse.parse_problem(parsed)
	if not normalized["ok"]:
		request_failed.emit(operation, normalized["error"])
		return
	problem_loaded.emit(normalized["value"])


func _finish_run(operation: String, parsed) -> void:
	var normalized := ApiResponse.parse_submission(parsed)
	if not normalized["ok"]:
		request_failed.emit(operation, normalized["error"])
		return
	public_run_completed.emit(normalized["value"])


func _finish_submission(operation: String, parsed) -> void:
	var normalized := ApiResponse.parse_submission(parsed)
	if not normalized["ok"]:
		request_failed.emit(operation, normalized["error"])
		return
	if normalized["value"].has("wallet"):
		_wallet_coins = int(normalized["value"]["wallet"]["coins"])
	submission_completed.emit(normalized["value"])


# -----------------------------------------------------------------------------
# Local device identity — an opaque per-install id, NOT a secret. Reused so
# repeated launches resume the same server-side guest account. Atomic
# tmp->rename write per project convention (scripts/autoload/*).
# -----------------------------------------------------------------------------
func _device_id() -> String:
	if FileAccess.file_exists(DEVICE_ID_PATH):
		var existing := FileAccess.get_file_as_string(DEVICE_ID_PATH).strip_edges()
		if not existing.is_empty():
			return existing
	var generated := Crypto.new().generate_random_bytes(16).hex_encode()
	_save_device_id(generated)
	return generated


func _save_device_id(value: String) -> void:
	var f := FileAccess.open(DEVICE_ID_PATH_TMP, FileAccess.WRITE)
	if f == null:
		push_error("GameApi: failed to open %s for write (err=%d)" % [DEVICE_ID_PATH_TMP, FileAccess.get_open_error()])
		return
	f.store_string(value)
	f.close()
	var dir := DirAccess.open("user://")
	if dir == null:
		push_error("GameApi: cannot open user:// for rename")
		return
	if FileAccess.file_exists(DEVICE_ID_PATH):
		dir.remove(DEVICE_ID_PATH)
	var rename_err := dir.rename(DEVICE_ID_PATH_TMP, DEVICE_ID_PATH)
	if rename_err != OK:
		push_error("GameApi: device id rename failed (err=%d)" % rename_err)
