# Quiz pack parser & validator. Accepts both .json (Godot-native) and .yml/.yaml
# (workbook plugin output — via the in-tree YAMLPackParser subset).
# Same ERR_* codes as the Electron version so the save/error UX matches.

class_name PackParser
extends RefCounted

const MAX_FILE_BYTES: int = 5_000_000  # 5 MB
const MAX_QUESTIONS: int = 1000        # per-pack question cap (docs/RISKS.md)
const MAX_Q_TEXT_CHARS: int = 2048     # per-question text cap


# Returns { "ok": true, "pack": Dictionary } on success
# or       { "ok": false, "code": String, "message": String, "line": int (optional) } on failure.
static func parse_file(path: String) -> Dictionary:
	var lower := path.to_lower()
	if not (lower.ends_with(".json") or lower.ends_with(".yml") or lower.ends_with(".yaml")):
		return _err("ERR_UNSUPPORTED_EXT", "지원 확장자: .json / .yml / .yaml")

	if not FileAccess.file_exists(path):
		return _err("ERR_FILE_NOT_FOUND", "파일이 없음: %s" % path)

	var size := FileAccess.get_size(path)
	if size > MAX_FILE_BYTES:
		return _err("ERR_FILE_TOO_LARGE", "파일이 5 MB 초과: %d bytes" % size)

	var src := FileAccess.get_file_as_string(path)
	if src.is_empty():
		return _err("ERR_EMPTY_FILE", "빈 파일")

	if lower.ends_with(".yml") or lower.ends_with(".yaml"):
		return parse_yaml_string(src)
	return parse_string(src)


static func parse_string(src: String) -> Dictionary:
	var parsed = JSON.parse_string(src)
	if parsed == null:
		return _err("ERR_JSON_PARSE", "JSON 파싱 실패 — 따옴표/괄호/콤마 확인")

	if typeof(parsed) != TYPE_DICTIONARY:
		return _err("ERR_ROOT_NOT_OBJECT", "최상위는 객체여야 합니다")

	var pack: Dictionary = parsed
	var validation := _validate_pack(pack)
	if not validation.is_empty():
		return validation

	return { "ok": true, "pack": pack }


static func parse_yaml_string(src: String) -> Dictionary:
	var raw := YAMLPackParser.parse(src)
	if not raw.get("ok", false):
		return raw  # already in ERR_YAML_* shape
	var pack: Dictionary = raw["pack"]
	var validation := _validate_pack(pack)
	if not validation.is_empty():
		return validation
	return { "ok": true, "pack": pack }


static func _validate_pack(pack: Dictionary) -> Dictionary:
	var meta = pack.get("meta", null)
	if typeof(meta) != TYPE_DICTIONARY:
		return _err("ERR_META_MISSING", "meta 객체가 없음")

	var title = meta.get("title", "")
	if typeof(title) != TYPE_STRING or title.is_empty():
		return _err("ERR_META_TITLE_MISSING", "meta.title이 비어있거나 문자열이 아님")
	if title.length() > 80:
		return _err("ERR_META_TITLE_TOO_LONG", "meta.title 80자 초과 (%d자)" % title.length())

	var questions = pack.get("questions", null)
	if typeof(questions) != TYPE_ARRAY:
		return _err("ERR_QUESTIONS_NOT_ARRAY", "questions가 배열이 아님")
	if (questions as Array).is_empty():
		return _err("ERR_NO_QUESTIONS", "questions가 비어있음")
	if (questions as Array).size() > MAX_QUESTIONS:
		return _err("ERR_TOO_MANY_QUESTIONS", "questions %d개 — 최대 %d개" % [(questions as Array).size(), MAX_QUESTIONS])

	for i in (questions as Array).size():
		var q = questions[i]
		var q_err := _validate_question(q, i)
		if not q_err.is_empty():
			return q_err

	return {}


static func _validate_question(q, idx: int) -> Dictionary:
	if typeof(q) != TYPE_DICTIONARY:
		return _err("ERR_QUESTION_NOT_OBJECT", "question[%d]가 객체가 아님" % idx)

	var qtype = q.get("type", "")
	if qtype != "mcq" and qtype != "ox":
		return _err("ERR_UNKNOWN_TYPE", "question[%d].type='%s' — mcq/ox만 허용" % [idx, qtype])

	var q_text = q.get("q", "")
	if typeof(q_text) != TYPE_STRING or q_text.is_empty():
		return _err("ERR_Q_MISSING", "question[%d].q가 비어있음" % idx)
	if (q_text as String).length() > MAX_Q_TEXT_CHARS:
		return _err("ERR_Q_TOO_LONG", "question[%d].q %d자 — 최대 %d자" % [idx, (q_text as String).length(), MAX_Q_TEXT_CHARS])

	match qtype:
		"mcq":
			var choices = q.get("choices", null)
			if typeof(choices) != TYPE_ARRAY:
				return _err("ERR_CHOICES_NOT_ARRAY", "question[%d].choices가 배열이 아님" % idx)
			var n_choices := (choices as Array).size()
			if n_choices < 2 or n_choices > 6:
				return _err("ERR_CHOICES_COUNT", "question[%d].choices는 2~6개 (현재 %d)" % [idx, n_choices])
			var answer = q.get("answer", -1)
			if typeof(answer) != TYPE_INT and typeof(answer) != TYPE_FLOAT:
				return _err("ERR_MCQ_ANSWER_NOT_INT", "question[%d].answer가 정수가 아님" % idx)
			var a_int := int(answer)
			if a_int < 0 or a_int >= n_choices:
				return _err("ERR_MCQ_ANSWER_OUT_OF_RANGE",
					"question[%d].answer=%d, choices=%d개" % [idx, a_int, n_choices])
		"ox":
			var answer = q.get("answer", null)
			if typeof(answer) != TYPE_BOOL:
				return _err("ERR_OX_ANSWER_NOT_BOOL",
					"question[%d].answer가 boolean이 아님 (\"true\" 문자열 금지)" % idx)

	return {}


static func _err(code: String, message: String) -> Dictionary:
	return { "ok": false, "code": code, "message": message }
