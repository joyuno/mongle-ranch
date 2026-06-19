# Run via:
#   godot --headless --script res://tests/test_runner.gd
# Exits non-zero on any failed assertion.
#
# Single-file harness (same pattern as study_game_godot) — covers the pure
# domain surface: characters, gacha pity, market math, ladder, github snacks,
# srs, leveling, pack parser.

extends SceneTree

var _failures: int = 0
var _passes: int = 0


func _initialize() -> void:
	print("--- test runner ---")
	_test_characters()
	_test_gacha()
	_test_market()
	_test_ladder()
	_test_github_snacks()
	_test_srs()
	_test_leveling()
	_test_pack_parser()
	_test_pack_import()
	print("--- %d passed, %d failed ---" % [_passes, _failures])
	quit(0 if _failures == 0 else 1)


# -----------------------------------------------------------------------------
# Characters
# -----------------------------------------------------------------------------
func _test_characters() -> void:
	_section("Characters")
	_eq(Characters.ROSTER.size(), 24, "로스터 24종")
	_eq(Characters.ids_of_rarity("common").size(), 10, "common 10종")
	_eq(Characters.ids_of_rarity("rare").size(), 8, "rare 8종")
	_eq(Characters.ids_of_rarity("epic").size(), 4, "epic 4종")
	_eq(Characters.ids_of_rarity("legendary").size(), 2, "legendary 2종")
	_eq(Characters.rarity_of("geumbung"), "legendary", "금붕 = legendary")
	_eq(Characters.rarity_of("byeolttong"), "legendary", "별똥 = legendary")
	_eq(Characters.rarity_of("dorong"), "common", "도롱 = common")
	_eq(Characters.rarity_of("haedal"), "epic", "해달 = epic")
	_eq(Characters.rarity_label("epic"), "에픽", "rarity 한국어 라벨")
	_eq(Characters.rarity_rank("legendary"), 3, "rarity 순서")
	_truthy(Characters.get_def("nope").is_empty(), "미존재 id → 빈 dict")
	_eq(Characters.sprite_path("moka"), "res://assets/characters/moka.png", "스프라이트 경로")
	# ids unique
	var ids := Characters.all_ids()
	var seen := {}
	for id in ids:
		seen[id] = true
	_eq(seen.size(), ids.size(), "id 중복 없음")
	# every roster entry has required personality keys
	var all_have := true
	for c in Characters.ROSTER:
		var p: Dictionary = c.get("personality", {})
		if not (p.has("move_speed") and p.has("idle_min") and p.has("idle_max") and p.has("emotes")):
			all_have = false
	_truthy(all_have, "성격 필드 완비")


# -----------------------------------------------------------------------------
# Gacha — pity guarantees under a fixed seed
# -----------------------------------------------------------------------------
func _test_gacha() -> void:
	_section("Gacha")
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345

	# 10-pull epic guarantee: force sinceEpic=9 → next must be epic+.
	var pity := { "sinceEpic": 9, "sinceLegendary": 0, "spark": 0 }
	var hits := true
	for i in 50:
		var r := Gacha.draw(pity, rng)
		if Characters.rarity_rank(String(r["rarity"])) < Characters.rarity_rank("epic"):
			hits = false
	_truthy(hits, "sinceEpic=9 → 항상 epic 이상")

	# Hard pity: sinceLegendary=39 → guaranteed legendary.
	var hard := { "sinceEpic": 0, "sinceLegendary": 39, "spark": 0 }
	var all_leg := true
	for i in 20:
		var r := Gacha.draw(hard, rng)
		if String(r["rarity"]) != "legendary":
			all_leg = false
	_truthy(all_leg, "sinceLegendary=39 → 확정 legendary")

	# Counters: epic draw resets sinceEpic but not necessarily legendary.
	var res := Gacha.draw({ "sinceEpic": 9, "sinceLegendary": 5, "spark": 3 }, rng)
	_eq(int(res["pity"]["sinceEpic"]), 0, "epic+ 획득 시 sinceEpic 리셋")
	_eq(int(res["pity"]["spark"]), 4, "스파크 +1")
	if String(res["rarity"]) != "legendary":
		_eq(int(res["pity"]["sinceLegendary"]), 6, "legendary 미획득 시 카운터 증가")
	else:
		_eq(int(res["pity"]["sinceLegendary"]), 0, "legendary 획득 시 리셋")

	# 40 sequential draws from zero always include ≥1 legendary (hard pity).
	var p := Gacha.default_pity()
	var got_leg := false
	for i in 40:
		var r := Gacha.draw(p, rng)
		p = r["pity"]
		if String(r["rarity"]) == "legendary":
			got_leg = true
	_truthy(got_leg, "40연 내 legendary 보장")

	_truthy(not Gacha.spark_ready({ "spark": 99 }), "스파크 99 → 미달")
	_truthy(Gacha.spark_ready({ "spark": 100 }), "스파크 100 → 사용 가능")
	_eq(int(Gacha.consume_spark({ "spark": 105 })["spark"]), 5, "스파크 소비 후 잔여")

	# Weighted distribution sanity: common should dominate 1000 plain draws.
	# 24종 분포에서 common 기대치 ≈ 79.5% (3σ 하한 ≈ 757). 여유 있게 720으로 검증.
	rng.seed = 777
	var commons := 0
	for i in 1000:
		var r := Gacha.draw(Gacha.default_pity(), rng)
		if String(r["rarity"]) == "common":
			commons += 1
	_truthy(commons > 720, "1000회 중 common 72%% 초과 (실측 %d)" % commons)


# -----------------------------------------------------------------------------
# Market
# -----------------------------------------------------------------------------
func _test_market() -> void:
	_section("Market")
	_eq(Market.base_price("common"), 300, "common 기본가 300")
	_eq(Market.base_price("legendary"), 20000, "legendary 기본가 20,000")
	_eq(Market.sell_price("common", 0, 1.0), 300, "Lv0 m=1.0 → 기본가")
	_eq(Market.sell_price("common", 50, 1.0), 600, "Lv50 → 2배 (1+0.02×50)")
	_eq(Market.sell_price("rare", 10, 1.0), 1440, "rare Lv10 → 1,440")
	_eq(Market.buy_price("common", 0, 1.0), 690, "구매가 = 판매가 × 2.3")
	_truthy(Market.sell_price("epic", 5, 0.85) < Market.sell_price("epic", 5, 1.15), "시세 반영")
	_eq(Market.sell_price("common", 0, 1.0, 1.5), 450, "인기일 보너스 1.5×")

	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var in_range := true
	var m := 1.0
	for i in 365:
		m = Market.next_multiplier(m, rng)
		if m < Market.M_MIN or m > Market.M_MAX:
			in_range = false
	_truthy(in_range, "1년 랜덤워크 [0.85, 1.15] 유지")

	var date := { "year": 2026, "month": 6, "day": 12, "weekday": 5 }
	var pop1 := Market.popular_of_day(date)
	var pop2 := Market.popular_of_day(date)
	_truthy(JSON.stringify(pop1) == JSON.stringify(pop2), "인기일 결정성 (같은 날 = 같은 결과)")
	if not pop1.is_empty():
		var b := float(pop1.get("bonus", 0.0))
		_truthy(b >= Market.POPULAR_MIN and b <= Market.POPULAR_MAX, "인기일 보너스 범위")
	else:
		_pass("이 날짜는 인기일 아님 (결정적)")

	rng.seed = 7
	var listings := Market.roll_listings(1.0, {}, rng)
	_truthy(listings.size() >= 3 and listings.size() <= 5, "매물 3~5개")
	var priced := true
	for l in listings:
		if int(l.get("price", 0)) <= 0 or Characters.get_def(String(l.get("id", ""))).is_empty():
			priced = false
	_truthy(priced, "매물 전부 유효 id + 양수 가격")
	_eq(Market.day_key({ "year": 2026, "month": 6, "day": 12 }), "2026-06-12", "day_key 포맷")


# -----------------------------------------------------------------------------
# Ladder
# -----------------------------------------------------------------------------
func _test_ladder() -> void:
	_section("Ladder")
	_eq(Ladder.prize_for(0), 0, "0정답 → 0")
	_eq(Ladder.prize_for(1), 200, "1정답 → 200")
	_eq(Ladder.prize_for(3), 800, "3정답 → 800")
	_eq(Ladder.prize_for(5), 3200, "5정답 완주 → 3,200")
	_eq(Ladder.prize_for(99), 3200, "초과 클램프")
	_eq(Ladder.tickets_earned(29, 30), 1, "30번째 정답 → 티켓 1")
	_eq(Ladder.tickets_earned(30, 31), 0, "31번째 → 추가 없음")
	_eq(Ladder.tickets_earned(59, 61), 1, "60 경계 통과 → 1")
	_eq(Ladder.tickets_earned(0, 90), 3, "한 번에 90정답 → 3")
	_eq(Ladder.capped_payout(3200, 0), 3200, "캡 미달 → 전액")
	_eq(Ladder.capped_payout(3200, 19000), 1000, "캡 경계 → 부분 지급")
	_eq(Ladder.capped_payout(3200, 20000), 0, "캡 도달 → 0")
	# Free streak shields — weekly milestone, capped.
	_eq(Ladder.shields_for_best(0), 0, "best 0 → 방패 0")
	_eq(Ladder.shields_for_best(6), 0, "best 6 → 방패 0")
	_eq(Ladder.shields_for_best(7), 1, "best 7 → 방패 1")
	_eq(Ladder.shields_for_best(14), 2, "best 14 → 방패 2")
	_eq(Ladder.shields_for_best(70), 2, "best 70 → 방패 2 (캡)")


# -----------------------------------------------------------------------------
# GithubSnacks
# -----------------------------------------------------------------------------
func _test_github_snacks() -> void:
	_section("GithubSnacks")
	var events := [
		{ "id": "300", "type": "PushEvent", "payload": { "distinct_size": 3 } },
		{ "id": "200", "type": "WatchEvent", "payload": {} },
		{ "id": "100", "type": "PushEvent", "payload": { "distinct_size": 2 } },
	]
	var first := GithubSnacks.count_new_commits(events, "")
	_eq(int(first["commits"]), 5, "첫 동기화 — 전체 커밋 5")
	_eq(String(first["latest_id"]), "300", "최신 이벤트 id 기록")

	var incr := GithubSnacks.count_new_commits(events, "100")
	_eq(int(incr["commits"]), 3, "증분 — id 100 이후만 (3)")
	var none := GithubSnacks.count_new_commits(events, "300")
	_eq(int(none["commits"]), 0, "변화 없음 → 0")

	_eq(GithubSnacks.snacks_to_grant(5, 0), 5, "캡 이내 전부 지급")
	_eq(GithubSnacks.snacks_to_grant(15, 0), 10, "일일 캡 10")
	_eq(GithubSnacks.snacks_to_grant(5, 8), 2, "오늘 8개 지급됨 → 2개만")
	_eq(GithubSnacks.snacks_to_grant(5, 10), 0, "캡 도달 → 0")


# -----------------------------------------------------------------------------
# SRS (ported)
# -----------------------------------------------------------------------------
func _test_srs() -> void:
	_section("SRS")
	var now := 1_700_000_000.0
	var after_wrong := SRS.grade_review(3, false, now)
	_eq(int(after_wrong["review_level"]), 0, "오답 → 레벨 0 리셋")
	var after_right := SRS.grade_review(0, true, now)
	_eq(int(after_right["review_level"]), 1, "정답 → 레벨 +1")
	_truthy(SRS.grade_review(5, true, now).is_empty(), "레벨 5 정답 → 졸업")
	_truthy(SRS.is_due("", now), "타임스탬프 없으면 due")
	_truthy(SRS.is_due("2000-01-01T00:00:00", now), "과거 → due")
	_truthy(not SRS.is_due("2090-01-01T00:00:00", now), "미래 → not due")


# -----------------------------------------------------------------------------
# Leveling (ported)
# -----------------------------------------------------------------------------
func _test_leveling() -> void:
	_section("Leveling")
	_eq(Leveling.level_from_xp(0), 1, "0 XP → Lv1")
	_eq(Leveling.level_from_xp(100), 2, "100 XP → Lv2")
	_eq(Leveling.level_from_xp(299), 2, "299 XP → Lv2")
	_eq(Leveling.level_from_xp(300), 3, "300 XP → Lv3")


# -----------------------------------------------------------------------------
# PackParser (ported)
# -----------------------------------------------------------------------------
func _test_pack_parser() -> void:
	_section("PackParser")
	var ok := PackParser.parse_string(JSON.stringify({
		"meta": { "title": "테스트" },
		"questions": [
			{ "type": "mcq", "q": "1+1?", "choices": ["1", "2"], "answer": 1 },
			{ "type": "ox", "q": "참?", "answer": true },
		],
	}))
	_truthy(ok.get("ok", false), "유효 팩 파싱")
	_eq((ok["pack"]["questions"] as Array).size(), 2, "문항 2개")

	_eq(PackParser.parse_string("not json")["code"], "ERR_JSON_PARSE", "JSON 오류 코드")
	_eq(PackParser.parse_string("{}")["code"], "ERR_META_MISSING", "meta 누락")
	var bad_answer := PackParser.parse_string(JSON.stringify({
		"meta": { "title": "t" },
		"questions": [ { "type": "mcq", "q": "?", "choices": ["a", "b"], "answer": 5 } ],
	}))
	_eq(bad_answer["code"], "ERR_MCQ_ANSWER_OUT_OF_RANGE", "answer 범위 검증")
	var bad_ox := PackParser.parse_string(JSON.stringify({
		"meta": { "title": "t" },
		"questions": [ { "type": "ox", "q": "?", "answer": "true" } ],
	}))
	_eq(bad_ox["code"], "ERR_OX_ANSWER_NOT_BOOL", "ox 불리언 강제")
	# Limits — docs/RISKS.md: 1,000-question / 2KB-text caps.
	var many: Array = []
	for i in 1001:
		many.append({ "type": "ox", "q": "q%d" % i, "answer": true })
	var too_many := PackParser.parse_string(JSON.stringify({ "meta": { "title": "t" }, "questions": many }))
	_eq(too_many["code"], "ERR_TOO_MANY_QUESTIONS", "1,000문항 상한")
	var long_q := PackParser.parse_string(JSON.stringify({
		"meta": { "title": "t" },
		"questions": [ { "type": "ox", "q": "가".repeat(2049), "answer": true } ],
	}))
	_eq(long_q["code"], "ERR_Q_TOO_LONG", "문항 2KB 상한")
	# Real pack on disk parses.
	var real := PackParser.parse_file("res://data/quizzes/clickhouse-basics.json")
	_truthy(real.get("ok", false), "번들 퀴즈팩 파싱")


# -----------------------------------------------------------------------------
# PackImport (유저 제작/임포트)
# -----------------------------------------------------------------------------
func _test_pack_import() -> void:
	_section("PackImport")
	# 정규화: 코드펜스 + 스마트따옴표 + 후행 콤마를 제거하면 유효 JSON으로 파싱된다.
	var dirty := "```json\n{ “meta”: { “title”: “T” }, “questions”: [ { “type”: “ox”, “q”: “Q”, “answer”: true, }, ], }\n```"
	var cleaned := PackImport.normalize_json(dirty)
	_truthy(PackParser.parse_string(cleaned).get("ok", false), "정규화(펜스·스마트따옴표·후행콤마) 후 파싱")
	# slugify: ASCII 안전, 비ASCII 제목은 'pack'으로.
	_eq(PackImport.slugify("APM 1 - 분산추적!"), "apm-1", "slugify ASCII")
	_eq(PackImport.slugify("한글전용제목"), "pack", "비ASCII 제목 → pack")
	# 프롬프트에 스키마 마커 포함.
	_truthy(PackImport.build_prompt("OTel").contains("\"questions\""), "프롬프트에 스키마 포함")
	# 비JSON 입력은 등록 거부.
	_eq(PackImport.import_text("그냥 텍스트")["ok"], false, "비JSON 등록 거부")
	# 정상 등록 → 목록 +1 → 저장본 재파싱 → 삭제 → 원복 (라운드트립).
	var before := PackImport.list_user_packs().size()
	var good := PackImport.import_text(JSON.stringify({
		"meta": { "title": "임포트테스트" },
		"questions": [ { "type": "mcq", "q": "1+1?", "choices": ["1", "2"], "answer": 1 } ],
	}))
	_truthy(good.get("ok", false), "유효 팩 user:// 저장")
	_eq(PackImport.list_user_packs().size(), before + 1, "유저 팩 목록 +1")
	_truthy(PackParser.parse_file(String(good.get("path", ""))).get("ok", false), "저장본 재파싱 가능")
	_truthy(PackImport.delete_user_pack(String(good.get("path", ""))), "유저 팩 삭제")
	_eq(PackImport.list_user_packs().size(), before, "삭제 후 목록 원복")
	# 번들(res://) 팩은 삭제 차단.
	_eq(PackImport.delete_user_pack("res://data/quizzes/clickhouse-basics.json"), false, "번들 팩 삭제 차단")


# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
func _section(name: String) -> void:
	print("\n[%s]" % name)


func _eq(actual, expected, label: String) -> void:
	if typeof(actual) == typeof(expected) and actual == expected:
		_pass(label)
	else:
		_fail(label, "expected %s, got %s" % [str(expected), str(actual)])


func _truthy(condition: bool, label: String) -> void:
	if condition:
		_pass(label)
	else:
		_fail(label, "expected truthy")


func _pass(label: String) -> void:
	_passes += 1
	print("  ✓ %s" % label)


func _fail(label: String, reason: String) -> void:
	_failures += 1
	push_error("  ✗ %s — %s" % [label, reason])
	print("  ✗ %s — %s" % [label, reason])
