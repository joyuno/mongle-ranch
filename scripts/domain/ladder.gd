# Quiz ladder ("더블 오어 나씽") math — pure functions.
#
# Design source: docs/GAME_DESIGN.md §2. A session is 5 questions; the prize
# doubles per correct answer (200 → 3,200). After every correct answer the
# player may bank the prize and end the session; a wrong answer or timeout
# zeroes the *session prize only* (level-ups and the 30-correct ticket
# counter are never rolled back — 무처벌 원칙).

class_name Ladder
extends RefCounted

const SESSION_SIZE: int = 5
# 기본 제한시간 30초. 팩 meta.default_time / 문항 time이 있으면 그쪽을 우선한다
# (pack_store.question_time_limit). 학습용이라 촉박하지 않게 잡는다.
const QUESTION_TIME: float = 30.0
const PRIZES: Array[int] = [200, 400, 800, 1600, 3200]

# Lifetime-correct milestone: every Nth correct answer grants a free gacha
# ticket (GitAnimals' "30 commits = 1 pet" mapped onto quiz answers).
const TICKET_EVERY_CORRECT: int = 30

# Daily coin earn cap from quizzes — anti-inflation guard.
const DAILY_COIN_CAP: int = 20000

# Streak restore price (Duolingo-2026-style paid revival).
const STREAK_RESTORE_COST: int = 2000

# Free streak-restore "shields" earned every Nth day of best streak, capped.
# Duolingo's streak-freeze study (Trophy 2026) found freeze-holders retain 17.19
# vs 11.62 days (+48%); free milestone refills signal care, not monetization.
# Pairing free shields with the paid restore keeps the 무처벌 원칙 intact.
const STREAK_SHIELD_EVERY: int = 7
const STREAK_SHIELD_CAP: int = 2


# Free shields the player should hold given a best streak, before any spends.
# At best=7 → 1, best=14 → 2, capped at STREAK_SHIELD_CAP.
static func shields_for_best(best: int) -> int:
	return clampi(best / STREAK_SHIELD_EVERY, 0, STREAK_SHIELD_CAP)


# Prize banked after answering `correct_count` questions correctly (0 → 0).
static func prize_for(correct_count: int) -> int:
	if correct_count <= 0:
		return 0
	return PRIZES[mini(correct_count, SESSION_SIZE) - 1]


# Tickets newly earned when lifetime correct moves old → new.
static func tickets_earned(old_total: int, new_total: int) -> int:
	if new_total <= old_total:
		return 0
	return new_total / TICKET_EVERY_CORRECT - old_total / TICKET_EVERY_CORRECT


# Clamp a quiz coin payout against today's already-earned amount.
static func capped_payout(amount: int, earned_today: int) -> int:
	return clampi(DAILY_COIN_CAP - earned_today, 0, amount)
