# GameApi contract test — drives real HTTP round-trips between the GameApi
# autoload's real HTTPRequest client and a minimal hand-rolled HTTP server
# (raw TCPServer/StreamPeerTCP) standing in for study_game_server. No mocking
# inside GameApi itself: every assertion here observes real request bytes
# sent and real response bytes parsed.
#
# Run via:
#   godot --headless --path . --script res://tests/game_api_contract.gd

extends SceneTree

# The bare autoload identifier (e.g. `GameApi.foo()`) only resolves for
# scripts compiled as part of normal scene instancing. A `--script` main
# loop is compiled before that global-constant registration applies, so
# this test reaches the same singleton node via the tree instead.
var _api: Node
var _progress_store: Node

var _server := TCPServer.new()
var _failures := 0
var _passes := 0

var _log_session: Array = []
var _log_problems: Array = []
var _log_problem: Array = []
var _log_run: Array = []
var _log_submission: Array = []
var _log_failed: Array = []


func _initialize() -> void:
	print("--- game_api_contract ---")
	_api = root.get_node("GameApi")
	_progress_store = root.get_node("ProgressStore")
	await process_frame  # let autoload _ready() run before driving it
	var listen_err := _server.listen(0, "127.0.0.1")
	if listen_err != OK:
		push_error("cannot start fake server (err=%d)" % listen_err)
		quit(1)
		return
	_api.set_base_url("http://127.0.0.1:%d" % _server.get_local_port())

	_api.session_ready.connect(func(user): _log_session.append(user))
	_api.problems_loaded.connect(func(problems): _log_problems.append(problems))
	_api.problem_loaded.connect(func(problem): _log_problem.append(problem))
	_api.public_run_completed.connect(func(result): _log_run.append(result))
	_api.submission_completed.connect(func(result): _log_submission.append(result))
	_api.request_failed.connect(func(op, code): _log_failed.append([op, code]))

	await _run()
	print("--- %d passed, %d failed ---" % [_passes, _failures])
	quit(0 if _failures == 0 else 1)


func _run() -> void:
	var token := await _test_session_and_auth_header()
	await _test_problem_strips_private_fields()
	await _test_public_run_never_touches_wallet()
	await _test_submit_grants_reward_and_updates_wallet()
	await _test_duplicate_request_while_busy()
	await _test_malformed_json()
	await _test_non_2xx()
	await _test_running_202()
	await _test_rate_limited_429()
	await _test_retryable_503()
	await _test_transport_failure()
	_test_token_never_persisted(token)


# -----------------------------------------------------------------------------
# 1-2-7: guest bootstrap, Authorization header propagation, memory-only token
# -----------------------------------------------------------------------------
func _test_session_and_auth_header() -> String:
	_section("session + auth header")
	var before := _log_session.size()
	_api.bootstrap_guest()
	var req := await _serve_once(201, JSON.stringify({
		"access_token": "test-token-abc123",
		"token_type": "bearer",
		"user": {"id": "u-1", "display_name": "Guest"},
	}))
	await _wait_len(_log_session, before + 1)
	_truthy(_log_session.size() == before + 1, "session_ready fired once")
	_eq(req.get("method", ""), "POST", "bootstrap: POST 사용")
	_eq(req.get("path", ""), "/v1/dev/sessions", "bootstrap: 경로")

	var before_problems := _log_problems.size()
	_api.fetch_problems()
	var auth_req := await _serve_once(200, "[]")
	await _wait_len(_log_problems, before_problems + 1)
	var auth_header: String = (auth_req.get("headers", {}) as Dictionary).get("authorization", "")
	_eq(auth_header, "Bearer test-token-abc123", "인증된 요청은 Authorization: Bearer <token> 전송")
	_eq(_api._access_token, "test-token-abc123", "토큰은 GameApi 메모리에만 보관")
	return "test-token-abc123"


# -----------------------------------------------------------------------------
# 3: problem payloads pass through ApiResponse — unknown/private keys stripped
# -----------------------------------------------------------------------------
func _test_problem_strips_private_fields() -> void:
	_section("problem passthrough strips private fields")
	var before := _log_problem.size()
	_api.fetch_problem("frequency-kits")
	await _serve_once(200, JSON.stringify({
		"slug": "frequency-kits", "title": "문자 키트 만들기", "stage": "practice",
		"concepts": ["hash-map"], "language": "python",
		"statement": "설명", "input_format": "입력", "output_format": "출력",
		"examples": [{"input": "abc\n", "output": "1\n"}],
		"starter_code": "pass\n",
		"hidden_tests": [{"input": "secret\n", "output": "42\n"}],
		"reference_solution": "print(42)\n",
	}))
	await _wait_len(_log_problem, before + 1)
	var problem: Dictionary = _log_problem[-1]
	_truthy(not problem.has("hidden_tests"), "hidden_tests 필드는 통과하지 않음")
	_truthy(not problem.has("reference_solution"), "reference_solution 필드는 통과하지 않음")
	_eq(problem.get("slug", ""), "frequency-kits", "허용 필드는 정상 전달")


# -----------------------------------------------------------------------------
# 4: public runs never grant reward or change wallet
# -----------------------------------------------------------------------------
func _test_public_run_never_touches_wallet() -> void:
	_section("public run never touches wallet")
	var wallet_before = _api.wallet_coins()
	var before := _log_run.size()
	_api.run_public_tests("frequency-kits", "print(1)\n")
	var req := await _serve_once(200, JSON.stringify({
		"submission_id": "sub-run-1", "verdict": "accepted",
		"passed_count": 2, "total_count": 2, "runtime_ms": 12, "memory_kb": 4096,
	}))
	await _wait_len(_log_run, before + 1)
	_eq(req.get("path", ""), "/v1/runs", "공개 실행: /v1/runs 호출")
	_truthy((req.get("body", "") as String).find("\"idempotency_key\"") != -1, "공개 실행도 서버 계약상 idempotency_key 동봉")
	_truthy(not (_log_run[-1] as Dictionary).has("wallet"), "공개 실행 결과에 wallet 없음")
	_eq(_api.wallet_coins(), wallet_before, "공개 실행 후 지갑 변동 없음")


# -----------------------------------------------------------------------------
# Final submission: reward + wallet flow through and GameApi caches the balance
# -----------------------------------------------------------------------------
func _test_submit_grants_reward_and_updates_wallet() -> void:
	_section("submit grants reward and updates wallet")
	var before := _log_submission.size()
	_api.submit_code("frequency-kits", "print(1)\n", "key-1")
	var req := await _serve_once(200, JSON.stringify({
		"submission_id": "sub-final-1", "verdict": "accepted",
		"passed_count": 6, "total_count": 6, "runtime_ms": 40, "memory_kb": 8192,
		"reward": {"granted": true, "coins": 300}, "wallet": {"coins": 300},
	}))
	await _wait_len(_log_submission, before + 1)
	_eq(req.get("path", ""), "/v1/submissions", "최종 제출: /v1/submissions 호출")
	_eq((_log_submission[-1] as Dictionary)["wallet"]["coins"], 300, "제출 결과에 지갑 잔액 포함")
	_eq(_api.wallet_coins(), 300, "제출 후 GameApi.wallet_coins() 갱신")


# -----------------------------------------------------------------------------
# 5: a second call while one request is in flight fails fast, does not queue
# -----------------------------------------------------------------------------
func _test_duplicate_request_while_busy() -> void:
	_section("duplicate call while busy")
	var before_failed := _log_failed.size()
	var before_problems := _log_problems.size()
	_api.fetch_problems()
	_api.fetch_problem("frequency-kits")  # fired before the first resolves
	_truthy(_log_failed.size() == before_failed + 1, "두번째 호출은 즉시 request_failed")
	_eq(_log_failed[-1][1], "request_in_flight", "사유: request_in_flight")
	await _serve_once(200, "[]")
	await _wait_len(_log_problems, before_problems + 1)


# -----------------------------------------------------------------------------
# 6: malformed JSON, non-2xx, 202/429/503, transport failure
# -----------------------------------------------------------------------------
func _test_malformed_json() -> void:
	_section("malformed JSON")
	var before := _log_failed.size()
	_api.fetch_problem("frequency-kits")
	await _serve_once(200, "not-json{")
	await _wait_len(_log_failed, before + 1)
	_eq(_log_failed[-1][0], "fetch_problem", "malformed JSON: operation 보존")


func _test_non_2xx() -> void:
	_section("non-2xx")
	var before := _log_failed.size()
	_api.fetch_problem("missing-slug")
	await _serve_once(404, JSON.stringify({"detail": "problem_not_found"}))
	await _wait_len(_log_failed, before + 1)
	_eq(_log_failed[-1][1], "http_404", "404 -> http_404")


func _test_running_202() -> void:
	_section("202 running")
	var before := _log_failed.size()
	_api.submit_code("frequency-kits", "print(1)\n", "key-pending")
	await _serve_once(202, JSON.stringify({"submission_id": "sub-pending"}))
	await _wait_len(_log_failed, before + 1)
	_eq(_log_failed[-1][1], "running", "202 -> running")


func _test_rate_limited_429() -> void:
	_section("429 rate limited")
	var before := _log_failed.size()
	_api.submit_code("frequency-kits", "print(1)\n", "key-limited")
	await _serve_once(429, JSON.stringify({"detail": "submission_rate_limited"}))
	await _wait_len(_log_failed, before + 1)
	_eq(_log_failed[-1][1], "rate_limited", "429 -> rate_limited")


func _test_retryable_503() -> void:
	_section("503 retryable")
	var before := _log_failed.size()
	_api.submit_code("frequency-kits", "print(1)\n", "key-outage")
	await _serve_once(503, JSON.stringify({"submission_id": "sub-outage"}))
	await _wait_len(_log_failed, before + 1)
	_eq(_log_failed[-1][1], "retryable", "503 -> retryable")


# A connection accepted then dropped with no response stands in for any
# client-side transport failure (refused, unreachable, timeout) — all
# collapse to the same HTTPRequest.RESULT_SUCCESS != result branch in
# GameApi. (A truly closed port was tried first but Windows Defender
# Firewall can silently drop the SYN instead of fast-failing with RST,
# making that variant flaky/slow — this is deterministic and fast.)
func _test_transport_failure() -> void:
	_section("transport failure (connection dropped mid-request)")
	var before := _log_failed.size()
	_api.fetch_problems()
	var peer := await _accept_connection()
	if peer != null:
		await _read_http_request(peer)
		peer.disconnect_from_host()
	await _wait_len(_log_failed, before + 1, 5.0)
	_eq(_log_failed[-1][1], "transport_error", "연결 종료 -> transport_error")


# -----------------------------------------------------------------------------
# 7: token never reaches ProgressStore / progress.json
# -----------------------------------------------------------------------------
func _test_token_never_persisted(token: String) -> void:
	_section("token stays out of saved progress")
	_truthy(not JSON.stringify(_progress_store.progress).contains(token), "ProgressStore 메모리에 토큰 없음")
	if FileAccess.file_exists("user://progress.json"):
		_truthy(not FileAccess.get_file_as_string("user://progress.json").contains(token), "progress.json에 토큰 없음")
	else:
		_pass("progress.json 미존재 — 토큰 유출 불가")


# -----------------------------------------------------------------------------
# Minimal raw HTTP/1.1 server over TCPServer/StreamPeerTCP
# -----------------------------------------------------------------------------
func _serve_once(status: int, body: String) -> Dictionary:
	var peer := await _accept_connection()
	if peer == null:
		_fail("fake server", "no connection accepted within timeout")
		return {}
	var req := await _read_http_request(peer)
	await _send_response(peer, status, body)
	return req


func _accept_connection() -> StreamPeerTCP:
	var frames := 0
	while not _server.is_connection_available():
		await process_frame
		frames += 1
		if frames > 600:
			return null
	return _server.take_connection()


func _read_http_request(peer: StreamPeerTCP) -> Dictionary:
	var raw := PackedByteArray()
	var header_end := -1
	var frames := 0
	while true:
		peer.poll()
		var avail := peer.get_available_bytes()
		if avail > 0:
			var chunk: Array = peer.get_partial_data(avail)
			if chunk[0] == OK:
				raw.append_array(chunk[1])
		header_end = _find_crlfcrlf(raw)
		if header_end != -1:
			var needed := header_end + 4 + _content_length(raw, header_end)
			if raw.size() >= needed:
				break
		await process_frame
		frames += 1
		if frames > 600:
			break
	return _parse_http_request(raw, maxi(header_end, 0))


func _find_crlfcrlf(raw: PackedByteArray) -> int:
	var last := raw.size() - 4
	for i in range(0, last + 1):
		if raw[i] == 13 and raw[i + 1] == 10 and raw[i + 2] == 13 and raw[i + 3] == 10:
			return i
	return -1


func _content_length(raw: PackedByteArray, header_end: int) -> int:
	var header_text := raw.slice(0, header_end).get_string_from_utf8()
	for line in header_text.split("\r\n"):
		if line.to_lower().begins_with("content-length:"):
			return int(line.substr(line.find(":") + 1).strip_edges())
	return 0


func _parse_http_request(raw: PackedByteArray, header_end: int) -> Dictionary:
	var header_text := raw.slice(0, header_end).get_string_from_utf8()
	var lines := header_text.split("\r\n")
	if lines.is_empty():
		return {}
	var request_line := lines[0].split(" ")
	var headers := {}
	for i in range(1, lines.size()):
		var sep := lines[i].find(":")
		if sep == -1:
			continue
		headers[lines[i].substr(0, sep).to_lower().strip_edges()] = lines[i].substr(sep + 1).strip_edges()
	var body := raw.slice(header_end + 4).get_string_from_utf8()
	return {
		"method": request_line[0] if request_line.size() > 0 else "",
		"path": request_line[1] if request_line.size() > 1 else "",
		"headers": headers,
		"body": body,
	}


func _send_response(peer: StreamPeerTCP, status: int, body: String) -> void:
	var body_bytes := body.to_utf8_buffer()
	var head := "HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [
		status, _reason_phrase(status), body_bytes.size(),
	]
	peer.put_data(head.to_utf8_buffer())
	if body_bytes.size() > 0:
		peer.put_data(body_bytes)
	await process_frame
	peer.disconnect_from_host()


func _reason_phrase(status: int) -> String:
	match status:
		200: return "OK"
		201: return "Created"
		202: return "Accepted"
		404: return "Not Found"
		422: return "Unprocessable Entity"
		429: return "Too Many Requests"
		503: return "Service Unavailable"
		_: return "OK"


# -----------------------------------------------------------------------------
# Test harness
# -----------------------------------------------------------------------------
func _wait_len(arr: Array, target_len: int, timeout_sec: float = 5.0) -> bool:
	var frames := 0
	var max_frames := int(timeout_sec * 60.0) + 60
	while arr.size() < target_len and frames < max_frames:
		await process_frame
		frames += 1
	return arr.size() >= target_len


func _section(name: String) -> void:
	print("\n[%s]" % name)


func _eq(actual, expected, label: String) -> void:
	if typeof(actual) == typeof(expected) and actual == expected:
		_pass(label)
	else:
		_fail(label, "expected %s, got %s" % [str(expected), str(actual)])


func _truthy(condition: bool, label: String) -> void:
	if condition:
		_pass(label)
	else:
		_fail(label, "expected truthy")


func _pass(label: String) -> void:
	_passes += 1
	print("  ✓ %s" % label)


func _fail(label: String, reason: String) -> void:
	_failures += 1
	push_error("  ✗ %s — %s" % [label, reason])
