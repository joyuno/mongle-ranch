# 개체 등급(★1~5) + 반짝(변종) — 희귀도 증폭 레이어. 순수 함수(Node 참조 없음).
#
# 같은 캐릭터라도 획득 시 숨김 등급이 굴려져 희소성·가격이 갈린다(★5 일반 > 기본 에픽).
# 융합(같은 종·같은 등급 2개 → 다음 등급 1개)이 중복 소진 싱크이자 등급 상승 경로.
# Design source: docs/GAME_DESIGN.md §2·§5.
class_name Grade
extends RefCounted

const MIN: int = 1
const MAX: int = 5

# 획득 시 등급 분포(per-mille, 합 1000). 낮게 편향 → ★5는 1%.
const ROLL_WEIGHTS: Dictionary = { 1: 600, 2: 250, 3: 100, 4: 40, 5: 10 }
# 가격 배수 — 등급에 가파르게 비례해 같은 캐릭터도 값이 크게 갈리게.
const PRICE_MULT: Dictionary = { 1: 1.0, 2: 1.5, 3: 2.5, 4: 4.0, 5: 7.0 }

const VARIANT_CHANCE: float = 0.005   # 반짝(이로치) 0.5% — 등급과 직교한 프레스티지
const VARIANT_PRICE_MULT: float = 3.0

const STAR: String = "★"


static func clamp_grade(g: int) -> int:
	return clampi(g, MIN, MAX)


static func roll_grade(rng: RandomNumberGenerator) -> int:
	var total := 0
	for g in ROLL_WEIGHTS:
		total += int(ROLL_WEIGHTS[g])
	var roll := rng.randi_range(0, total - 1)
	var acc := 0
	for g in [1, 2, 3, 4, 5]:
		acc += int(ROLL_WEIGHTS[g])
		if roll < acc:
			return g
	return MIN


static func roll_variant(rng: RandomNumberGenerator, chance: float = VARIANT_CHANCE) -> bool:
	return rng.randf() < chance


static func price_mult(grade: int, variant: bool = false) -> float:
	var m := float(PRICE_MULT.get(clamp_grade(grade), 1.0))
	return m * (VARIANT_PRICE_MULT if variant else 1.0)


static func stars(grade: int) -> String:
	return STAR.repeat(clamp_grade(grade))


# 융합 결과: 같은 등급 2개 → 등급+1(MAX 상한). 반짝은 둘 중 하나라도 있으면 유지.
static func fuse_result(grade: int, variant_a: bool, variant_b: bool) -> Dictionary:
	return { "grade": clamp_grade(grade + 1), "variant": variant_a or variant_b }


# ★5는 더 올릴 수 없음 — 융합 가능 여부.
static func can_fuse(grade: int) -> bool:
	return clamp_grade(grade) < MAX
