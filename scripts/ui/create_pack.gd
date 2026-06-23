# 문제집 만들기/가져오기 화면 — 생성(내 챗봇용 프롬프트 복사) · 등록(붙여넣기) ·
# 가져오기(URL) · 내 문제집 관리(삭제). 앱은 LLM을 직접 호출하지 않는다(비용 0):
# 생성은 유저 자신의 ChatGPT/Gemini/Claude에서 하고, 결과 JSON을 붙여넣거나 URL로
# 가져온다. 모든 입력은 PackImport(정규화 → PackParser 검증 → user://quizzes 저장)로 일원화.
extends Control

const QUIZ_SCENE := "res://scenes/Quiz.tscn"

var topic_edit: LineEdit
var paste_edit: TextEdit
var url_edit: LineEdit
var status_label: Label
var user_list_box: VBoxContainer
var _http: HTTPRequest
var _http_mode: String = ""        # "listing"(폴더 목록) | "file"(팩 본문)
var _url_queue: Array = []         # [{ name, url }] — 폴더 내 파일 큐
var _seen_names: Dictionary = {}   # 중복 판정 집합(정규화 파일명)
var _current_name: String = ""
var _imported: int = 0
var _skipped: int = 0
var _failed: int = 0


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 12.0
	add_child(_http)
	_http.request_completed.connect(_on_http_completed)
	_build_ui()
	_refresh_user_list()


# -----------------------------------------------------------------------------
# UI
# -----------------------------------------------------------------------------
func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	# ─ 상단 바
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	root.add_child(bar)
	var back := Button.new()
	Icons.decorate_button(back, "back", "퀴즈")
	back.pressed.connect(func() -> void: Sfx.play("click"); get_tree().change_scene_to_file(QUIZ_SCENE))
	_wire_button(back)
	bar.add_child(back)
	var title := Icons.labeled("quiz", "문제집 만들기 / 가져오기", ThemeSetup.C_TEXT, 24)
	(title.get_child(1) as Label).add_theme_font_size_override("font_size", 24)
	bar.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	status_label = Label.new()
	status_label.add_theme_color_override("font_color", ThemeSetup.C_WARN)
	bar.add_child(status_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	scroll.add_child(body)

	# ─ ① 내 챗봇으로 만들기 (프롬프트 복사)
	var gen := _make_section(body, "sparkle", "① 내 챗봇으로 만들기")
	var gen_note := Label.new()
	gen_note.text = "주제를 적고 프롬프트를 복사해 ChatGPT·Gemini·Claude에 붙여넣으세요.\n나온 JSON을 아래 ②에 다시 붙여넣으면 등록됩니다. (앱은 AI를 직접 쓰지 않아요)"
	gen_note.add_theme_color_override("font_color", ThemeSetup.C_MUTED)
	gen.add_child(gen_note)
	var gen_row := HBoxContainer.new()
	gen_row.add_theme_constant_override("separation", 8)
	gen.add_child(gen_row)
	topic_edit = LineEdit.new()
	topic_edit.placeholder_text = "주제 (예: JLPT N2 문법, 분산추적 기초)"
	topic_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gen_row.add_child(topic_edit)
	var copy_btn := Button.new()
	Icons.decorate_button(copy_btn, "scroll", "프롬프트 복사")
	copy_btn.pressed.connect(_on_copy_prompt)
	_wire_button(copy_btn)
	gen_row.add_child(copy_btn)

	# ─ ② 붙여넣어 등록
	var paste := _make_section(body, "scroll", "② 붙여넣어 등록")
	var paste_btn := Button.new()
	Icons.decorate_button(paste_btn, "retry", "클립보드에서 붙여넣기")
	paste_btn.pressed.connect(_on_paste_clipboard)
	_wire_button(paste_btn)
	paste.add_child(paste_btn)
	paste_edit = TextEdit.new()
	paste_edit.placeholder_text = "여기에 JSON 문제집을 붙여넣으세요"
	paste_edit.custom_minimum_size = Vector2(0, 150)
	paste_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	# TextEdit는 테마 기본이 어두워 코지 톤을 깨므로 크림 카드로 직접 스타일링.
	paste_edit.add_theme_stylebox_override("normal", ThemeSetup.card(ThemeSetup.C_PANEL, ThemeSetup.C_BORDER, 10, false))
	paste_edit.add_theme_stylebox_override("focus", ThemeSetup.card(ThemeSetup.C_PANEL, ThemeSetup.C_ACCENT, 10, false))
	paste_edit.add_theme_color_override("font_color", ThemeSetup.C_INK)
	paste_edit.add_theme_color_override("font_placeholder_color", ThemeSetup.C_MUTED)
	paste_edit.add_theme_color_override("caret_color", ThemeSetup.C_INK)
	paste.add_child(paste_edit)
	var register_btn := Button.new()
	Icons.decorate_button(register_btn, "correct", "등록하기")
	register_btn.pressed.connect(_on_register)
	_accent(register_btn)
	_wire_button(register_btn)
	paste.add_child(register_btn)

	# ─ ③ URL에서 가져오기
	var url_sec := _make_section(body, "collection", "③ URL에서 가져오기")
	var url_note := Label.new()
	url_note.text = "GitHub 폴더 URL을 넣으면 그 폴더의 모든 .json 팩을 한 번에 등록해요(중복 파일명은 자동 스킵). 단일 raw/blob 링크도 가능."
	url_note.add_theme_color_override("font_color", ThemeSetup.C_MUTED)
	url_sec.add_child(url_note)
	var url_row := HBoxContainer.new()
	url_row.add_theme_constant_override("separation", 8)
	url_sec.add_child(url_row)
	url_edit = LineEdit.new()
	url_edit.placeholder_text = "https://raw.githubusercontent.com/.../pack.json"
	url_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	url_row.add_child(url_edit)
	var import_btn := Button.new()
	Icons.decorate_button(import_btn, "correct", "가져오기")
	import_btn.pressed.connect(_on_import_url)
	_accent(import_btn)
	_wire_button(import_btn)
	url_row.add_child(import_btn)

	# ─ ④ 내 문제집 (삭제 관리)
	var mine := _make_section(body, "delete", "④ 내 문제집")
	user_list_box = VBoxContainer.new()
	user_list_box.add_theme_constant_override("separation", 6)
	mine.add_child(user_list_box)


func _make_section(parent: Control, icon: String, title: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	var card := ThemeSetup.card()
	card.content_margin_top = 6
	card.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", card)
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var t := Icons.labeled(icon, title, ThemeSetup.C_TEXT, 20)
	t.alignment = BoxContainer.ALIGNMENT_BEGIN
	(t.get_child(1) as Label).add_theme_font_size_override("font_size", 20)
	box.add_child(t)
	return box


# 1차 액션(등록·가져오기) — 코랄 강조 버튼.
func _accent(btn: Button) -> void:
	var ac := ThemeSetup.C_ACCENT
	btn.add_theme_stylebox_override("normal", ThemeSetup.card(ac, ac.darkened(0.14), 12, true))
	btn.add_theme_stylebox_override("hover", ThemeSetup.card(ac.lightened(0.06), ac.darkened(0.14), 12, true))
	btn.add_theme_stylebox_override("pressed", ThemeSetup.card(ac.darkened(0.08), ac.darkened(0.2), 12, false))
	btn.add_theme_color_override("font_color", ThemeSetup.C_INK)


func _wire_button(btn: Button) -> void:
	btn.mouse_entered.connect(Juice.hover.bind(btn, true))
	btn.mouse_exited.connect(Juice.hover.bind(btn, false))
	btn.pressed.connect(Juice.punch.bind(btn))


# -----------------------------------------------------------------------------
# 동작
# -----------------------------------------------------------------------------
func _on_copy_prompt() -> void:
	Sfx.play("click")
	DisplayServer.clipboard_set(PackImport.build_prompt(topic_edit.text))
	_status("프롬프트를 복사했어요 — 챗봇에 붙여넣고 답을 받아 ②에 다시 붙여넣으세요.", false)


func _on_paste_clipboard() -> void:
	Sfx.play("click")
	paste_edit.text = DisplayServer.clipboard_get()
	_status("붙여넣었어요. '등록하기'를 누르세요.", false)


func _on_register() -> void:
	var r := PackImport.import_text(paste_edit.text)
	if bool(r.get("ok", false)):
		Sfx.play("levelup")
		paste_edit.text = ""
		_status("'%s' 문제집을 등록했어요!" % String(r.get("title", "")), false)
		_refresh_user_list()
	else:
		Sfx.play("wrong")
		_status("등록 실패: %s" % String(r.get("message", r.get("code", "알 수 없는 오류"))), true)


# URL 입력: 깃허브 페이지/폴더면 Contents API로 폴더 내 모든 .json을 등록(중복 스킵),
# raw 단일 파일이면 그것만 등록. JSON 경로를 끝까지 안 쳐도 폴더 URL만으로 동작.
func _on_import_url() -> void:
	var url := url_edit.text.strip_edges()
	if not (url.begins_with("http://") or url.begins_with("https://")):
		_status("http(s):// 로 시작하는 URL을 입력하세요.", true)
		return
	_url_queue.clear()
	_seen_names = PackImport.existing_basenames()  # 번들+유저 기존 파일명(정규화)
	_imported = 0
	_skipped = 0
	_failed = 0
	var api := PackImport.github_contents_api(url)
	if api.is_empty():
		# raw 등 직접 단일 파일.
		_http_mode = "file"
		_current_name = PackImport.basename_of(url)
		if _http.request(url) != OK:
			_status("요청 실패", true)
			return
		_status("가져오는 중…", false)
	else:
		# 깃허브 폴더/파일 — Contents API(무인증)로 목록부터. User-Agent 필수.
		_http_mode = "listing"
		if _http.request(api, ["User-Agent: mongle-ranch", "Accept: application/vnd.github+json"]) != OK:
			_status("요청 실패", true)
			return
		_status("깃허브에서 목록을 읽는 중…", false)


func _on_http_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var ok_http := result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300
	if _http_mode == "listing":
		if not ok_http:
			_status("목록 가져오기 실패 (응답 %d) — 공개 저장소 URL인지 확인하세요." % code, true)
			return
		var parsed = JSON.parse_string(body.get_string_from_utf8())
		if typeof(parsed) == TYPE_ARRAY:
			for item in parsed:
				if typeof(item) != TYPE_DICTIONARY or String(item.get("type", "")) != "file":
					continue
				var low := String(item.get("name", "")).to_lower()
				if low.ends_with(".json") or low.ends_with(".yml") or low.ends_with(".yaml"):
					_url_queue.append({ "name": String(item.get("name", "")), "url": String(item.get("download_url", "")) })
			if _url_queue.is_empty():
				_status("이 폴더에 .json/.yml 퀴즈팩이 없어요.", true)
				return
		elif typeof(parsed) == TYPE_DICTIONARY and parsed.has("download_url"):
			_url_queue.append({ "name": String(parsed.get("name", "pack.json")), "url": String(parsed["download_url"]) })
		else:
			_status("응답을 해석할 수 없어요.", true)
			return
		_http_mode = "file"
		_process_next()
		return
	# _http_mode == "file": body = 팩 본문. 결과 누적 후 다음 항목.
	if not ok_http:
		_failed += 1
	else:
		var r := PackImport.import_raw(body.get_string_from_utf8(), _current_name)
		if bool(r.get("ok", false)):
			_imported += 1
		elif bool(r.get("skipped", false)):
			_skipped += 1
		else:
			_failed += 1
	_process_next()


# 큐의 다음 파일을 중복(파일명) 스킵하며 처리. 비면 요약 표시.
func _process_next() -> void:
	while not _url_queue.is_empty():
		var item: Dictionary = _url_queue.pop_front()
		var key := PackImport.storage_name(String(item.get("name", "")))
		if _seen_names.has(key):
			_skipped += 1
			continue
		_seen_names[key] = true
		_current_name = String(item.get("name", ""))
		if _http.request(String(item.get("url", ""))) != OK:
			_failed += 1
			continue
		return  # 응답 대기
	if _imported > 0:
		Sfx.play("levelup")
	url_edit.text = ""
	_status("등록 %d · 중복 스킵 %d · 실패 %d" % [_imported, _skipped, _failed], _failed > 0)
	_refresh_user_list()


func _on_delete(path: String) -> void:
	if PackImport.delete_user_pack(path):
		Sfx.play("click")
		_status("삭제했어요.", false)
		_refresh_user_list()


func _refresh_user_list() -> void:
	for child in user_list_box.get_children():
		child.queue_free()
	var paths := PackImport.list_user_packs()
	if paths.is_empty():
		var empty := Label.new()
		empty.text = "아직 만든 문제집이 없어요. 위에서 등록해 보세요!"
		empty.add_theme_color_override("font_color", ThemeSetup.C_MUTED)
		user_list_box.add_child(empty)
		return
	for path: String in paths:
		var parsed := PackParser.parse_file(path)
		var pack_title := path.get_file()
		var count := 0
		if parsed.get("ok", false):
			var meta: Dictionary = parsed["pack"].get("meta", {})
			pack_title = String(meta.get("title", pack_title))
			count = (parsed["pack"].get("questions", []) as Array).size()
		else:
			pack_title = "%s (깨진 팩)" % pack_title
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var name_l := Label.new()
		name_l.text = "%s · %d문항" % [pack_title, count] if count > 0 else pack_title
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_l)
		var del := Button.new()
		Icons.decorate_button(del, "delete", "삭제")
		del.add_theme_color_override("font_color", ThemeSetup.C_DANGER)
		del.pressed.connect(_on_delete.bind(path))
		_wire_button(del)
		row.add_child(del)
		user_list_box.add_child(row)


func _status(msg: String, is_error: bool) -> void:
	status_label.text = msg
	status_label.add_theme_color_override("font_color",
		ThemeSetup.C_DANGER if is_error else ThemeSetup.C_ACCENT_2)
