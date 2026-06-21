# NPC market price math — pure functions. Animal-Crossing-style daily rate.
#
# Design source: docs/GAME_DESIGN.md §5.
#   sell  = base × m × (1 + 0.02 × level)
#   buy   = sell × 2.3            (the spread is the main coin sink)
#   m     = daily random walk, prev ± 0.10, clamped to [0.85, 1.15]
#   popular day: once a week one rarity sells for ×1.3~1.6
# Day rotation/state lives in ProgressStore; this module is stateless.

class_name Market
extends RefCounted

const BASE_PRICE: Dictionary = {
	"common": 300,
	"rare": 1200,
	"epic": 5000,
	"legendary": 20000,
}

const BUY_SPREAD: float = 2.3
const LEVEL_BONUS: float = 0.02
const M_MIN: float = 0.85
const M_MAX: float = 1.15
const M_STEP: float = 0.10
const POPULAR_MIN: float = 1.3
const POPULAR_MAX: float = 1.6
const DAILY_SELL_LIMIT: int = 3
const LISTINGS_MIN: int = 3
const LISTINGS_MAX: int = 5


static func base_price(rarity: String) -> int:
	return int(BASE_PRICE.get(rarity, 300))


static func sell_price(rarity: String, level: int, m: float, popular_bonus: float = 1.0,
		grade: int = 1, variant: bool = false) -> int:
	var raw := float(base_price(rarity)) * m * (1.0 + LEVEL_BONUS * float(maxi(0, level))) \
		* popular_bonus * Grade.price_mult(grade, variant)
	return maxi(1, int(round(raw)))


static func buy_price(rarity: String, level: int, m: float, popular_bonus: float = 1.0,
		grade: int = 1, variant: bool = false) -> int:
	return maxi(1, int(round(float(sell_price(rarity, level, m, popular_bonus, grade, variant)) * BUY_SPREAD)))


# One step of the daily random walk.
static func next_multiplier(prev: float, rng: RandomNumberGenerator) -> float:
	var stepped := prev + rng.randf_range(-M_STEP, M_STEP)
	return clampf(stepped, M_MIN, M_MAX)


# Popular day — deterministic per ISO week so save-scumming the clock within
# a week never re-rolls it. Returns { "rarity": String, "bonus": float } on the
# popular weekday, {} otherwise.
static func popular_of_day(date: Dictionary) -> Dictionary:
	var year := int(date.get("year", 2026))
	var month := int(date.get("month", 1))
	var day := int(date.get("day", 1))
	var weekday := int(date.get("weekday", 0))  # 0 = Sunday in Godot
	# Stable per-week hash → which weekday is "popular" + which rarity.
	var week := _week_key(year, month, day, weekday)
	var h := hash("%d-popular" % week)
	if weekday != int(abs(h)) % 7:
		return {}
	var rarities := Characters.RARITY_ORDER
	var rarity: String = rarities[int(abs(h >> 3)) % rarities.size()]
	var bonus := POPULAR_MIN + (float(int(abs(h >> 7)) % 100) / 100.0) * (POPULAR_MAX - POPULAR_MIN)
	return { "rarity": rarity, "bonus": snappedf(bonus, 0.01) }


# Roll today's NPC listings: 3~5 entries of { id, level, price }. Prices use
# the buy formula so the NPC always charges the spread.
static func roll_listings(m: float, popular: Dictionary, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var listings: Array[Dictionary] = []
	var n := rng.randi_range(LISTINGS_MIN, LISTINGS_MAX)
	for i in n:
		var roll := Gacha.draw(Gacha.default_pity(), rng)  # plain weighted pick, pity-less
		var id: String = roll["id"]
		var rarity: String = roll["rarity"]
		var level := rng.randi_range(1, 10)
		var grade := Grade.roll_grade(rng)
		var variant := Grade.roll_variant(rng)
		var bonus := float(popular.get("bonus", 1.0)) if String(popular.get("rarity", "")) == rarity else 1.0
		listings.append({
			"id": id,
			"level": level,
			"grade": grade,
			"variant": variant,
			"price": buy_price(rarity, level, m, bonus, grade, variant),
		})
	return listings


# Days are keyed "YYYY-MM-DD" — the store compares against this to decide
# when to advance the walk and re-roll listings.
static func day_key(date: Dictionary) -> String:
	return "%04d-%02d-%02d" % [int(date.get("year", 0)), int(date.get("month", 0)), int(date.get("day", 0))]


static func _week_key(year: int, month: int, day: int, weekday: int) -> int:
	# Approximate ISO-week bucket: days-since-epoch / 7. Good enough for a
	# deterministic weekly re-roll; exactness across year boundaries is moot.
	var days := year * 372 + month * 31 + day  # monotonic pseudo-ordinal
	return (days - weekday) / 7
