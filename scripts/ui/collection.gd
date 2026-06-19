# 도감 화면 — [도감] 12종 수집 현황(미보유 실루엣) + [내 친구들] 보유 개체 관리
# (목장 표시 토글 · 합성). 코드-우선 UI, collection_changed 시그널 구독.
extends Control

const RANCH_SCENE := "res://scenes/Ranch.tscn"

var tabs: TabContainer
var dex_grid: GridContainer
var friends_list: VBoxContainer
var detail_box: VBoxContainer
var status_label: Label
var merge_popup: PopupPanel
var merge_list: VBoxContainer
var merge_confirm: ConfirmationDialog
var selected_uid: int = -1
var pending_src_uid: int = -1


func _ready() -> void:
	_build_ui()
	ProgressStore.collection_changed.connect(_refresh)
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
	var title := Icons.labeled("collection", "도감", ThemeSetup.C_TEXT, 24)
	(title.get_child(1) as Label).add_theme_font_size_override("font_size", 24)
	bar.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	status_label = Label.new()
	status_label.add_theme_color_override("font_color", ThemeSetup.C_WARN)
	bar.add_child(status_label)

	# ─ 탭
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)

	# [도감] 탭
	var dex_scroll := ScrollContainer.new()
	dex_scroll.name = "도감"
	tabs.add_child(dex_scroll)
	dex_grid = GridContainer.new()
	dex_grid.columns = 4
	dex_grid.add_theme_constant_override("h_separation", 12)
	dex_grid.add_theme_constant_override("v_separation", 12)
	dex_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dex_scroll.add_child(dex_grid)

	# [내 친구들] 탭
	var friends := HBoxContainer.new()
	friends.name = "내 친구들"
	friends.add_theme_constant_override("separation", 16)
	tabs.add_child(friends)
	var list_scroll := ScrollContainer.new()
	list_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.size_flags_stretch_ratio = 1.2
	friends.add_child(list_scroll)
	friends_list = VBoxContainer.new()
	friends_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	friends_list.add_theme_constant_override("separation", 6)
	list_scroll.add_child(friends_list)
	var detail_panel := PanelContainer.new()
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	friends.add_child(detail_panel)
	detail_box = VBoxContainer.new()
	detail_box.add_theme_constant_override("separation", 8)
	detail_panel.add_child(detail_box)

	# ─ 합성 대상 선택 팝업
	merge_popup = PopupPanel.new()
	add_child(merge_popup)
	var merge_root := VBoxContainer.new()
	merge_root.add_theme_constant_override("separation", 8)
	merge_popup.add_child(merge_root)
	var merge_title := Label.new()
	merge_title.text = "합성 재료를 선택하세요 — 선택한 개체는 사라지고 레벨이 합산됩니다"
	merge_root.add_child(merge_title)
	merge_list = VBoxContainer.new()
	merge_list.add_theme_constant_override("separation", 6)
	merge_root.add_child(merge_list)

	# ─ 합성 확인 다이얼로그
	merge_confirm = ConfirmationDialog.new()
	merge_confirm.title = "합성 확인"
	merge_confirm.ok_button_text = "합성한다"
	merge_confirm.cancel_button_text = "취소"
	merge_confirm.confirmed.connect(_on_merge_confirmed)
	add_child(merge_confirm)


# -----------------------------------------------------------------------------
# 갱신
# -----------------------------------------------------------------------------
func _refresh() -> void:
	_rebuild_dex()
	_rebuild_friends()
	if selected_uid >= 0 and ProgressStore.get_character(selected_uid).is_empty():
		selected_uid = -1
	_rebuild_detail()


func _rebuild_dex() -> void:
	for child in dex_grid.get_children():
		child.queue_free()
	# id → { count, max_level } 집계
	var stats: Dictionary = {}
	for e in ProgressStore.get_collection():
		var id := String(e.get("id", ""))
		var s: Dictionary = stats.get(id, { "count": 0, "max_level": 0 })
		s["count"] = int(s["count"]) + 1
		s["max_level"] = maxi(int(s["max_level"]), int(e.get("level", 1)))
		stats[id] = s
	for def in Characters.ROSTER:
		var id := String(def.get("id", ""))
		dex_grid.add_child(_make_dex_cell(def, stats.get(id, {})))


func _make_dex_cell(def: Dictionary, stat: Dictionary) -> PanelContainer:
	var id := String(def.get("id", ""))
	var rarity := String(def.get("rarity", "common"))
	var owned := not stat.is_empty()
	var cell := PanelContainer.new()
	# m5: 설명 한 줄이 하단에서 잘리지 않게 세로 최소 높이 확보(상하 패딩은 테마 대칭).
	cell.custom_minimum_size = Vector2(260, 210)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 4)
	cell.add_child(box)
	var thumb_wrap := CenterContainer.new()
	var thumb := _make_thumb(id, 96)
	if not owned:
		thumb.modulate = Color(0.42, 0.40, 0.45)  # m4: 통검정 대신 부드러운 회보라 실루엣
	thumb_wrap.add_child(thumb)
	if not owned:
		# m4: 미해금 표시로 작은 lock 아이콘을 실루엣 위에 겹쳐 둔다.
		thumb_wrap.add_child(Icons.make("lock", ThemeSetup.C_MUTED, 28))
	box.add_child(thumb_wrap)
	var name_l := Label.new()
	name_l.text = String(def.get("name", "?")) if owned else "???"
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.add_theme_font_size_override("font_size", 18)
	box.add_child(name_l)
	# m6: 희귀도를 글자색만이 아니라 작은 알약(pill)으로 — 그리드에서 한눈에 스캔되도록.
	#     RARITY_COLORS를 채운 배경으로 쓰고 그 위엔 크림색 글자(채도 높은 바탕이라 대비 충분).
	var rarity_color: Color = ThemeSetup.RARITY_COLORS.get(rarity, ThemeSetup.C_MUTED)
	box.add_child(_make_rarity_pill(rarity, rarity_color))
	var info := Label.new()
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_color_override("font_color", ThemeSetup.C_MUTED)
	info.text = "보유 %d마리 · 최고 Lv.%d" % [int(stat.get("count", 0)), int(stat.get("max_level", 1))] if owned else "아직 만나지 못했어요"
	box.add_child(info)
	if owned:
		var motif := Label.new()
		motif.text = String(def.get("motif", ""))
		motif.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		motif.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		motif.add_theme_color_override("font_color", ThemeSetup.C_MUTED)
		motif.add_theme_font_size_override("font_size", 13)
		box.add_child(motif)
	return cell


func _rebuild_friends() -> void:
	for child in friends_list.get_children():
		child.queue_free()
	var col := ProgressStore.get_collection()
	if col.is_empty():
		var empty := Label.new()
		empty.text = "아직 친구가 없어요 — 가챠에서 만나 보세요!"
		empty.add_theme_color_override("font_color", ThemeSetup.C_MUTED)
		friends_list.add_child(empty)
		return
	for e in col:
		var uid := int(e.get("uid", -1))
		var id := String(e.get("id", ""))
		var def := Characters.get_def(id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(_make_thumb(id, 36))
		var btn := Button.new()
		btn.text = "%s Lv.%d · %s" % [String(def.get("name", "?")), int(e.get("level", 1)),
			String(e.get("obtainedAt", "")).left(10)]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_on_select_friend.bind(uid))
		_wire_button(btn)
		row.add_child(btn)
		friends_list.add_child(row)


func _on_select_friend(uid: int) -> void:
	Sfx.play("click")
	selected_uid = uid
	status_label.text = ""
	_rebuild_detail()
	Juice.pop_in(detail_box)


func _rebuild_detail() -> void:
	for child in detail_box.get_children():
		child.queue_free()
	if selected_uid < 0:
		var hint := Label.new()
		hint.text = "왼쪽에서 친구를 선택하세요"
		hint.add_theme_color_override("font_color", ThemeSetup.C_MUTED)
		detail_box.add_child(hint)
		return
	var e := ProgressStore.get_character(selected_uid)
	var id := String(e.get("id", ""))
	var def := Characters.get_def(id)
	var rarity := String(def.get("rarity", "common"))

	var thumb_wrap := CenterContainer.new()
	thumb_wrap.add_child(_make_thumb(id, 120))
	detail_box.add_child(thumb_wrap)
	var name_l := Label.new()
	name_l.text = "%s Lv.%d" % [String(def.get("name", "?")), int(e.get("level", 1))]
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.add_theme_font_size_override("font_size", 22)
	detail_box.add_child(name_l)
	var rarity_l := Label.new()
	rarity_l.text = Characters.rarity_label(rarity)
	rarity_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rarity_l.add_theme_color_override("font_color", ThemeSetup.RARITY_COLORS.get(rarity, ThemeSetup.C_TEXT))
	detail_box.add_child(rarity_l)
	var meta := Label.new()
	meta.text = "획득일: %s\n%s" % [String(e.get("obtainedAt", "")).left(10), String(def.get("motif", ""))]
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	meta.add_theme_color_override("font_color", ThemeSetup.C_MUTED)
	detail_box.add_child(meta)

	# 목장 표시 토글
	var ranch_toggle := CheckButton.new()
	ranch_toggle.text = "목장에 표시"
	ranch_toggle.set_pressed_no_signal(_ranch_uids().has(selected_uid))
	ranch_toggle.toggled.connect(_on_ranch_toggled)
	detail_box.add_child(ranch_toggle)

	# 합성
	var dupes := _same_id_others(id, selected_uid)
	var merge_btn := Button.new()
	Icons.decorate_button(merge_btn, "merge", "합성 (같은 친구 레벨 합치기)")
	merge_btn.disabled = dupes.is_empty()
	merge_btn.pressed.connect(_open_merge_popup)
	_wire_button(merge_btn)
	detail_box.add_child(merge_btn)
	if dupes.is_empty():
		var no_dupe := Label.new()
		no_dupe.text = "합성하려면 같은 종류의 친구가 1마리 더 필요해요"
		no_dupe.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		no_dupe.add_theme_color_override("font_color", ThemeSetup.C_MUTED)
		no_dupe.add_theme_font_size_override("font_size", 13)
		detail_box.add_child(no_dupe)


# -----------------------------------------------------------------------------
# 목장 표시 토글
# -----------------------------------------------------------------------------
func _ranch_uids() -> Array:
	var uids: Array = []
	for m in ProgressStore.ranch_members():
		uids.append(int(m.get("uid", -1)))
	return uids


func _on_ranch_toggled(pressed: bool) -> void:
	var uids := _ranch_uids()
	if pressed:
		if uids.size() >= ProgressStore.RANCH_DISPLAY_MAX:
			status_label.text = "목장에는 최대 %d마리까지만 표시할 수 있어요" % ProgressStore.RANCH_DISPLAY_MAX
			_rebuild_detail()  # 체크 상태 원복
			return
		if not uids.has(selected_uid):
			uids.append(selected_uid)
	else:
		uids.erase(selected_uid)
	ProgressStore.set_ranch_roster(uids)  # collection_changed → _refresh


# -----------------------------------------------------------------------------
# 합성
# -----------------------------------------------------------------------------
func _same_id_others(id: String, except_uid: int) -> Array:
	var out: Array = []
	for e in ProgressStore.get_collection():
		if String(e.get("id", "")) == id and int(e.get("uid", -1)) != except_uid:
			out.append(e)
	return out


func _open_merge_popup() -> void:
	for child in merge_list.get_children():
		child.queue_free()
	var dst := ProgressStore.get_character(selected_uid)
	for e in _same_id_others(String(dst.get("id", "")), selected_uid):
		var src_uid := int(e.get("uid", -1))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(_make_thumb(String(e.get("id", "")), 32))
		var btn := Button.new()
		btn.text = "Lv.%d · 획득 %s" % [int(e.get("level", 1)), String(e.get("obtainedAt", "")).left(10)]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_merge_src_picked.bind(src_uid))
		_wire_button(btn)
		row.add_child(btn)
		merge_list.add_child(row)
	merge_popup.popup_centered()


func _on_merge_src_picked(src_uid: int) -> void:
	merge_popup.hide()
	pending_src_uid = src_uid
	var src := ProgressStore.get_character(src_uid)
	var dst := ProgressStore.get_character(selected_uid)
	var def := Characters.get_def(String(dst.get("id", "")))
	merge_confirm.dialog_text = "%s Lv.%d 개체가 영원히 사라지고\n선택한 %s Lv.%d에 레벨이 합산됩니다.\n\n되돌릴 수 없어요!" % [
		String(def.get("name", "?")), int(src.get("level", 1)),
		String(def.get("name", "?")), int(dst.get("level", 1))]
	merge_confirm.popup_centered()


func _on_merge_confirmed() -> void:
	var r: Dictionary = ProgressStore.merge_characters(pending_src_uid, selected_uid)
	pending_src_uid = -1
	if bool(r.get("ok", false)):
		Sfx.play("levelup")
		status_label.text = "합성 완료! Lv.%d이 되었어요" % int(r.get("level", 1))
	else:
		status_label.text = "합성에 실패했어요 (%s)" % String(r.get("reason", ""))


# -----------------------------------------------------------------------------
# 헬퍼
# -----------------------------------------------------------------------------
func _wire_button(btn: Button) -> void:
	btn.mouse_entered.connect(Juice.hover.bind(btn, true))
	btn.mouse_exited.connect(Juice.hover.bind(btn, false))
	btn.pressed.connect(Juice.punch.bind(btn))


# 희귀도 알약 — RARITY_COLORS 채운 바탕 + 크림 글자. 가로는 글자에 맞춰 자동(중앙 정렬).
func _make_rarity_pill(rarity: String, color: Color) -> CenterContainer:
	var wrap := CenterContainer.new()
	var pill := PanelContainer.new()
	var sb := ThemeSetup.card(color, color.darkened(0.18), 999, false)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	pill.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.text = Characters.rarity_label(rarity)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", ThemeSetup.C_PANEL)  # 크림색 — 채도 높은 바탕에 대비
	lbl.add_theme_font_size_override("font_size", 14)
	pill.add_child(lbl)
	wrap.add_child(pill)
	return wrap


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
