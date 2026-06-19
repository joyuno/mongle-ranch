# Player progress — autoloaded, persists to user://progress.json (atomic write,
# same tmp→rename pattern as study_game_godot). Holds wallet, collection,
# gacha pity, NPC market state, streak, GitHub snack ledger and quiz stats.
#
# 무처벌 원칙 (docs/GAME_DESIGN.md §2): nothing in this store ever removes a
# character or lowers a level except an explicit player action (merge / sell).

extends Node

signal progress_changed
signal coins_changed(amount: int)
signal tickets_changed(count: int)
signal snacks_changed(count: int)
signal collection_changed
signal character_obtained(uid: int, id: String, rarity: String)
signal character_leveled(uid: int, level: int)
signal pity_changed(pity: Dictionary)
signal market_changed
signal streak_changed(count: int)
signal quiet_mode_changed(enabled: bool)
signal timer_enabled_changed(enabled: bool)
signal font_size_scale_changed(scale: int)
signal github_username_changed(username: String)

const SCHEMA_VERSION: int = 1
const MAX_SESSION_HISTORY: int = 100
const SAVE_PATH: String = "user://progress.json"
const SAVE_PATH_TMP: String = "user://progress.json.tmp"
const SAVE_PATH_BAK: String = "user://progress.json.bak"

const STARTER_COINS: int = 3000
const RANCH_DISPLAY_MAX: int = 30
const COLLECTION_CAP: int = 500   # sanity clamp on load — not a gameplay limit

var progress: Dictionary = _default_progress()
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	_load_from_disk()
	ensure_market_day()


# -----------------------------------------------------------------------------
# Read-only accessors
# -----------------------------------------------------------------------------
func get_coins() -> int:
	return int(progress.get("coins", 0))


func get_tickets() -> int:
	return int(progress.get("gachaTickets", 0))


func get_snacks() -> int:
	return int(progress.get("snacks", 0))


func get_xp() -> int:
	return int(progress.get("totalXP", 0))


func get_level() -> int:
	return Leveling.level_from_xp(get_xp())


func get_total_correct() -> int:
	return int(progress.get("totalCorrect", 0))


func get_collection() -> Array:
	var c = progress.get("collection", [])
	return c if typeof(c) == TYPE_ARRAY else []


func get_character(uid: int) -> Dictionary:
	for e in get_collection():
		if int(e.get("uid", -1)) == uid:
			return e
	return {}


func owned_ids() -> Array[String]:
	var ids: Array[String] = []
	for e in get_collection():
		var id := String(e.get("id", ""))
		if not ids.has(id):
			ids.append(id)
	return ids


# Characters shown on the ranch — first RANCH_DISPLAY_MAX by default, or the
# player-picked roster from the collection screen.
func ranch_members() -> Array:
	var roster = progress.get("ranchRoster", [])
	var col := get_collection()
	if typeof(roster) != TYPE_ARRAY or (roster as Array).is_empty():
		return col.slice(0, mini(col.size(), RANCH_DISPLAY_MAX))
	var members: Array = []
	for uid in roster:
		var e := get_character(int(uid))
		if not e.is_empty():
			members.append(e)
		if members.size() >= RANCH_DISPLAY_MAX:
			break
	return members


func set_ranch_roster(uids: Array) -> void:
	progress["ranchRoster"] = uids.slice(0, RANCH_DISPLAY_MAX)
	_persist()
	collection_changed.emit()


func get_pity() -> Dictionary:
	var p = progress.get("pity", Gacha.default_pity())
	return p if typeof(p) == TYPE_DICTIONARY else Gacha.default_pity()


func get_streak() -> Dictionary:
	var s = progress.get("streak", {})
	return s if typeof(s) == TYPE_DICTIONARY else {}


func get_github_username() -> String:
	return String(progress.get("githubUsername", ""))


func get_github_last_event_id() -> String:
	return String(progress.get("githubLastEventId", ""))


func is_quiet_mode() -> bool:
	return bool(progress.get("quietMode", false))


func is_timer_enabled() -> bool:
	return bool(progress.get("timerEnabled", true))


func get_font_size_scale() -> int:
	return int(progress.get("fontSizeScale", 1))


func get_wrong_note() -> Array:
	var w = progress.get("wrongNote", [])
	return w if typeof(w) == TYPE_ARRAY else []


func get_progress_value(key: String, fallback):
	return progress.get(key, fallback)


# -----------------------------------------------------------------------------
# Wallet
# -----------------------------------------------------------------------------
func add_coins(amount: int) -> void:
	progress["coins"] = maxi(0, get_coins() + amount)
	_persist()
	progress_changed.emit()
	coins_changed.emit(get_coins())


func spend_coins(amount: int) -> bool:
	if get_coins() < amount:
		return false
	progress["coins"] = get_coins() - amount
	_persist()
	progress_changed.emit()
	coins_changed.emit(get_coins())
	return true


# Quiz payouts go through the daily anti-inflation cap (Ladder.DAILY_COIN_CAP).
# Returns the amount actually granted.
func add_quiz_coins(amount: int) -> int:
	var today := _today_key()
	var ledger: Dictionary = progress.get("coinsEarnedToday", {})
	if String(ledger.get("day", "")) != today:
		ledger = { "day": today, "amount": 0 }
	var granted := Ladder.capped_payout(amount, int(ledger.get("amount", 0)))
	ledger["amount"] = int(ledger.get("amount", 0)) + granted
	progress["coinsEarnedToday"] = ledger
	if granted > 0:
		add_coins(granted)
	else:
		_persist()
	return granted


func add_tickets(n: int) -> void:
	if n <= 0:
		return
	progress["gachaTickets"] = get_tickets() + n
	_persist()
	progress_changed.emit()
	tickets_changed.emit(get_tickets())


# -----------------------------------------------------------------------------
# Quiz integration — called by PackStore
# -----------------------------------------------------------------------------
func add_xp(amount: int) -> void:
	progress["totalXP"] = maxi(0, get_xp() + amount)
	progress["level"] = Leveling.level_from_xp(get_xp())
	_persist()
	progress_changed.emit()


# One lifetime-correct tick: milestone tickets + a random owned character
# levels up (GitAnimals' "every contribution levels a random pet").
func record_correct_answer() -> Dictionary:
	var old_total := get_total_correct()
	var new_total := old_total + 1
	progress["totalCorrect"] = new_total
	var tickets := Ladder.tickets_earned(old_total, new_total)
	if tickets > 0:
		progress["gachaTickets"] = get_tickets() + tickets
	var leveled := _random_levelup()
	_persist()
	progress_changed.emit()
	if tickets > 0:
		tickets_changed.emit(get_tickets())
	return { "tickets": tickets, "leveled": leveled }


func touch_streak() -> void:
	var today := _today_key()
	var s := get_streak()
	var last := String(s.get("lastDay", ""))
	if last == today:
		return
	var count := int(s.get("count", 0))
	count = count + 1 if last == _yesterday_key() else 1
	# Earn a free restore shield each weekly milestone, held up to the cap.
	# count only steps +1 per day here, so each multiple of 7 is hit once per
	# climb (restores jump count via restore_streak and never re-trigger it).
	var shields := int(s.get("shields", 0))
	if count > 0 and count % Ladder.STREAK_SHIELD_EVERY == 0:
		shields = mini(Ladder.STREAK_SHIELD_CAP, shields + 1)
	progress["streak"] = {
		"lastDay": today,
		"count": count,
		"best": maxi(count, int(s.get("best", 0))),
		"brokenCount": int(s.get("brokenCount", 0)),
		"shields": shields,
	}
	_persist()
	streak_changed.emit(count)


func get_streak_shields() -> int:
	return int(get_streak().get("shields", 0))


# Streak revival. Spends a free shield first (Duolingo milestone-refill model),
# falling back to a paid restore only when no shield is held. Returns whether
# the restore was free so the UI can phrase it as care, not a charge.
func restore_streak() -> Dictionary:
	var s := get_streak()
	var best := int(s.get("best", 0))
	if best <= int(s.get("count", 0)):
		return { "ok": false, "reason": "nothing_to_restore" }
	var free := int(s.get("shields", 0)) > 0
	if free:
		s["shields"] = int(s.get("shields", 0)) - 1
	elif not spend_coins(Ladder.STREAK_RESTORE_COST):
		return { "ok": false, "reason": "not_enough_coins", "cost": Ladder.STREAK_RESTORE_COST }
	s["count"] = best
	s["lastDay"] = _today_key()
	progress["streak"] = s
	_persist()
	streak_changed.emit(best)
	return { "ok": true, "count": best, "free": free }


func record_session(record: Dictionary) -> void:
	var sessions: Array = progress.get("sessions", [])
	sessions.append(record)
	if sessions.size() > MAX_SESSION_HISTORY:
		sessions = sessions.slice(sessions.size() - MAX_SESSION_HISTORY)
	progress["sessions"] = sessions
	_persist()
	progress_changed.emit()


# -----------------------------------------------------------------------------
# Gacha
# -----------------------------------------------------------------------------
# pay ∈ {"coins", "ticket"}.
func gacha_pull(pay: String) -> Dictionary:
	match pay:
		"coins":
			if not spend_coins(Gacha.PULL_COST_COIN):
				return { "ok": false, "reason": "not_enough_coins" }
		"ticket":
			if get_tickets() < 1:
				return { "ok": false, "reason": "not_enough_tickets" }
			progress["gachaTickets"] = get_tickets() - 1
			tickets_changed.emit(get_tickets())
		_:
			return { "ok": false, "reason": "bad_payment" }
	var result := Gacha.draw(get_pity(), rng)
	progress["pity"] = result["pity"]
	var uid := _grant_character(String(result["id"]))
	_persist()
	progress_changed.emit()
	pity_changed.emit(get_pity())
	return { "ok": true, "uid": uid, "id": result["id"], "rarity": result["rarity"] }


func spark_redeem(id: String) -> Dictionary:
	if not Gacha.spark_ready(get_pity()):
		return { "ok": false, "reason": "spark_not_ready" }
	if Characters.get_def(id).is_empty():
		return { "ok": false, "reason": "unknown_character" }
	progress["pity"] = Gacha.consume_spark(get_pity())
	var uid := _grant_character(id)
	_persist()
	progress_changed.emit()
	pity_changed.emit(get_pity())
	return { "ok": true, "uid": uid, "id": id, "rarity": Characters.rarity_of(id) }


# -----------------------------------------------------------------------------
# Collection — merge / feed / level
# -----------------------------------------------------------------------------
# Sacrifice src (deleted forever) and add its levels onto dst. The only way
# duplicates leave the collection besides selling.
func merge_characters(src_uid: int, dst_uid: int) -> Dictionary:
	if src_uid == dst_uid:
		return { "ok": false, "reason": "same_character" }
	var src := get_character(src_uid)
	var dst := get_character(dst_uid)
	if src.is_empty() or dst.is_empty():
		return { "ok": false, "reason": "not_found" }
	if String(src.get("id", "")) != String(dst.get("id", "")):
		return { "ok": false, "reason": "different_species" }
	var col := get_collection()
	for i in col.size():
		if int(col[i].get("uid", -1)) == dst_uid:
			col[i]["level"] = int(col[i].get("level", 1)) + int(src.get("level", 1))
			character_leveled.emit(dst_uid, int(col[i]["level"]))
	progress["collection"] = col.filter(func(e): return int(e.get("uid", -1)) != src_uid)
	_remove_from_roster(src_uid)
	_persist()
	progress_changed.emit()
	collection_changed.emit()
	return { "ok": true, "level": int(get_character(dst_uid).get("level", 1)) }


# Feed a GitHub snack: +1 level and a happy emote (UI side).
func feed_snack(uid: int) -> Dictionary:
	if get_snacks() < 1:
		return { "ok": false, "reason": "no_snacks" }
	var e := get_character(uid)
	if e.is_empty():
		return { "ok": false, "reason": "not_found" }
	progress["snacks"] = get_snacks() - 1
	var col := get_collection()
	for i in col.size():
		if int(col[i].get("uid", -1)) == uid:
			col[i]["level"] = int(col[i].get("level", 1)) + 1
			character_leveled.emit(uid, int(col[i]["level"]))
	progress["collection"] = col
	_persist()
	progress_changed.emit()
	snacks_changed.emit(get_snacks())
	collection_changed.emit()
	return { "ok": true, "level": int(get_character(uid).get("level", 1)) }


# -----------------------------------------------------------------------------
# GitHub snacks — called by GithubSync (already capped by GithubSnacks domain)
# -----------------------------------------------------------------------------
func grant_snacks(n: int, latest_event_id: String) -> int:
	var today := _today_key()
	var ledger: Dictionary = progress.get("snacksGrantedToday", {})
	if String(ledger.get("day", "")) != today:
		ledger = { "day": today, "count": 0 }
	var granted := GithubSnacks.snacks_to_grant(n, int(ledger.get("count", 0)))
	ledger["count"] = int(ledger.get("count", 0)) + granted
	progress["snacksGrantedToday"] = ledger
	if not latest_event_id.is_empty():
		progress["githubLastEventId"] = latest_event_id
	if granted > 0:
		progress["snacks"] = get_snacks() + granted
	_persist()
	progress_changed.emit()
	if granted > 0:
		snacks_changed.emit(get_snacks())
	return granted


func snacks_granted_today() -> int:
	var ledger: Dictionary = progress.get("snacksGrantedToday", {})
	if String(ledger.get("day", "")) != _today_key():
		return 0
	return int(ledger.get("count", 0))


func set_github_username(username: String) -> void:
	var clean := username.strip_edges()
	if clean == get_github_username():
		return
	progress["githubUsername"] = clean
	progress["githubLastEventId"] = ""  # new account starts a fresh ledger
	_persist()
	github_username_changed.emit(clean)


# -----------------------------------------------------------------------------
# Market
# -----------------------------------------------------------------------------
func get_market() -> Dictionary:
	var m = progress.get("market", {})
	return m if typeof(m) == TYPE_DICTIONARY else {}


# Advance the daily walk + re-roll listings if the calendar day changed.
func ensure_market_day() -> void:
	var date := Time.get_datetime_dict_from_system()
	var today := Market.day_key(date)
	var market := get_market()
	if String(market.get("day", "")) == today:
		return
	var prev_m := float(market.get("m", 1.0))
	var m := Market.next_multiplier(prev_m, rng)
	var popular := Market.popular_of_day(date)
	progress["market"] = {
		"day": today,
		"m": m,
		"popular": popular,
		"listings": Market.roll_listings(m, popular, rng),
		"soldToday": 0,
	}
	_persist()
	market_changed.emit()


func sell_character(uid: int) -> Dictionary:
	ensure_market_day()
	var market := get_market()
	if int(market.get("soldToday", 0)) >= Market.DAILY_SELL_LIMIT:
		return { "ok": false, "reason": "daily_limit" }
	var e := get_character(uid)
	if e.is_empty():
		return { "ok": false, "reason": "not_found" }
	var id := String(e.get("id", ""))
	var rarity := Characters.rarity_of(id)
	var popular: Dictionary = market.get("popular", {})
	var bonus := float(popular.get("bonus", 1.0)) if String(popular.get("rarity", "")) == rarity else 1.0
	var price := Market.sell_price(rarity, int(e.get("level", 1)), float(market.get("m", 1.0)), bonus)
	progress["collection"] = get_collection().filter(func(c): return int(c.get("uid", -1)) != uid)
	_remove_from_roster(uid)
	market["soldToday"] = int(market.get("soldToday", 0)) + 1
	progress["market"] = market
	add_coins(price)
	collection_changed.emit()
	market_changed.emit()
	return { "ok": true, "price": price, "id": id }


func buy_listing(index: int) -> Dictionary:
	ensure_market_day()
	var market := get_market()
	var listings: Array = market.get("listings", [])
	if index < 0 or index >= listings.size():
		return { "ok": false, "reason": "bad_index" }
	var item: Dictionary = listings[index]
	if not spend_coins(int(item.get("price", 0))):
		return { "ok": false, "reason": "not_enough_coins" }
	var uid := _grant_character(String(item.get("id", "")), int(item.get("level", 1)))
	listings.remove_at(index)
	market["listings"] = listings
	progress["market"] = market
	_persist()
	market_changed.emit()
	return { "ok": true, "uid": uid, "id": item.get("id", "") }


# -----------------------------------------------------------------------------
# Wrong note + quiz session resume (ported from study_game_godot)
# -----------------------------------------------------------------------------
func add_wrong_entry(entry: Dictionary) -> void:
	var wrong: Array = progress.get("wrongNote", [])
	var qh: String = entry.get("questionHash", "")
	for i in wrong.size():
		if wrong[i].get("questionHash", "") == qh:
			wrong[i]["timesWrong"] = int(wrong[i].get("timesWrong", 1)) + 1
			wrong[i]["lastWrongAt"] = entry.get("lastWrongAt", "")
			wrong[i]["userAnswer"] = entry.get("userAnswer", null)
			progress["wrongNote"] = wrong
			_persist()
			progress_changed.emit()
			return
	wrong.append(entry)
	progress["wrongNote"] = wrong
	_persist()
	progress_changed.emit()


func remove_wrong_entry(question_hash: String) -> void:
	progress["wrongNote"] = get_wrong_note().filter(
		func(e): return e.get("questionHash", "") != question_hash)
	_persist()
	progress_changed.emit()


func update_wrong_entry_srs(question_hash: String, review_level: int, next_review_at: String) -> void:
	var wrong: Array = progress.get("wrongNote", [])
	for i in wrong.size():
		if wrong[i].get("questionHash", "") == question_hash:
			wrong[i]["reviewLevel"] = review_level
			wrong[i]["nextReviewAt"] = next_review_at
			progress["wrongNote"] = wrong
			_persist()
			progress_changed.emit()
			return


func get_quiz_session(pack_id: String) -> Dictionary:
	var s = progress.get("quizSessions", {})
	if typeof(s) != TYPE_DICTIONARY:
		return {}
	var e = (s as Dictionary).get(pack_id, {})
	return e if typeof(e) == TYPE_DICTIONARY else {}


func save_quiz_session(pack_id: String, data: Dictionary) -> void:
	if pack_id.is_empty():
		return
	var s: Dictionary = progress.get("quizSessions", {})
	if typeof(s) != TYPE_DICTIONARY:
		s = {}
	s[pack_id] = data
	progress["quizSessions"] = s
	_persist()


func clear_quiz_session(pack_id: String) -> void:
	if pack_id.is_empty():
		return
	var s = progress.get("quizSessions", {})
	if typeof(s) != TYPE_DICTIONARY or not (s as Dictionary).has(pack_id):
		return
	(s as Dictionary).erase(pack_id)
	progress["quizSessions"] = s
	_persist()


# -----------------------------------------------------------------------------
# Settings
# -----------------------------------------------------------------------------
func set_quiet_mode(enabled: bool) -> void:
	progress["quietMode"] = enabled
	_persist()
	quiet_mode_changed.emit(enabled)


func set_timer_enabled(enabled: bool) -> void:
	progress["timerEnabled"] = enabled
	_persist()
	timer_enabled_changed.emit(enabled)


func set_font_size_scale(scale: int) -> void:
	var clamped := clampi(scale, 0, 2)
	progress["fontSizeScale"] = clamped
	_persist()
	font_size_scale_changed.emit(clamped)


# -----------------------------------------------------------------------------
# Internal helpers
# -----------------------------------------------------------------------------
func _grant_character(id: String, level: int = 1) -> int:
	var uid := int(progress.get("nextUid", 1))
	progress["nextUid"] = uid + 1
	var col := get_collection()
	col.append({
		"uid": uid,
		"id": id,
		"level": maxi(1, level),
		"obtainedAt": Time.get_datetime_string_from_system(true),
	})
	progress["collection"] = col
	character_obtained.emit(uid, id, Characters.rarity_of(id))
	collection_changed.emit()
	return uid


# GitAnimals-style: a random owned character gains +1 level per contribution
# (here: per correct answer). Returns { uid, id, level } or {}.
func _random_levelup() -> Dictionary:
	var col := get_collection()
	if col.is_empty():
		return {}
	var i := rng.randi_range(0, col.size() - 1)
	col[i]["level"] = int(col[i].get("level", 1)) + 1
	progress["collection"] = col
	var uid := int(col[i].get("uid", -1))
	character_leveled.emit(uid, int(col[i]["level"]))
	return { "uid": uid, "id": col[i].get("id", ""), "level": col[i]["level"] }


func _remove_from_roster(uid: int) -> void:
	var roster = progress.get("ranchRoster", [])
	if typeof(roster) == TYPE_ARRAY:
		progress["ranchRoster"] = (roster as Array).filter(func(u): return int(u) != uid)


func _today_key() -> String:
	return Market.day_key(Time.get_datetime_dict_from_system())


func _yesterday_key() -> String:
	var yesterday := Time.get_datetime_dict_from_unix_time(
		int(Time.get_unix_time_from_system()) - 86400)
	return Market.day_key(yesterday)


# -----------------------------------------------------------------------------
# Persistence — atomic write + clamped load (.bak fallback per RISKS.md)
# -----------------------------------------------------------------------------
func _persist() -> void:
	var f := FileAccess.open(SAVE_PATH_TMP, FileAccess.WRITE)
	if f == null:
		push_error("ProgressStore: failed to open %s for write (err=%d)" % [SAVE_PATH_TMP, FileAccess.get_open_error()])
		return
	f.store_string(JSON.stringify(progress, "  "))
	f.close()
	var dir := DirAccess.open("user://")
	if dir == null:
		push_error("ProgressStore: cannot open user:// for rename")
		return
	if FileAccess.file_exists(SAVE_PATH):
		dir.copy(SAVE_PATH, SAVE_PATH_BAK)
		dir.remove(SAVE_PATH)
	var rename_err := dir.rename(SAVE_PATH_TMP, SAVE_PATH)
	if rename_err != OK:
		push_error("ProgressStore: rename failed (err=%d)" % rename_err)


func _load_from_disk() -> void:
	var parsed = null
	for path in [SAVE_PATH, SAVE_PATH_BAK]:
		if not FileAccess.file_exists(path):
			continue
		parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			break
		push_warning("ProgressStore: %s unreadable — trying fallback" % path)
		parsed = null
	if parsed == null:
		return
	var merged := _default_progress()
	for k in (parsed as Dictionary).keys():
		merged[k] = parsed[k]
	progress = _sanitize(merged)


# Clamp values on load (RISKS.md security/low: schema validation, no crypto).
func _sanitize(p: Dictionary) -> Dictionary:
	p["coins"] = maxi(0, int(p.get("coins", 0)))
	p["gachaTickets"] = maxi(0, int(p.get("gachaTickets", 0)))
	p["snacks"] = maxi(0, int(p.get("snacks", 0)))
	p["totalXP"] = maxi(0, int(p.get("totalXP", 0)))
	p["totalCorrect"] = maxi(0, int(p.get("totalCorrect", 0)))
	var col = p.get("collection", [])
	if typeof(col) != TYPE_ARRAY:
		col = []
	var clean: Array = []
	var max_uid := 0
	for e in col:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		if Characters.get_def(String(e.get("id", ""))).is_empty():
			continue
		e["uid"] = int(e.get("uid", 0))
		e["level"] = clampi(int(e.get("level", 1)), 1, 99999)
		max_uid = maxi(max_uid, int(e["uid"]))
		clean.append(e)
		if clean.size() >= COLLECTION_CAP:
			break
	p["collection"] = clean
	p["nextUid"] = maxi(int(p.get("nextUid", 1)), max_uid + 1)
	if typeof(p.get("pity", null)) != TYPE_DICTIONARY:
		p["pity"] = Gacha.default_pity()
	return p


func _default_progress() -> Dictionary:
	return {
		"schemaVersion": SCHEMA_VERSION,
		"totalXP": 0,
		"level": 1,
		"coins": STARTER_COINS,
		"gachaTickets": 1,     # one free pull so the ranch is never empty
		"snacks": 0,
		"totalCorrect": 0,
		"collection": [],
		"ranchRoster": [],
		"nextUid": 1,
		"pity": Gacha.default_pity(),
		"market": {},
		"streak": { "lastDay": "", "count": 0, "best": 0, "shields": 0 },
		"coinsEarnedToday": {},
		"snacksGrantedToday": {},
		"githubUsername": "",
		"githubLastEventId": "",
		"sessions": [],
		"wrongNote": [],
		"quizSessions": {},
		"quietMode": false,
		"timerEnabled": true,
		"fontSizeScale": 1,
	}
