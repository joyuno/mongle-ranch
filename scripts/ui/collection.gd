# 도감 화면 — [도감] 12종 수집 현황(미보유 실루엣) + [내 친구들] 보유 개체 관리
# (목장 표시 토글 · 융합 · 일괄 융합 · 교배). 코드-우선 UI, collection_changed 시그널 구독.
extends Control

const RANCH_SCENE := "res://scenes/Ranch.tscn"
const TINT_SHADER := "res://assets/shaders/tint.gdshader"

var tabs: TabContainer
var dex_grid: GridContainer
var friends_list: VBoxContainer
var detail_box: VBoxContainer
var status_label: Label
var merge_popup: PopupPanel
var merge_list: VBoxContainer
var merge_confirm: ConfirmationDialog
var breed_popup: PopupPanel
var breed_list: VBoxContainer
var breed_title: Label
var breed_confirm: ConfirmationDialog
var selected_uid: int = -1
var pending_src_uid: int = -1
var breed_a_uid: int = -1   # 교배 1단계로 고른 부모(없으면 -1)
var pending_breed_b_uid: int = -1


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

	# ─ 융합 재료 선택 팝업 (같은 종·같은 등급만 나열)
	merge_popup = PopupPanel.new()
	add_child(merge_popup)
	var merge_root := VBoxContainer.new()
	merge_root.add_theme_constant_override("separation", 8)
	merge_popup.add_child(merge_root)
	var merge_title := Label.new()
	merge_title.text = "융합 재료를 고르세요 — 같은 등급 2개가 ★N+1 한 마리가 됩니다.\n재료 개체는 사라지고 되돌릴 수 없어요."
	merge_root.add_child(merge_title)
	merge_list = VBoxContainer.new()
	merge_list.add_theme_constant_override("separation", 6)
	merge_root.add_child(merge_list)

	# ─ 융합 확인 다이얼로그
	merge_confirm = ConfirmationDialog.new()
	merge_confirm.title = "융합 확인"
	merge_confirm.ok_button_text = "융합한다"
	merge_confirm.cancel_button_text = "취소"
	merge_confirm.confirmed.connect(_on_merge_confirmed)
	add_child(merge_confirm)

	# ─ 교배 부모 선택 팝업 (A → B 두 번 고른다)
	breed_popup = PopupPanel.new()
	add_child(breed_popup)
	var breed_root := VBoxContainer.new()
	breed_root.add_theme_constant_override("separation", 8)
	breed_popup.add_child(breed_root)
	breed_title = Label.new()
	breed_root.add_child(breed_title)
	var breed_scroll := ScrollContainer.new()
	breed_scroll.custom_minimum_size = Vector2(360, 320)
	breed_root.add_child(breed_scroll)
	breed_list = VBoxContainer.new()
	breed_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	breed_list.add_theme_constant_override("separation", 6)
	breed_scroll.add_child(breed_list)

	# ─ 교배 확인 다이얼로그
	breed_confirm = ConfirmationDialog.new()
	breed_confirm.title = "교배 확인"
	breed_confirm.ok_button_text = "교배한다"
	breed_confirm.cancel_button_text = "취소"
	breed_confirm.confirmed.connect(_on_breed_confirmed)
	add_child(breed_confirm)


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
	# id → { count, max_level, max_grade } 집계 — 등급은 새 희귀도 증폭 축이라 같이 집계.
	var stats: Dictionary = {}
	for e in ProgressStore.get_collection():
		var id := String(e.get("id", ""))
		var s: Dictionary = stats.get(id, { "count": 0, "max_level": 0, "max_grade": 1 })
		s["count"] = int(s["count"]) + 1
		s["max_level"] = maxi(int(s["max_level"]), int(e.get("level", 1)))
		s["max_grade"] = maxi(int(s["max_grade"]), int(e.get("grade", 1)))
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
	# 보유 시 최고 등급 ★을 골드로 — 같은 종도 등급에 따라 가치가 갈리는 새 축이라 스캔되게.
	if owned:
		box.add_child(_make_grade_label(int(stat.get("max_grade", 1)), HORIZONTAL_ALIGNMENT_CENTER))
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
	# ─ 상단 액션: 교배(부모 2마리 + 코인 → 자식 1마리). 보유가 2마리 이상일 때만.
	var breed_btn := Button.new()
	Icons.decorate_button(breed_btn, "sparkle", "교배 (부모 2마리 + %d코인 → 새 친구)" % Breeding.COIN_COST)
	breed_btn.disabled = col.size() < 2
	breed_btn.pressed.connect(_open_breed_popup)
	_wire_button(breed_btn)
	friends_list.add_child(breed_btn)
	for e in col:
		var uid := int(e.get("uid", -1))
		var id := String(e.get("id", ""))
		var def := Characters.get_def(id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(_make_thumb(id, 36, int(e.get("tint", 0))))
		var btn := Button.new()
		btn.text = "%s %s Lv.%d%s · %s" % [String(def.get("name", "?")),
			Grade.stars(int(e.get("grade", 1))), int(e.get("level", 1)),
			" 반짝" if bool(e.get("variant", false)) else "",
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
	var grade := int(e.get("grade", 1))
	var variant := bool(e.get("variant", false))

	var thumb_wrap := CenterContainer.new()
	thumb_wrap.add_child(_make_thumb(id, 120, int(e.get("tint", 0))))
	detail_box.add_child(thumb_wrap)
	var name_l := Label.new()
	name_l.text = "%s Lv.%d" % [String(def.get("name", "?")), int(e.get("level", 1))]
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.add_theme_font_size_override("font_size", 22)
	detail_box.add_child(name_l)
	# 등급 ★ + 반짝 — 이름 바로 아래에 골드로(희귀도 증폭 축을 또렷이).
	detail_box.add_child(_make_grade_label(grade, HORIZONTAL_ALIGNMENT_CENTER, variant))
	var rarity_l := Label.new()
	rarity_l.text = Characters.rarity_label(rarity)
	rarity_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rarity_l.add_theme_color_override("font_color", ThemeSetup.RARITY_COLORS.get(rarity, ThemeSetup.C_TEXT))
	detail_box.add_child(rarity_l)
	var meta := Label.new()
	var tint_note := "\n교배 개체 (색조 보유)" if int(e.get("tint", 0)) > 0 else ""
	meta.text = "획득일: %s\n%s%s" % [String(e.get("obtainedAt", "")).left(10), String(def.get("motif", "")), tint_note]
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

	# ─ 융합: 같은 종·같은 등급 재료가 있고 ★5가 아닐 때만 활성.
	var fusible := _fuse_candidates(id, grade, selected_uid)
	var can_fuse := Grade.can_fuse(grade) and not fusible.is_empty()
	var fuse_btn := Button.new()
	Icons.decorate_button(fuse_btn, "merge", "융합 (같은 ★ 2개 → ★%d)" % Grade.clamp_grade(grade + 1))
	fuse_btn.disabled = not can_fuse
	fuse_btn.pressed.connect(_open_merge_popup)
	_wire_button(fuse_btn)
	detail_box.add_child(fuse_btn)

	# ─ 일괄 융합: 이 종의 같은 등급 중복쌍을 한 번에 모두 융합.
	var batch_btn := Button.new()
	Icons.decorate_button(batch_btn, "merge", "일괄 융합 (중복쌍 자동)")
	batch_btn.disabled = not _has_any_fusible_pair(id)
	batch_btn.pressed.connect(_on_batch_fuse.bind(id))
	_wire_button(batch_btn)
	detail_box.add_child(batch_btn)

	if not Grade.can_fuse(grade):
		var maxed := Label.new()
		maxed.text = "이미 ★%d — 더 융합할 수 없는 최고 등급이에요" % Grade.MAX
		maxed.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		maxed.add_theme_color_override("font_color", ThemeSetup.C_MUTED)
		maxed.add_theme_font_size_override("font_size", 13)
		detail_box.add_child(maxed)
	elif fusible.is_empty():
		var no_dupe := Label.new()
		no_dupe.text = "융합하려면 같은 종류·같은 ★ 친구가 1마리 더 필요해요"
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
# 융합 (같은 종·같은 등급 2개 → ★+1)
# -----------------------------------------------------------------------------
# 선택 개체와 같은 종·같은 등급인 다른 개체들(융합 재료 후보).
func _fuse_candidates(id: String, grade: int, except_uid: int) -> Array:
	var out: Array = []
	for e in ProgressStore.get_collection():
		if String(e.get("id", "")) == id and int(e.get("grade", 1)) == grade \
				and int(e.get("uid", -1)) != except_uid:
			out.append(e)
	return out


# 그 종에 같은 등급 중복쌍이 (★5 미만으로) 하나라도 있는지 — 일괄 융합 활성 판단.
func _has_any_fusible_pair(id: String) -> bool:
	var by_grade: Dictionary = {}
	for e in ProgressStore.get_collection():
		if String(e.get("id", "")) != id or not Grade.can_fuse(int(e.get("grade", 1))):
			continue
		var g := int(e.get("grade", 1))
		by_grade[g] = int(by_grade.get(g, 0)) + 1
		if int(by_grade[g]) >= 2:
			return true
	return false


func _open_merge_popup() -> void:
	for child in merge_list.get_children():
		child.queue_free()
	var dst := ProgressStore.get_character(selected_uid)
	var id := String(dst.get("id", ""))
	var grade := int(dst.get("grade", 1))
	for e in _fuse_candidates(id, grade, selected_uid):
		var src_uid := int(e.get("uid", -1))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(_make_thumb(id, 32, int(e.get("tint", 0))))
		var btn := Button.new()
		btn.text = "%s Lv.%d%s · 획득 %s" % [Grade.stars(int(e.get("grade", 1))), int(e.get("level", 1)),
			" 반짝" if bool(e.get("variant", false)) else "", String(e.get("obtainedAt", "")).left(10)]
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
	var grade := int(dst.get("grade", 1))
	merge_confirm.dialog_text = "%s %s 개체가 영원히 사라지고\n선택한 %s %s가 ★%d가 됩니다.\n\n되돌릴 수 없어요!" % [
		String(def.get("name", "?")), Grade.stars(int(src.get("grade", 1))),
		String(def.get("name", "?")), Grade.stars(grade), Grade.clamp_grade(grade + 1)]
	merge_confirm.popup_centered()


func _on_merge_confirmed() -> void:
	var r: Dictionary = ProgressStore.fuse_characters(pending_src_uid, selected_uid)
	pending_src_uid = -1
	if bool(r.get("ok", false)):
		Sfx.play("levelup")
		status_label.text = "융합 완료! %s%s가 되었어요" % [Grade.stars(int(r.get("grade", 1))),
			" 반짝" if bool(r.get("variant", false)) else ""]
	else:
		status_label.text = "융합에 실패했어요 (%s)" % _fuse_reason_ko(String(r.get("reason", "")))


func _on_batch_fuse(id: String) -> void:
	var r: Dictionary = ProgressStore.batch_fuse(id)
	if bool(r.get("ok", false)):
		Sfx.play("levelup")
		status_label.text = "%d회 융합했어요" % int(r.get("fused", 0))
	else:
		status_label.text = "융합할 중복쌍이 없어요"


func _fuse_reason_ko(reason: String) -> String:
	match reason:
		"same_character": return "같은 개체끼리는 융합할 수 없어요"
		"not_found": return "개체를 찾을 수 없어요"
		"different_species": return "다른 종류는 융합할 수 없어요"
		"different_grade": return "등급이 달라요"
		"max_grade": return "이미 최고 등급이에요"
		_: return reason


# -----------------------------------------------------------------------------
# 교배 (부모 2마리 + 코인 → 자식 1마리)
# -----------------------------------------------------------------------------
func _open_breed_popup() -> void:
	Sfx.play("click")
	breed_a_uid = -1   # A부터 다시 고른다
	_rebuild_breed_list()
	breed_popup.popup_centered()


# 부모 후보 목록을 다시 그린다. A 미선택이면 1단계, 선택했으면 2단계(A 제외).
func _rebuild_breed_list() -> void:
	for child in breed_list.get_children():
		child.queue_free()
	if breed_a_uid < 0:
		breed_title.text = "교배할 첫 번째 부모를 고르세요 (1/2)"
	else:
		var a := ProgressStore.get_character(breed_a_uid)
		var a_def := Characters.get_def(String(a.get("id", "")))
		breed_title.text = "첫 부모: %s %s — 두 번째 부모를 고르세요 (2/2)" % [
			String(a_def.get("name", "?")), Grade.stars(int(a.get("grade", 1)))]
	for e in ProgressStore.get_collection():
		var uid := int(e.get("uid", -1))
		if uid == breed_a_uid:
			continue   # 같은 개체를 두 부모로 쓸 수 없음
		var id := String(e.get("id", ""))
		var def := Characters.get_def(id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(_make_thumb(id, 32, int(e.get("tint", 0))))
		var btn := Button.new()
		btn.text = "%s %s Lv.%d%s" % [String(def.get("name", "?")), Grade.stars(int(e.get("grade", 1))),
			int(e.get("level", 1)), " 반짝" if bool(e.get("variant", false)) else ""]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_on_breed_parent_picked.bind(uid))
		_wire_button(btn)
		row.add_child(btn)
		breed_list.add_child(row)


func _on_breed_parent_picked(uid: int) -> void:
	Sfx.play("click")
	if breed_a_uid < 0:
		breed_a_uid = uid
		_rebuild_breed_list()   # 2단계로
		return
	# 2단계 — B 확정 → 확인 다이얼로그.
	breed_popup.hide()
	pending_breed_b_uid = uid
	var a := ProgressStore.get_character(breed_a_uid)
	var b := ProgressStore.get_character(uid)
	var a_def := Characters.get_def(String(a.get("id", "")))
	var b_def := Characters.get_def(String(b.get("id", "")))
	breed_confirm.dialog_text = "%s %s + %s %s\n부모 2마리와 %d코인을 소모하고 부모는 사라집니다.\n\n되돌릴 수 없어요!" % [
		String(a_def.get("name", "?")), Grade.stars(int(a.get("grade", 1))),
		String(b_def.get("name", "?")), Grade.stars(int(b.get("grade", 1))), Breeding.COIN_COST]
	breed_confirm.popup_centered()


func _on_breed_confirmed() -> void:
	var r: Dictionary = ProgressStore.breed_characters(breed_a_uid, pending_breed_b_uid)
	breed_a_uid = -1
	pending_breed_b_uid = -1
	if bool(r.get("ok", false)):
		Sfx.play("levelup")
		selected_uid = int(r.get("uid", -1))   # 자식을 상세 패널에 띄운다
		var def := Characters.get_def(String(r.get("id", "")))
		status_label.text = "교배 성공! %s %s%s 새 친구가 태어났어요" % [
			String(def.get("name", "?")), Grade.stars(int(r.get("grade", 1))),
			" 반짝" if bool(r.get("variant", false)) else ""]
	else:
		status_label.text = "교배에 실패했어요 (%s)" % _breed_reason_ko(String(r.get("reason", "")))


func _breed_reason_ko(reason: String) -> String:
	match reason:
		"same_character": return "같은 개체끼리는 교배할 수 없어요"
		"not_found": return "개체를 찾을 수 없어요"
		"not_enough_coins": return "코인이 부족해요 (%d코인 필요)" % Breeding.COIN_COST
		_: return reason


# -----------------------------------------------------------------------------
# 헬퍼
# -----------------------------------------------------------------------------
func _wire_button(btn: Button) -> void:
	btn.mouse_entered.connect(Juice.hover.bind(btn, true))
	btn.mouse_exited.connect(Juice.hover.bind(btn, false))
	btn.pressed.connect(Juice.punch.bind(btn))


# 등급 ★ 라벨 — 골드(legendary 색)로. variant면 뒤에 "반짝" 표식을 같은 골드로 붙인다.
func _make_grade_label(grade: int, align: int, variant: bool = false) -> Label:
	var lbl := Label.new()
	lbl.text = Grade.stars(grade) + ("  반짝" if variant else "")
	lbl.horizontal_alignment = align
	lbl.add_theme_color_override("font_color", ThemeSetup.RARITY_COLORS["legendary"])
	return lbl


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
# tint>0(교배 색조)이면 hue-rotate 셰이더를 입힌다(0=원본 색, material 미부여).
func _make_thumb(id: String, size: int = 64, tint: int = 0) -> Control:
	var path := Characters.sprite_path(id)
	if ResourceLoader.exists(path):
		var tr := TextureRect.new()
		tr.texture = load(path)
		tr.custom_minimum_size = Vector2(size, size)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if tint > 0:
			var mat := ShaderMaterial.new()
			mat.shader = load(TINT_SHADER)
			mat.set_shader_parameter("hue_shift", float(tint) / 360.0)
			tr.material = mat
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
