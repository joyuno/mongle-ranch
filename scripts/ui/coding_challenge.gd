# 코딩 챌린지 화면 — GameApi 경계로만 study_game_server와 통신한다(Judge0/Piston을
# 직접 호출하지 않음). 데스크톱은 좌(문제) 42% / 우(코드) 58% 분할, 760px 미만은
# 문제/코드 탭으로 전환 — CodeEdit 노드는 재생성하지 않고 재부모화해 소스를 보존한다.

extends Control

const RANCH_SCENE := "res://scenes/Ranch.tscn"
const PROBLEM_SLUG := "frequency-kits"
const NARROW_BREAKPOINT := 760.0

const STAGE_LABELS := {
	"learn": "학습", "practice": "연습", "interview": "면접", "challenge": "도전",
}
const VERDICT_LABELS := {
	"accepted": "정답", "wrong_answer": "오답", "compile_error": "컴파일 오류",
	"runtime_error": "실행 오류", "time_limit": "시간 초과", "memory_limit": "메모리 초과",
	"output_limit": "출력 초과", "internal_error": "채점 서버 오류",
}

enum ViewState { CONNECTING, LOADING, READY, RUNNING_PUBLIC, SUBMITTING, RESULT, ERROR }

var _view_state: ViewState = ViewState.CONNECTING
var _problem: Dictionary = {}
var _submit_key := ""
var _last_result: Dictionary = {}
var _last_result_kind := ""  # "run" or "submission"
var _error_message := ""
var _narrow_mode := false

var _status_label: Label
var _wallet_label: Label
var _code_edit: CodeEdit
var _run_btn: Button
var _submit_btn: Button
var _result_panel: VBoxContainer
var _inline_error_label: Label
var _problem_body: VBoxContainer
var _layout_host: Control
var _left_panel: Control
var _right_panel: Control


func _ready() -> void:
	_build_layout()
	GameApi.session_ready.connect(_on_session_ready)
	GameApi.problem_loaded.connect(_on_problem_loaded)
	GameApi.public_run_completed.connect(_on_public_run_completed)
	GameApi.submission_completed.connect(_on_submission_completed)
	GameApi.request_failed.connect(_on_request_failed)
	resized.connect(_on_resized)
	_wallet_label.text = ThemeSetup.fmt_int(GameApi.wallet_coins())
	_start_flow()


func _start_flow() -> void:
	if GameApi.has_session():
		_set_state(ViewState.LOADING)
		GameApi.fetch_problem(PROBLEM_SLUG)
	else:
		_set_state(ViewState.CONNECTING)
		GameApi.bootstrap_guest()
	_refresh_problem_panel()


# -----------------------------------------------------------------------------
# Layout — code-first build, narrow fallback reparents (never recreates) the
# same CodeEdit/problem-panel nodes so source and scroll state survive.
# -----------------------------------------------------------------------------
func _build_layout() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	_build_top_bar(root)

	_layout_host = Control.new()
	_layout_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_layout_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_layout_host)

	_left_panel = _build_left_panel()
	_right_panel = _build_right_panel()
	_narrow_mode = size.x < NARROW_BREAKPOINT
	_apply_responsive_layout()


func _build_top_bar(parent: Node) -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	parent.add_child(bar)

	var back := Button.new()
	Icons.decorate_button(back, "back", "목장")
	back.pressed.connect(func() -> void: Sfx.play("click"); get_tree().change_scene_to_file(RANCH_SCENE))
	_wire_button(back)
	bar.add_child(back)

	var title := Icons.labeled("coding", "코딩 챌린지", ThemeSetup.C_TEXT, 24)
	(title.get_child(1) as Label).add_theme_font_size_override("font_size", 24)
	bar.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)

	_status_label = Label.new()
	_status_label.add_theme_color_override("font_color", ThemeSetup.C_MUTED)
	bar.add_child(_status_label)

	var wallet_chip := Icons.labeled("gold", "0", ThemeSetup.C_WARN.darkened(0.1), 20)
	_wallet_label = wallet_chip.get_child(1) as Label
	bar.add_child(wallet_chip)


func _build_left_panel() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	_problem_body = body
	return scroll


func _build_right_panel() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var lang_label := Label.new()
	lang_label.text = "Python"
	lang_label.add_theme_color_override("font_color", ThemeSetup.C_MUTED)
	box.add_child(lang_label)

	_code_edit = CodeEdit.new()
	_code_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_code_edit.custom_minimum_size = Vector2(0, 240)
	_code_edit.gutters_draw_line_numbers = true
	_code_edit.indent_size = 4
	_code_edit.indent_use_spaces = true
	_code_edit.wrap_mode = TextEdit.LINE_WRAPPING_NONE
	_code_edit.text_changed.connect(_on_source_edited)
	box.add_child(_code_edit)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	box.add_child(btn_row)
	_run_btn = Button.new()
	_run_btn.text = "공개 테스트 실행"
	_run_btn.disabled = true
	_run_btn.pressed.connect(_on_run_pressed)
	_wire_button(_run_btn)
	btn_row.add_child(_run_btn)
	_submit_btn = Button.new()
	_submit_btn.text = "제출하기"
	_submit_btn.disabled = true
	_submit_btn.pressed.connect(_on_submit_pressed)
	_wire_button(_submit_btn)
	btn_row.add_child(_submit_btn)

	_inline_error_label = Label.new()
	_inline_error_label.add_theme_color_override("font_color", ThemeSetup.C_DANGER)
	_inline_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_inline_error_label.visible = false
	box.add_child(_inline_error_label)

	_result_panel = VBoxContainer.new()
	_result_panel.add_theme_constant_override("separation", 4)
	box.add_child(_result_panel)

	return box


func _on_resized() -> void:
	var narrow := size.x < NARROW_BREAKPOINT
	if narrow != _narrow_mode:
		_narrow_mode = narrow
		_apply_responsive_layout()


func _apply_responsive_layout() -> void:
	if _left_panel.get_parent() != null:
		_left_panel.get_parent().remove_child(_left_panel)
	if _right_panel.get_parent() != null:
		_right_panel.get_parent().remove_child(_right_panel)
	for c in _layout_host.get_children():
		_layout_host.remove_child(c)
		c.queue_free()

	if _narrow_mode:
		var tabs := TabContainer.new()
		tabs.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_left_panel.name = "문제"
		_right_panel.name = "코드"
		tabs.add_child(_left_panel)
		tabs.add_child(_right_panel)
		_layout_host.add_child(tabs)
	else:
		var hbox := HBoxContainer.new()
		hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hbox.add_theme_constant_override("separation", 16)
		_left_panel.size_flags_stretch_ratio = 0.42
		_right_panel.size_flags_stretch_ratio = 0.58
		hbox.add_child(_left_panel)
		hbox.add_child(_right_panel)
		_layout_host.add_child(hbox)


func _wire_button(btn: Button) -> void:
	btn.mouse_entered.connect(Juice.hover.bind(btn, true))
	btn.mouse_exited.connect(Juice.hover.bind(btn, false))
	btn.pressed.connect(Juice.punch.bind(btn))


# -----------------------------------------------------------------------------
# State machine
# -----------------------------------------------------------------------------
func _set_state(state: ViewState) -> void:
	_view_state = state
	var runnable := state == ViewState.READY or state == ViewState.RESULT
	_run_btn.disabled = not runnable
	_submit_btn.disabled = not runnable
	match state:
		ViewState.CONNECTING:
			_status_label.text = "연결 중..."
		ViewState.LOADING:
			_status_label.text = "문제를 불러오는 중..."
		ViewState.READY, ViewState.RESULT:
			_status_label.text = "연결됨"
		ViewState.RUNNING_PUBLIC:
			_status_label.text = "공개 테스트 실행 중..."
		ViewState.SUBMITTING:
			_status_label.text = "제출 중..."
		ViewState.ERROR:
			_status_label.text = "연결 안 됨"


# -----------------------------------------------------------------------------
# GameApi signal handlers
# -----------------------------------------------------------------------------
func _on_session_ready(_user: Dictionary) -> void:
	_set_state(ViewState.LOADING)
	GameApi.fetch_problem(PROBLEM_SLUG)


func _on_problem_loaded(problem: Dictionary) -> void:
	_problem = problem
	if _code_edit.text.is_empty():
		_code_edit.text = String(problem.get("starter_code", ""))
	_set_state(ViewState.READY)
	_refresh_problem_panel()


func _on_public_run_completed(result: Dictionary) -> void:
	_last_result = result
	_last_result_kind = "run"
	_inline_error_label.visible = false
	_set_state(ViewState.RESULT)
	_refresh_result_panel()


func _on_submission_completed(result: Dictionary) -> void:
	_last_result = result
	_last_result_kind = "submission"
	_submit_key = ""  # terminal result — the next submit attempt gets a fresh key
	_inline_error_label.visible = false
	_set_state(ViewState.RESULT)
	_refresh_result_panel()
	_wallet_label.text = ThemeSetup.fmt_int(GameApi.wallet_coins())


func _on_request_failed(operation: String, code: String) -> void:
	var message := _describe_error(code)
	match operation:
		"bootstrap_guest", "fetch_problem":
			_error_message = message
			_set_state(ViewState.ERROR)
			_refresh_problem_panel()
		"run_public_tests", "submit_code":
			_inline_error_label.text = message
			_inline_error_label.visible = true
			_set_state(ViewState.RESULT if not _last_result.is_empty() else ViewState.READY)


func _describe_error(code: String) -> String:
	match code:
		"transport_error":
			return "서버에 연결할 수 없어요. 로컬 서버가 켜져 있는지 확인해 주세요."
		"http_404":
			return "문제를 찾을 수 없어요."
		"rate_limited":
			return "요청이 너무 잦아요. 잠시 후 다시 시도해 주세요."
		"retryable":
			return "채점 서버가 잠깐 응답하지 않았어요. 같은 코드로 다시 시도해 주세요."
		"running":
			return "이전 요청이 아직 처리 중이에요. 잠시만 기다려 주세요."
		"not_authenticated":
			return "연결이 끊어졌어요. 화면을 다시 열어 주세요."
		_:
			return "잠시 문제가 생겼어요. 다시 시도해 주세요."


# -----------------------------------------------------------------------------
# User actions
# -----------------------------------------------------------------------------
func _on_run_pressed() -> void:
	if _run_btn.disabled:
		return
	Sfx.play("click")
	_inline_error_label.visible = false
	_set_state(ViewState.RUNNING_PUBLIC)
	GameApi.run_public_tests(PROBLEM_SLUG, _code_edit.text)


func _on_submit_pressed() -> void:
	if _submit_btn.disabled:
		return
	Sfx.play("click")
	_inline_error_label.visible = false
	if _submit_key.is_empty():
		_submit_key = Crypto.new().generate_random_bytes(16).hex_encode()
	_set_state(ViewState.SUBMITTING)
	GameApi.submit_code(PROBLEM_SLUG, _code_edit.text, _submit_key)


func _on_source_edited() -> void:
	_submit_key = ""


func _on_retry_pressed() -> void:
	Sfx.play("click")
	_error_message = ""
	_start_flow()


# -----------------------------------------------------------------------------
# Problem panel
# -----------------------------------------------------------------------------
func _refresh_problem_panel() -> void:
	for c in _problem_body.get_children():
		_problem_body.remove_child(c)
		c.queue_free()

	if _problem.is_empty():
		var msg := Label.new()
		msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if _view_state == ViewState.ERROR:
			msg.text = _error_message
			msg.add_theme_color_override("font_color", ThemeSetup.C_DANGER)
			_problem_body.add_child(msg)
			var retry := Button.new()
			retry.text = "다시 시도"
			retry.pressed.connect(_on_retry_pressed)
			_wire_button(retry)
			_problem_body.add_child(retry)
		else:
			msg.text = "연결 중..." if _view_state == ViewState.CONNECTING else "문제를 불러오는 중..."
			msg.add_theme_color_override("font_color", ThemeSetup.C_MUTED)
			_problem_body.add_child(msg)
		return

	var title := Label.new()
	title.text = String(_problem.get("title", ""))
	title.add_theme_font_size_override("font_size", ThemeSetup.FS_TITLE)
	_problem_body.add_child(title)

	var meta := HBoxContainer.new()
	meta.add_theme_constant_override("separation", 8)
	_problem_body.add_child(meta)
	var stage_chip := Label.new()
	stage_chip.text = String(STAGE_LABELS.get(_problem.get("stage", ""), _problem.get("stage", "")))
	stage_chip.add_theme_color_override("font_color", ThemeSetup.C_ACCENT.darkened(0.2))
	meta.add_child(stage_chip)
	for concept in (_problem.get("concepts", []) as Array):
		var chip := Label.new()
		chip.text = "#%s" % String(concept)
		chip.add_theme_color_override("font_color", ThemeSetup.C_MUTED)
		meta.add_child(chip)

	var statement := Label.new()
	statement.text = String(_problem.get("statement", ""))
	statement.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_problem_body.add_child(statement)

	var io_label := Label.new()
	io_label.text = "%s\n%s" % [String(_problem.get("input_format", "")), String(_problem.get("output_format", ""))]
	io_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	io_label.add_theme_color_override("font_color", ThemeSetup.C_MUTED)
	_problem_body.add_child(io_label)

	var examples: Array = _problem.get("examples", [])
	for i in examples.size():
		var ex: Dictionary = examples[i]
		var ex_panel := PanelContainer.new()
		ex_panel.add_theme_stylebox_override("panel", ThemeSetup.card(ThemeSetup.C_PANEL_2, ThemeSetup.C_BORDER, 12, false))
		var ex_box := VBoxContainer.new()
		ex_panel.add_child(ex_box)
		var ex_title := Label.new()
		ex_title.text = "예제 %d" % (i + 1)
		ex_title.add_theme_font_size_override("font_size", 14)
		ex_box.add_child(ex_title)
		var ex_input := Label.new()
		ex_input.text = "입력\n%s" % String(ex.get("input", ""))
		ex_box.add_child(ex_input)
		var ex_output := Label.new()
		ex_output.text = "출력\n%s" % String(ex.get("output", ""))
		ex_box.add_child(ex_output)
		_problem_body.add_child(ex_panel)


# -----------------------------------------------------------------------------
# Result panel
# -----------------------------------------------------------------------------
func _refresh_result_panel() -> void:
	for c in _result_panel.get_children():
		_result_panel.remove_child(c)
		c.queue_free()
	if _last_result.is_empty():
		return

	var verdict := String(_last_result.get("verdict", ""))
	var verdict_row := Label.new()
	verdict_row.text = "%s — %d/%d" % [
		String(VERDICT_LABELS.get(verdict, verdict)),
		int(_last_result.get("passed_count", 0)),
		int(_last_result.get("total_count", 0)),
	]
	verdict_row.add_theme_color_override("font_color", ThemeSetup.C_OK if verdict == "accepted" else ThemeSetup.C_DANGER)
	verdict_row.add_theme_font_size_override("font_size", ThemeSetup.FS_SUB)
	_result_panel.add_child(verdict_row)

	if _last_result_kind != "submission":
		var hint := Label.new()
		hint.text = "공개 예제 기준 결과예요. 제출하면 숨겨진 케이스까지 채점해요."
		hint.add_theme_color_override("font_color", ThemeSetup.C_MUTED)
		_result_panel.add_child(hint)
		return

	var perf := Label.new()
	perf.text = "%d ms · %d KB" % [int(_last_result.get("runtime_ms", 0)), int(_last_result.get("memory_kb", 0))]
	perf.add_theme_color_override("font_color", ThemeSetup.C_MUTED)
	_result_panel.add_child(perf)

	var reward: Dictionary = _last_result.get("reward", {})
	if reward.get("granted", false):
		var reward_label := Label.new()
		reward_label.text = "보상 +%d 코인" % int(reward.get("coins", 0))
		reward_label.add_theme_color_override("font_color", ThemeSetup.C_WARN.darkened(0.1))
		_result_panel.add_child(reward_label)
	elif verdict == "accepted":
		var already_label := Label.new()
		already_label.text = "이미 이 문제의 보상을 받았어요"
		already_label.add_theme_color_override("font_color", ThemeSetup.C_MUTED)
		_result_panel.add_child(already_label)

	var wallet: Dictionary = _last_result.get("wallet", {})
	if wallet.has("coins"):
		var wallet_row := Label.new()
		wallet_row.text = "현재 잔액 %s 코인" % ThemeSetup.fmt_int(int(wallet["coins"]))
		wallet_row.add_theme_color_override("font_color", ThemeSetup.C_MUTED)
		_result_panel.add_child(wallet_row)
