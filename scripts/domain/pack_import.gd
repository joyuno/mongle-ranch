# 유저 제작/임포트 퀴즈팩 파이프라인 (순수 도메인 — Node/Scene 참조 없음).
#
# 모바일에서 res://는 읽기전용이라 유저가 만든/가져온 팩은 반드시 쓰기 가능한
# user://quizzes/ 에 둔다. 붙여넣기(JSON)·URL(JSON/YAML) 입력을 정규화 →
# 기존 PackParser 검증 게이트 통과 → 정규 JSON으로 atomic 저장(tmp→rename).
# 저장은 입력 포맷과 무관하게 항상 .json (로드 시 PackParser가 .json 경로로 처리).
class_name PackImport
extends RefCounted

const USER_DIR := "user://quizzes"


static func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(USER_DIR):
		DirAccess.make_dir_recursive_absolute(USER_DIR)


# 챗봇 출력의 흔한 오염 제거: 코드펜스·앞뒤 산문 제거, 스마트따옴표/NBSP 정규화,
# 후행 콤마 제거. JSON '객체' 가정(첫 '{' ~ 마지막 '}'). 모바일 복붙의 곡선 따옴표는
# JSON에서 하드 신택스 에러라 반드시 직선 따옴표로 치환해야 한다.
static func normalize_json(text: String) -> String:
	var s := text
	s = s.replace("“", "\"").replace("”", "\"")  # “ ” → "
	s = s.replace("‘", "'").replace("’", "'")     # ‘ ’ → '
	s = s.replace(" ", " ")                             # NBSP → space
	var first := s.find("{")
	var last := s.rfind("}")
	if first >= 0 and last > first:
		s = s.substr(first, last - first + 1)
	var re := RegEx.new()
	re.compile(",\\s*([}\\]])")  # 후행 콤마: ,] / ,} → ] / }
	s = re.sub(s, "$1", true)
	return s.strip_edges()


# 제목 → 파일시스템 안전한 ASCII slug (한글 등 비ASCII는 표시용 meta.title이 담당).
static func slugify(title: String) -> String:
	var re := RegEx.new()
	re.compile("[^a-z0-9]+")
	var slug := re.sub(title.to_lower(), "-", true)
	slug = slug.lstrip("-").rstrip("-")
	if slug.is_empty():
		slug = "pack"
	return slug.left(40)


# 붙여넣기(JSON 텍스트) 등록. 결과: { ok, path, title } 또는 { ok=false, code, message }.
static func import_text(text: String) -> Dictionary:
	var normalized := normalize_json(text)
	if normalized.is_empty():
		return { "ok": false, "code": "ERR_EMPTY", "message": "내용이 비어 있어요" }
	var parsed := PackParser.parse_string(normalized)
	if not parsed.get("ok", false):
		return parsed
	return _store(parsed["pack"])


# URL/파일 원문 + 확장자 힌트로 등록(YAML도 허용). 저장은 항상 정규 JSON.
static func import_raw(raw: String, ext_hint: String) -> Dictionary:
	var low := ext_hint.to_lower()
	var parsed: Dictionary
	if low.ends_with("yml") or low.ends_with("yaml"):
		parsed = PackParser.parse_yaml_string(raw)
	else:
		var normalized := normalize_json(raw)
		if normalized.is_empty():
			return { "ok": false, "code": "ERR_EMPTY", "message": "내용이 비어 있어요" }
		parsed = PackParser.parse_string(normalized)
	if not parsed.get("ok", false):
		return parsed
	return _store(parsed["pack"])


static func _store(pack: Dictionary) -> Dictionary:
	_ensure_dir()
	var title := String((pack.get("meta", {}) as Dictionary).get("title", "pack"))
	var base := slugify(title)
	var path := "%s/%s.json" % [USER_DIR, base]
	var n := 2
	while FileAccess.file_exists(path):
		path = "%s/%s-%d.json" % [USER_DIR, base, n]
		n += 1
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return { "ok": false, "code": "ERR_WRITE", "message": "저장 실패(쓰기 열기 err=%d)" % FileAccess.get_open_error() }
	f.store_string(JSON.stringify(pack, "  "))
	f.close()
	var dir := DirAccess.open("user://")
	if dir == null:
		return { "ok": false, "code": "ERR_WRITE", "message": "저장 실패(user:// 열기)" }
	var err := dir.rename(tmp, path)
	if err != OK:
		return { "ok": false, "code": "ERR_WRITE", "message": "저장 실패(rename err=%d)" % err }
	return { "ok": true, "path": path, "title": title }


# 유저 팩 경로 목록(.json/.yml/.yaml). 정렬된 user:// 절대경로.
static func list_user_packs() -> Array:
	_ensure_dir()
	var out: Array = []
	var dir := DirAccess.open(USER_DIR)
	if dir == null:
		return out
	for fname in dir.get_files():
		var low := fname.to_lower()
		if low.ends_with(".json") or low.ends_with(".yml") or low.ends_with(".yaml"):
			out.append("%s/%s" % [USER_DIR, fname])
	out.sort()
	return out


static func delete_user_pack(path: String) -> bool:
	if not path.begins_with(USER_DIR):
		return false  # 번들(res://) 팩은 삭제 불가
	if not FileAccess.file_exists(path):
		return false
	var dir := DirAccess.open("user://")
	if dir == null:
		return false
	return dir.remove(path) == OK


static func is_user_pack(path: String) -> bool:
	return path.begins_with("user://")


# 유저가 자기 챗봇(ChatGPT/Gemini/Claude)에 붙여넣을 프롬프트 — 우리 JSON 스키마 박제.
# 생성은 유저 자신의 LLM에서(앱 비용 0). truncation 방지를 위해 1회 분량을 제한 권장.
static func build_prompt(topic: String, count: int = 10) -> String:
	var t := topic.strip_edges()
	if t.is_empty():
		t = "<주제를 여기에 적어줘>"
	return "아래 스키마에 정확히 맞는 퀴즈 문제집 JSON을 만들어 줘.\n\n" \
		+ "주제: " + t + "\n" \
		+ "문항 수: " + str(count) + "개 (한 번에 많으면 잘릴 수 있으니 30개 이하 권장)\n\n" \
		+ "[규칙]\n" \
		+ "- 출력은 오직 raw JSON 하나. 코드펜스나 설명 문장, 앞뒤 텍스트 절대 금지.\n" \
		+ "- 따옴표는 ASCII 큰따옴표만 사용. 한글 따옴표나 전각문자 금지.\n" \
		+ "- 스키마:\n" \
		+ "  {\n" \
		+ "    \"meta\": { \"title\": \"제목(80자 이내)\", \"default_time\": 30, \"tags\": [\"태그\"] },\n" \
		+ "    \"questions\": [\n" \
		+ "      { \"type\": \"mcq\", \"q\": \"질문\", \"choices\": [\"보기1\",\"보기2\",\"보기3\",\"보기4\"], \"answer\": 0, \"explanation\": \"해설\" },\n" \
		+ "      { \"type\": \"ox\", \"q\": \"참/거짓 진술\", \"answer\": true, \"explanation\": \"해설\" }\n" \
		+ "    ]\n" \
		+ "  }\n" \
		+ "- mcq: choices 2~6개, answer는 정답 보기의 0-based 정수 인덱스.\n" \
		+ "- ox: answer는 boolean(true/false). \"true\" 문자열 금지.\n" \
		+ "- 각 질문 q는 2000자 이내, 한국어로."
