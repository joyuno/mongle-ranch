# 가챠 화면 — 단발/10연 뽑기, TRANS_ELASTIC 등장 연출, 천장(에픽/레전더리/스파크)
# 카운터, 스파크 교환, 확률 공시(접기/펼치기). 코드-우선 UI, ProgressStore 시그널 구독.
extends Control

const RANCH_SCENE := "res://scenes/Ranch.tscn"
const GACHA_MACHINE_PATH := "res://assets/decor/gacha_machine.png"

var coin_label: Label
var ticket_label: Label
var pity_label: Label
var status_label: Label
var pull_coin_btn: Button
var pull_ticket_btn: Button
var pull_ten_btn: Button
var spark_btn: Button
var result_area: VBoxContainer
var odds_toggle: Button
var odds_box: VBoxContainer
var flash_rect: ColorRect
var spark_popup: PopupPanel
var dex_summary_label: Label
var dex_gauge: ProgressBar
var spark_status_label: Label
var spark_gauge: ProgressBar


func _ready() -> void:
	_build_ui()
	ProgressStore.coins_changed.connect(func(_amount: int) -> void: _refresh())
	ProgressStore.tickets_changed.connect(func(_count: int) -> void: _refresh())
	ProgressStore.pity_changed.connect(func(_pity: Dictionary) -> void: _refresh())
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
	var title := Icons.labeled("gacha", "가챠", ThemeSetup.C_TEXT, 24)
	(title.get_child(1) as Label).add_theme_font_size_override("font_size", 24)
	bar.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	var coin_box := Icons.labeled("coin", "", ThemeSetup.C_TEXT, 18)
	coin_label = coin_box.get_child(1) as Label
	coin_label.add_theme_font_size_override("font_size", 18)
	bar.add_child(coin_box)
	var ticket_box := Icons.labeled("ticket", "", ThemeSetup.C_TEXT, 18)
	ticket_label = ticket_box.get_child(1) as Label
	ticket_label.add_theme_font_size_override("font_size", 18)
	bar.add_child(ticket_box)

	# ─ 천장 카운터
	pity_label = Label.new()
	pity_label.add_theme_color_override("font_color", ThemeSetup.C_MUTED)
	root.add_child(pity_label)

	# ─ 뽑기 버튼
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	root.add_child(buttons)
	pull_coin_btn = Button.new()
	Icons.decorate_button(pull_coin_btn, "coin", "1,000코인 뽑기")
	pull_coin_btn.pressed.connect(func() -> void: _on_pull("coins"))
	_wire_button(pull_coin_btn)
	buttons.add_child(pull_coin_btn)
	pull_ticket_btn = Button.new()
	Icons.decorate_button(pull_ticket_btn, "ticket", "티켓 뽑기")
	pull_ticket_btn.pressed.connect(func() -> void: _on_pull("ticket"))
	_wire_button(pull_ticket_btn)
	buttons.add_child(pull_ticket_btn)
	pull_ten_btn = Button.new()
	Icons.decorate_button(pull_ten_btn, "coin", "10,000코인 10연")
	pull_ten_btn.pressed.connect(_on_pull_ten)
	_wire_button(pull_ten_btn)
	buttons.add_child(pull_ten_btn)
	spark_btn = Button.new()
	Icons.decorate_button(spark_btn, "sparkle", "스파크 교환")
	spark_btn.pressed.connect(func() -> void: Sfx.play("click"); spark_popup.popup_centered())
	_wire_button(spark_btn)
	buttons.add_child(spark_btn)

	status_label = Label.new()
	status_label.add_theme_color_override("font_color", ThemeSetup.C_WARN)
	root.add_child(status_label)

	# ─ 결과 영역 (idle 무대는 상단 정렬이라 result_area가 늘어나도 바·텍스트가
	# 위로 모이고, 확률 공시 토글이 바로 아래 붙도록 min 높이를 압축한다)
	result_area = VBoxContainer.new()
	result_area.alignment = BoxContainer.ALIGNMENT_CENTER
	result_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	result_area.custom_minimum_size = Vector2(0, 230)
	root.add_child(result_area)
	_show_idle_stage()

	# ─ 확률 공시 (접기/펼치기)
	odds_toggle = Button.new()
	odds_toggle.text = "확률 공시 ▸"
	odds_toggle.pressed.connect(_on_odds_toggle)
	_wire_button(odds_toggle)
	root.add_child(odds_toggle)
	odds_box = VBoxContainer.new()
	odds_box.visible = false
	root.add_child(odds_box)
	_build_odds_rows()

	# ─ 에픽+ 배경 플래시 (최상단, 입력 통과)
	flash_rect = ColorRect.new()
	flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash_rect.color = Color(1, 1, 1, 0)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash_rect)

	_build_spark_popup()


func _build_odds_rows() -> void:
	var total := 0.0
	for def in Characters.ROSTER:
		total += float(def.get("weight", 0.0))
	for def in Characters.ROSTER:
		var rarity := String(def.get("rarity", "common"))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var name_l := Label.new()
		name_l.text = "%s (%s)" % [String(def.get("name", "?")), Characters.rarity_label(rarity)]
		name_l.custom_minimum_size = Vector2(220, 0)
		name_l.add_theme_color_override("font_color", ThemeSetup.RARITY_COLORS.get(rarity, ThemeSetup.C_TEXT))
		row.add_child(name_l)
		var pct := Label.new()
		pct.text = "%.3f%%" % (float(def.get("weight", 0.0)) / total * 100.0)
		pct.add_theme_color_override("font_color", ThemeSetup.C_MUTED)
		row.add_child(pct)
		odds_box.add_child(row)
	var note := Label.new()
	note.text = "천장: 10연 내 에픽 이상 보장 · 31연부터 레전더리 확률 +10%p/회 · 40연 하드 천장 · 100스파크 = 원하는 친구 선택"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", ThemeSetup.C_MUTED)
	odds_box.add_child(note)


func _build_spark_popup() -> void:
	spark_popup = PopupPanel.new()
	add_child(spark_popup)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	spark_popup.add_child(box)
	var t := Icons.labeled("sparkle", "스파크 교환 — 원하는 친구를 선택하세요 (스파크 %d 소모)" % Gacha.SPARK_TARGET, ThemeSetup.C_TEXT, 18)
	box.add_child(t)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	box.add_child(grid)
	for def in Characters.ROSTER:
		var id := String(def.get("id", ""))
		var rarity := String(def.get("rarity", "common"))
		var cell := VBoxContainer.new()
		cell.alignment = BoxContainer.ALIGNMENT_CENTER
		var thumb_wrap := CenterContainer.new()
		thumb_wrap.add_child(_make_thumb(id, 56))
		cell.add_child(thumb_wrap)
		var pick := Button.new()
		pick.text = "%s\n%s" % [String(def.get("name", "?")), Characters.rarity_label(rarity)]
		pick.pressed.connect(_on_spark_pick.bind(id))
		_wire_button(pick)
		cell.add_child(pick)
		grid.add_child(cell)


# -----------------------------------------------------------------------------
# 동작
# -----------------------------------------------------------------------------
func _on_pull(pay: String) -> void:
	var r: Dictionary = ProgressStore.gacha_pull(pay)
	if not bool(r.get("ok", false)):
		_show_status(_reason_text(String(r.get("reason", ""))))
		return
	Sfx.play("gacha_spin")
	_show_status("")
	_show_single_result(String(r.get("id", "")), String(r.get("rarity", "common")))


func _on_pull_ten() -> void:
	if ProgressStore.get_coins() < Gacha.PULL_COST_COIN * 10:
		_show_status("코인이 부족해요 (10연은 %s코인)" % ThemeSetup.fmt_int(Gacha.PULL_COST_COIN * 10))
		return
	var results: Array[Dictionary] = []
	for i in 10:
		var r: Dictionary = ProgressStore.gacha_pull("coins")
		if not bool(r.get("ok", false)):
			# Shouldn't happen after the pre-check, but never leave the player
			# part-charged: refund the unpulled remainder and show what we got.
			ProgressStore.add_coins((10 - results.size()) * Gacha.PULL_COST_COIN)
			break
		results.append(r)
	if results.is_empty():
		_show_status("코인이 부족해요")
		return
	Sfx.play("gacha_spin")
	_show_status("")
	_show_ten_results(results)


func _on_spark_pick(id: String) -> void:
	spark_popup.hide()
	var r: Dictionary = ProgressStore.spark_redeem(id)
	if not bool(r.get("ok", false)):
		_show_status(_reason_text(String(r.get("reason", ""))))
		return
	Sfx.play("gacha_spin")
	_show_status("스파크 교환 완료!")
	_show_single_result(String(r.get("id", "")), String(r.get("rarity", "common")))


func _on_odds_toggle() -> void:
	Sfx.play("click")
	odds_box.visible = not odds_box.visible
	odds_toggle.text = "확률 공시 ▾" if odds_box.visible else "확률 공시 ▸"


# -----------------------------------------------------------------------------
# 결과 연출
# -----------------------------------------------------------------------------
func _show_single_result(id: String, rarity: String) -> void:
	_clear_results()
	var center := CenterContainer.new()
	result_area.add_child(center)
	var card := _make_result_card(id, 128, 22)
	center.add_child(card)
	if Characters.rarity_rank(rarity) >= Characters.rarity_rank("epic"):
		_flash(ThemeSetup.RARITY_COLORS.get(rarity, Color.WHITE))
	_pop_in(card, 0.0)
	_reward_feedback(rarity, card)
	_add_close_button()


func _show_ten_results(results: Array[Dictionary]) -> void:
	_clear_results()
	var center := CenterContainer.new()
	result_area.add_child(center)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	center.add_child(grid)
	var best_rank := -1
	var best_rarity := ""
	for i in results.size():
		var rarity := String(results[i].get("rarity", "common"))
		if Characters.rarity_rank(rarity) > best_rank:
			best_rank = Characters.rarity_rank(rarity)
			best_rarity = rarity
		var card := _make_result_card(String(results[i].get("id", "")), 56, 14)
		grid.add_child(card)
		_pop_in(card, 0.06 * i)
	if best_rank >= Characters.rarity_rank("epic"):
		_flash(ThemeSetup.RARITY_COLORS.get(best_rarity, Color.WHITE))
	_reward_feedback(best_rarity, self)
	_add_close_button()


func _make_result_card(id: String, thumb_size: int, font_size: int) -> PanelContainer:
	var def := Characters.get_def(id)
	var rarity := String(def.get("rarity", "common"))
	var card := PanelContainer.new()
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)
	var thumb_wrap := CenterContainer.new()
	thumb_wrap.add_child(_make_thumb(id, thumb_size))
	box.add_child(thumb_wrap)
	var name_l := Label.new()
	name_l.text = String(def.get("name", "?"))
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.add_theme_font_size_override("font_size", font_size)
	box.add_child(name_l)
	var rarity_l := Label.new()
	rarity_l.text = Characters.rarity_label(rarity)
	rarity_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rarity_l.add_theme_color_override("font_color", ThemeSetup.RARITY_COLORS.get(rarity, ThemeSetup.C_TEXT))
	box.add_child(rarity_l)
	return card


func _pop_in(node: Control, delay: float) -> void:
	node.scale = Vector2(0.05, 0.05)
	await get_tree().process_frame
	if not is_instance_valid(node):
		return
	node.pivot_offset = node.size / 2.0
	var tw := create_tween()
	tw.tween_property(node, "scale", Vector2.ONE, 0.7) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT).set_delay(delay)


# 결과 희귀도별 효과음 + 연출. 레전더리만 hitstop으로 임팩트를 준다.
# 엘라스틱 등장이 차오를 즈음(≈0.35s)에 징글을 울린다.
func _reward_feedback(rarity: String, node: Node) -> void:
	var delay := 0.35
	var t := create_tween()
	t.tween_interval(delay)
	t.tween_callback(func() -> void:
		Sfx.play("gacha_" + rarity)
		if is_instance_valid(node) and node is Control:
			Juice.sparkle(node as Control))
	if rarity == "legendary":
		Juice.hitstop(self, 0.10)


func _wire_button(btn: Button) -> void:
	# n2: 크림 버튼 위 아이콘이 흰색 기본틴트로 묻히지 않게 C_TEXT로 틴트해 대비 확보.
	for s in ["icon_normal_color", "icon_hover_color", "icon_pressed_color"]:
		btn.add_theme_color_override(s, ThemeSetup.C_TEXT)
	btn.mouse_entered.connect(Juice.hover.bind(btn, true))
	btn.mouse_exited.connect(Juice.hover.bind(btn, false))
	btn.pressed.connect(Juice.punch.bind(btn))


func _flash(color: Color) -> void:
	flash_rect.color = Color(color.r, color.g, color.b, 0.0)
	var tw := create_tween()
	tw.tween_property(flash_rect, "color:a", 0.5, 0.08)
	tw.tween_property(flash_rect, "color:a", 0.0, 0.5)


func _clear_results() -> void:
	dex_summary_label = null
	dex_gauge = null
	spark_status_label = null
	spark_gauge = null
	for child in result_area.get_children():
		child.queue_free()


# 뽑기 전(idle) 무대 — 캡슐머신 + 도감 요약 + 스파크 게이지로 빈 공백을 채운다.
# 결과가 나오면 _clear_results()로 치워지고, 결과를 닫으면 다시 이 무대로 돌아온다.
func _show_idle_stage() -> void:
	_clear_results()
	# m-gacha: 일러스트·바·텍스트 블록을 상단으로 모아 하단 빈 공백을 줄인다.
	var stage := VBoxContainer.new()
	stage.alignment = BoxContainer.ALIGNMENT_BEGIN
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_theme_constant_override("separation", 8)
	result_area.add_child(stage)

	# ─ 캡슐머신 (가벼운 상하 bob 트윈)
	if ResourceLoader.exists(GACHA_MACHINE_PATH):
		var machine_wrap := CenterContainer.new()
		var machine := TextureRect.new()
		machine.texture = load(GACHA_MACHINE_PATH)
		# 머신을 ~15% 키워 빈 세로 공백을 채우고 히어로를 강조한다. CenterContainer +
		# stage VBox 흐름 안이라, 짧은 화면에서도 게이지/CTA를 밀어내지 덮지 않는다.
		machine.custom_minimum_size = Vector2(230, 230)
		machine.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		machine.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		machine_wrap.add_child(machine)
		stage.add_child(machine_wrap)
		var bob := create_tween().set_loops()
		bob.tween_property(machine, "position:y", -6.0, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		bob.tween_property(machine, "position:y", 0.0, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var hint := Label.new()
	hint.text = "뽑기 버튼을 눌러 새 친구를 만나 보세요!"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", ThemeSetup.C_MUTED)
	stage.add_child(hint)

	# ─ 1차 CTA (화면 주인공인 머신 바로 아래 큰 코랄 버튼 — 위계 정상화, 리뷰 M5)
	var cta_wrap := CenterContainer.new()
	var cta := Button.new()
	Icons.decorate_button(cta, "gacha", "1,000코인 뽑기")
	cta.custom_minimum_size = Vector2(240, 54)
	cta.add_theme_font_size_override("font_size", 18)
	var cta_sb := ThemeSetup.card(ThemeSetup.C_ACCENT, ThemeSetup.C_ACCENT.darkened(0.14), 14, true)
	cta.add_theme_stylebox_override("normal", cta_sb)
	cta.add_theme_stylebox_override("hover", ThemeSetup.card(ThemeSetup.C_ACCENT.lightened(0.06), ThemeSetup.C_ACCENT.darkened(0.14), 14, true))
	cta.add_theme_stylebox_override("pressed", ThemeSetup.card(ThemeSetup.C_ACCENT.darkened(0.08), ThemeSetup.C_ACCENT.darkened(0.2), 14, false))
	cta.add_theme_color_override("font_color", ThemeSetup.C_INK)
	cta.pressed.connect(func() -> void: _on_pull("coins"))
	_wire_button(cta)
	cta_wrap.add_child(cta)
	stage.add_child(cta_wrap)

	# ─ 도감 수집 요약 (+ 컴플리트 시 골드 강조)
	dex_summary_label = Label.new()
	dex_summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dex_summary_label.add_theme_font_size_override("font_size", 18)
	dex_summary_label.add_theme_color_override("font_color", ThemeSetup.C_TEXT)
	stage.add_child(dex_summary_label)

	# ─ 도감 진행바 (연한 트랙이 항상 보이고, 만석이면 골드 채움)
	var dex_wrap := CenterContainer.new()
	dex_gauge = ProgressBar.new()
	dex_gauge.show_percentage = false
	dex_gauge.custom_minimum_size = Vector2(240, 12)
	dex_gauge.max_value = maxi(1, Characters.ROSTER.size())
	_style_track(dex_gauge)
	dex_wrap.add_child(dex_gauge)
	stage.add_child(dex_wrap)

	# ─ 스파크 라벨 + 게이지 (스파크가 충분하면 골드 채움 + "교환 가능!")
	spark_status_label = Label.new()
	spark_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spark_status_label.add_theme_color_override("font_color", ThemeSetup.C_MUTED)
	stage.add_child(spark_status_label)

	var gauge_wrap := CenterContainer.new()
	spark_gauge = ProgressBar.new()
	spark_gauge.show_percentage = false
	spark_gauge.custom_minimum_size = Vector2(240, 12)
	spark_gauge.max_value = Gacha.SPARK_TARGET
	_style_track(spark_gauge)
	gauge_wrap.add_child(spark_gauge)
	stage.add_child(gauge_wrap)

	_refresh_idle_stage()


# 진행바에 연한 트랙(C_PANEL_2)을 깔아 100%일 때 구분선처럼 보이지 않게 한다.
func _style_track(bar: ProgressBar) -> void:
	bar.add_theme_stylebox_override("background",
		ThemeSetup.card(ThemeSetup.C_PANEL_2, ThemeSetup.C_BORDER, 8, false))


# 완료면 done_color로 채움(기본 골드), 아니면 기본 코랄 채움.
# 도감 컴플리트(수동적 성취)와 스파크 교환가능(능동적 CTA)을 색으로 구분하려고
# done_color를 호출처에서 주입한다 — 도감은 민트, 스파크는 골드/코랄.
func _fill_color(bar: ProgressBar, done: bool, done_color: Color = ThemeSetup.RARITY_COLORS["legendary"]) -> void:
	var c: Color = done_color if done else ThemeSetup.C_ACCENT
	bar.add_theme_stylebox_override("fill",
		ThemeSetup.card(c, c.darkened(0.12), 8, false))


func _refresh_idle_stage() -> void:
	var owned := ProgressStore.owned_ids().size()
	var total := Characters.ROSTER.size()
	var dex_done := total > 0 and owned >= total
	if is_instance_valid(dex_summary_label):
		dex_summary_label.text = ("도감 컴플리트! %d / %d" if dex_done else "도감 %d / %d 수집") % [owned, total]
		dex_summary_label.add_theme_color_override("font_color",
			ThemeSetup.RARITY_COLORS["legendary"] if dex_done else ThemeSetup.C_TEXT)
	if is_instance_valid(dex_gauge):
		dex_gauge.value = owned
		# 도감 컴플리트는 차분한 민트(수동적 성취) — 스파크 CTA와 색으로 구분.
		_fill_color(dex_gauge, dex_done, ThemeSetup.C_ACCENT_2)
	var spark := int(ProgressStore.get_pity().get("spark", 0))
	var spark_done := spark >= Gacha.SPARK_TARGET
	if is_instance_valid(spark_gauge):
		spark_gauge.value = mini(spark, Gacha.SPARK_TARGET)  # 100% 초과 오버플로 방지(클램프)
		# 스파크 교환가능은 따뜻한 골드(능동적 교환 CTA) — 도감 민트와 명확히 구분.
		_fill_color(spark_gauge, spark_done, ThemeSetup.RARITY_COLORS["legendary"])
	if is_instance_valid(spark_status_label):
		# 100 초과는 바를 채우되 텍스트로 '교환 N회분 + 여유'를 환산해 보여준다.
		if spark_done:
			var times := spark / Gacha.SPARK_TARGET
			spark_status_label.text = "교환 가능! 스파크 %d (교환 %d회분)" % [spark, times]
		else:
			spark_status_label.text = "스파크 %d / %d" % [spark, Gacha.SPARK_TARGET]
		spark_status_label.add_theme_color_override("font_color",
			ThemeSetup.RARITY_COLORS["legendary"] if spark_done else ThemeSetup.C_MUTED)


# 결과를 닫고 idle 무대로 돌아가는 버튼.
func _add_close_button() -> void:
	var close_wrap := CenterContainer.new()
	var close := Button.new()
	Icons.decorate_button(close, "back", "닫기")
	close.pressed.connect(func() -> void: Sfx.play("click"); _show_idle_stage())
	_wire_button(close)
	close_wrap.add_child(close)
	result_area.add_child(close_wrap)


# -----------------------------------------------------------------------------
# 갱신 · 헬퍼
# -----------------------------------------------------------------------------
func _refresh() -> void:
	coin_label.text = ThemeSetup.fmt_int(ProgressStore.get_coins())
	ticket_label.text = "%d" % ProgressStore.get_tickets()
	var pity: Dictionary = ProgressStore.get_pity()
	var epic_left := maxi(0, Gacha.EPIC_PITY_EVERY - int(pity.get("sinceEpic", 0)))
	var leg_left := maxi(0, Gacha.LEGENDARY_HARD_PITY - int(pity.get("sinceLegendary", 0)))
	pity_label.text = "에픽 보장까지 %d회 · 레전더리 천장까지 %d회 · 스파크 %d/%d" % [
		epic_left, leg_left, int(pity.get("spark", 0)), Gacha.SPARK_TARGET]
	# 위계 단서(보조): 자금/티켓이 모자란 액션은 disabled로 흐려 눌러볼 수 없게 하고,
	# 스파크 교환이 준비되면 연한 코랄 틴트 + "가능" 표시로 살짝 끌어올린다(공짜/가능 액션
	# 을 놓치지 않게). 어디까지나 큰 코랄 CTA보다 조용한 보조 신호로 둔다.
	pull_coin_btn.disabled = ProgressStore.get_coins() < Gacha.PULL_COST_COIN
	pull_ticket_btn.disabled = ProgressStore.get_tickets() < 1
	pull_ten_btn.disabled = ProgressStore.get_coins() < Gacha.PULL_COST_COIN * 10
	var spark_ok := Gacha.spark_ready(pity)
	spark_btn.disabled = not spark_ok
	_set_spark_available(spark_ok)
	_refresh_idle_stage()


# 스파크 교환이 가능할 때만 연한 코랄 배경 + "· 가능" 라벨로 살짝 강조한다(터치엔
# 호버가 없으니 텍스트/배경으로 드러낸다). 불가 시 오버라이드를 제거해 테마 기본
# (disabled 포함) 스타일로 되돌린다. 큰 코랄 CTA보다 조용한 보조 신호로 유지한다.
func _set_spark_available(available: bool) -> void:
	if available:
		spark_btn.text = "스파크 교환 · 가능"
		spark_btn.add_theme_stylebox_override("normal",
			ThemeSetup.card(ThemeSetup.C_ACCENT_SOFT, ThemeSetup.C_ACCENT, 10, false))
	else:
		spark_btn.text = "스파크 교환"
		spark_btn.remove_theme_stylebox_override("normal")


func _show_status(text: String) -> void:
	status_label.text = text


func _reason_text(reason: String) -> String:
	match reason:
		"not_enough_coins":
			return "코인이 부족해요 (1회 %s코인)" % ThemeSetup.fmt_int(Gacha.PULL_COST_COIN)
		"not_enough_tickets":
			return "티켓이 없어요 — 정답 30개마다 1장!"
		"spark_not_ready":
			return "스파크가 아직 %d개 모이지 않았어요" % Gacha.SPARK_TARGET
		"unknown_character":
			return "알 수 없는 친구예요"
		_:
			return "뽑기에 실패했어요 (%s)" % reason


# 캐릭터 썸네일 — 에셋이 있으면 TextureRect, 없으면 id 해시 파스텔 ColorRect 폴백.
func _make_thumb(id: String, size: int = 64) -> Control:
	var path := Characters.sprite_path(id)
	if ResourceLoader.exists(path):
		var tr := TextureRect.new()
		tr.texture = load(path)
		tr.custom_minimum_size = Vector2(size, size)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		return tr
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(size, size)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.from_hsv(float(absi(hash(id)) % 360) / 360.0, 0.30, 0.92)
	sb.set_corner_radius_all(int(size / 4.0))
	panel.add_theme_stylebox_override("panel", sb)
	var letter := Label.new()
	letter.text = String(Characters.get_def(id).get("name", "?")).left(1)
	letter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	letter.add_theme_font_size_override("font_size", maxi(12, int(size * 0.38)))
	letter.add_theme_color_override("font_color", Color(0.13, 0.14, 0.18))
	panel.add_child(letter)
	return panel


