# Gacha draw + pity — pure functions over an injected RandomNumberGenerator
# so tests can fix the seed.
#
# Design source: docs/GAME_DESIGN.md §2. Pity ladder:
#   * soft pity A : every 10th pull (sinceEpic >= 9) guarantees epic-or-better
#   * soft pity B : from the 31st legendary-less pull, legendary chance grows
#                   +10%p per pull (sinceLegendary >= 30)
#   * hard pity   : the 40th legendary-less pull is a guaranteed legendary
#   * spark       : every pull grants +1 spark point; at 100 the player may
#                   pick any character outright (handled by the store/UI —
#                   this module only counts).

class_name Gacha
extends RefCounted

const PULL_COST_COIN: int = 1000
const EPIC_PITY_EVERY: int = 10      # pulls per guaranteed epic+
const LEGENDARY_SOFT_START: int = 30 # sinceLegendary at which the ramp begins
const LEGENDARY_SOFT_STEP: float = 0.10
const LEGENDARY_HARD_PITY: int = 40
const SPARK_TARGET: int = 100


static func default_pity() -> Dictionary:
	return { "sinceEpic": 0, "sinceLegendary": 0, "spark": 0 }


# Roll one pull. Mutates nothing — returns { "id", "rarity", "pity" } where
# pity is the *next* pity state to persist.
static func draw(pity: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var since_epic := int(pity.get("sinceEpic", 0))
	var since_leg := int(pity.get("sinceLegendary", 0))
	var spark := int(pity.get("spark", 0))

	var id := ""
	# Hard pity first, then the soft-pity ramp, then the epic guarantee,
	# then a plain weighted draw.
	if since_leg + 1 >= LEGENDARY_HARD_PITY:
		id = _weighted_pick_from(Characters.ids_of_rarity("legendary"), rng)
	elif since_leg >= LEGENDARY_SOFT_START and rng.randf() < float(since_leg - LEGENDARY_SOFT_START + 1) * LEGENDARY_SOFT_STEP:
		id = _weighted_pick_from(Characters.ids_of_rarity("legendary"), rng)
	elif since_epic + 1 >= EPIC_PITY_EVERY:
		var pool: Array[String] = []
		pool.append_array(Characters.ids_of_rarity("epic"))
		pool.append_array(Characters.ids_of_rarity("legendary"))
		id = _weighted_pick_from(pool, rng)
	else:
		id = _weighted_pick(rng)

	var rarity := Characters.rarity_of(id)
	var next := {
		"sinceEpic": 0 if Characters.rarity_rank(rarity) >= Characters.rarity_rank("epic") else since_epic + 1,
		"sinceLegendary": 0 if rarity == "legendary" else since_leg + 1,
		"spark": spark + 1,
	}
	return { "id": id, "rarity": rarity, "pity": next }


static func spark_ready(pity: Dictionary) -> bool:
	return int(pity.get("spark", 0)) >= SPARK_TARGET


# Spend a spark redemption — returns the next pity state (spark reset only;
# epic/legendary counters are untouched because spark is not a draw).
static func consume_spark(pity: Dictionary) -> Dictionary:
	var next := pity.duplicate()
	next["spark"] = maxi(0, int(pity.get("spark", 0)) - SPARK_TARGET)
	return next


# Plain GitAnimals-style per-mille weighted pick over the full roster.
static func _weighted_pick(rng: RandomNumberGenerator) -> String:
	return _weighted_pick_from(Characters.all_ids(), rng)


static func _weighted_pick_from(ids: Array[String], rng: RandomNumberGenerator) -> String:
	var total := 0
	for id in ids:
		total += _mille(id)
	if total <= 0 or ids.is_empty():
		return ids[0] if not ids.is_empty() else ""
	var roll := rng.randi_range(0, total - 1)
	var acc := 0
	for id in ids:
		acc += _mille(id)
		if roll < acc:
			return id
	return ids[ids.size() - 1]


static func _mille(id: String) -> int:
	return maxi(1, int(round(float(Characters.get_def(id).get("weight", 0.0)) * 1000.0)))
