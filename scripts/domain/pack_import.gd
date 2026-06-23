# 유저 제작/임포트 퀴즈팩 파이프라인 (순수 도메인 — Node/Scene 참조 없음).
#
# 모바일에서 res://는 읽기전용이라 유저가 만든/가져온 팩은 반드시 쓰기 가능한
# user://quizzes/ 에 둔다. 붙여넣기(JSON)·URL(JSON/YAML) 입력을 정규화 →
# 기존 PackParser 검증 게이트 통과 → 정규 JSON으로 atomic 저장(tmp→rename).
# 저장은 입력 포맷과 무관하게 항상 .json (로드 시 PackParser가 .json 경로로 처리).
class_name PackImport
extends RefCounted

const USER_DIR := "user://quizzes"
const BUNDLED_DIR := "res://data/quizzes"


static func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(USER_DIR):
		DirAccess.make_dir_recursive_absolute(USER_DIR)


# 소스 파일명 → 저장 파일명(.json 고정, ASCII slug). 멱등: jlpt-n2-vocab-5.json → 동일.
# 중복 판정·저장 모두 이 정규화 이름을 쓴다.
static func storage_name(source_name: String) -> String:
	var base := source_name.get_file()
	var dot := base.rfind(".")
	if dot > 0:
		base = base.substr(0, dot)
	return slugify(base) + ".json"


# URL/경로의 마지막 경로 세그먼트(파일명). 쿼리스트링 제거.
static func basename_of(url: String) -> String:
	var u := url.split("?")[0]
	return u.get_file()


# 이미 등록된(번들 res:// + 유저 user://) 팩 파일명 집합(정규화). 중복 판정용.
static func existing_basenames() -> Dictionary:
	var seen := {}
	for d in [BUNDLED_DIR, USER_DIR]:
		var dir := DirAccess.open(d)
		if dir == null:
			continue
		for fname in dir.get_files():
			var low := fname.to_lower()
			if low.ends_with(".json") or low.ends_with(".yml") or low.ends_with(".yaml"):
				seen[storage_name(fname)] = true
	return seen


static func is_duplicate_name(source_name: String) -> bool:
	return existing_basenames().has(storage_name(source_name))


# github.com 페이지/폴더 URL → GitHub Contents API URL(무인증 공개)로 변환.
# 폴더면 파일 배열, 단일 파일이면 객체를 돌려준다(download_url 포함). 토큰 불필요.
# 이미 raw URL(raw.githubusercontent.com)이거나 깃허브가 아니면 "" 반환 → 직접 GET.
static func github_contents_api(url: String) -> String:
	var u := url.strip_edges()
	if u.contains("raw.githubusercontent.com"):
		return ""  # 이미 raw 단일 파일 — 직접 받는다
	if u.begins_with("https://api.github.com/"):
		return u
	var g := _parse_github(u)
	if g.is_empty():
		return ""
	var api := "https://api.github.com/repos/%s/%s/contents" % [g["owner"], g["repo"]]
	if not String(g["path"]).is_empty():
		api += "/" + String(g["path"])
	if not String(g["branch"]).is_empty():
		api += "?ref=" + String(g["branch"])
	return api


# github.com/{owner}/{repo}[/tree|blob/{branch}/{path...}] → { owner, repo, branch, path }.
static func _parse_github(url: String) -> Dictionary:
	var marker := "github.com/"
	var i := url.find(marker)
	if i < 0:
		return {}
	var rest := url.substr(i + marker.length()).split("?")[0].trim_suffix("/")
	var parts := rest.split("/")
	if parts.size() < 2:
		return {}
	var owner := parts[0]
	var repo := parts[1].trim_suffix(".git")
	var branch := ""
	var path := ""
	if parts.size() >= 4 and (parts[2] == "tree" or parts[2] == "blob"):
		branch = parts[3]
		path = "/".join(parts.slice(4))
	return { "owner": owner, "repo": repo, "branch": branch, "path": path }


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


# URL/파일 원문 + 소스 파일명으로 등록(YAML도 허용). 저장은 항상 정규 JSON.
# source_name이 있으면 그 파일명으로 저장(중복 판정 기준)하고, 이미 있으면 스킵한다.
static func import_raw(raw: String, source_name: String = "") -> Dictionary:
	if not source_name.is_empty() and is_duplicate_name(source_name):
		return { "ok": false, "code": "DUP", "message": "이미 등록된 파일명", "skipped": true }
	var low := source_name.to_lower()
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
	var fname := storage_name(source_name) if not source_name.is_empty() else ""
	return _store(parsed["pack"], fname)


static func _store(pack: Dictionary, filename: String = "") -> Dictionary:
	_ensure_dir()
	var title := String((pack.get("meta", {}) as Dictionary).get("title", "pack"))
	var base := filename.trim_suffix(".json") if not filename.is_empty() else slugify(title)
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
