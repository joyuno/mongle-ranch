# 목장 화면을 배회하는 캐릭터 1마리 (Control 루트 + TextureRect body).
# docs/GAME_DESIGN.md §6 — personality(Characters.ROSTER) 기반
# idle ↔ walk ↔ sleep 상태머신 + 숨쉬기/이모트/드래그 상호작용.
#
# 에셋 PNG가 없으면(개발 초기) id 해시에서 유도한 파스텔 색으로
# 둥근 몸 + 귀 2 + 점눈 2 + 분홍 볼을 직접 그리는 폴백을 사용한다 —
# 에셋 없이도 게임이 완성되어야 한다.

extends Control

signal clicked(uid: int)

const SPRITE_SIZE := 112.0
const DRAG_THRESHOLD := 6.0

# 이모지 → 라인 글리프(assets/icons). bespoke 아트 위 OS 컬러 이모지 톤 충돌 제거.
# 매핑 없으면 중립 글리프로 폴백 → 원본 컬러 이모지는 절대 노출 안 됨.
const EMOTE_ICON := {
	"💤": "moon", "😪": "moon", "🫠": "moon", "🌙": "moon",
	"❤️": "heart", "💗": "heart", "💚": "heart", "🤎": "heart", "💛": "heart",
	"🎵": "music", "🎶": "music",
	"✨": "sparkles", "🌟": "sparkles", "💡": "lightbulb",
	"⭐": "star",
	"🌱": "leaf", "🍂": "leaf", "🌰": "leaf",
	"👀": "eye", "📖": "eye", "📚": "eye",
	"💦": "droplets", "🫧": "droplets",
	"☁️": "cloud", "☕": "coffee",
	"🥇": "award", "💪": "award",
	"😳": "smile", "❗": "message-circle", "❓": "message-circle", "…": "message-circle",
	"⬆️": "arrow-up", "✏️": "lightbulb",
	"🐣": "egg", "🐟": "fish",
	"👋": "hand", "🎉": "party-popper", "🍪": "cookie", "🔥": "flame",
}
const EMOTE_FALLBACK := "message-circle"

var uid: int = -1
var char_id: String = ""
var level: int = 1
var personality: Dictionary = {}
var bounds_provider: Callable = Callable()
var friend_position_provider: Callable = Callable()  # call(exclude_uid) -> Vector2 (없으면 Vector2.INF)

var _body: TextureRect
var _emote_bubble: PanelContainer
var _emote_icon: TextureRect
var _level_label: Label
var _breath_tween: Tween
var _use_fallback := false
var _fallback_color := Color.WHITE
var _facing := 1.0          # 1 = 오른쪽, -1 = 왼쪽 (폴백 드로잉 미러용)
var _sleeping := false
var _dragging := false
var _pressed := false
var _press_pos := Vector2.ZERO
var _emote_token := 0
var _level_reveal_token := 0   # 탭으로 띄운 레벨 라벨 자동 숨김용 (hover와 충돌 방지)
var _walk_tween: Tween
var _bounce_tween: Tween
var _rng := RandomNumberGenerator.new()


# ranch가 add_child 전에 호출. entry = { uid, id, level } (ProgressStore 컬렉션 항목).
func setup(entry: Dictionary, bounds_provider_cb: Callable, friend_provider: Callable = Callable()) -> void:
	uid = int(entry.get("uid", -1))
	char_id = String(entry.get("id", ""))
	level = int(entry.get("level", 1))
	bounds_provider = bounds_provider_cb
	friend_position_provider = friend_provider
	var def := Characters.get_def(char_id)
	personality = def.get("personality", {})


func _ready() -> void:
	_rng.randomize()
	custom_minimum_size = Vector2(SPRITE_SIZE, SPRITE_SIZE)
	size = custom_minimum_size
	pivot_offset = Vector2(SPRITE_SIZE * 0.5, SPRITE_SIZE)  # 발밑 피벗 (레벨업 펄스용)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_nodes()
	gui_input.connect(_on_gui_input)
	_start_breathing()
	if Characters.rarity_of(char_id) == "legendary":
		_start_sparkle()
	# 코루틴으로 시작 (await 없이 fire-and-forget)
	_behave_loop()
	_emote_loop()


# -----------------------------------------------------------------------------
# 노드 구성 — 코드-우선 빌드
# -----------------------------------------------------------------------------
func _build_nodes() -> void:
	_body = TextureRect.new()
	_body.size = Vector2(SPRITE_SIZE, SPRITE_SIZE)
	_body.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_body.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_body.pivot_offset = Vector2(SPRITE_SIZE * 0.5, SPRITE_SIZE)  # 발밑 고정 squash&stretch
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var path := Characters.sprite_path(char_id)
	if ResourceLoader.exists(path):
		_body.texture = load(path)
	else:
		_use_fallback = true
		_fallback_color = _pastel_from_id(char_id)
		_body.draw.connect(_draw_fallback_body)
	add_child(_body)
	_body.queue_redraw()

	# 이모트 말풍선 (머리 위, 평소 숨김) — 라인 글리프 아이콘
	_emote_bubble = PanelContainer.new()
	_emote_bubble.visible = false
	_emote_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bubble := StyleBoxFlat.new()
	bubble.bg_color = Color(1, 1, 1, 0.94)
	bubble.border_color = Color(0.89, 0.84, 0.74)
	bubble.set_border_width_all(2)
	bubble.set_corner_radius_all(11)
	bubble.content_margin_left = 6
	bubble.content_margin_right = 6
	bubble.content_margin_top = 4
	bubble.content_margin_bottom = 4
	bubble.shadow_color = Color(0.231, 0.196, 0.161, 0.16)
	bubble.shadow_size = 4
	_emote_bubble.add_theme_stylebox_override("panel", bubble)
	_emote_icon = TextureRect.new()
	_emote_icon.custom_minimum_size = Vector2(22, 22)
	_emote_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_emote_icon.modulate = Color(0.29, 0.25, 0.21)  # INK 톤 라인
	_emote_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_emote_bubble.add_child(_emote_icon)
	add_child(_emote_bubble)

	# 레벨 라벨 (발밑) — 평소 숨김, hover 시에만(디버그 라벨 인상 제거). 외곽선.
	_level_label = Label.new()
	_level_label.text = "Lv.%d" % level
	_level_label.size = Vector2(SPRITE_SIZE, 16)
	_level_label.position = Vector2(0, SPRITE_SIZE - 12)
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_level_label.visible = false
	_level_label.add_theme_font_size_override("font_size", 12)
	_level_label.add_theme_color_override("font_color", Color(0.29, 0.25, 0.21))
	_level_label.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.85))
	_level_label.add_theme_constant_override("outline_size", 5)
	add_child(_level_label)
	mouse_entered.connect(func(): _level_label.visible = true)
	mouse_exited.connect(func(): _level_label.visible = false)


# 발밑 그림자 — 깊이(스폰 y) 비례 + 2겹 소프트 엣지 + INK 톤(순흑 금지).
func _draw() -> void:
	var vh := maxf(float(get_viewport_rect().size.y), 1.0)
	var depth := clampf((position.y / vh - 0.30) / 0.50, 0.0, 1.0)  # 0=먼(위) .. 1=가까운(아래)
	var sc := lerpf(0.76, 1.14, depth)
	var a := lerpf(0.11, 0.20, depth)
	var ink := Color(0.231, 0.196, 0.161)
	var center := Vector2(SPRITE_SIZE * 0.5, SPRITE_SIZE - 4.0)
	draw_set_transform(center, 0.0, Vector2(1.0, 0.34))
	draw_circle(Vector2.ZERO, SPRITE_SIZE * 0.34 * sc, Color(ink.r, ink.g, ink.b, a * 0.5))
	draw_circle(Vector2.ZERO, SPRITE_SIZE * 0.25 * sc, Color(ink.r, ink.g, ink.b, a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# 폴백 바디 — 파스텔 둥근 몸 + 작은 귀 2 + 점눈 2 + 분홍 볼 2
func _draw_fallback_body() -> void:
	if not _use_fallback:
		return
	var cx := SPRITE_SIZE * 0.5
	var r := SPRITE_SIZE * 0.34
	var body_center := Vector2(cx, SPRITE_SIZE - r - 8.0)
	var ear_color := _fallback_color.darkened(0.08)
	_body.draw_circle(Vector2(cx - r * 0.55, body_center.y - r * 0.82), r * 0.28, ear_color)
	_body.draw_circle(Vector2(cx + r * 0.55, body_center.y - r * 0.82), r * 0.28, ear_color)
	_body.draw_circle(body_center, r, _fallback_color)
	# 이목구비는 바라보는 방향으로 살짝 치우침
	var shift := r * 0.16 * _facing
	var eye_y := body_center.y - r * 0.18
	var eye_color := Color(0.18, 0.16, 0.18)
	_body.draw_circle(Vector2(cx - r * 0.3 + shift, eye_y), r * 0.07, eye_color)
	_body.draw_circle(Vector2(cx + r * 0.3 + shift, eye_y), r * 0.07, eye_color)
	var cheek_color := Color(1.0, 0.62, 0.7, 0.55)
	_body.draw_circle(Vector2(cx - r * 0.48 + shift, eye_y + r * 0.32), r * 0.13, cheek_color)
	_body.draw_circle(Vector2(cx + r * 0.48 + shift, eye_y + r * 0.32), r * 0.13, cheek_color)


static func _pastel_from_id(id: String) -> Color:
	var hue := float(absi(id.hash()) % 360) / 360.0
	return Color.from_hsv(hue, 0.38, 0.95)


# -----------------------------------------------------------------------------
# 상태머신 — idle ↔ walk ↔ sleep
# -----------------------------------------------------------------------------
func _behave_loop() -> void:
	await get_tree().process_frame  # 마당 레이아웃 확정 대기
	while is_inside_tree():
		var wait := _rng.randf_range(
			float(personality.get("idle_min", 1.0)),
			float(personality.get("idle_max", 3.0)))
		await get_tree().create_timer(wait).timeout
		if not is_inside_tree():
			return
		if _dragging:
			continue
		if _rng.randf() < _effective_sleep_chance():
			await _do_sleep()
		else:
			await _do_walk()


func _effective_sleep_chance() -> float:
	var chance := float(personality.get("sleep_chance", 0.1))
	if bool(personality.get("night_owl", false)):
		var hour := int(Time.get_datetime_dict_from_system()["hour"])
		var is_night := hour >= 22 or hour < 6
		if not is_night:
			chance *= 2.0  # 야행성: 낮에는 졸림
	return clampf(chance, 0.0, 0.9)


func _do_sleep() -> void:
	_sleeping = true
	var secs := _rng.randf_range(3.0, 6.0)
	_show_emote("💤", secs)
	var t := create_tween()
	t.tween_property(_body, "rotation", 0.16, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(secs).timeout
	if not is_inside_tree():
		return
	var back := create_tween()
	back.tween_property(_body, "rotation", 0.0, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_sleeping = false


func _do_walk() -> void:
	var bounds := _get_bounds()
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return
	# 집순이: 거의 이동하지 않고 제자리 스케일 흔들림
	if bool(personality.get("homebody", false)) and _rng.randf() < 0.8:
		await _wobble_in_place()
		return
	var target := _pick_target(bounds)
	var dist := position.distance_to(target)
	if dist < 4.0:
		return
	var speed := maxf(float(personality.get("move_speed", 60.0)), 1.0)
	var dur := dist / speed
	_set_facing(1.0 if target.x >= position.x else -1.0)
	if _walk_tween and _walk_tween.is_valid():
		_walk_tween.kill()
	_walk_tween = create_tween()
	_walk_tween.tween_property(self, "position", target, dur)
	_start_bounce(bool(personality.get("hop", false)))
	# tween.finished 대신 동일 시간 타이머 대기 — 드래그로 트윈이 kill돼도 루프가 멈추지 않음
	await get_tree().create_timer(dur).timeout
	_stop_bounce()


func _pick_target(bounds: Rect2) -> Vector2:
	var target := Vector2(
		_rng.randf_range(bounds.position.x, bounds.end.x),
		_rng.randf_range(bounds.position.y, bounds.end.y))
	if bool(personality.get("follower", false)) and friend_position_provider.is_valid():
		var friend = friend_position_provider.call(uid)
		if friend is Vector2 and (friend as Vector2).is_finite():
			target = (friend as Vector2) + Vector2(_rng.randf_range(-70, 70), _rng.randf_range(-50, 50))
	elif bool(personality.get("corner_lover", false)):
		var corners: Array[Vector2] = [
			bounds.position,
			Vector2(bounds.end.x, bounds.position.y),
			Vector2(bounds.position.x, bounds.end.y),
			bounds.end,
		]
		target = target.lerp(corners[_rng.randi_range(0, 3)], 0.7)
	return target.clamp(bounds.position, bounds.end)


func _get_bounds() -> Rect2:
	if bounds_provider.is_valid():
		var r = bounds_provider.call()
		if r is Rect2:
			return r
	return Rect2()


func _wobble_in_place() -> void:
	if _breath_tween and _breath_tween.is_valid():
		_breath_tween.kill()
	var t := create_tween()
	t.tween_property(_body, "scale", Vector2(1.07, 0.93), 0.16).set_trans(Tween.TRANS_SINE)
	t.tween_property(_body, "scale", Vector2(0.95, 1.05), 0.16).set_trans(Tween.TRANS_SINE)
	t.tween_property(_body, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_SINE)
	await t.finished
	_start_breathing()


func _set_facing(dir: float) -> void:
	if is_equal_approx(_facing, dir):
		return
	_facing = dir
	if _use_fallback:
		_body.queue_redraw()
	else:
		_body.flip_h = _facing < 0.0


# 걷기 y 바운스 — hop이면 진폭 큰 포물선 아크 (TRANS_SINE 2단 루프)
func _start_bounce(hop: bool) -> void:
	_stop_bounce()
	var amp := 16.0 if hop else 6.0
	var half := 0.22 if hop else 0.14
	_bounce_tween = create_tween().set_loops()
	_bounce_tween.tween_property(_body, "position:y", -amp, half).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_bounce_tween.tween_property(_body, "position:y", 0.0, half).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


func _stop_bounce() -> void:
	if _bounce_tween and _bounce_tween.is_valid():
		_bounce_tween.kill()
	_bounce_tween = null
	_body.position.y = 0.0


# -----------------------------------------------------------------------------
# 생명감 — 숨쉬기 / 레전더리 반짝
# -----------------------------------------------------------------------------
# 숨쉬기 — _body.scale 루프(루트 scale은 깊이 전용이라 분리). 연출이 _body를
# 잠시 점유하면 kill 후 _start_breathing으로 재개한다.
func _start_breathing() -> void:
	if _breath_tween and _breath_tween.is_valid():
		_breath_tween.kill()
	if not is_inside_tree():
		return
	var period := _rng.randf_range(1.6, 2.4)  # 개체별 주기를 어긋나게 → 동기화 방지
	_breath_tween = create_tween().set_loops()
	_breath_tween.tween_property(_body, "scale", Vector2(1.04, 0.96), period * 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_breath_tween.tween_property(_body, "scale", Vector2.ONE, period * 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# 깊이(y) 스케일 — 루트에 적용(발밑 피벗). ranch가 position.y 기준으로 호출.
func set_depth(d: float) -> void:
	scale = Vector2(d, d)


func _start_sparkle() -> void:
	var t := create_tween().set_loops()
	t.tween_property(_body, "modulate", Color(1.3, 1.22, 0.92), 0.9) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(_body, "modulate", Color.WHITE, 0.9) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# -----------------------------------------------------------------------------
# 이모트
# -----------------------------------------------------------------------------
func _emote_loop() -> void:
	while is_inside_tree():
		await get_tree().create_timer(_rng.randf_range(5.0, 30.0)).timeout
		if not is_inside_tree():
			return
		if _sleeping or _dragging:
			continue
		var emotes: Array = personality.get("emotes", [])
		if emotes.is_empty():
			continue
		_show_emote(String(emotes[_rng.randi_range(0, emotes.size() - 1)]), 1.5)


func _show_emote(key: String, secs: float) -> void:
	var icon_name := String(EMOTE_ICON.get(key, EMOTE_FALLBACK))
	var path := "res://assets/icons/%s.svg" % icon_name
	if not ResourceLoader.exists(path):
		return  # 아이콘 없으면 표시 안 함 (원본 컬러 이모지 노출 금지)
	_emote_icon.texture = load(path)
	_emote_token += 1
	var token := _emote_token
	_emote_bubble.visible = true
	_emote_bubble.reset_size()
	_emote_bubble.position = Vector2(
		SPRITE_SIZE * 0.5 - _emote_bubble.size.x * 0.5,
		-_emote_bubble.size.y - 2.0)
	await get_tree().create_timer(secs).timeout
	if token == _emote_token and is_instance_valid(_emote_bubble):
		_emote_bubble.visible = false


# -----------------------------------------------------------------------------
# 상호작용 — 클릭 / 드래그 / 레벨업 리액션
# -----------------------------------------------------------------------------
func _on_gui_input(event: InputEvent) -> void:
	# 터치 기기: hover가 없으므로 탭(press)에서 레벨 라벨을 띄우고 잠시 후 자동 숨김.
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_pressed = true
			_press_pos = get_global_mouse_position()
			_reveal_level_temporarily()
		else:
			if _dragging:
				_end_drag()
			elif _pressed:
				clicked.emit(uid)
				_joy_jump()
			_pressed = false
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressed = true
			_press_pos = get_global_mouse_position()
			_reveal_level_temporarily()  # 데스크톱 클릭에서도 동일하게 노출(hover와 무해하게 공존)
		else:
			if _dragging:
				_end_drag()
			elif _pressed:
				clicked.emit(uid)
				_joy_jump()
			_pressed = false
	elif event is InputEventMouseMotion and _pressed:
		if not _dragging and get_global_mouse_position().distance_to(_press_pos) > DRAG_THRESHOLD:
			_begin_drag()
		if _dragging:
			position += (event as InputEventMouseMotion).relative


# 탭/클릭 시 레벨 라벨을 띄우고 ~2초 뒤 자동 숨김. hover(mouse_exited)가 먼저
# 숨겨도 무해하고, 타이머는 토큰으로 최신 탭만 유효 — 숨쉬기 트윈은 건드리지 않음.
func _reveal_level_temporarily() -> void:
	_level_label.visible = true
	_level_reveal_token += 1
	var token := _level_reveal_token
	var timer := get_tree().create_timer(2.0)
	timer.timeout.connect(func() -> void:
		if token == _level_reveal_token and is_instance_valid(_level_label):
			_level_label.visible = false)


func _begin_drag() -> void:
	_dragging = true
	if _walk_tween and _walk_tween.is_valid():
		_walk_tween.kill()
	_stop_bounce()


func _end_drag() -> void:
	_dragging = false
	var bounds := _get_bounds()
	if bounds.size.x > 0.0 and bounds.size.y > 0.0:
		position = position.clamp(bounds.position, bounds.end)
	# 놓은 자리에서 _behave_loop가 자연스럽게 재개됨


func _joy_jump() -> void:
	_stop_bounce()
	var t := create_tween()
	t.tween_property(_body, "position:y", -20.0, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(_body, "position:y", 0.0, 0.26).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


# ranch가 ProgressStore.character_leveled 수신 시 호출
func react_levelup(new_level: int = -1) -> void:
	if new_level > 0:
		level = new_level
		_level_label.text = "Lv.%d" % level
	_show_emote("⬆️", 1.5)
	# 레벨업 펄스는 _body에(루트 scale은 깊이 전용). 끝나면 숨쉬기 재개.
	if _breath_tween and _breath_tween.is_valid():
		_breath_tween.kill()
	var t := create_tween()
	t.tween_property(_body, "scale", Vector2(1.18, 1.18), 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(_body, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	t.tween_callback(_start_breathing)
