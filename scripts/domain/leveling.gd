# Leveling / combo / promotion thresholds.
# Ported from shared/constants/leveling.ts.

class_name Leveling
extends RefCounted

const XP_PER_CORRECT: int = 10
const PROMOTION_LEVELS: Array[int] = [5, 10, 20]

enum EffectStage { NOVICE, JUNIOR, SENIOR, LEGEND }

# Triangular: 100 * n * (n+1) / 2 ≤ xp → next level.
static func level_from_xp(xp: int) -> int:
	if xp <= 0:
		return 1
	var n := 1
	while (100 * n * (n + 1)) / 2 <= xp:
		n += 1
	return n


# Combo bonus per correct streak. 5+ triggers On Fire glow.
static func combo_multiplier(combo: int) -> float:
	if combo >= 10:
		return 3.0
	if combo >= 5:
		return 2.0
	if combo >= 2:
		return 1.5
	return 1.0


static func is_on_fire(combo: int) -> bool:
	return combo >= 5


static func effect_stage_from_level(level: int) -> EffectStage:
	if level >= 20:
		return EffectStage.LEGEND
	if level >= 10:
		return EffectStage.SENIOR
	if level >= 5:
		return EffectStage.JUNIOR
	return EffectStage.NOVICE


static func effect_stage_name(stage: EffectStage) -> String:
	match stage:
		EffectStage.NOVICE: return "novice"
		EffectStage.JUNIOR: return "junior"
		EffectStage.SENIOR: return "senior"
		EffectStage.LEGEND: return "legend"
	return "novice"
