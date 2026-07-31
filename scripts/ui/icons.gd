# Lucide(ISC) SVG 아이콘을 TextureRect로 만드는 헬퍼. 이모지 대체.
class_name Icons
extends RefCounted

# 의미 이름 → Lucide 파일명 (SVG가 없으면 make()가 빈 TextureRect 반환 → 라벨과 병기)
const MAP: Dictionary = {
	# 재화·아이템 (기존)
	"luck_charm": "clover",
	"xp_boost": "zap",
	"combo_insure": "flame",
	"scroll": "scroll-text",
	"gold": "coins",
	"shards": "gem",
	"ticket": "ticket",
	"trophy": "trophy",
	"sword": "sword",
	"lock": "lock",
	# 네비게이션·화면
	"home": "house",
	"quiz": "book-open",
	"coding": "lightbulb",
	"gacha": "dices",
	"collection": "library",
	"market": "store",
	"wrong_note": "notebook-pen",
	"settings": "settings",
	# 액션·재화·연출
	"snack": "cookie",
	"study": "timer",
	"sparkle": "sparkles",
	"streak": "flame",
	"coin": "coins",
	"back": "arrow-left",
	"correct": "circle-check",
	"wrong": "x",
	"retry": "refresh-cw",
	"buy": "shopping-bag",
	"sell": "hand-coins",
	"merge": "refresh-cw",
	"delete": "trash-2",
	"star": "star",
}

static func make(semantic: String, color: Color, size: int = 20) -> TextureRect:
	var t := TextureRect.new()
	var file: String = MAP.get(semantic, semantic)
	var path := "res://assets/icons/%s.svg" % file
	if ResourceLoader.exists(path):
		t.texture = load(path)
	t.custom_minimum_size = Vector2(size, size)
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.modulate = color
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


# 버튼에 Lucide 아이콘을 달고 텍스트(이모지 제거판)를 설정한다. SVG 부재 시
# 아이콘만 비어 라벨로 식별된다. 버튼의 시그널/로직은 호출부가 그대로 유지.
static func decorate_button(btn: Button, semantic: String, text: String) -> void:
	var file: String = MAP.get(semantic, semantic)
	var path := "res://assets/icons/%s.svg" % file
	if ResourceLoader.exists(path):
		btn.icon = load(path)
		btn.add_theme_constant_override("h_separation", 6)
		btn.expand_icon = false
	if not text.is_empty():
		btn.text = text


# 아이콘 + 라벨을 가로로 묶은 HBox. SVG 부재 시에도 라벨이 식별을 보장한다.
# 라벨 폰트색은 테마(C_TEXT)를 따르고, 아이콘만 color로 틴트한다.
static func labeled(semantic: String, text: String, color: Color, size: int = 20) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(make(semantic, color, size))
	# 라벨은 항상 자식[1]로 둔다(빈 문자열이어도). 호출부가 get_child(1)로
	# 동적 값을 갱신할 수 있게 보장한다.
	var lbl := Label.new()
	lbl.text = text
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(lbl)
	return box
