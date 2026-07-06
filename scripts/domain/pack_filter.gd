# 퀴즈 팩 카테고리 분류 + 검색 매칭. 순수 함수 — Node/Scene 참조 없음(테스트 가능).
class_name PackFilter
extends RefCounted

# 표시 순서 고정. 신규 카테고리는 여기에 추가.
const CATEGORIES: Array = [
	{ "key": "japanese", "name": "일본어" },
	{ "key": "semiconductor", "name": "반도체" },
	{ "key": "observability", "name": "관측성" },
	{ "key": "clickhouse", "name": "ClickHouse" },
	{ "key": "data-eng", "name": "데이터 엔지니어" },
	{ "key": "ai-eng", "name": "AI 엔지니어" },
	{ "key": "backend", "name": "백엔드" },
	{ "key": "linux", "name": "Linux" },
	{ "key": "logpresso", "name": "Logpresso" },
]


# 제목 + 태그를 소문자 한 문자열로 — 폴백 분류·검색 공용.
static func _hay(meta: Dictionary) -> String:
	var s := String(meta.get("title", ""))
	for t in meta.get("tags", []):
		s += " " + String(t)
	return s.to_lower()


# meta.category가 있으면 그것을, 없으면 키워드 버킷(유저 임포트 팩 폴백). "" = 미분류.
static func category_of(meta: Dictionary) -> String:
	var c := String(meta.get("category", "")).strip_edges()
	if not c.is_empty():
		return c
	var h := _hay(meta)
	if h.contains("jlpt") or h.contains("일본어") or h.contains("japanese"): return "japanese"
	if h.contains("semiconductor") or h.contains("반도체"): return "semiconductor"
	if h.contains("observability") or h.contains("otel") or h.contains("opentelemetry") or h.contains("apm") or h.contains("rum"): return "observability"
	if h.contains("clickhouse"): return "clickhouse"
	if h.contains("kafka"): return "data-eng"
	if h.contains("logpresso"): return "logpresso"
	if h.contains("linux"): return "linux"
	return ""


# category "" = 전체, query "" = 아무거나. 둘은 AND 결합.
static func matches(meta: Dictionary, category: String, query: String) -> bool:
	if not category.is_empty() and category_of(meta) != category:
		return false
	var q := query.strip_edges().to_lower()
	if q.is_empty():
		return true
	return _hay(meta).contains(q)
