# 절차적 교배 — 부모 두 마리 형질을 재조합해 자식 1마리를 산출(순수 함수).
#
# 런타임 이미지 생성 API는 호출하지 않는다(docs/RISKS.md HIGH). 자식의 '유니크함'은
# 종 상속 + 등급 롤 + 반짝 변종 + 색조(tint hue) 블렌드로 만들고, 표시는 기존 스프라이트에
# 런타임 색조 회전 + 등급 별 오버레이로 합성한다(외부 API·비용·IP 0).
# Design source: docs/GAME_DESIGN.md §2.
class_name Breeding
extends RefCounted

const COIN_COST: int = 800
const MUTATION_CHANCE: float = 0.12   # 자식 종이 더 높은 부모 희귀도의 한 단계 위로 변이
const LUCKY_GRADE_CHANCE: float = 0.10
const SHINY_CHANCE: float = 0.015     # 가챠(0.5%)보다 약간 높음 — 교배 보상감


# 부모 정보 → 자식. rng 주입(테스트 시드 고정).
# 반환: { id, grade, variant, tint }  (tint = 1..359 색상 hue, 자식은 항상 색조 부여)
static func offspring(a_id: String, b_id: String, a_grade: int, b_grade: int,
		a_variant: bool, b_variant: bool, a_tint: int, b_tint: int,
		rng: RandomNumberGenerator) -> Dictionary:
	# 종: 변이 시 더 높은 부모 희귀도의 한 단계 위에서 무작위, 아니면 부모 중 하나.
	var child_id := ""
	if rng.randf() < MUTATION_CHANCE:
		var hi := maxi(Characters.rarity_rank(Characters.rarity_of(a_id)),
			Characters.rarity_rank(Characters.rarity_of(b_id)))
		var up := mini(hi + 1, Characters.RARITY_ORDER.size() - 1)
		var pool := Characters.ids_of_rarity(Characters.RARITY_ORDER[up])
		child_id = pool[rng.randi_range(0, pool.size() - 1)] if not pool.is_empty() else a_id
	else:
		child_id = a_id if rng.randf() < 0.5 else b_id

	# 등급: 부모 평균 ± 1 롤, 가끔 행운 +1.
	var g := int(round((a_grade + b_grade) / 2.0)) + rng.randi_range(-1, 1)
	if rng.randf() < LUCKY_GRADE_CHANCE:
		g += 1
	g = Grade.clamp_grade(g)

	# 반짝: 둘 다 반짝이면 상속, 아니면 SHINY_CHANCE 롤.
	var variant := (a_variant and b_variant) or rng.randf() < SHINY_CHANCE

	# 색조: 부모 hue 원형 평균 + 지터. 부모 tint가 0이면 종 id 해시로 시드.
	var ha := a_tint if a_tint > 0 else (absi(a_id.hash()) % 360)
	var hb := b_tint if b_tint > 0 else (absi(b_id.hash()) % 360)
	var tint := _circular_mean(ha, hb) + rng.randi_range(-20, 20)
	tint = ((tint % 360) + 360) % 360
	if tint == 0:
		tint = 1  # 0은 '색조 없음(원본)'을 의미하므로 자식은 최소 1.

	return { "id": child_id, "grade": g, "variant": variant, "tint": tint }


# 두 hue(0..359)의 원형 평균 — 색상환을 가로지르는 경우를 처리.
static func _circular_mean(a: int, b: int) -> int:
	var diff := absi(a - b)
	if diff <= 180:
		return (a + b) / 2
	return (((a + b) / 2) + 180) % 360
