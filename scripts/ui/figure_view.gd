# 결정 구조 3D 시각화 — 학습 문제 이해도용. 캐릭터가 아니라 '문제 설명'에만 3D 렌더 사용.
# 엔진 교체 없이 SubViewport(3D)를 2D 퀴즈 UI에 박는다. 학습자가 드래그로 회전시켜
# 코너/면/체심 원자를 직접 확인 → "면심입방이 어떻게 생겼는지"를 제로베이스도 파악.
# 원자 색으로 종류 구분(코너=블루, 면=코랄, 체심=민트, 내부=라벤더).
class_name FigureView
extends SubViewportContainer

const ATOM_R := 0.115   # 화합물(rocksalt/fluorite)은 원자가 많아 약간 작게 → 가독성
const COL_CORNER := Color("#7FA8D8")   # 코너
const COL_FACE := Color("#E79AA0")     # 면심
const COL_BODY := Color("#8FC9AE")     # 체심
const COL_INNER := Color("#B79AD8")    # 내부(다이아몬드)
const COL_EDGE := Color("#6A5F50")

var figure: String = ""
var _vp: SubViewport
var _pivot: Node3D
var _yaw := 0.7
var _pitch := 0.45
var _dragging := false
var _mat_corner: StandardMaterial3D
var _mat_face: StandardMaterial3D
var _mat_body: StandardMaterial3D
var _mat_inner: StandardMaterial3D
var _mat_edge: StandardMaterial3D


# figure → 유효 원자 수 설명(제로베이스용). 빈 문자열이면 미지원.
static func caption_for(name: String) -> String:
	match name.strip_edges().to_lower():
		"sc", "simple_cubic", "단순입방":
			return "단순입방(SC): 코너 8 × 1/8 = 유효 1개"
		"bcc", "체심입방":
			return "체심입방(BCC): 코너 8 × 1/8 + 중심 1 = 유효 2개"
		"fcc", "면심입방":
			return "면심입방(FCC): 코너 8 × 1/8 + 면 6 × 1/2 = 유효 4개"
		"diamond", "다이아몬드", "si":
			return "다이아몬드 구조(Si·Ge): FCC(4) + 내부 4 = 유효 8개"
		"hcp", "육방조밀":
			return "육방조밀(HCP): 유효 6개, 충진율 74% (c/a ≈ 1.633)"
		"zincblende", "zinc_blende", "sphalerite", "섬아연광", "gaas", "zns":
			return "섬아연광(ZnS·GaAs): FCC + 사면체 자리 4 — 화합물 반도체 구조"
		"rocksalt", "rock_salt", "nacl", "halite", "암염":
			return "암염(NaCl): 두 FCC 격자가 맞물린 구조, 각 이온 6배위"
		"cscl", "cesium_chloride", "염화세슘":
			return "염화세슘(CsCl): 단순입방 + 체심에 다른 이온, 8배위"
		"fluorite", "caf2", "calcium_fluoride", "형석":
			return "형석(CaF2): Ca FCC + F 8개 사면체 자리"
		_:
			return ""


static func is_supported(name: String) -> bool:
	return not caption_for(name).is_empty()


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP  # 드래그 회전 입력 수신
	_build_materials()
	_vp = SubViewport.new()
	# 투명 3D SubViewport는 GL Compatibility(우리 렌더러)에서 불안정 → 솔리드 크림 배경.
	_vp.transparent_bg = false
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_2X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.size = Vector2i(480, 320)  # 레이아웃 전에도 렌더 타깃 크기 확보(stretch가 이후 갱신)
	add_child(_vp)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#FAF4E8")   # 패널과 동일 크림 톤
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 0.75
	env.environment = e
	_vp.add_child(env)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-52, -38, 0)
	key.light_energy = 1.1
	_vp.add_child(key)

	# 반대편 약한 필 라이트 — 그림자 쪽 원자도 색이 읽히도록(가독성).
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(40, 145, 0)
	fill.light_energy = 0.45
	_vp.add_child(fill)

	# 카메라 거리: 회전 시 셀 체대각(≈0.87) + 원자 반지름이 항상 화면에 들어오도록 여유.
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0, 3.6)
	cam.fov = 32.0
	_vp.add_child(cam)

	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	_apply_rot()
	if not figure.is_empty():
		_rebuild()


func set_figure(name: String) -> void:
	figure = name.strip_edges().to_lower()
	if is_inside_tree() and _pivot != null:
		_rebuild()


func _process(delta: float) -> void:
	if not _dragging and _pivot != null:
		_yaw += delta * 0.45   # 정지 시 잔잔한 자동 회전 → 3D 입체감 전달
		_apply_rot()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
	elif event is InputEventScreenTouch:
		_dragging = event.pressed
	elif (event is InputEventMouseMotion and _dragging) or event is InputEventScreenDrag:
		var rel: Vector2 = event.relative
		_yaw -= rel.x * 0.01
		_pitch = clampf(_pitch - rel.y * 0.01, -1.3, 1.3)
		_apply_rot()


func _apply_rot() -> void:
	if _pivot != null:
		_pivot.rotation = Vector3(_pitch, _yaw, 0)


# ─────────────────────────────────────────────────────────────────────────────
func _build_materials() -> void:
	_mat_corner = _atom_mat(COL_CORNER)
	_mat_face = _atom_mat(COL_FACE)
	_mat_body = _atom_mat(COL_BODY)
	_mat_inner = _atom_mat(COL_INNER)
	_mat_edge = StandardMaterial3D.new()
	_mat_edge.albedo_color = COL_EDGE
	_mat_edge.roughness = 0.9


func _atom_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.5
	m.metallic = 0.0
	m.rim_enabled = true
	m.rim = 0.3
	return m


func _rebuild() -> void:
	for ch in _pivot.get_children():
		ch.queue_free()
	match figure:
		"sc", "simple_cubic", "단순입방":
			_cubic(false, false, [])
		"bcc", "체심입방":
			_cubic(false, true, [])
		"fcc", "면심입방":
			_cubic(true, false, [])
		"diamond", "다이아몬드", "si":
			_cubic(true, false, [
				Vector3(0.25, 0.25, 0.25), Vector3(0.75, 0.75, 0.25),
				Vector3(0.75, 0.25, 0.75), Vector3(0.25, 0.75, 0.75)])
		"hcp", "육방조밀":
			_hcp()
		"zincblende", "zinc_blende", "sphalerite", "섬아연광", "gaas", "zns":
			# A = FCC 부격자(코너+면), B = 사면체 자리 4개. 두 원소 → 두 색.
			_compound_fcc([
				Vector3(0.25, 0.25, 0.25), Vector3(0.75, 0.75, 0.25),
				Vector3(0.75, 0.25, 0.75), Vector3(0.25, 0.75, 0.75)])
		"rocksalt", "rock_salt", "nacl", "halite", "암염":
			_rocksalt()
		"cscl", "cesium_chloride", "염화세슘":
			_cscl()
		"fluorite", "caf2", "calcium_fluoride", "형석":
			# Ca = FCC 부격자, F = 8개 사면체 자리 전부.
			_compound_fcc([
				Vector3(0.25, 0.25, 0.25), Vector3(0.75, 0.25, 0.25),
				Vector3(0.25, 0.75, 0.25), Vector3(0.25, 0.25, 0.75),
				Vector3(0.75, 0.75, 0.25), Vector3(0.75, 0.25, 0.75),
				Vector3(0.25, 0.75, 0.75), Vector3(0.75, 0.75, 0.75)])
		_:
			pass


# [0,1] 격자좌표 → 원점 중심 [-0.5,0.5].
func _c(x: float, y: float, z: float) -> Vector3:
	return Vector3(x - 0.5, y - 0.5, z - 0.5)


func _cubic(face: bool, body: bool, interior: Array) -> void:
	var corners := [
		_c(0, 0, 0), _c(1, 0, 0), _c(1, 1, 0), _c(0, 1, 0),
		_c(0, 0, 1), _c(1, 0, 1), _c(1, 1, 1), _c(0, 1, 1)]
	var edges := [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4],
		[0, 4], [1, 5], [2, 6], [3, 7]]
	for e in edges:
		_edge(corners[e[0]], corners[e[1]])
	for v in corners:
		_atom(v, _mat_corner)
	if face:
		for v in [_c(0.5, 0.5, 0), _c(0.5, 0.5, 1), _c(0.5, 0, 0.5),
				_c(0.5, 1, 0.5), _c(0, 0.5, 0.5), _c(1, 0.5, 0.5)]:
			_atom(v, _mat_face)
	if body:
		_atom(_c(0.5, 0.5, 0.5), _mat_body)
	for v in interior:
		_atom(_c(v.x, v.y, v.z), _mat_inner)


# 셀 모서리 + 8 코너 원자(공통). 코너 색은 mat 인자로 받는다(화합물 부격자 구분).
func _cell_frame(corner_mat: StandardMaterial3D) -> void:
	var corners: Array[Vector3] = [
		_c(0, 0, 0), _c(1, 0, 0), _c(1, 1, 0), _c(0, 1, 0),
		_c(0, 0, 1), _c(1, 0, 1), _c(1, 1, 1), _c(0, 1, 1)]
	var edges := [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4],
		[0, 4], [1, 5], [2, 6], [3, 7]]
	for e: Array in edges:
		_edge(corners[e[0]], corners[e[1]])
	for v: Vector3 in corners:
		_atom(v, corner_mat)


# 화합물 FCC 구조: 원소 A가 FCC 부격자(코너+면) 전부 = COL_CORNER 한 색,
# 원소 B는 interior 사면체 자리 = COL_FACE 한 색. (zincblende / fluorite)
func _compound_fcc(interior: Array) -> void:
	_cell_frame(_mat_corner)
	for v: Vector3 in [_c(0.5, 0.5, 0), _c(0.5, 0.5, 1), _c(0.5, 0, 0.5),
			_c(0.5, 1, 0.5), _c(0, 0.5, 0.5), _c(1, 0.5, 0.5)]:
		_atom(v, _mat_corner)
	for v: Vector3 in interior:
		_atom(_c(v.x, v.y, v.z), _mat_face)


# 암염(NaCl): A = FCC(코너 8 + 면 6), B = 모서리 중점 12 + 체심 1. 맞물린 두 FCC.
func _rocksalt() -> void:
	_cell_frame(_mat_corner)
	for v: Vector3 in [_c(0.5, 0.5, 0), _c(0.5, 0.5, 1), _c(0.5, 0, 0.5),
			_c(0.5, 1, 0.5), _c(0, 0.5, 0.5), _c(1, 0.5, 0.5)]:
		_atom(v, _mat_corner)
	# 12 모서리 중점.
	for v: Vector3 in [
			_c(0.5, 0, 0), _c(0.5, 1, 0), _c(0.5, 0, 1), _c(0.5, 1, 1),
			_c(0, 0.5, 0), _c(1, 0.5, 0), _c(0, 0.5, 1), _c(1, 0.5, 1),
			_c(0, 0, 0.5), _c(1, 0, 0.5), _c(0, 1, 0.5), _c(1, 1, 0.5)]:
		_atom(v, _mat_face)
	_atom(_c(0.5, 0.5, 0.5), _mat_face)  # 체심


# 염화세슘(CsCl): A = 코너 8, B = 체심 1. bcc 아님(서로 다른 이온 → 두 색).
func _cscl() -> void:
	_cell_frame(_mat_corner)
	_atom(_c(0.5, 0.5, 0.5), _mat_face)


func _hcp() -> void:
	var h := 0.5
	for layer in [-h, h]:
		_atom(Vector3(0, layer, 0), _mat_corner)
		for i in 6:
			var a := float(i) / 6.0 * TAU
			_atom(Vector3(cos(a) * 0.5, layer, sin(a) * 0.5), _mat_corner)
	for i in 3:
		var a := (float(i) / 3.0 + 1.0 / 6.0) * TAU
		_atom(Vector3(cos(a) * 0.29, 0, sin(a) * 0.29), _mat_face)
	# 상·하 육각 기둥 모서리.
	for i in 6:
		var a := float(i) / 6.0 * TAU
		var x := cos(a) * 0.5
		var z := sin(a) * 0.5
		_edge(Vector3(x, -h, z), Vector3(x, h, z))


func _atom(pos: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = ATOM_R
	sm.height = ATOM_R * 2.0
	sm.radial_segments = 20
	sm.rings = 10
	mi.mesh = sm
	mi.material_override = mat
	mi.position = pos
	_pivot.add_child(mi)


func _edge(a: Vector3, b: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.012
	cm.bottom_radius = 0.012
	cm.height = a.distance_to(b)
	cm.radial_segments = 6
	mi.mesh = cm
	mi.material_override = _mat_edge
	var mid := (a + b) * 0.5
	var dir := (b - a).normalized()
	var basis := Basis()
	if absf(dir.dot(Vector3.UP)) < 0.999:  # 실린더 기본축 +Y → dir 정렬
		basis = Basis(Quaternion(Vector3.UP, dir))
	mi.transform = Transform3D(basis, mid)
	_pivot.add_child(mi)
