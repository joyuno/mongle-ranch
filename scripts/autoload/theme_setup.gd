# Builds a global Theme at boot — cozy pastel light palette (docs/DESIGN_SPEC.md
# §D). Applied via get_tree().root.theme so every Control auto-inherits.
#
# Cozy direction (2026 Soft-UI research): cream backgrounds (never pure white),
# warm dark-brown text (never pure black), soft pastel accents, rounded corners
# and a gentle drop shadow on every card. Built in code (not a .tres) so the
# styling stays greppable and avoids unstable binary diffs.

extends Node

# Runtime load (not preload) so the first --import pass can complete before
# the OTF .import metadata is required.
const FONT_REGULAR_PATH := "res://assets/fonts/Pretendard-Regular.otf"
const FONT_BOLD_PATH := "res://assets/fonts/Pretendard-Bold.otf"
const FONT_JP_REGULAR_PATH := "res://assets/fonts/NotoSansJP-Regular.woff2"
const FONT_JP_BOLD_PATH := "res://assets/fonts/NotoSansJP-Bold.woff2"

# ─ Cozy pastel light palette (single source of truth for every screen) ─
const C_BG        := Color("#FAF4E8")  # 크림 배경 (순백 금지)
const C_PANEL     := Color("#FFFDF7")  # 카드 표면
const C_PANEL_2   := Color("#F3E9D6")  # raised / 버튼 기본
const C_BORDER    := Color("#E4D5BC")
const C_TEXT      := Color("#4A3F35")  # 따뜻한 다크브라운 (순흑 금지)
const C_MUTED     := Color("#9A8A76")
const C_ACCENT    := Color("#F2A0A8")  # 소프트 코랄 — 긍정/CTA
const C_ACCENT_SOFT := Color("#FBDCDF")  # 코랄 연한 배경
const C_ACCENT_2  := Color("#A8D8C0")  # 민트 — 보조
const C_OK        := Color("#8FCB8F")  # 부드러운 초록
const C_WARN      := Color("#F5C97A")  # 부드러운 노랑
const C_DANGER    := Color("#E89090")  # 부드러운 빨강 (경고도 순함)
const C_INK       := Color("#3B3129")  # 캐릭터 잉크색과 동일 — 섀도/외곽선 베이스

# ─ Typography tokens (인라인 override 대신 이 토큰을 쓴다) ─
const FS_BODY    := 15
const FS_SUB     := 18
const FS_TITLE   := 24
const FS_DISPLAY := 32

# ─ 공통 라운드/섀도 상수 ─
const RADIUS_CARD   := 16
const RADIUS_BUTTON := 12

# 희귀도 색 — 단일 출처(가챠·도감·시장이 공유). 크림 배경 대비를 위해
# 라이트 테마용으로 retune(기존 다크값은 크림 위에서 묻혔음).
const RARITY_COLORS := {
	"common": Color("#6B7280"),     # 차분한 회색
	"rare": Color("#3E7FD6"),       # 또렷한 파랑
	"epic": Color("#9B5FD0"),       # 보라
	"legendary": Color("#C8941E"),  # 진한 골드
}


func _ready() -> void:
	var theme := Theme.new()
	var font_regular: Font = load(FONT_REGULAR_PATH) as Font
	var font_bold: Font = load(FONT_BOLD_PATH) as Font

	# JP fallback so kana/kanji resolve instead of tofu on platforms without
	# OS font fallback.
	var jp_regular: Font = load(FONT_JP_REGULAR_PATH) as Font
	var jp_bold: Font = load(FONT_JP_BOLD_PATH) as Font
	if font_regular and jp_regular:
		font_regular.fallbacks = [jp_regular]
	if font_bold and jp_bold:
		font_bold.fallbacks = [jp_bold]

	if font_regular:
		theme.default_font = font_regular
	theme.default_font_size = FS_BODY

	# ─ Label
	theme.set_color("font_color", "Label", C_TEXT)

	# ─ Button (idle / hover / pressed / disabled) — 둥근 코지 버튼 + 섀도
	var btn_normal := _stylebox(C_PANEL_2, C_BORDER, RADIUS_BUTTON, true)
	var btn_hover := _stylebox(C_PANEL_2.lightened(0.05), C_ACCENT, RADIUS_BUTTON, true)
	var btn_pressed := _stylebox(C_ACCENT_SOFT, C_ACCENT, RADIUS_BUTTON, false)
	var btn_disabled := _stylebox(C_PANEL, C_BORDER, RADIUS_BUTTON, false)
	btn_disabled.bg_color.a = 0.6
	theme.set_stylebox("normal", "Button", btn_normal)
	theme.set_stylebox("hover", "Button", btn_hover)
	theme.set_stylebox("pressed", "Button", btn_pressed)
	theme.set_stylebox("focus", "Button", _stylebox(C_PANEL_2, C_ACCENT, RADIUS_BUTTON, false))
	theme.set_stylebox("disabled", "Button", btn_disabled)
	theme.set_color("font_color", "Button", C_TEXT)
	theme.set_color("font_hover_color", "Button", C_INK)
	theme.set_color("font_pressed_color", "Button", C_INK)
	theme.set_color("font_disabled_color", "Button", C_MUTED)
	if font_bold:
		theme.set_font("font", "Button", font_bold)
	theme.set_font_size("font_size", "Button", FS_BODY)

	# ─ OptionButton
	theme.set_stylebox("normal", "OptionButton", btn_normal)
	theme.set_stylebox("hover", "OptionButton", btn_hover)
	theme.set_stylebox("pressed", "OptionButton", btn_pressed)
	theme.set_stylebox("focus", "OptionButton", _stylebox(C_PANEL_2, C_ACCENT, RADIUS_BUTTON, false))
	theme.set_color("font_color", "OptionButton", C_TEXT)

	# ─ PanelContainer / Panel (카드 — 라운드 + 부드러운 섀도)
	theme.set_stylebox("panel", "PanelContainer", _stylebox(C_PANEL, C_BORDER, RADIUS_CARD, true))
	theme.set_stylebox("panel", "Panel", _stylebox(C_PANEL, C_BORDER, RADIUS_CARD, true))

	# ─ PopupMenu (간식 메뉴 등)
	theme.set_stylebox("panel", "PopupMenu", _stylebox(C_PANEL, C_BORDER, RADIUS_CARD, true))
	theme.set_color("font_color", "PopupMenu", C_TEXT)
	theme.set_color("font_hover_color", "PopupMenu", C_INK)

	# ─ ProgressBar (타이머 / 진행바) — 둥근, 코랄 채움
	var pb_bg := _stylebox(C_PANEL_2, C_BORDER, 8, false)
	var pb_fg := _stylebox(C_ACCENT, C_ACCENT.darkened(0.12), 8, false)
	theme.set_stylebox("background", "ProgressBar", pb_bg)
	theme.set_stylebox("fill", "ProgressBar", pb_fg)
	theme.set_color("font_color", "ProgressBar", C_TEXT)

	# ─ LineEdit (설정 GitHub 입력 등) — 다크 기본 대신 크림 입력 카드
	var le_normal := _stylebox(C_PANEL, C_BORDER, RADIUS_BUTTON, false)
	var le_focus := _stylebox(C_PANEL, C_ACCENT, RADIUS_BUTTON, false)
	theme.set_stylebox("normal", "LineEdit", le_normal)
	theme.set_stylebox("focus", "LineEdit", le_focus)
	theme.set_color("font_color", "LineEdit", C_TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", C_MUTED)
	theme.set_color("caret_color", "LineEdit", C_ACCENT)
	theme.set_color("selection_color", "LineEdit", C_ACCENT_SOFT)

	# ─ TabContainer / TabBar (도감 탭) — 라이트 톤
	var tab_sel := _stylebox(C_PANEL, C_ACCENT, RADIUS_BUTTON, false)
	var tab_unsel := _stylebox(C_PANEL_2, C_BORDER, RADIUS_BUTTON, false)
	tab_unsel.bg_color.a = 0.7
	for cls in ["TabContainer", "TabBar"]:
		theme.set_stylebox("tab_selected", cls, tab_sel)
		theme.set_stylebox("tab_unselected", cls, tab_unsel)
		theme.set_stylebox("tab_hovered", cls, _stylebox(C_PANEL_2, C_ACCENT, RADIUS_BUTTON, false))
		theme.set_color("font_selected_color", cls, C_INK)
		theme.set_color("font_unselected_color", cls, C_MUTED)
		theme.set_color("font_hovered_color", cls, C_TEXT)
	theme.set_stylebox("panel", "TabContainer", _stylebox(C_PANEL, C_BORDER, RADIUS_CARD, false))

	# ─ CheckButton (설정 토글) — 행 전체가 색칠되지 않게 배경 비우고 글자만
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		theme.set_stylebox(st, "CheckButton", empty)
	theme.set_color("font_color", "CheckButton", C_TEXT)
	theme.set_color("font_hover_color", "CheckButton", C_INK)
	theme.set_color("font_pressed_color", "CheckButton", C_INK)
	theme.set_stylebox("normal", "CheckBox", empty)
	theme.set_color("font_color", "CheckBox", C_TEXT)
	# 토글 스위치 그래픽(코지 pill) — 절차 생성 텍스처. 없으면 엔진 기본 사용.
	var tog_on := "res://assets/decor/toggle_on.png"
	var tog_off := "res://assets/decor/toggle_off.png"
	if ResourceLoader.exists(tog_on) and ResourceLoader.exists(tog_off):
		theme.set_icon("checked", "CheckButton", load(tog_on))
		theme.set_icon("unchecked", "CheckButton", load(tog_off))

	# ─ ScrollBar (세로/가로) — 다크 거터 제거: 트랙 옅게, 그래버 탄색 라운드
	var sb_track := _stylebox(C_BG, C_BG, 6, false)
	sb_track.bg_color.a = 0.0
	sb_track.border_color.a = 0.0
	var grabber := _stylebox(C_BORDER, C_BORDER, 6, false)
	var grabber_hi := _stylebox(C_MUTED, C_MUTED, 6, false)
	for cls in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", cls, sb_track)
		theme.set_stylebox("scroll_focus", cls, sb_track)
		theme.set_stylebox("grabber", cls, grabber)
		theme.set_stylebox("grabber_highlight", cls, grabber_hi)
		theme.set_stylebox("grabber_pressed", cls, grabber_hi)

	# ─ 루트 클리어 컬러 = 크림 배경
	RenderingServer.set_default_clear_color(C_BG)

	get_tree().root.theme = theme

	# ─ OS 창을 디자인 해상도(1280x800)로 고정 + 중앙 정렬 (hidpi 스케일 보정).
	if DisplayServer.get_name() != "headless":
		var target_size := Vector2i(1280, 800)
		DisplayServer.window_set_size(target_size)
		var screen_size := DisplayServer.screen_get_size()
		DisplayServer.window_set_position((screen_size - target_size) / 2)


# Helper — FlatStyleBox with bg, border, corner radius, optional soft shadow.
static func _stylebox(bg: Color, border: Color, radius: int, shadow: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(radius)
	sb.corner_detail = 12
	sb.anti_aliasing = true
	sb.anti_aliasing_size = 1.0
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	if shadow:
		sb.shadow_color = Color(C_INK.r, C_INK.g, C_INK.b, 0.16)
		sb.shadow_size = 8
		sb.shadow_offset = Vector2(0, 4)
	return sb


# 코드에서 임의 색의 카드 스타일을 만들 때 쓰는 공개 헬퍼 (화면 스크립트용).
static func card(bg: Color = C_PANEL, border: Color = C_BORDER, radius: int = RADIUS_CARD, shadow: bool = true) -> StyleBoxFlat:
	return _stylebox(bg, border, radius, shadow)


# 천단위 콤마 정수 포맷 — 모든 화면이 코인/숫자에 공유(683000 → "683,000").
static func fmt_int(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out
