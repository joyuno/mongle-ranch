# Juice — 코지 톤의 절제된 게임필 헬퍼 (docs/DESIGN_SPEC.md §E).
# 순수 정적 함수. 모두 Tween 기반이라 C# 없이 동작하고, 헤드리스에서도
# 크래시하지 않는다(트윈은 안전). 스크린셰이크·과한 탄성은 코지 톤에 안 맞아
# 쓰지 않는다.

class_name Juice
extends RefCounted


# 버튼 등에 hover 시 살짝 부풀고 떠오르는 느낌. mouse_entered/exited에 연결.
# 한 줄 연결용: btn.mouse_entered.connect(Juice.hover.bind(btn, true))
static func hover(node: Control, on: bool) -> void:
	if not is_instance_valid(node):
		return
	node.pivot_offset = node.size * 0.5
	var t := node.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(node, "scale", Vector2.ONE * (1.06 if on else 1.0), 0.16)


# 클릭 순간 살짝 눌렀다 돌아오는 펀치. pressed에 연결.
static func punch(node: Control) -> void:
	if not is_instance_valid(node):
		return
	node.pivot_offset = node.size * 0.5
	var t := node.create_tween().set_trans(Tween.TRANS_QUAD)
	t.tween_property(node, "scale", Vector2.ONE * 0.94, 0.06)
	t.tween_property(node, "scale", Vector2.ONE, 0.10).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# 카드/팝업 등장 — 살짝 작게 + 투명에서 통통 튀어나옴.
static func pop_in(node: Control, delay: float = 0.0) -> void:
	if not is_instance_valid(node):
		return
	node.pivot_offset = node.size * 0.5
	node.scale = Vector2.ONE * 0.9
	node.modulate.a = 0.0
	var t := node.create_tween().set_parallel(true)
	t.tween_property(node, "scale", Vector2.ONE, 0.28).set_delay(delay) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(node, "modulate:a", 1.0, 0.2).set_delay(delay)


# "+12" 같은 보상 라벨이 위로 떠오르며 사라짐. parent의 좌표계 기준 at 위치.
static func float_label(parent: Node, text: String, color: Color, at: Vector2) -> void:
	if not is_instance_valid(parent):
		return
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.8))
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.position = at
	lbl.z_index = 100
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(lbl)
	var t := lbl.create_tween().set_parallel(true)
	t.tween_property(lbl, "position:y", at.y - 56.0, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(lbl, "modulate:a", 0.0, 0.9).set_delay(0.3)
	t.chain().tween_callback(lbl.queue_free)


# 짧은 반짝임 — sparkle 텍스처가 있으면 노드 위에 1~2개 띄운다.
const SPARKLE_TEX := "res://assets/swords/fx_success.png"  # 있으면 사용, 없으면 무시
static func sparkle(node: Control) -> void:
	if not is_instance_valid(node):
		return
	# 텍스처가 없으면 작은 코랄 원 펄스로 대체 (에셋 의존 0).
	var dot := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 0.95, 0.7, 0.9)
	sb.set_corner_radius_all(20)
	dot.add_theme_stylebox_override("panel", sb)
	dot.custom_minimum_size = Vector2(14, 14)
	dot.size = Vector2(14, 14)
	dot.position = node.size * 0.5 - Vector2(7, 7)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.z_index = 60
	node.add_child(dot)
	var t := dot.create_tween().set_parallel(true)
	t.tween_property(dot, "scale", Vector2.ONE * 2.4, 0.4).set_ease(Tween.EASE_OUT)
	t.tween_property(dot, "modulate:a", 0.0, 0.4)
	t.chain().tween_callback(dot.queue_free)


# 레전더리 등장 등 임팩트 순간만 — 짧게 시간을 멈췄다 푼다.
static func hitstop(node: Node, amount: float = 0.08) -> void:
	if not is_instance_valid(node):
		return
	Engine.time_scale = 0.07
	var timer := node.get_tree().create_timer(amount * 0.07, true, false, true)
	timer.timeout.connect(func(): Engine.time_scale = 1.0)
