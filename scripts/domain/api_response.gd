# Strict normalizer for study_game_server API payloads. The server is a
# separate, independently-evolving process — every value it sends is
# untrusted input from the UI's point of view. No raw server dictionary
# is ever handed to UI code; only the allowlisted fields below survive.
#
# Every function returns either:
#   { "ok": true,  "value": <normalized Variant> }
#   { "ok": false, "error": <stable snake_case code> }

class_name ApiResponse
extends RefCounted

const VERDICTS := [
	"accepted", "wrong_answer", "compile_error", "runtime_error",
	"time_limit", "memory_limit", "output_limit", "internal_error",
]
const STAGES := ["learn", "practice", "interview", "challenge"]
const MAX_TEXT := 20000
const MAX_STARTER_CODE := 32768


static func parse_session(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _err("root_not_dict")
	var d: Dictionary = value
	var token = d.get("access_token", null)
	if typeof(token) != TYPE_STRING or (token as String).is_empty():
		return _err("missing_access_token")
	var user = d.get("user", null)
	if typeof(user) != TYPE_DICTIONARY:
		return _err("missing_user")
	var user_id = (user as Dictionary).get("id", null)
	if typeof(user_id) != TYPE_STRING or (user_id as String).is_empty():
		return _err("missing_user_id")
	var display_name = (user as Dictionary).get("display_name", null)
	if typeof(display_name) != TYPE_STRING:
		return _err("missing_display_name")
	return _ok({
		"access_token": token,
		"user": { "id": user_id, "display_name": display_name },
	})


static func parse_problem_list(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return _err("root_not_array")
	var out: Array[Dictionary] = []
	for item in (value as Array):
		if typeof(item) != TYPE_DICTIONARY:
			return _err("item_not_dict")
		var parsed := _normalize_problem(item)
		if not parsed.get("ok", false):
			return parsed
		out.append(parsed["value"])
	return _ok(out)


static func parse_problem(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _err("root_not_dict")
	return _normalize_problem(value)


static func parse_submission(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _err("root_not_dict")
	var d: Dictionary = value
	var submission_id = d.get("submission_id", null)
	if typeof(submission_id) != TYPE_STRING or (submission_id as String).is_empty():
		return _err("missing_submission_id")
	var verdict = d.get("verdict", null)
	if typeof(verdict) != TYPE_STRING or not VERDICTS.has(verdict):
		return _err("unknown_verdict")
	var passed_count = _as_int(d.get("passed_count", null))
	if passed_count == null or passed_count < 0:
		return _err("invalid_passed_count")
	var total_count = _as_int(d.get("total_count", null))
	if total_count == null or total_count < 0:
		return _err("invalid_total_count")
	var runtime_ms = _as_int(d.get("runtime_ms", null))
	if runtime_ms == null or runtime_ms < 0:
		return _err("invalid_runtime_ms")
	var memory_kb = _as_int(d.get("memory_kb", null))
	if memory_kb == null or memory_kb < 0:
		return _err("invalid_memory_kb")

	var out := {
		"submission_id": submission_id,
		"verdict": verdict,
		"passed_count": passed_count,
		"total_count": total_count,
		"runtime_ms": runtime_ms,
		"memory_kb": memory_kb,
	}

	if d.has("reward"):
		var reward = d.get("reward")
		if typeof(reward) != TYPE_DICTIONARY:
			return _err("invalid_reward")
		var granted = (reward as Dictionary).get("granted", null)
		if typeof(granted) != TYPE_BOOL:
			return _err("invalid_reward_granted")
		var coins = _as_int((reward as Dictionary).get("coins", null))
		if coins == null or coins < 0:
			return _err("invalid_reward_coins")
		out["reward"] = { "granted": granted, "coins": coins }

	if d.has("wallet"):
		var wallet = d.get("wallet")
		if typeof(wallet) != TYPE_DICTIONARY:
			return _err("invalid_wallet")
		var wallet_coins = _as_int((wallet as Dictionary).get("coins", null))
		if wallet_coins == null or wallet_coins < 0:
			return _err("invalid_wallet_coins")
		out["wallet"] = { "coins": wallet_coins }

	return _ok(out)


static func _normalize_problem(d: Dictionary) -> Dictionary:
	var slug = d.get("slug", null)
	if typeof(slug) != TYPE_STRING or (slug as String).is_empty():
		return _err("missing_slug")
	var title = d.get("title", null)
	if typeof(title) != TYPE_STRING or (title as String).is_empty() or (title as String).length() > MAX_TEXT:
		return _err("missing_title")
	var stage = d.get("stage", null)
	if typeof(stage) != TYPE_STRING or not STAGES.has(stage):
		return _err("unknown_stage")
	var concepts = d.get("concepts", null)
	if typeof(concepts) != TYPE_ARRAY:
		return _err("missing_concepts")
	var normalized_concepts: Array[String] = []
	for c in (concepts as Array):
		if typeof(c) != TYPE_STRING:
			return _err("invalid_concept")
		normalized_concepts.append(c)
	var language = d.get("language", null)
	if language != "python":
		return _err("unsupported_language")
	var statement = d.get("statement", null)
	if typeof(statement) != TYPE_STRING or (statement as String).is_empty() or (statement as String).length() > MAX_TEXT:
		return _err("missing_statement")
	var input_format = d.get("input_format", null)
	if typeof(input_format) != TYPE_STRING or (input_format as String).length() > MAX_TEXT:
		return _err("missing_input_format")
	var output_format = d.get("output_format", null)
	if typeof(output_format) != TYPE_STRING or (output_format as String).length() > MAX_TEXT:
		return _err("missing_output_format")
	var examples = d.get("examples", null)
	if typeof(examples) != TYPE_ARRAY:
		return _err("missing_examples")
	var normalized_examples: Array[Dictionary] = []
	for ex in (examples as Array):
		if typeof(ex) != TYPE_DICTIONARY:
			return _err("invalid_example")
		var ex_input = (ex as Dictionary).get("input", null)
		var ex_output = (ex as Dictionary).get("output", null)
		if typeof(ex_input) != TYPE_STRING or typeof(ex_output) != TYPE_STRING:
			return _err("invalid_example")
		normalized_examples.append({ "input": ex_input, "output": ex_output })
	var starter_code = d.get("starter_code", null)
	if typeof(starter_code) != TYPE_STRING:
		return _err("missing_starter_code")
	if (starter_code as String).length() > MAX_STARTER_CODE:
		return _err("starter_code_too_large")

	return _ok({
		"slug": slug,
		"title": title,
		"stage": stage,
		"concepts": normalized_concepts,
		"language": language,
		"statement": statement,
		"input_format": input_format,
		"output_format": output_format,
		"examples": normalized_examples,
		"starter_code": starter_code,
	})


# Returns the int value of a JSON number (JSON decodes whole numbers as
# TYPE_FLOAT), or null (typed Variant) if `value` is not a number.
static func _as_int(value: Variant) -> Variant:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return null
	return int(value)


static func _ok(value: Variant) -> Dictionary:
	return { "ok": true, "value": value }


static func _err(error: String) -> Dictionary:
	return { "ok": false, "error": error }
