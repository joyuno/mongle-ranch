# 목장(홈) 화면 — docs/GAME_DESIGN.md §6·§7 + 코지 리디자인(docs/DESIGN_SPEC §C·§D).
# 상단 HUD(코인/티켓/간식/스트릭) + 중앙 마당(5레이어 배경 + 캐릭터 배회) + 하단 네비.
# 모든 상태 갱신은 ProgressStore/GithubSync autoload signal 구독으로만 —
# 다른 화면 노드를 직접 참조하지 않는다.

extends Control

const CHARACTER_SPRITE := preload("res://scenes/CharacterSprite.tscn")
const SPRITE_SIZE := 112.0
const YARD_MARGIN := 12.0
const DECOR_DIR := "res://assets/decor"

# 의미명 / 한글 라벨 / 씬 — 네비 버튼.
const NAV_ITEMS: Array[Dictionary] = [
	{ "icon": "quiz", "label": "퀴즈", "scene": "res://scenes/Quiz.tscn" },
	{ "icon": "gacha", "label": "뽑기", "scene": "res://scenes/Gacha.tscn" },
	{ "icon": "collection", "label": "도감", "scene": "res://scenes/Collection.tscn" },
	{ "icon": "market", "label": "시장", "scene": "res://scenes/Market.tscn" },
	{ "icon": "wrong_note", "label": "오답노트", "scene": "res://scenes/WrongNote.tscn" },
	{ "icon": "settings", "label": "설정", "scene": "res://scenes/Settings.tscn" },
]

var _coin_label: Label
var _ticket_label: Label
var _snack_label: Label
var _streak_label: Label
var _sync_label: Label
var _yard: Panel
var _decor_layer: Control
var _empty_label: Label
var _toast_label: Label
var _feed_menu: PopupMenu
var _feed_target_uid: int = -1
var _sprites: Dictionary = {}  # uid(int) -> CharacterSprite
var _toast_token := 0
var _spawn_index := 0  # 격자 분산 스폰용 누적 인덱스
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_build_layout()

	ProgressStore.coins_changed.connect(_on_coins_changed)
	ProgressStore.tickets_changed.connect(_on_tickets_changed)
	ProgressStore.snacks_changed.connect(_on_snacks_changed)
	ProgressStore.streak_changed.connect(_on_streak_changed)
	ProgressStore.collection_changed.connect(_on_collection_changed)
	ProgressStore.character_leveled.connect(_on_character_leveled)
	GithubSync.sync_started.connect(_on_sync_started)
	GithubSync.sync_failed.connect(_on_sync_failed)
	GithubSync.snacks_arrived.connect(_on_snacks_arrived)

	_refresh_hud()
	ProgressStore.ensure_market_day()
	GithubSync.sync()

	await get_tree().process_frame  # 마당 크기 확정 후 배경/스프라이트 배치
	_apply_daylight()
	_place_decor()
	_rebuild_sprites()
	if _yard != null and not _yard.resized.is_connected(_on_yard_resized):
		_yard.resized.connect(_on_yard_resized)


# -----------------------------------------------------------------------------
# 레이아웃 — 코드-우선 빌드
# -----------------------------------------------------------------------------
func _build_layout() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	# ─ 상단 HUD 바 (카드로 감싼 칩들)
	var hud_card := PanelContainer.new()
	vbox.add_child(hud_card)
	var hud := HBoxContainer.new()
	hud.add_theme_constant_override("separation", 16)
	hud_card.add_child(hud)
	_coin_label = _make_hud_chip(hud, "gold", ThemeSetup.C_WARN.darkened(0.1))
	_ticket_label = _make_hud_chip(hud, "ticket", ThemeSetup.C_ACCENT)
	_snack_label = _make_hud_chip(hud, "snack", Color("#C58A4E"))
	_streak_label = _make_hud_chip(hud, "flame", Color("#E8734A"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud.add_child(spacer)
	_sync_label = Label.new()
	_sync_label.add_theme_font_size_override("font_size", 14)
	_sync_label.add_theme_color_override("font_color", ThemeSetup.C_MUTED)
	hud.add_child(_sync_label)

	# ─ 중앙 마당 (배경 5레이어 + 캐릭터)
	_yard = Panel.new()
	_yard.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_yard.clip_contents = true
	var yard_sb := StyleBoxFlat.new()
	yard_sb.bg_color = Color("#9FD08C")  # 잔디 베이스(레이어 로드 전 폴백)
	yard_sb.set_corner_radius_all(20)
	yard_sb.corner_detail = 12
	_yard.add_theme_stylebox_override("panel", yard_sb)
	vbox.add_child(_yard)
	_build_background()

	_empty_label = Label.new()
	_empty_label.text = "퀴즈를 풀고 첫 친구를 데려와 보세요!  (무료 티켓 1장 보유 중)"
	_empty_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty_label.add_theme_font_size_override("font_size", 18)
	_empty_label.add_theme_color_override("font_color", Color("#3c5a34"))
	_empty_label.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.7))
	_empty_label.add_theme_constant_override("outline_size", 5)
	_empty_label.visible = false
	_yard.add_child(_empty_label)

	# ─ 하단 네비 버튼 행 (아이콘 + 라벨)
	# 맨 앞에 비인터랙티브 '목장' 홈 앵커 칩 — "지금 여기가 목장" 신호.
	# 네비 버튼들은 다른 화면으로 떠나는 런처라 active 표시가 거짓이 되므로,
	# 떠나지 않는 별도 칩으로만 홈을 고정한다(CONTEXT의 가짜 active 금지).
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 8)
	vbox.add_child(nav)
	nav.add_child(_make_home_anchor())
	for item in NAV_ITEMS:
		nav.add_child(_make_nav_button(item))

	_build_overlays()


# ─ 마당 배경: 하늘 그라데이션 / 원경 언덕 / 잔디 / (소품) / 전경 비네트
func _build_background() -> void:
	# 1. 하늘 (세로 그라데이션)
	var sky_grad := Gradient.new()
	sky_grad.set_color(0, Color("#AEC6CF"))
	sky_grad.add_point(0.55, Color("#DCEBD8"))
	sky_grad.set_color(1, Color("#FAF0DC"))
	var sky_tex := GradientTexture2D.new()
	sky_tex.gradient = sky_grad
	sky_tex.fill_from = Vector2(0, 0)
	sky_tex.fill_to = Vector2(0, 1)
	sky_tex.width = 8
	sky_tex.height = 256
	var sky := _bg_rect(sky_tex, 0)
	_yard.add_child(sky)

	# 2. 원경/근경 언덕 (하단 정렬, 가로 확장)
	# z는 0 이상이어야 한다 — 음수면 부모 Panel 그리기 뒤로 밀려 안 보인다.
	for entry in [["hill_far", 0, 0.46], ["hill_near", 1, 0.62]]:
		var path := "%s/%s.png" % [DECOR_DIR, entry[0]]
		if not ResourceLoader.exists(path):
			continue
		var hill := TextureRect.new()
		hill.texture = load(path)
		hill.stretch_mode = TextureRect.STRETCH_SCALE
		hill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hill.z_index = int(entry[1])
		hill.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		hill.anchor_top = float(entry[2])
		hill.offset_top = 0
		hill.offset_bottom = 0
		hill.offset_left = 0
		hill.offset_right = 0
		_yard.add_child(hill)

	# 3. 잔디 바닥 (하단 절반, 위→아래 어두워지는 그라데이션)
	var grass_grad := Gradient.new()
	grass_grad.set_color(0, Color("#A9D795"))
	grass_grad.set_color(1, Color("#86C06F"))
	var grass_tex := GradientTexture2D.new()
	grass_tex.gradient = grass_grad
	grass_tex.fill_from = Vector2(0, 0)
	grass_tex.fill_to = Vector2(0, 1)
	grass_tex.width = 8
	grass_tex.height = 128
	var grass := TextureRect.new()
	grass.texture = grass_tex
	grass.stretch_mode = TextureRect.STRETCH_SCALE
	grass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grass.z_index = 2
	grass.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	grass.anchor_top = 0.5
	grass.offset_top = 0
	grass.offset_left = 0
	grass.offset_right = 0
	grass.offset_bottom = 0
	_yard.add_child(grass)

	# 3.5 지평선 헤이즈 밴드 — 하늘→잔디 경계를 대기원근으로 부드럽게.
	var haze_grad := Gradient.new()
	haze_grad.set_color(0, Color(1, 1, 1, 0))
	haze_grad.add_point(0.5, Color(1, 1, 1, 0.42))
	haze_grad.set_color(1, Color(1, 1, 1, 0))
	var haze_tex := GradientTexture2D.new()
	haze_tex.gradient = haze_grad
	haze_tex.fill_from = Vector2(0, 0)
	haze_tex.fill_to = Vector2(0, 1)
	haze_tex.width = 8
	haze_tex.height = 64
	var haze := TextureRect.new()
	haze.texture = haze_tex
	haze.stretch_mode = TextureRect.STRETCH_SCALE
	haze.mouse_filter = Control.MOUSE_FILTER_IGNORE
	haze.z_index = 2
	haze.set_anchors_preset(Control.PRESET_TOP_WIDE)
	haze.anchor_top = 0.40
	haze.anchor_bottom = 0.60
	haze.offset_top = 0
	haze.offset_bottom = 0
	haze.offset_left = 0
	haze.offset_right = 0
	_yard.add_child(haze)

	# 4. 소품 레이어 (full rect, _place_decor가 채움)
	_decor_layer = Control.new()
	_decor_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_decor_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_decor_layer.z_index = 3
	_yard.add_child(_decor_layer)

	# 5. 전경 비네트 (가장자리만 살짝 어둡게 — '안전한 방' 신호)
	var vign := ColorRect.new()
	vign.color = Color(0, 0, 0, 0)
	vign.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vign.z_index = 4090
	vign.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sh := _vignette_shader()
	if sh != null:
		var mat := ShaderMaterial.new()
		mat.shader = sh
		vign.material = mat
	_yard.add_child(vign)

	# 6. 떠다니는 꽃잎/반짝 파티클 (정적 코지)
	var petals := CPUParticles2D.new()
	petals.amount = 14
	petals.lifetime = 9.0
	petals.preprocess = 4.0
	petals.z_index = 4080
	petals.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	petals.emission_rect_extents = Vector2(640, 8)
	petals.position = Vector2(640, 16)
	petals.direction = Vector2(0, 1)
	petals.gravity = Vector2(6, 10)
	petals.initial_velocity_min = 8.0
	petals.initial_velocity_max = 20.0
	petals.angular_velocity_min = -40.0
	petals.angular_velocity_max = 40.0
	petals.scale_amount_min = 2.0
	petals.scale_amount_max = 4.0
	petals.color = Color(1.0, 0.95, 0.98, 0.55)
	_yard.add_child(petals)


func _bg_rect(tex: Texture2D, z: int) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.z_index = z
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	return r


# 부드러운 라디얼 비네트 셰이더 (실패해도 무시 — 비네트는 선택적 폴리시).
func _vignette_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
void fragment() {
	vec2 d = UV - vec2(0.5);
	float r = length(d) * 1.32;
	float a = smoothstep(0.62, 1.0, r) * 0.16;
	COLOR = vec4(0.231, 0.196, 0.161, a);
}
"""
	return sh


# 소품 배치 — 마당 크기에 비례. resized마다 재배치.
func _place_decor() -> void:
	if _decor_layer == null:
		return
	for c in _decor_layer.get_children():
		c.queue_free()
	var s := _yard.size
	if s.x < 100 or s.y < 100:
		return
	# (decor_id, x비율, y비율(발밑 기준), 폭px). 꽃은 작게, 울타리는 하단
	# 가장자리를 따라 연속 배치해 '뭔가를 두른다'는 의미를 살린다.
	var layout := [
		["tree", 0.11, 0.52, 150.0],
		["tree", 0.90, 0.46, 122.0],
		["pond", 0.76, 0.92, 168.0],
		["stump", 0.21, 0.95, 92.0],
		["rock", 0.62, 0.78, 66.0],
		["fence", 0.07, 0.995, 132.0],
		["fence", 0.155, 0.995, 132.0],
		["fence", 0.24, 0.995, 132.0],
		["flower_pink", 0.40, 0.70, 30.0],
		["flower_purple", 0.52, 0.96, 30.0],
		["flower_blue", 0.84, 0.74, 30.0],
		["flower_pink", 0.46, 0.80, 26.0],
		["flower_purple", 0.68, 0.66, 26.0],
		["grasstuft", 0.58, 0.995, 86.0],
		["grasstuft", 0.40, 0.995, 86.0],
		["grasstuft", 0.95, 0.995, 86.0],
	]
	for d in layout:
		var path := "%s/%s.png" % [DECOR_DIR, String(d[0])]
		if not ResourceLoader.exists(path):
			continue
		var tex: Texture2D = load(path)
		var w := float(d[3])
		var h := w * (float(tex.get_height()) / float(tex.get_width()))
		var spr := TextureRect.new()
		spr.texture = tex
		spr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		spr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		spr.custom_minimum_size = Vector2(w, h)
		spr.size = Vector2(w, h)
		spr.position = Vector2(s.x * float(d[1]) - w * 0.5, s.y * float(d[2]) - h)
		_decor_layer.add_child(spr)


func _on_yard_resized() -> void:
	_place_decor()


# 시각 기반 낮밤 — 마당(배경+캐릭터)에만 틴트. HUD/네비는 풀컬러 유지.
# 무처벌: 단지 접속 시각의 분위기일 뿐 페널티 0.
func _apply_daylight() -> void:
	if _yard == null:
		return
	var hour: int = int(Time.get_datetime_dict_from_system().get("hour", 12))
	var tint: Color
	if hour >= 22 or hour < 6:
		tint = Color(0.80, 0.84, 0.98)   # 밤: 서늘하고 살짝 어둡게
	elif hour < 8:
		tint = Color(1.0, 0.95, 0.90)    # 이른 아침
	elif hour >= 18 and hour < 20:
		tint = Color(1.0, 0.92, 0.86)    # 노을
	elif hour >= 20:
		tint = Color(0.92, 0.90, 0.98)   # 초저녁
	else:
		tint = Color(1.0, 1.0, 1.0)      # 낮
	_yard.modulate = tint


func _make_hud_chip(parent: Control, icon: String, tint: Color) -> Label:
	# 옅은 pill 카드로 감싸 위계를 준다.
	var pill := PanelContainer.new()
	var pill_sb := ThemeSetup.card(ThemeSetup.C_PANEL_2, ThemeSetup.C_BORDER, 14, false)
	pill_sb.content_margin_left = 12
	pill_sb.content_margin_right = 14
	pill_sb.content_margin_top = 4
	pill_sb.content_margin_bottom = 4
	pill.add_theme_stylebox_override("panel", pill_sb)
	parent.add_child(pill)
	var chip := HBoxContainer.new()
	chip.add_theme_constant_override("separation", 6)
	pill.add_child(chip)
	var ic := Icons.make(icon, tint, 22)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.add_child(ic)
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 18)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip.add_child(label)
	return label


# 홈 앵커 칩 — 클릭 불가(런처를 떠나지 않음). C_ACCENT_SOFT pill로 "여기가 목장"을
# 은은히 고정해, 6개 동일 버튼이 아니라 닻이 내려진 런처로 읽히게 한다.
func _make_home_anchor() -> PanelContainer:
	var pill := PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.custom_minimum_size.y = 52
	var sb := ThemeSetup.card(ThemeSetup.C_ACCENT_SOFT, ThemeSetup.C_ACCENT, 14, false)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	pill.add_theme_stylebox_override("panel", sb)
	var box := HBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(box)
	var ic := Icons.make("house", ThemeSetup.C_ACCENT.darkened(0.15), 20)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(ic)
	var lbl := Label.new()
	lbl.text = "목장"
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_color_override("font_color", ThemeSetup.C_INK)
	box.add_child(lbl)
	return pill


func _make_nav_button(item: Dictionary) -> Button:
	var btn := Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size.y = 52
	var box := HBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	var ic := Icons.make(String(item["icon"]), ThemeSetup.C_TEXT, 20)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(ic)
	var lbl := Label.new()
	lbl.text = String(item["label"])
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(lbl)
	btn.add_child(box)
	btn.pressed.connect(_on_nav_pressed.bind(String(item["scene"])))
	btn.pressed.connect(Juice.punch.bind(btn))
	btn.mouse_entered.connect(Juice.hover.bind(btn, true))
	btn.mouse_exited.connect(Juice.hover.bind(btn, false))
	return btn


# -----------------------------------------------------------------------------
# HUD 갱신
# -----------------------------------------------------------------------------
func _refresh_hud() -> void:
	_on_coins_changed(ProgressStore.get_coins())
	_on_tickets_changed(ProgressStore.get_tickets())
	_on_snacks_changed(ProgressStore.get_snacks())
	_on_streak_changed(int(ProgressStore.get_streak().get("count", 0)))
	var username := ProgressStore.get_github_username()
	if username.is_empty():
		_sync_label.text = "GitHub 미연결"
	else:
		_sync_label.text = "GitHub: %s" % username


func _on_coins_changed(amount: int) -> void:
	_coin_label.text = ThemeSetup.fmt_int(amount)


func _on_tickets_changed(count: int) -> void:
	_ticket_label.text = ThemeSetup.fmt_int(count)


func _on_snacks_changed(count: int) -> void:
	_snack_label.text = ThemeSetup.fmt_int(count)


func _on_streak_changed(count: int) -> void:
	_streak_label.text = str(count)


func _on_sync_started() -> void:
	_sync_label.text = "GitHub 동기화 중…"


func _on_sync_failed(_reason: String) -> void:
	_refresh_hud()


func _on_snacks_arrived(granted: int, commits: int) -> void:
	_refresh_hud()
	Sfx.play("snack")
	_show_toast("GitHub 커밋 %d개 → 간식 +%d" % [commits, granted])


# -----------------------------------------------------------------------------
# 캐릭터 스프라이트 관리
# -----------------------------------------------------------------------------
func _on_collection_changed() -> void:
	_rebuild_sprites()


func _rebuild_sprites() -> void:
	var members: Array = ProgressStore.ranch_members()
	var seen: Dictionary = {}
	var bounds := _yard_bounds()
	for entry in members:
		var member_uid := int(entry.get("uid", -1))
		seen[member_uid] = true
		if _sprites.has(member_uid):
			continue
		var sprite = CHARACTER_SPRITE.instantiate()
		sprite.setup(entry, _yard_bounds, _friend_position)
		sprite.position = _spawn_position(bounds)
		sprite.z_index = clampi(int(sprite.position.y), 4, 4000)  # 첫 프레임부터 잔디 위
		var d0 := clampf((sprite.position.y / maxf(_yard.size.y, 1.0) - 0.44) / 0.50, 0.0, 1.0)
		sprite.set_depth(lerpf(0.72, 1.18, d0))
		sprite.clicked.connect(_on_character_clicked)
		_yard.add_child(sprite)
		_sprites[member_uid] = sprite
	for existing_uid in _sprites.keys():
		if not seen.has(existing_uid):
			_sprites[existing_uid].queue_free()
			_sprites.erase(existing_uid)
	_empty_label.visible = members.is_empty()


# 격자(7×4)+지터 스폰 — 동일 y 한 줄 군집 대신 잔디 전역에 자연 산개.
func _spawn_position(bounds: Rect2) -> Vector2:
	var cols := 7
	var rows := 8
	var col := _spawn_index % cols
	var row := (_spawn_index / cols) % rows
	_spawn_index += 1
	var cw := bounds.size.x / float(cols)
	var ch := bounds.size.y / float(rows)
	return Vector2(
		bounds.position.x + (float(col) + _rng.randf_range(0.12, 0.88)) * cw,
		bounds.position.y + (float(row) + _rng.randf_range(0.12, 0.88)) * ch)


func _yard_bounds() -> Rect2:
	var s := _yard.size
	# 캐릭터는 잔디 중하단에서 배회 — 지평선 아래로 내리고 세로 범위를 넓혀
	# '단체사진' 군집을 방지(시니어 리뷰 M2).
	var top := s.y * 0.47
	return Rect2(
		Vector2(YARD_MARGIN, top),
		Vector2(maxf(s.x - SPRITE_SIZE - YARD_MARGIN * 2.0, 0.0),
			maxf(s.y - SPRITE_SIZE - YARD_MARGIN - top, 0.0)))


func _friend_position(exclude_uid: int) -> Vector2:
	var others: Array[Vector2] = []
	for sprite_uid in _sprites:
		if int(sprite_uid) == exclude_uid:
			continue
		var sprite = _sprites[sprite_uid]
		if is_instance_valid(sprite):
			others.append(sprite.position)
	if others.is_empty():
		return Vector2.INF
	return others[_rng.randi_range(0, others.size() - 1)]


func _sort_sprites() -> void:
	var yh := maxf(_yard.size.y, 1.0)
	for sprite_uid in _sprites:
		var sprite = _sprites[sprite_uid]
		if is_instance_valid(sprite):
			sprite.z_index = clampi(int(sprite.position.y), 4, 4000)
			# 깊이(y) 비례 스케일 — 위(먼) 작게, 아래(가까운) 크게. 배경 원근과 일치.
			var nrm := clampf((sprite.position.y / yh - 0.44) / 0.50, 0.0, 1.0)
			sprite.set_depth(lerpf(0.72, 1.18, nrm))


func _on_character_leveled(uid: int, level: int) -> void:
	if _sprites.has(uid) and is_instance_valid(_sprites[uid]):
		_sprites[uid].react_levelup(level)
		Sfx.play("levelup")


# -----------------------------------------------------------------------------
# 간식 주기
# -----------------------------------------------------------------------------
func _on_character_clicked(uid: int) -> void:
	if ProgressStore.get_snacks() <= 0:
		Sfx.play("click")
		return
	_feed_target_uid = uid
	_feed_menu.popup(Rect2i(Vector2i(get_viewport().get_mouse_position()), Vector2i.ZERO))


func _on_feed_menu_pressed(id: int) -> void:
	if id != 0 or _feed_target_uid < 0:
		return
	var result := ProgressStore.feed_snack(_feed_target_uid)
	_feed_target_uid = -1
	if not bool(result.get("ok", false)):
		_show_toast("간식을 줄 수 없어요 (%s)" % String(result.get("reason", "")))


# -----------------------------------------------------------------------------
# 네비게이션 · 토스트
# -----------------------------------------------------------------------------
func _on_nav_pressed(scene_path: String) -> void:
	Sfx.play("transition")
	if ResourceLoader.exists(scene_path):
		get_tree().change_scene_to_file(scene_path)
	else:
		_show_toast("아직 준비 중인 화면이에요")


func _show_toast(text: String) -> void:
	_toast_token += 1
	var token := _toast_token
	_toast_label.text = text
	_toast_label.modulate = Color.WHITE
	_toast_label.visible = true
	_toast_label.reset_size()
	_toast_label.position = Vector2((size.x - _toast_label.size.x) * 0.5, 64.0)
	Juice.pop_in(_toast_label)
	await get_tree().create_timer(2.5).timeout
	if token != _toast_token or not is_instance_valid(_toast_label):
		return
	var t := create_tween()
	t.tween_property(_toast_label, "modulate:a", 0.0, 0.4)
	await t.finished
	if token == _toast_token and is_instance_valid(_toast_label):
		_toast_label.visible = false
		_toast_label.modulate.a = 1.0


# 토스트 라벨 + 간식 컨텍스트 메뉴 + Y-sort 타이머 (overlay/하우스키핑).
func _build_overlays() -> void:
	# ─ 토스트 (컨테이너 밖 오버레이 — 위치는 _show_toast에서 계산)
	_toast_label = Label.new()
	_toast_label.visible = false
	_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_label.add_theme_font_size_override("font_size", 16)
	_toast_label.add_theme_color_override("font_color", ThemeSetup.C_TEXT)
	var toast_sb := StyleBoxFlat.new()
	toast_sb.bg_color = ThemeSetup.C_PANEL
	toast_sb.border_color = ThemeSetup.C_ACCENT
	toast_sb.set_border_width_all(2)
	toast_sb.set_corner_radius_all(12)
	toast_sb.shadow_color = Color(ThemeSetup.C_INK.r, ThemeSetup.C_INK.g, ThemeSetup.C_INK.b, 0.18)
	toast_sb.shadow_size = 6
	toast_sb.content_margin_left = 14
	toast_sb.content_margin_right = 14
	toast_sb.content_margin_top = 8
	toast_sb.content_margin_bottom = 8
	_toast_label.add_theme_stylebox_override("normal", toast_sb)
	_toast_label.z_index = 4095
	add_child(_toast_label)

	# ─ 간식 주기 컨텍스트 메뉴
	_feed_menu = PopupMenu.new()
	_feed_menu.add_item("간식 주기", 0)
	_feed_menu.id_pressed.connect(_on_feed_menu_pressed)
	add_child(_feed_menu)

	# ─ Y-sort: position.y 기준 z_index 갱신 타이머 (캐릭터가 잔디·소품 위로)
	var zsort := Timer.new()
	zsort.wait_time = 0.25
	zsort.autostart = true
	zsort.timeout.connect(_sort_sprites)
	add_child(zsort)
