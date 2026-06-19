# 설정 화면 — GitHub username 연동(토큰 UI 금지), 간식 적립 현황, 스트릭 복구,
# 타이머/폰트/조용 모드, 퀴즈팩 안내, 세이브 초기화(2단 확인).
extends Control

const RANCH_SCENE := "res://scenes/Ranch.tscn"
const QUIZ_DIR := "res://data/quizzes"

var username_edit: LineEdit
var snack_label: Label
var streak_label: Label
var restore_btn: Button
var status_label: Label
var reset_confirm_1: ConfirmationDialog
var reset_confirm_2: ConfirmationDialog
var reset_done: AcceptDialog


func _ready() -> void:
	_build_ui()
	ProgressStore.coins_changed.connect(func(_amount: int) -> void: _refresh())
	ProgressStore.streak_changed.connect(func(_count: int) -> void: _refresh())
	ProgressStore.snacks_changed.connect(func(_count: int) -> void: _refresh())
	_refresh()


# -----------------------------------------------------------------------------
# UI 구성
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
	Icons.decorate_button(back, "back", "목장")
	back.pressed.connect(func() -> void: Sfx.play("click"); get_tree().change_scene_to_file(RANCH_SCENE))
	_wire_button(back)
	bar.add_child(back)
	var title := Icons.labeled("settings", "설정", ThemeSetup.C_TEXT, 24)
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
	root.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	scroll.add_child(body)

	# ─ GitHub 간식 배달
	var gh_box := _make_section(body, "snack", "GitHub 간식 배달")
	var gh_row := HBoxContainer.new()
	gh_row.add_theme_constant_override("separation", 8)
	gh_box.add_child(gh_row)
	username_edit = LineEdit.new()
	username_edit.placeholder_text = "GitHub username"
	username_edit.text = ProgressStore.get_github_username()
	username_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gh_row.add_child(username_edit)
	var save_btn := Button.new()
	save_btn.text = "저장"
	save_btn.pressed.connect(_on_save_username)
	_wire_button(save_btn)
	gh_row.add_child(save_btn)
	var gh_note := Label.new()
	gh_note.text = "공개 활동만 읽습니다. 토큰·로그인 불필요."
	gh_note.add_theme_color_override("font_color", ThemeSetup.C_MUTED)
	gh_box.add_child(gh_note)
	snack_label = Label.new()
	gh_box.add_child(snack_label)

	# ─ 스트릭
	var streak_box := _make_section(body, "streak", "스트릭")
	streak_label = Label.new()
	streak_box.add_child(streak_label)
	restore_btn = Button.new()
	Icons.decorate_button(restore_btn, "streak", "스트릭 복구 (%s코인)" % _fmt(Ladder.STREAK_RESTORE_COST))
	restore_btn.pressed.connect(_on_restore_streak)
	_wire_button(restore_btn)
	streak_box.add_child(restore_btn)

	# ─ 퀴즈 환경
	var quiz_box := _make_section(body, "quiz", "퀴즈 환경")
	var timer_check := CheckButton.new()
	timer_check.text = "문제 타이머 (10초)"
	timer_check.set_pressed_no_signal(ProgressStore.is_timer_enabled())
	timer_check.toggled.connect(func(on: bool) -> void: ProgressStore.set_timer_enabled(on))
	quiz_box.add_child(timer_check)
	var font_row := HBoxContainer.new()
	font_row.add_theme_constant_override("separation", 8)
	quiz_box.add_child(font_row)
	var font_label := Label.new()
	font_label.text = "폰트 크기"
	font_row.add_child(font_label)
	var font_option := OptionButton.new()
	font_option.custom_minimum_size = Vector2(140, 40)  # 드롭다운 폭 확보(리뷰 m2)
	# OS 기본 콤보박스 대신 둥근 크림 카드로 — 화면 전체 코지 톤에 맞춘다.
	for st in ["normal", "hover", "pressed", "focus"]:
		font_option.add_theme_stylebox_override(st, ThemeSetup.card(ThemeSetup.C_ACCENT_SOFT, ThemeSetup.C_ACCENT, 12, false))
	font_option.add_theme_color_override("font_color", ThemeSetup.C_INK)
	font_option.add_theme_color_override("font_hover_color", ThemeSetup.C_INK)
	font_option.add_theme_color_override("font_pressed_color", ThemeSetup.C_INK)
	font_option.add_theme_color_override("font_focus_color", ThemeSetup.C_INK)
	# 펼친 드롭다운(PopupMenu)도 크림 카드 + 잉크색 글씨로 — OS 기본 리스트 방지.
	var font_popup := font_option.get_popup()
	font_popup.add_theme_stylebox_override("panel", ThemeSetup.card(ThemeSetup.C_PANEL, ThemeSetup.C_BORDER, 12, true))
	font_popup.add_theme_color_override("font_color", ThemeSetup.C_INK)
	font_popup.add_theme_color_override("font_hover_color", ThemeSetup.C_ACCENT)
	font_option.add_item("작게", 0)
	font_option.add_item("보통", 1)
	font_option.add_item("크게", 2)
	font_option.select(clampi(ProgressStore.get_font_size_scale(), 0, 2))
	font_option.item_selected.connect(func(index: int) -> void: ProgressStore.set_font_size_scale(index))
	font_row.add_child(font_option)
	var quiet_check := CheckButton.new()
	quiet_check.text = "조용 모드 (효과음·연출 최소화)"
	quiet_check.set_pressed_no_signal(ProgressStore.is_quiet_mode())
	quiet_check.toggled.connect(func(on: bool) -> void: ProgressStore.set_quiet_mode(on))
	quiz_box.add_child(quiet_check)

	# ─ 퀴즈팩
	var pack_box := _make_section(body, "scroll", "퀴즈팩")
	var pack_note := Label.new()
	pack_note.text = "퀴즈 화면의 '➕ 내 문제집 만들기 / 가져오기'에서 직접 추가할 수 있어요.\n(PC 개발 시: %s 폴더의 JSON도 자동 인식)" % QUIZ_DIR
	pack_note.add_theme_color_override("font_color", ThemeSetup.C_MUTED)
	pack_box.add_child(pack_note)

	# ─ 데이터
	var data_box := _make_section(body, "delete", "데이터")
	var reset_btn := Button.new()
	reset_btn.text = "세이브 초기화"
	reset_btn.add_theme_color_override("font_color", ThemeSetup.C_DANGER)
	reset_btn.pressed.connect(func() -> void: Sfx.play("click"); reset_confirm_1.popup_centered())
	_wire_button(reset_btn)
	data_box.add_child(reset_btn)
	var reset_note := Label.new()
	reset_note.text = "모든 친구·코인·기록이 삭제됩니다. 초기화 후 게임이 종료됩니다."
	reset_note.add_theme_color_override("font_color", ThemeSetup.C_MUTED)
	data_box.add_child(reset_note)

	# ─ 초기화 2단 확인 다이얼로그
	reset_confirm_1 = ConfirmationDialog.new()
	reset_confirm_1.title = "세이브 초기화"
	reset_confirm_1.dialog_text = "정말 세이브를 초기화할까요?\n모든 친구·코인·기록이 사라집니다."
	reset_confirm_1.ok_button_text = "계속"
	reset_confirm_1.cancel_button_text = "취소"
	reset_confirm_1.confirmed.connect(func() -> void: reset_confirm_2.popup_centered())
	add_child(reset_confirm_1)
	reset_confirm_2 = ConfirmationDialog.new()
	reset_confirm_2.title = "마지막 확인"
	reset_confirm_2.dialog_text = "마지막 확인입니다.\n되돌릴 수 없어요. 정말 모두 삭제할까요?"
	reset_confirm_2.ok_button_text = "모두 삭제"
	reset_confirm_2.cancel_button_text = "취소"
	reset_confirm_2.confirmed.connect(_on_reset_save)
	add_child(reset_confirm_2)
	reset_done = AcceptDialog.new()
	reset_done.title = "초기화 완료"
	reset_done.dialog_text = "세이브를 삭제했어요.\n확인을 누르면 게임이 종료됩니다.\n다시 실행하면 새로 시작해요."
	reset_done.confirmed.connect(func() -> void: get_tree().quit())
	reset_done.canceled.connect(func() -> void: get_tree().quit())
	add_child(reset_done)


func _make_section(parent: Control, icon: String, title: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	# 테마 기본 카드와 같은 톤(C_PANEL·C_BORDER·라운드·섀도)을 유지하되 위/아래
	# 안쪽 여백만 8→6으로 살짝 조여, 코지한 숨통은 두고 폼처럼 휑하지 않게 한다.
	var card := ThemeSetup.card()
	card.content_margin_top = 6
	card.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", card)
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var t := Icons.labeled(icon, title, ThemeSetup.C_TEXT, 20)
	# 제목은 내용·읽기 흐름에 맞춰 좌측 정렬(라벨 헬퍼 기본은 중앙 정렬).
	t.alignment = BoxContainer.ALIGNMENT_BEGIN
	(t.get_child(1) as Label).add_theme_font_size_override("font_size", 20)
	box.add_child(t)
	return box


# -----------------------------------------------------------------------------
# 동작
# -----------------------------------------------------------------------------
func _wire_button(btn: Button) -> void:
	btn.mouse_entered.connect(Juice.hover.bind(btn, true))
	btn.mouse_exited.connect(Juice.hover.bind(btn, false))
	btn.pressed.connect(Juice.punch.bind(btn))


func _on_save_username() -> void:
	Sfx.play("click")
	ProgressStore.set_github_username(username_edit.text)
	status_label.text = "GitHub 사용자명을 저장했어요"
	_refresh()


func _on_restore_streak() -> void:
	var r: Dictionary = ProgressStore.restore_streak()
	if bool(r.get("ok", false)):
		Sfx.play("levelup")
		if bool(r.get("free", false)):
			status_label.text = "무료 복구권으로 스트릭을 %d일로 되살렸어요!" % int(r.get("count", 0))
		else:
			status_label.text = "스트릭을 %d일로 복구했어요!" % int(r.get("count", 0))
		return
	match String(r.get("reason", "")):
		"not_enough_coins":
			status_label.text = "코인이 부족해요 (복구 비용 %s코인)" % _fmt(Ladder.STREAK_RESTORE_COST)
		"nothing_to_restore":
			status_label.text = "복구할 스트릭이 없어요"
		_:
			status_label.text = "복구에 실패했어요 (%s)" % String(r.get("reason", ""))


func _on_reset_save() -> void:
	# progress.json + 백업/임시 파일까지 지워야 .bak 폴백으로 복원되지 않는다.
	var dir := DirAccess.open("user://")
	if dir != null:
		for p in ["progress.json", "progress.json.bak", "progress.json.tmp"]:
			if dir.file_exists(p):
				dir.remove(p)
	reset_done.popup_centered()


# -----------------------------------------------------------------------------
# 갱신 · 헬퍼
# -----------------------------------------------------------------------------
func _refresh() -> void:
	snack_label.text = "오늘 간식 적립 %d/%d" % [
		ProgressStore.snacks_granted_today(), GithubSnacks.DAILY_SNACK_CAP]
	var s: Dictionary = ProgressStore.get_streak()
	var count := int(s.get("count", 0))
	var best := int(s.get("best", 0))
	var shields := int(s.get("shields", 0))
	var shield_txt := "  무료 복구권 %d개" % shields if shields > 0 else ""
	streak_label.text = "현재 %d일 · 최고 %d일%s" % [count, best, shield_txt]
	restore_btn.visible = best > count
	# 무료 복구권이 있으면 코인 없이 복구된다는 걸 버튼에 드러낸다.
	if shields > 0:
		Icons.decorate_button(restore_btn, "lock", "스트릭 복구 (무료 복구권 사용)")
	else:
		Icons.decorate_button(restore_btn, "streak", "스트릭 복구 (%s코인)" % _fmt(Ladder.STREAK_RESTORE_COST))


func _fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var i := s.length()
	while i > 3:
		out = "," + s.substr(i - 3, 3) + out
		i -= 3
	out = s.substr(0, i) + out
	return ("-" + out) if n < 0 else out
