# 퀴즈 화면 — (A) 팩 선택 → (B) 사다리 세션 (더블 오어 나씽, docs/GAME_DESIGN.md §2).
# 세션 로직은 전부 PackStore(autoload)에 있고, 이 화면은 시그널 구독 + 렌더링만 한다.
# 오답노트에서 PackStore.load_review_session() 후 진입한 복습 모드는 팩 선택을
# 건너뛰고 바로 세션 UI를 보여준다 (사다리/상금 UI 숨김, 진행 카운터만).

extends Control

const RANCH_SCENE := "res://scenes/Ranch.tscn"
const WRONG_NOTE_SCENE := "res://scenes/WrongNote.tscn"
const CREATE_PACK_SCENE := "res://scenes/CreatePack.tscn"
const QUIZ_DIR := "res://data/quizzes"
const COLUMN_MARGIN_X := 240
const COLUMN_MARGIN_Y := 24

# 팩 카드 좌측 컬러바 — 저채도 더스티 톤(성인 파스텔). 팩 id 해시로 안정 선택.
const STRIPE_PALETTE: Array[Color] = [
	Color(0.85, 0.66, 0.66),  # 더스티 코랄
	Color(0.66, 0.78, 0.71),  # 세이지 민트
	Color(0.74, 0.71, 0.83),  # 더스티 라벤더
	Color(0.86, 0.78, 0.62),  # 머스터드 베이지
	Color(0.66, 0.74, 0.82),  # 더스티 블루
]

# ─ (A) 팩 선택
var pack_root: VBoxContainer
var pack_list_box: VBoxContainer
var pack_status_label: Label

# ─ (B) 사다리 세션
var session_root: VBoxContainer
var session_title_label: Label
var ladder_bar: HBoxContainer
var ladder_cells: Array[PanelContainer] = []
var ladder_labels: Array[Label] = []
var review_progress_label: Label
var timer_bar: ProgressBar
var passage_panel: PanelContainer
var passage_label: RichTextLabel   # 드래그 복사 가능(RichTextLabel + selection_enabled)
var question_label: RichTextLabel
var choices_box: VBoxContainer
var glossary_box: VBoxContainer

# 구조 시각화(figure 필드) — 제로베이스 학습 지원, 토글 on/off.
var figure_panel: PanelContainer
var figure_view: FigureView
var figure_toggle: CheckButton
var figure_caption: Label
var _current_figure: String = ""

var feedback_panel: PanelContainer
var feedback_title: Label
var feedback_explanation: RichTextLabel
var feedback_answer: RichTextLabel
var feedback_bonus_box: VBoxContainer
var cash_out_btn: Button
var advance_btn: Button

var result_panel: PanelContainer
var result_title: Label
var result_lines_box: VBoxContainer
var retry_btn: Button
var to_wrong_note_btn: Button

var _timeout_fired := false
var _choice_press_pos: Vector2 = Vector2.ZERO
var _choice_pressed: bool = false

# 팩 목록 카테고리 필터 + 검색. 파싱 캐시로 키입력마다 재파싱하지 않는다.
var _pack_cache: Array = []  # [{path, pack}]
var _active_category: String = ""
var _search_query: String = ""
var _chip_row: HBoxContainer
var _search_edit: LineEdit


func _ready() -> void:
	_build_pack_select()
	_build_session_ui()
	PackStore.pack_loaded.connect(_on_pack_loaded)
	PackStore.question_changed.connect(_on_question_changed)
	PackStore.feedback.connect(_on_feedback)
	PackStore.ladder_changed.connect(_on_ladder_changed)
	PackStore.session_completed.connect(_on_session_completed)
	if PackStore.is_review_mode and PackStore.phase == "IN_QUESTION":
		# 복습 세션은 씬 전환 전에 이미 시작됨 — 시그널은 지나갔으므로 직접 렌더.
		_enter_session()
		_render_question(PackStore.current_question())
	else:
		_show_pack_select()


func _process(_delta: float) -> void:
	if session_root == null or not session_root.visible:
		return
	if PackStore.phase != "IN_QUESTION" or not ProgressStore.is_timer_enabled():
		return
	var limit := PackStore.question_time_limit()
	var remain := PackStore.time_remaining_for_question()
	timer_bar.max_value = maxf(0.001, limit)
	timer_bar.value = remain
	if remain <= 0.0 and not _timeout_fired:
		_timeout_fired = true  # quiet하게 1회만 — 자동 오답 처리
		PackStore.submit_answer(-1)


func _unhandled_input(event: InputEvent) -> void:
	if session_root == null or not session_root.visible:
		return
	if event.is_action_pressed("ui_skip"):
		if PackStore.phase == "FEEDBACK":
			PackStore.advance()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and PackStore.phase == "IN_QUESTION":
		var key := int((event as InputEventKey).keycode)
		if key < KEY_1 or key > KEY_6:
			return
		var idx := key - int(KEY_1)
		var q := PackStore.current_question()
		match String(q.get("type", "")):
			"mcq":
				var choices: Array = q.get("choices", [])
				if idx < choices.size():
					PackStore.submit_answer(idx)
					get_viewport().set_input_as_handled()
			"ox":
				if idx == 0:
					PackStore.submit_answer(true)
					get_viewport().set_input_as_handled()
				elif idx == 1:
					PackStore.submit_answer(false)
					get_viewport().set_input_as_handled()


# ─────────────────────────────────────────────────────────────────────────────
# (A) 팩 선택
# ─────────────────────────────────────────────────────────────────────────────
func _build_pack_select() -> void:
	pack_root = VBoxContainer.new()
	pack_root.add_theme_constant_override("separation", 12)
	add_child(pack_root)
	_anchor_column(pack_root, COLUMN_MARGIN_X, COLUMN_MARGIN_Y)

	var header := HBoxContainer.new()
	var back := Button.new()
	Icons.decorate_button(back, "back", "목장")
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(func(): Sfx.play("click"); get_tree().change_scene_to_file(RANCH_SCENE))
	_wire_button(back)
	header.add_child(back)
	var title := Icons.labeled("quiz", "퀴즈 사다리 — 팩 선택", ThemeSetup.C_TEXT, 24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.alignment = BoxContainer.ALIGNMENT_CENTER
	(title.get_child(1) as Label).add_theme_font_size_override("font_size", 24)
	header.add_child(title)
	var spacer := Control.new()
	spacer.custom_minimum_size.x = 80
	header.add_child(spacer)
	pack_root.add_child(header)

	var hint := Label.new()
	hint.text = "세션당 %d문제 · 문제당 %d초 · 정답마다 상금 2배 (%s → %s코인) · 정답 후 멈추면 확정" % [
		Ladder.SESSION_SIZE, int(Ladder.QUESTION_TIME),
		_fmt(Ladder.PRIZES[0]), _fmt(Ladder.PRIZES[Ladder.SESSION_SIZE - 1]),
	]
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", ThemeSetup.C_MUTED)
	pack_root.add_child(hint)

	# ─ 카테고리 칩 + 검색 필터 바 (hint와 목록 사이)
	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = "🔍 검색: 제목·태그…"
	_search_edit.clear_button_enabled = true
	_search_edit.text_changed.connect(func(t: String) -> void:
		_search_query = t
		_apply_filter())
	pack_root.add_child(_search_edit)
	var chip_scroll := ScrollContainer.new()
	chip_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	chip_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	chip_scroll.custom_minimum_size.y = 44
	_chip_row = HBoxContainer.new()
	_chip_row.add_theme_constant_override("separation", 6)
	chip_scroll.add_child(_chip_row)
	pack_root.add_child(chip_scroll)

	pack_status_label = Label.new()
	pack_status_label.visible = false
	pack_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pack_status_label.add_theme_color_override("font_color", ThemeSetup.C_DANGER)
	pack_root.add_child(pack_status_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pack_root.add_child(scroll)
	# 우측 마진으로 카드 내용이 세로 스크롤바에 가리지 않게.
	var list_margin := MarginContainer.new()
	list_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_margin.add_theme_constant_override("margin_right", 24)
	scroll.add_child(list_margin)
	pack_list_box = VBoxContainer.new()
	pack_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pack_list_box.add_theme_constant_override("separation", 8)
	list_margin.add_child(pack_list_box)


func _populate_pack_list() -> void:
	_rebuild_pack_cache()
	_rebuild_chips()
	_apply_filter()


# 팩 파싱은 화면 진입 시 1회 — 이후 필터/검색은 캐시에서(키입력마다 재파싱 방지).
func _rebuild_pack_cache() -> void:
	_pack_cache.clear()
	# 유저 제작/임포트(user://) 팩을 먼저, 그다음 번들(res://) 팩.
	# (모바일은 res://가 읽기전용이라 유저 팩은 user://quizzes 에서 온다.)
	var paths: Array[String] = []
	for up in PackImport.list_user_packs():
		paths.append(up)
	var dir := DirAccess.open(QUIZ_DIR)
	if dir != null:
		var names: Array[String] = []
		for f in dir.get_files():
			if f.to_lower().ends_with(".json"):
				names.append(f)
		names.sort()
		for f in names:
			paths.append("%s/%s" % [QUIZ_DIR, f])
	for path in paths:
		var parsed := PackParser.parse_file(path)
		if not parsed.get("ok", false):
			continue  # 깨진 팩은 목록에서 제외 (파서가 검증 책임)
		_pack_cache.append({"path": path, "pack": parsed["pack"]})


# 비어있지 않은 카테고리만 칩으로(카운트 포함). "전체" 칩이 맨 앞.
func _rebuild_chips() -> void:
	for c in _chip_row.get_children():
		c.queue_free()
	var counts: Dictionary = {}
	for e in _pack_cache:
		var k := PackFilter.category_of(e.pack.get("meta", {}))
		counts[k] = int(counts.get(k, 0)) + 1
	_add_chip("전체", "", _pack_cache.size())
	for cat in PackFilter.CATEGORIES:
		var n := int(counts.get(cat.key, 0))
		if n > 0:
			_add_chip(String(cat.name), String(cat.key), n)


func _add_chip(label: String, key: String, n: int) -> void:
	var b := Button.new()
	b.text = "%s %d" % [label, n]
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.button_pressed = (_active_category == key)
	b.set_meta("cat", key)
	b.pressed.connect(func() -> void:
		Sfx.play("click")
		_active_category = key
		_sync_chip_pressed()
		_apply_filter())
	_chip_row.add_child(b)


func _sync_chip_pressed() -> void:
	for c in _chip_row.get_children():
		if c is Button:
			(c as Button).button_pressed = (String((c as Button).get_meta("cat", "")) == _active_category)


# 캐시에서 활성 카테고리 + 검색어에 맞는 팩만 목록에 그린다.
func _apply_filter() -> void:
	_clear_children(pack_list_box)
	pack_status_label.visible = false
	pack_list_box.add_child(_make_create_entry())  # 항상 최상단 만들기/가져오기
	if _pack_cache.is_empty():
		_show_pack_status("아직 퀴즈팩이 없어요. 위 '문제집 만들기'로 추가해 보세요!")
		return
	var shown := 0
	for e in _pack_cache:
		if PackFilter.matches(e.pack.get("meta", {}), _active_category, _search_query):
			pack_list_box.add_child(_make_pack_card(e.path, e.pack))
			shown += 1
	if shown == 0:
		_show_pack_status("조건에 맞는 팩이 없어요.")


# 목록 최상단 진입 버튼 — 코랄 톤으로 1차 동선을 명확히.
func _make_create_entry() -> Button:
	var btn := Button.new()
	Icons.decorate_button(btn, "sparkle", "➕ 내 문제집 만들기 / 가져오기")
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size.y = 56
	btn.add_theme_stylebox_override("normal",
		ThemeSetup.card(ThemeSetup.C_ACCENT_SOFT, ThemeSetup.C_ACCENT, 14, false))
	btn.add_theme_color_override("font_color", ThemeSetup.C_INK)
	btn.pressed.connect(func() -> void: Sfx.play("click"); get_tree().change_scene_to_file(CREATE_PACK_SCENE))
	_wire_button(btn)
	return btn


# 팩 카드 1장 — 번들/유저 공통. 좌측 컬러바 · 과목 아이콘 · 제목/문항수 · (유저면)배지 · 이어하기.
func _make_pack_card(path: String, pack: Dictionary) -> Button:
	var f := path.get_file()
	var meta: Dictionary = pack.get("meta", {})
	var count: int = (pack.get("questions", []) as Array).size()
	var cursor := _saved_cursor(path)
	var card := Button.new()
	card.text = ""
	card.focus_mode = Control.FOCUS_NONE
	card.custom_minimum_size.y = 64
	card.pressed.connect(_on_pack_pressed.bind(path))
	_wire_button(card)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 10
	row.offset_right = -14
	row.offset_top = 8
	row.offset_bottom = -8
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)

	# 팩 id(파일명) 해시 → 고정 더스티 팔레트로 결정론적 컬러바(같은 팩=항상 같은 색).
	var bar_color: Color = STRIPE_PALETTE[absi(f.hash()) % STRIPE_PALETTE.size()]
	var color_bar := Panel.new()
	color_bar.custom_minimum_size = Vector2(4, 0)
	color_bar.size_flags_vertical = Control.SIZE_FILL
	color_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar_sb := StyleBoxFlat.new()
	bar_sb.bg_color = bar_color
	bar_sb.set_corner_radius_all(2)
	color_bar.add_theme_stylebox_override("panel", bar_sb)
	row.add_child(color_bar)

	# 과목별 아이콘 — 제목+태그 키워드로 결정. 컬러바와 동일 결정론 색으로 틴트.
	var icon_name := _subject_icon(String(meta.get("title", f)), meta.get("tags", []))
	var icon := Icons.make(icon_name, bar_color, 24)
	row.add_child(icon)

	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_col.add_theme_constant_override("separation", 2)
	text_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title_l := Label.new()
	title_l.text = String(meta.get("title", f))
	title_l.add_theme_font_size_override("font_size", 17)
	title_l.add_theme_color_override("font_color", ThemeSetup.C_TEXT)
	title_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_col.add_child(title_l)
	var count_l := Label.new()
	count_l.text = "%d문항" % count
	count_l.add_theme_font_size_override("font_size", 14)
	count_l.add_theme_color_override("font_color", ThemeSetup.C_MUTED)
	count_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_col.add_child(count_l)
	row.add_child(text_col)

	# 유저가 만든/가져온 팩은 '내 것' 배지로 표시.
	if PackImport.is_user_pack(path):
		var mine_pill := PanelContainer.new()
		mine_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mine_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mine_pill.add_theme_stylebox_override("panel",
			ThemeSetup.card(ThemeSetup.C_ACCENT_2, ThemeSetup.C_ACCENT_2.darkened(0.18), 10, false))
		var mine_l := Label.new()
		mine_l.text = "내 것"
		mine_l.add_theme_font_size_override("font_size", 13)
		mine_l.add_theme_color_override("font_color", ThemeSetup.C_INK)
		mine_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mine_pill.add_child(mine_l)
		row.add_child(mine_pill)

	# 이어하기 가능한 팩은 코랄 알약 배지로 강조(터치 사용자 식별). cursor==0이면 미표시.
	if cursor > 0:
		var resume_pill := PanelContainer.new()
		resume_pill.size_flags_horizontal = Control.SIZE_SHRINK_END
		resume_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		resume_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		resume_pill.add_theme_stylebox_override("panel",
			ThemeSetup.card(ThemeSetup.C_ACCENT_SOFT, ThemeSetup.C_ACCENT, 12, false))
		var resume_l := Label.new()
		resume_l.text = "▶ 이어하기 %d번째" % (cursor + 1)
		resume_l.add_theme_font_size_override("font_size", 14)
		resume_l.add_theme_color_override("font_color", ThemeSetup.C_INK)
		resume_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		resume_pill.add_child(resume_l)
		row.add_child(resume_pill)

	return card


# 저장된 이어하기 커서 (0이면 처음부터).
func _saved_cursor(path: String) -> int:
	return int(ProgressStore.get_quiz_session(path).get("cursor", 0))


# 팩 제목+태그 키워드로 과목 아이콘 선택 (스캔성). assets/icons/ 실존 파일만 사용.
# 매칭 없으면 book-open 폴백. 키워드 우선순위는 검사 순서로 결정.
func _subject_icon(title: String, tags: Array) -> String:
	var hay := title.to_lower()
	for t in tags:
		hay += " " + String(t).to_lower()
	if hay.contains("jlpt") or hay.contains("일본어") or hay.contains("문법") \
			or hay.contains("단어") or hay.contains("language") or hay.contains("japanese"):
		return "scroll-text"
	if hay.contains("clickhouse") or hay.contains("database") or hay.contains("데이터베이스") \
			or hay.contains("db"):
		return "library"
	if hay.contains("apm") or hay.contains("otel") or hay.contains("observability") \
			or hay.contains("rum") or hay.contains("telemetry") or hay.contains("관측") \
			or hay.contains("추적"):
		return "zap"
	return "book-open"


func _on_pack_pressed(path: String) -> void:
	Sfx.play("click")
	var result := PackStore.load_pack_from_path(path)
	if not result.get("ok", false):
		_show_pack_status("팩을 열 수 없어요 — %s" % String(result.get("message", "")))


func _show_pack_status(msg: String) -> void:
	pack_status_label.text = msg
	pack_status_label.visible = true


# ─────────────────────────────────────────────────────────────────────────────
# (B) 사다리 세션 UI 빌드
# ─────────────────────────────────────────────────────────────────────────────
func _build_session_ui() -> void:
	session_root = VBoxContainer.new()
	session_root.add_theme_constant_override("separation", 12)
	session_root.visible = false
	add_child(session_root)
	_anchor_column(session_root, COLUMN_MARGIN_X, COLUMN_MARGIN_Y)

	session_title_label = Label.new()
	session_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	session_title_label.add_theme_color_override("font_color", ThemeSetup.C_MUTED)
	session_root.add_child(session_title_label)

	# 사다리 진행 표시 — 5칸 (200 / 400 / 800 / 1,600 / 3,200)
	ladder_bar = HBoxContainer.new()
	ladder_bar.add_theme_constant_override("separation", 8)
	for i in Ladder.SESSION_SIZE:
		var cell := PanelContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var lbl := Label.new()
		lbl.text = _fmt(Ladder.PRIZES[i])
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(lbl)
		ladder_bar.add_child(cell)
		ladder_cells.append(cell)
		ladder_labels.append(lbl)
	session_root.add_child(ladder_bar)
	_on_ladder_changed(0, 0, Ladder.prize_for(1))

	# 복습 모드 진행 카운터 (사다리 대신 표시)
	review_progress_label = Label.new()
	review_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	review_progress_label.add_theme_font_size_override("font_size", 18)
	review_progress_label.visible = false
	session_root.add_child(review_progress_label)

	timer_bar = ProgressBar.new()
	timer_bar.show_percentage = false
	timer_bar.custom_minimum_size.y = 14
	session_root.add_child(timer_bar)

	# 지문 (있을 때만)
	passage_panel = PanelContainer.new()
	passage_panel.visible = false
	var passage_scroll := ScrollContainer.new()
	passage_scroll.custom_minimum_size.y = 140
	passage_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	passage_label = _selectable_text(17, ThemeSetup.C_TEXT)
	passage_scroll.add_child(passage_label)
	passage_panel.add_child(passage_scroll)
	session_root.add_child(passage_panel)

	question_label = _selectable_text(22, ThemeSetup.C_TEXT)
	session_root.add_child(question_label)

	_build_figure_panel()  # 질문 아래 구조 시각화 + 토글

	# 용어 카드 — 질문 아래, 보기 위. 문항의 glossary 필드로 채움(없으면 숨김).
	glossary_box = VBoxContainer.new()
	glossary_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	glossary_box.add_theme_constant_override("separation", 6)
	glossary_box.visible = false
	session_root.add_child(glossary_box)

	choices_box = VBoxContainer.new()
	choices_box.add_theme_constant_override("separation", 8)
	session_root.add_child(choices_box)

	_build_feedback_panel()
	_build_result_panel()


# 드래그로 선택·복사 가능한 읽기전용 텍스트(RichTextLabel, bbcode off — 프로젝트 규칙).
func _selectable_text(font_size: int, color: Color) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = false
	r.selection_enabled = true       # 마우스 드래그 선택
	r.context_menu_enabled = true    # 우클릭 복사 메뉴
	r.shortcut_keys_enabled = true   # Ctrl+C 복사
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_theme_font_size_override("normal_font_size", font_size)
	r.add_theme_color_override("default_color", color)
	return r


# 구조 시각화 패널 — 질문 아래. figure 필드가 있으면 단위격자 등을 그리고 토글로 on/off.
func _build_figure_panel() -> void:
	figure_panel = PanelContainer.new()
	figure_panel.visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	figure_panel.add_child(box)
	var header := HBoxContainer.new()
	var title := Icons.labeled("eye", "구조 그림 (제로베이스 도움)", ThemeSetup.C_TEXT, 16)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	figure_toggle = CheckButton.new()
	figure_toggle.text = "보기"
	figure_toggle.button_pressed = ProgressStore.is_figures_enabled()
	figure_toggle.toggled.connect(_on_figure_toggled)
	header.add_child(figure_toggle)
	box.add_child(header)
	figure_view = FigureView.new()
	figure_view.custom_minimum_size = Vector2(0, 240)
	box.add_child(figure_view)
	figure_caption = Label.new()
	figure_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	figure_caption.add_theme_color_override("font_color", ThemeSetup.C_MUTED)
	box.add_child(figure_caption)
	session_root.add_child(figure_panel)


func _update_figure() -> void:
	var has := not _current_figure.is_empty() and FigureView.is_supported(_current_figure)
	figure_panel.visible = has  # figure 있으면 패널(토글 포함) 노출
	var show := has and ProgressStore.is_figures_enabled()
	figure_view.visible = show
	figure_caption.visible = show
	if show:
		figure_view.set_figure(_current_figure)
		figure_caption.text = FigureView.caption_for(_current_figure)


func _on_figure_toggled(pressed: bool) -> void:
	Sfx.play("click")
	ProgressStore.set_figures_enabled(pressed)
	_update_figure()


func _build_feedback_panel() -> void:
	feedback_panel = PanelContainer.new()
	feedback_panel.visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	feedback_panel.add_child(box)

	feedback_title = Label.new()
	feedback_title.add_theme_font_size_override("font_size", 20)
	box.add_child(feedback_title)

	feedback_answer = _selectable_text(16, ThemeSetup.C_OK)
	feedback_answer.visible = false
	box.add_child(feedback_answer)

	feedback_explanation = _selectable_text(16, ThemeSetup.C_MUTED)
	box.add_child(feedback_explanation)

	feedback_bonus_box = VBoxContainer.new()
	box.add_child(feedback_bonus_box)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	cash_out_btn = Button.new()
	cash_out_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cash_out_btn.custom_minimum_size.y = 44
	cash_out_btn.focus_mode = Control.FOCUS_NONE
	cash_out_btn.pressed.connect(func(): Sfx.play("coin"); PackStore.cash_out())
	_wire_button(cash_out_btn)
	buttons.add_child(cash_out_btn)
	advance_btn = Button.new()
	advance_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	advance_btn.custom_minimum_size.y = 44
	advance_btn.focus_mode = Control.FOCUS_NONE
	advance_btn.pressed.connect(func(): Sfx.play("click"); PackStore.advance())
	_wire_button(advance_btn)
	buttons.add_child(advance_btn)
	box.add_child(buttons)

	session_root.add_child(feedback_panel)


func _build_result_panel() -> void:
	result_panel = PanelContainer.new()
	result_panel.visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	result_panel.add_child(box)

	result_title = Label.new()
	result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_title.add_theme_font_size_override("font_size", 22)
	box.add_child(result_title)

	result_lines_box = VBoxContainer.new()
	box.add_child(result_lines_box)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	retry_btn = Button.new()
	Icons.decorate_button(retry_btn, "retry", "다시 도전")
	retry_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	retry_btn.custom_minimum_size.y = 44
	retry_btn.focus_mode = Control.FOCUS_NONE
	retry_btn.pressed.connect(_on_retry_pressed)
	_wire_button(retry_btn)
	buttons.add_child(retry_btn)
	to_wrong_note_btn = Button.new()
	Icons.decorate_button(to_wrong_note_btn, "wrong_note", "오답노트로")
	to_wrong_note_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	to_wrong_note_btn.custom_minimum_size.y = 44
	to_wrong_note_btn.focus_mode = Control.FOCUS_NONE
	to_wrong_note_btn.pressed.connect(func(): Sfx.play("click"); get_tree().change_scene_to_file(WRONG_NOTE_SCENE))
	_wire_button(to_wrong_note_btn)
	buttons.add_child(to_wrong_note_btn)
	var ranch_btn := Button.new()
	Icons.decorate_button(ranch_btn, "home", "목장으로")
	ranch_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ranch_btn.custom_minimum_size.y = 44
	ranch_btn.focus_mode = Control.FOCUS_NONE
	ranch_btn.pressed.connect(func(): Sfx.play("click"); get_tree().change_scene_to_file(RANCH_SCENE))
	_wire_button(ranch_btn)
	buttons.add_child(ranch_btn)
	box.add_child(buttons)

	session_root.add_child(result_panel)


# ─────────────────────────────────────────────────────────────────────────────
# 화면 전환 / 렌더링
# ─────────────────────────────────────────────────────────────────────────────
func _show_pack_select() -> void:
	session_root.visible = false
	pack_root.visible = true
	_populate_pack_list()


func _enter_session() -> void:
	pack_root.visible = false
	session_root.visible = true
	feedback_panel.visible = false
	result_panel.visible = false
	var is_review := PackStore.is_review_mode
	ladder_bar.visible = not is_review  # 복습 모드: 사다리/상금 UI 숨김
	review_progress_label.visible = is_review
	session_title_label.text = String(PackStore.pack.get("meta", {}).get("title", ""))


func _render_question(q: Dictionary) -> void:
	_timeout_fired = false
	feedback_panel.visible = false
	result_panel.visible = false

	var passage := String(q.get("passage", ""))
	passage_panel.visible = not passage.is_empty()
	passage_label.text = passage

	question_label.text = String(q.get("q", ""))
	_current_figure = String(q.get("figure", ""))
	_update_figure()
	_render_glossary(q.get("glossary", []))

	_clear_children(choices_box)
	match String(q.get("type", "")):
		"mcq":
			var choices: Array = q.get("choices", [])
			for i in choices.size():
				choices_box.add_child(_make_choice(i, String(choices[i])))
		"ox":
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 12)
			var o_btn := Button.new()
			Icons.decorate_button(o_btn, "correct", "O (맞다)")
			o_btn.add_theme_font_size_override("font_size", 28)
			o_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			o_btn.custom_minimum_size.y = 90
			o_btn.focus_mode = Control.FOCUS_NONE
			o_btn.pressed.connect(_submit.bind(true))
			_wire_button(o_btn)
			row.add_child(o_btn)
			var x_btn := Button.new()
			Icons.decorate_button(x_btn, "wrong", "X (아니다)")
			x_btn.add_theme_font_size_override("font_size", 28)
			x_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			x_btn.custom_minimum_size.y = 90
			x_btn.focus_mode = Control.FOCUS_NONE
			x_btn.pressed.connect(_submit.bind(false))
			_wire_button(x_btn)
			row.add_child(x_btn)
			choices_box.add_child(row)

	if PackStore.is_review_mode:
		var total := PackStore.review_hashes.size()
		var idx := total - PackStore.session_questions_left + 1
		review_progress_label.text = "복습 %d / %d" % [clampi(idx, 1, maxi(1, total)), total]

	var timed := ProgressStore.is_timer_enabled()
	timer_bar.visible = timed
	if timed:
		timer_bar.max_value = maxf(0.001, PackStore.question_time_limit())
		timer_bar.value = timer_bar.max_value


func _submit(answer) -> void:
	if PackStore.phase != "IN_QUESTION":
		return
	PackStore.submit_answer(answer)


# 보기 카드 — 탭하면 정답 선택, 드래그하면 텍스트 선택(복사). RichTextLabel selection.
func _make_choice(idx: int, text: String) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", ThemeSetup.card(ThemeSetup.C_PANEL, ThemeSetup.C_BORDER, 12, false))
	panel.custom_minimum_size.y = 44
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 16)
	pad.add_theme_constant_override("margin_right", 16)
	pad.add_theme_constant_override("margin_top", 9)
	pad.add_theme_constant_override("margin_bottom", 9)
	panel.add_child(pad)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = false
	rt.selection_enabled = true        # 드래그로 선택·복사
	rt.context_menu_enabled = true     # 우클릭 복사
	rt.shortcut_keys_enabled = true    # Ctrl+C
	rt.fit_content = true
	rt.scroll_active = false
	rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rt.mouse_filter = Control.MOUSE_FILTER_STOP
	rt.add_theme_font_size_override("normal_font_size", 18)
	rt.add_theme_color_override("default_color", ThemeSetup.C_TEXT)
	rt.text = "%d. %s" % [idx + 1, text]
	rt.gui_input.connect(_on_choice_gui_input.bind(idx, rt))
	rt.mouse_entered.connect(func() -> void: panel.modulate = Color(1.07, 1.07, 1.07))
	rt.mouse_exited.connect(func() -> void: panel.modulate = Color.WHITE)
	pad.add_child(rt)
	return panel


# 탭(거의 안 움직이고 선택 텍스트 없음) = 정답. 드래그(이동/선택) = 복사로 간주, 정답 미선택.
func _on_choice_gui_input(event: InputEvent, idx: int, rt: RichTextLabel) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			_choice_press_pos = mb.position
			_choice_pressed = true
		elif _choice_pressed:
			_choice_pressed = false
			if mb.position.distance_to(_choice_press_pos) < 6.0 and rt.get_selected_text().is_empty():
				Sfx.play("click")
				_submit(idx)
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_choice_press_pos = st.position
			_choice_pressed = true
		elif _choice_pressed:
			_choice_pressed = false
			if st.position.distance_to(_choice_press_pos) < 8.0 and rt.get_selected_text().is_empty():
				Sfx.play("click")
				_submit(idx)


# ─────────────────────────────────────────────────────────────────────────────
# PackStore 시그널 핸들러
# ─────────────────────────────────────────────────────────────────────────────
func _on_pack_loaded(_meta: Dictionary, _total: int) -> void:
	_enter_session()


func _on_question_changed(_index: int, question: Dictionary) -> void:
	_render_question(question)


func _on_ladder_changed(step: int, _prize: int, _next_prize: int) -> void:
	for i in ladder_cells.size():
		if i < step:        # 이미 획득한 단계
			ladder_cells[i].add_theme_stylebox_override("panel",
				_stylebox(ThemeSetup.C_ACCENT_SOFT, ThemeSetup.C_OK, 6))
			ladder_labels[i].add_theme_color_override("font_color", ThemeSetup.C_OK)
		elif i == step:     # 지금 도전 중인 단계
			ladder_cells[i].add_theme_stylebox_override("panel",
				_stylebox(ThemeSetup.C_PANEL_2, ThemeSetup.C_ACCENT, 6))
			ladder_labels[i].add_theme_color_override("font_color", ThemeSetup.C_TEXT)
		else:
			ladder_cells[i].add_theme_stylebox_override("panel",
				_stylebox(ThemeSetup.C_PANEL, ThemeSetup.C_BORDER, 6))
			ladder_labels[i].add_theme_color_override("font_color", ThemeSetup.C_MUTED)


func _on_feedback(correct: bool, explanation: String, info: Dictionary) -> void:
	_set_choices_disabled(true)
	timer_bar.visible = false
	feedback_panel.visible = true
	# 정답일 때만 효과음(밝은 ding). 오답 처벌 톤은 코지 원칙상 추가하지 않는다.
	if correct:
		Sfx.play("correct")
	Juice.pop_in(feedback_panel)
	var col: Color = ThemeSetup.C_OK if correct else ThemeSetup.C_DANGER
	feedback_panel.add_theme_stylebox_override("panel", _stylebox(ThemeSetup.C_PANEL, col, 8))
	feedback_title.text = "정답!" if correct else "오답"
	feedback_title.add_theme_color_override("font_color", col)
	# 정답 선택지 블록을 초록으로 하이라이트(오답이면 내가 고른 블록은 빨강).
	_highlight_choices(int(info.get("correct_btn", -1)), int(info.get("user_btn", -1)), correct)
	# 오답일 때 정답 텍스트도 명시(정답일 땐 숨김).
	var answer_label := String(info.get("answer_label", ""))
	feedback_answer.visible = not correct and not answer_label.is_empty()
	if feedback_answer.visible:
		feedback_answer.text = "정답: %s" % answer_label
	# 해설 — 정답/오답 모두 동일하게 표시.
	feedback_explanation.text = explanation
	feedback_explanation.visible = not explanation.is_empty()

	_clear_children(feedback_bonus_box)
	for b in info.get("bonuses", []):
		var lbl := Label.new()
		lbl.text = String(b)
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.add_theme_color_override("font_color", ThemeSetup.C_WARN)
		feedback_bonus_box.add_child(lbl)

	# 버튼 구성:
	#  복습       → [다음]
	#  정답(진행) → [받고 멈추기] [다음 문제]
	#  오답·완주  → [결과 보기]  (PackStore가 정산을 보류했다가 여기서 정산)
	cash_out_btn.visible = false
	advance_btn.visible = false
	if PackStore.is_review_mode:
		advance_btn.text = "다음 (Space)"
		advance_btn.visible = true
	elif correct and PackStore.session_step < Ladder.SESSION_SIZE:
		cash_out_btn.text = "%s코인 받고 멈추기" % _fmt(PackStore.current_prize())
		cash_out_btn.visible = true
		advance_btn.text = "다음 문제 (다음 상금 %s)" % _fmt(Ladder.prize_for(PackStore.session_step + 1))
		advance_btn.visible = true
	else:
		advance_btn.text = "결과 보기 (Space)"
		advance_btn.visible = true


func _on_session_completed(record: Dictionary) -> void:
	feedback_panel.visible = false
	_set_choices_disabled(true)
	timer_bar.visible = false
	cash_out_btn.visible = false
	advance_btn.visible = false
	result_panel.visible = true
	Juice.pop_in(result_panel)
	_clear_children(result_lines_box)

	var is_review := bool(record.get("review", false))
	if is_review:
		result_title.text = "복습 완료"
		_add_result_line("정답 %d / %d" % [int(record.get("correct", 0)), PackStore.review_hashes.size()], ThemeSetup.C_TEXT)
	else:
		var prize := int(record.get("prize", 0))
		var granted := int(record.get("granted", 0))
		if int(record.get("steps", 0)) >= Ladder.SESSION_SIZE:
			result_title.text = "사다리 완주!"
			Sfx.play("levelup")
		elif prize > 0:
			result_title.text = "상금 확정!"
			Sfx.play("coin")
		else:
			result_title.text = "세션 종료"
		_add_result_line("정답 %d개" % int(record.get("correct", 0)), ThemeSetup.C_TEXT)
		if prize > 0:
			_add_result_line("상금 %s코인 → +%s코인 지급" % [_fmt(prize), _fmt(granted)], ThemeSetup.C_OK)
			if granted < prize:
				_add_result_line("일일 획득 상한 도달 — 초과분은 지급되지 않았어요", ThemeSetup.C_WARN)
		else:
			_add_result_line("이번 세션 상금은 없어요. 레벨업·티켓 보상은 그대로! (무처벌 원칙)", ThemeSetup.C_MUTED)

	retry_btn.visible = not is_review
	to_wrong_note_btn.visible = is_review


func _on_retry_pressed() -> void:
	var path := PackStore.pack_source
	if path.is_empty():
		_show_pack_select()
		return
	var result := PackStore.load_pack_from_path(path)
	if not result.get("ok", false):
		_show_pack_select()


# ─────────────────────────────────────────────────────────────────────────────
# 헬퍼
# ─────────────────────────────────────────────────────────────────────────────
func _add_result_line(text: String, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", color)
	result_lines_box.add_child(lbl)


func _set_choices_disabled(disabled: bool) -> void:
	for c in choices_box.get_children():
		if c is Button:
			(c as Button).disabled = disabled
		else:
			for cc in c.get_children():
				if cc is Button:
					(cc as Button).disabled = disabled


# 렌더 순서대로 평탄화한 선택지 버튼 목록 (mcq=choices 순, ox=[O, X]).
func _choice_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for c in choices_box.get_children():
		if c is Button:
			out.append(c)
		else:
			for cc in c.get_children():
				if cc is Button:
					out.append(cc)
	return out


# 정답 블록은 초록, 오답이면 내가 고른 블록은 빨강으로 칠한다.
# 다음 문항 렌더 시 버튼이 새로 생성되므로 색은 자동 초기화된다.
func _highlight_choices(correct_btn: int, user_btn: int, correct: bool) -> void:
	var btns := _choice_buttons()
	if correct_btn >= 0 and correct_btn < btns.size():
		_paint_button(btns[correct_btn], ThemeSetup.C_OK)
	if not correct and user_btn >= 0 and user_btn < btns.size() and user_btn != correct_btn:
		_paint_button(btns[user_btn], ThemeSetup.C_DANGER)


func _paint_button(btn: Button, border: Color) -> void:
	var sb := _stylebox(border.darkened(0.55), border, 6)
	sb.set_border_width_all(2)
	for s in ["normal", "hover", "pressed", "disabled", "focus"]:
		btn.add_theme_stylebox_override(s, sb)
	btn.add_theme_color_override("font_disabled_color", ThemeSetup.C_TEXT)
	btn.add_theme_color_override("font_color", ThemeSetup.C_TEXT)


# ── 용어 카드 (glossary) — 문항의 질문·보기 속 어려운 용어를 쉬운 설명 카드로.
# 'word｜reading｜meaning' 스칼라(또는 dict)를 파싱. reading 비면 생략. 설명은
# 길 수 있어 카드 폭 안에서 줄바꿈한다. (godot 본가 quiz.gd에서 이식)
func _render_glossary(entries) -> void:
	_clear_children(glossary_box)
	var list: Array = entries if typeof(entries) == TYPE_ARRAY else []
	if list.is_empty():
		glossary_box.visible = false
		return
	glossary_box.visible = true
	var header := Label.new()
	header.text = "📖 용어 카드 — 모르는 단어 설명"
	header.add_theme_font_size_override("font_size", 13)
	header.add_theme_color_override("font_color", ThemeSetup.C_ACCENT)
	glossary_box.add_child(header)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 6)
	glossary_box.add_child(flow)
	for e in list:
		var card := _make_gloss_card(e)
		if card != null:
			flow.add_child(card)


func _make_gloss_card(entry) -> Control:
	var word := ""
	var reading := ""
	var meaning := ""
	if typeof(entry) == TYPE_DICTIONARY:
		word = String(entry.get("word", ""))
		reading = String(entry.get("reading", ""))
		meaning = String(entry.get("meaning", ""))
	else:
		var parts := String(entry).replace("|", "｜").split("｜")
		if parts.size() >= 1: word = parts[0].strip_edges()
		if parts.size() >= 2: reading = parts[1].strip_edges()
		if parts.size() >= 3: meaning = parts[2].strip_edges()
	if word.is_empty():
		return null

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _stylebox(ThemeSetup.C_PANEL_2, ThemeSetup.C_BORDER, 7))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)
	panel.add_child(vb)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	vb.add_child(top)
	var word_label := Label.new()
	word_label.text = word
	word_label.add_theme_font_size_override("font_size", 16)
	word_label.add_theme_color_override("font_color", ThemeSetup.C_TEXT)
	top.add_child(word_label)
	if not reading.is_empty():
		var reading_label := Label.new()
		reading_label.text = reading
		reading_label.add_theme_font_size_override("font_size", 13)
		reading_label.add_theme_color_override("font_color", ThemeSetup.C_OK)
		reading_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(reading_label)

	var meaning_label := Label.new()
	meaning_label.text = meaning if not meaning.is_empty() else "—"
	meaning_label.add_theme_font_size_override("font_size", 13)
	meaning_label.add_theme_color_override("font_color", ThemeSetup.C_MUTED)
	meaning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	meaning_label.custom_minimum_size = Vector2(240, 0)
	vb.add_child(meaning_label)
	return panel


func _wire_button(btn: Button) -> void:
	btn.mouse_entered.connect(Juice.hover.bind(btn, true))
	btn.mouse_exited.connect(Juice.hover.bind(btn, false))
	btn.pressed.connect(Juice.punch.bind(btn))


static func _clear_children(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


static func _anchor_column(c: Control, margin_x: int, margin_y: int) -> void:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_left = margin_x
	c.offset_right = -margin_x
	c.offset_top = margin_y
	c.offset_bottom = -margin_y


static func _stylebox(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


# 1600 → "1,600"
static func _fmt(n: int) -> String:
	var s := str(n)
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return out
