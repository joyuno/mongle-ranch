# 오답노트 화면 — ProgressStore.get_wrong_note() 목록 카드 + SRS due 복습 시작.
# due 항목만 모아 PackStore.load_review_session()으로 복습 세션을 만들고
# Quiz 씬으로 넘긴다 (Quiz 쪽이 복습 모드를 감지해 팩 선택을 건너뜀).

extends Control

const RANCH_SCENE := "res://scenes/Ranch.tscn"
const QUIZ_SCENE := "res://scenes/Quiz.tscn"
const PREVIEW_CHARS := 80

var review_btn: Button
var list_box: VBoxContainer


func _ready() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	add_child(root)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 240
	root.offset_right = -240
	root.offset_top = 24
	root.offset_bottom = -24

	var header := HBoxContainer.new()
	var back := Button.new()
	Icons.decorate_button(back, "back", "목장")
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(func(): Sfx.play("click"); get_tree().change_scene_to_file(RANCH_SCENE))
	_wire_button(back)
	header.add_child(back)
	var title := Icons.labeled("wrong_note", "오답노트", ThemeSetup.C_TEXT, 24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.alignment = BoxContainer.ALIGNMENT_CENTER
	(title.get_child(1) as Label).add_theme_font_size_override("font_size", 24)
	header.add_child(title)
	var spacer := Control.new()
	spacer.custom_minimum_size.x = 80
	header.add_child(spacer)
	root.add_child(header)

	review_btn = Button.new()
	review_btn.custom_minimum_size.y = 48
	review_btn.focus_mode = Control.FOCUS_NONE
	review_btn.pressed.connect(_on_review_pressed)
	_wire_button(review_btn)
	root.add_child(review_btn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 8)
	scroll.add_child(list_box)

	ProgressStore.progress_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	for c in list_box.get_children():
		list_box.remove_child(c)
		c.queue_free()

	var entries := ProgressStore.get_wrong_note()
	var due_count := 0
	for e in entries:
		if typeof(e) == TYPE_DICTIONARY and SRS.is_due(String(e.get("nextReviewAt", ""))):
			due_count += 1
	Icons.decorate_button(review_btn, "retry", "복습 시작 (due %d문항)" % due_count)
	review_btn.disabled = due_count == 0

	if entries.is_empty():
		var empty := Label.new()
		empty.text = "오답이 없어요 — 완벽해요!"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_color_override("font_color", ThemeSetup.C_MUTED)
		list_box.add_child(empty)
		return

	for e in entries:
		if typeof(e) == TYPE_DICTIONARY:
			list_box.add_child(_make_card(e))


func _make_card(entry: Dictionary) -> PanelContainer:
	var snap = entry.get("questionSnapshot", {})
	var q_text := String(snap.get("q", "")) if typeof(snap) == TYPE_DICTIONARY else ""
	if q_text.length() > PREVIEW_CHARS:
		q_text = q_text.substr(0, PREVIEW_CHARS) + "…"
	var next_review := String(entry.get("nextReviewAt", ""))
	var due := SRS.is_due(next_review)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",
		_stylebox(ThemeSetup.C_PANEL, ThemeSetup.C_WARN if due else ThemeSetup.C_BORDER, 8))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)

	var q_lbl := Label.new()
	q_lbl.text = q_text
	q_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(q_lbl)

	var meta_lbl := Label.new()
	meta_lbl.text = "%s · 틀린 횟수 %d회 · 복습: %s" % [
		String(entry.get("packTitle", "")),
		int(entry.get("timesWrong", 1)),
		SRS.format_due_in(next_review),
	]
	meta_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	meta_lbl.add_theme_color_override("font_color", ThemeSetup.C_WARN if due else ThemeSetup.C_MUTED)
	col.add_child(meta_lbl)

	var del := Button.new()
	Icons.decorate_button(del, "delete", "")
	del.tooltip_text = "오답노트에서 삭제"
	del.focus_mode = Control.FOCUS_NONE
	del.custom_minimum_size = Vector2(44, 44)
	var hash_key := String(entry.get("questionHash", ""))
	del.pressed.connect(func(): Sfx.play("click"); ProgressStore.remove_wrong_entry(hash_key))
	_wire_button(del)
	row.add_child(del)

	return card


# 모든 버튼에 hover/press juice + click sfx를 단다.
func _wire_button(btn: Button) -> void:
	btn.mouse_entered.connect(Juice.hover.bind(btn, true))
	btn.mouse_exited.connect(Juice.hover.bind(btn, false))
	btn.pressed.connect(Juice.punch.bind(btn))


func _on_review_pressed() -> void:
	Sfx.play("click")
	var due_entries: Array = []
	for e in ProgressStore.get_wrong_note():
		if typeof(e) == TYPE_DICTIONARY and SRS.is_due(String(e.get("nextReviewAt", ""))):
			due_entries.append(e)
	if due_entries.is_empty():
		return
	if PackStore.load_review_session(due_entries):
		get_tree().change_scene_to_file(QUIZ_SCENE)


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
