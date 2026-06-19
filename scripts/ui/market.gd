# 시장 화면 — 오늘 시세·인기일 배너, NPC 매물 구매, 내 친구 판매(일일 3마리).
# 가격 공식은 scripts/domain/market.gd — sell_character와 동일한 식으로 예상가 표시.
extends Control

const RANCH_SCENE := "res://scenes/Ranch.tscn"

var coin_label: HBoxContainer
var coin_label_value: Label
var rate_chip: PanelContainer
var rate_label: Label
var popular_banner: Label
var status_label: Label
var listings_box: HBoxContainer
var sold_label: Label
var sell_list: VBoxContainer
var sell_confirm: ConfirmationDialog
var pending_sell_uid: int = -1


func _ready() -> void:
	ProgressStore.ensure_market_day()
	_build_ui()
	ProgressStore.market_changed.connect(_refresh)
	ProgressStore.collection_changed.connect(_refresh)
	ProgressStore.coins_changed.connect(func(_amount: int) -> void: _refresh())
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
	var title := Icons.labeled("market", "시장", ThemeSetup.C_TEXT, 24)
	(title.get_child(1) as Label).add_theme_font_size_override("font_size", 24)
	bar.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	coin_label = Icons.labeled("coin", "", ThemeSetup.C_TEXT, 18)
	coin_label_value = coin_label.get_child(1) as Label
	coin_label_value.add_theme_font_size_override("font_size", 18)
	bar.add_child(coin_label)

	# ─ 시세 · 인기일
	# 2차 리뷰(minor): 시세 배수를 칩/배지로 승격 — 유불리에 따라 업/다운색.
	var rate_row := HBoxContainer.new()
	root.add_child(rate_row)
	rate_chip = PanelContainer.new()
	rate_chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	rate_label = Label.new()
	rate_label.add_theme_font_size_override("font_size", 18)
	rate_chip.add_child(rate_label)
	rate_row.add_child(rate_chip)
	popular_banner = Label.new()
	popular_banner.add_theme_font_size_override("font_size", 18)
	popular_banner.add_theme_color_override("font_color", ThemeSetup.C_WARN)
	popular_banner.visible = false
	root.add_child(popular_banner)
	status_label = Label.new()
	status_label.add_theme_color_override("font_color", ThemeSetup.C_WARN)
	root.add_child(status_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	# B2: 우측 패딩으로 '판매'/'구매' 버튼이 세로 스크롤바를 침범하지 않게 한다.
	# (2차 리뷰: 16→32 — 판매 버튼이 스크롤바에 너무 근접하던 문제 해소)
	var body_margin := MarginContainer.new()
	body_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_margin.add_theme_constant_override("margin_right", 32)
	body_margin.add_theme_constant_override("margin_left", 0)
	scroll.add_child(body_margin)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	body_margin.add_child(body)

	# ─ NPC 매물
	var npc_title := Icons.labeled("buy", "NPC 매물 (매일 회전)", ThemeSetup.C_TEXT, 20)
	(npc_title.get_child(1) as Label).add_theme_font_size_override("font_size", 20)
	body.add_child(npc_title)
	listings_box = HBoxContainer.new()
	listings_box.add_theme_constant_override("separation", 12)
	body.add_child(listings_box)

	# ─ 내 친구 판매
	var sell_header := HBoxContainer.new()
	sell_header.add_theme_constant_override("separation", 12)
	body.add_child(sell_header)
	var sell_title := Icons.labeled("sell", "내 친구 판매", ThemeSetup.C_TEXT, 20)
	(sell_title.get_child(1) as Label).add_theme_font_size_override("font_size", 20)
	sell_header.add_child(sell_title)
	sold_label = Label.new()
	sold_label.add_theme_color_override("font_color", ThemeSetup.C_MUTED)
	sell_header.add_child(sold_label)
	sell_list = VBoxContainer.new()
	sell_list.add_theme_constant_override("separation", 6)
	body.add_child(sell_list)

	# ─ 판매 확인 다이얼로그
	sell_confirm = ConfirmationDialog.new()
	sell_confirm.title = "판매 확인"
	sell_confirm.ok_button_text = "판매한다"
	sell_confirm.cancel_button_text = "취소"
	sell_confirm.confirmed.connect(_on_sell_confirmed)
	add_child(sell_confirm)


# -----------------------------------------------------------------------------
# 갱신
# -----------------------------------------------------------------------------
func _refresh() -> void:
	coin_label_value.text = ThemeSetup.fmt_int(ProgressStore.get_coins())
	var market: Dictionary = ProgressStore.get_market()
	var m := float(market.get("m", 1.0))
	_apply_rate_chip(m)
	var popular: Dictionary = market.get("popular", {})
	if not popular.is_empty() and popular.has("rarity"):
		popular_banner.visible = true
		popular_banner.text = "오늘 %s 인기일! ×%.2f" % [
			Characters.rarity_label(String(popular.get("rarity", ""))),
			float(popular.get("bonus", 1.0))]
	else:
		popular_banner.visible = false
	_rebuild_listings(market)
	_rebuild_sell_list(market)


func _rebuild_listings(market: Dictionary) -> void:
	for child in listings_box.get_children():
		child.queue_free()
	var listings: Array = market.get("listings", [])
	if listings.is_empty():
		var empty := Label.new()
		empty.text = "오늘 매물이 모두 팔렸어요 — 내일 다시 와 보세요!"
		empty.add_theme_color_override("font_color", ThemeSetup.C_MUTED)
		listings_box.add_child(empty)
		return
	for i in listings.size():
		var item: Dictionary = listings[i]
		listings_box.add_child(_make_listing_card(item, i))


func _make_listing_card(item: Dictionary, index: int) -> PanelContainer:
	var id := String(item.get("id", ""))
	var def := Characters.get_def(id)
	var rarity := String(def.get("rarity", "common"))
	var price := int(item.get("price", 0))
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(170, 0)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)
	var thumb_wrap := CenterContainer.new()
	thumb_wrap.add_child(_make_thumb(id, 72))
	box.add_child(thumb_wrap)
	var name_l := Label.new()
	name_l.text = "%s Lv.%d" % [String(def.get("name", "?")), int(item.get("level", 1))]
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name_l)
	var rarity_l := Label.new()
	rarity_l.text = Characters.rarity_label(rarity)
	rarity_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rarity_l.add_theme_color_override("font_color", ThemeSetup.RARITY_COLORS.get(rarity, ThemeSetup.C_TEXT))
	box.add_child(rarity_l)
	var price_box := Icons.labeled("coin", ThemeSetup.fmt_int(price), ThemeSetup.C_TEXT, 18)
	price_box.alignment = BoxContainer.ALIGNMENT_CENTER
	# 클립 방지: 6자리 가격(예 100,000+)도 잘리지 않게 라벨을 콘텐츠 크기로 유지.
	# clip_text를 끄고 autowrap off로 두어 좁은 기기에서도 숫자 전체가 보이게 한다.
	var npc_price_lbl := price_box.get_child(1) as Label
	npc_price_lbl.clip_text = false
	npc_price_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	box.add_child(price_box)
	var buy := Button.new()
	Icons.decorate_button(buy, "buy", "구매")
	buy.disabled = ProgressStore.get_coins() < price
	buy.pressed.connect(_on_buy.bind(index))
	_wire_button(buy)
	box.add_child(buy)
	return card


func _rebuild_sell_list(market: Dictionary) -> void:
	for child in sell_list.get_children():
		child.queue_free()
	var sold := int(market.get("soldToday", 0))
	sold_label.text = "오늘 판매 %d/%d" % [sold, Market.DAILY_SELL_LIMIT]
	var limit_reached := sold >= Market.DAILY_SELL_LIMIT
	var col := ProgressStore.get_collection()
	if col.is_empty():
		var empty := Label.new()
		empty.text = "팔 수 있는 친구가 없어요"
		empty.add_theme_color_override("font_color", ThemeSetup.C_MUTED)
		sell_list.add_child(empty)
		return
	var m := float(market.get("m", 1.0))
	var popular: Dictionary = market.get("popular", {})
	for row_idx in col.size():
		var e: Dictionary = col[row_idx]
		var uid := int(e.get("uid", -1))
		var id := String(e.get("id", ""))
		var def := Characters.get_def(id)
		var rarity := String(def.get("rarity", "common"))
		var level := int(e.get("level", 1))
		# progress_store.sell_character와 동일한 공식으로 예상가 계산
		var bonus := float(popular.get("bonus", 1.0)) if String(popular.get("rarity", "")) == rarity else 1.0
		var price := Market.sell_price(rarity, level, m, bonus)
		# 2차 리뷰(major): 고정 컬럼으로 정렬 — [아이콘+이름 240][등급 100]
		# [예상가 160][판매 120]. EXPAND_FILL이 만들던 거대한 빈공간 제거 + 행 압축.
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.custom_minimum_size.y = 44

		# [컬럼1] 아이콘 + 이름 — 240px 고정
		var name_col := HBoxContainer.new()
		name_col.add_theme_constant_override("separation", 8)
		name_col.custom_minimum_size = Vector2(240, 0)
		name_col.add_child(_make_thumb(id, 36))
		var name_l := Label.new()
		name_l.text = "%s Lv.%d" % [String(def.get("name", "?")), level]
		name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_col.add_child(name_l)
		row.add_child(name_col)

		# [컬럼2] 등급 — 100px 고정
		var rarity_l := Label.new()
		rarity_l.text = Characters.rarity_label(rarity)
		rarity_l.custom_minimum_size = Vector2(100, 0)
		rarity_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		rarity_l.add_theme_color_override("font_color", ThemeSetup.RARITY_COLORS.get(rarity, ThemeSetup.C_TEXT))
		row.add_child(rarity_l)

		# [컬럼3] 예상가 — 160px는 최소폭일 뿐, 콘텐츠가 길면 늘어나게 둔다.
		# 클립 방지(기기 핵심): 6자리 예상가(예 100,000+)도 좁은 화면에서 잘리지 않게
		# 라벨 clip_text off + autowrap off로 숫자 전체가 보이도록 보장한다.
		var price_box := Icons.labeled("coin", "예상가 %s" % ThemeSetup.fmt_int(price), ThemeSetup.C_TEXT, 16)
		price_box.custom_minimum_size = Vector2(160, 0)
		var price_lbl := price_box.get_child(1) as Label
		price_lbl.clip_text = false
		price_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_child(price_box)

		# [컬럼4] 판매 버튼 — 120px 고정.
		# 판매(코인 획득)와 NPC 구매(코인 지출)는 반대 방향 거래라 코랄로 색을 분리해
		# 한눈에 구분되게 한다(리뷰: 구매/판매 동색 → 오조작 위험).
		var sell := Button.new()
		Icons.decorate_button(sell, "sell", "판매")
		sell.custom_minimum_size = Vector2(120, 0)
		sell.disabled = limit_reached
		if not limit_reached:
			var ac := ThemeSetup.C_ACCENT
			sell.add_theme_stylebox_override("normal", ThemeSetup.card(ac, ac.darkened(0.14), 12, true))
			sell.add_theme_stylebox_override("hover", ThemeSetup.card(ac.lightened(0.06), ac.darkened(0.14), 12, true))
			sell.add_theme_stylebox_override("pressed", ThemeSetup.card(ac.darkened(0.08), ac.darkened(0.2), 12, false))
			sell.add_theme_color_override("font_color", ThemeSetup.C_INK)
		sell.pressed.connect(_on_sell_pressed.bind(uid, price))
		_wire_button(sell)
		row.add_child(sell)

		# 코지 톤: 스프레드시트처럼 균일하던 판매 목록에 줄 추적용 교차 배경을 깐다.
		# 짝수 인덱스 행만 옅은 C_PANEL_2 틴트, 홀수 행은 투명. 두 경우 모두 동일한
		# 콘텐츠 여백을 가진 PanelContainer로 감싸 컬럼 정렬이 어긋나지 않게 한다.
		var row_wrap := PanelContainer.new()
		# 짝수=옅은 틴트, 홀수=투명. 두 스타일박스의 테두리폭·여백을 똑같이 맞춰
		# (틴트 행만 안쪽으로 밀려 컬럼이 어긋나는 일이 없게) 한다.
		var band_bg: Color = ThemeSetup.C_PANEL_2 if row_idx % 2 == 0 else Color(0, 0, 0, 0)
		var band := ThemeSetup.card(band_bg, band_bg, 10, false)
		band.content_margin_left = 8
		band.content_margin_right = 8
		band.content_margin_top = 2
		band.content_margin_bottom = 2
		row_wrap.add_theme_stylebox_override("panel", band)
		row_wrap.add_child(row)
		sell_list.add_child(row_wrap)


# -----------------------------------------------------------------------------
# 동작
# -----------------------------------------------------------------------------
func _on_buy(index: int) -> void:
	var r: Dictionary = ProgressStore.buy_listing(index)
	if bool(r.get("ok", false)):
		Sfx.play("coin")
		var def := Characters.get_def(String(r.get("id", "")))
		status_label.text = "%s이(가) 목장에 왔어요!" % String(def.get("name", "?"))
		return
	match String(r.get("reason", "")):
		"not_enough_coins":
			status_label.text = "코인이 부족해요"
		"bad_index":
			status_label.text = "이미 팔린 매물이에요"
		_:
			status_label.text = "구매에 실패했어요 (%s)" % String(r.get("reason", ""))


func _on_sell_pressed(uid: int, price: int) -> void:
	pending_sell_uid = uid
	var e := ProgressStore.get_character(uid)
	var def := Characters.get_def(String(e.get("id", "")))
	sell_confirm.dialog_text = "%s Lv.%d을(를) %s코인에 판매할까요?\n\n판매하면 영원히 이별하게 돼요. 되돌릴 수 없어요!" % [
		String(def.get("name", "?")), int(e.get("level", 1)), ThemeSetup.fmt_int(price)]
	sell_confirm.popup_centered()


func _on_sell_confirmed() -> void:
	var r: Dictionary = ProgressStore.sell_character(pending_sell_uid)
	pending_sell_uid = -1
	if bool(r.get("ok", false)):
		Sfx.play("coin")
		var def := Characters.get_def(String(r.get("id", "")))
		status_label.text = "%s코인에 판매했어요. 잘 가, %s…" % [
			ThemeSetup.fmt_int(int(r.get("price", 0))), String(def.get("name", "?"))]
		return
	match String(r.get("reason", "")):
		"daily_limit":
			status_label.text = "오늘은 더 팔 수 없어요 (일일 %d마리 제한)" % Market.DAILY_SELL_LIMIT
		"not_found":
			status_label.text = "그 친구를 찾을 수 없어요"
		_:
			status_label.text = "판매에 실패했어요 (%s)" % String(r.get("reason", ""))


# -----------------------------------------------------------------------------
# 헬퍼
# -----------------------------------------------------------------------------
# 시세 칩: m>1.0이면 업색(코랄 ▲), m<1.0이면 다운색(블루 ▼), m==1.0은 중립.
func _apply_rate_chip(m: float) -> void:
	var up := m > 1.0
	var down := m < 1.0
	var arrow := "▲" if up else ("▼" if down else "■")
	rate_label.text = "오늘 시세 %s ×%.2f" % [arrow, m]
	var accent: Color = ThemeSetup.C_ACCENT if up else (ThemeSetup.RARITY_COLORS["rare"] if down else ThemeSetup.C_MUTED)
	var bg: Color = ThemeSetup.C_ACCENT_SOFT if up else ThemeSetup.C_PANEL_2
	rate_chip.add_theme_stylebox_override("panel", ThemeSetup.card(bg, accent, 10, false))
	rate_label.add_theme_color_override("font_color", accent if (up or down) else ThemeSetup.C_TEXT)


func _wire_button(btn: Button) -> void:
	# n2: 크림 버튼 위 코인/액션 아이콘이 묻히지 않게 C_TEXT로 틴트해 대비 확보.
	for s in ["icon_normal_color", "icon_hover_color", "icon_pressed_color"]:
		btn.add_theme_color_override(s, ThemeSetup.C_TEXT)
	btn.mouse_entered.connect(Juice.hover.bind(btn, true))
	btn.mouse_exited.connect(Juice.hover.bind(btn, false))
	btn.pressed.connect(Juice.punch.bind(btn))


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


