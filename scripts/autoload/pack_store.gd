# Active quiz pack — autoloaded. Ladder-session edition of study_game_godot's
# PackStore: a session is a 5-question "더블 오어 나씽" run (Ladder domain).
#
# Per correct answer (never rolled back — 무처벌 원칙):
#   * XP via Leveling
#   * ProgressStore.record_correct_answer() → random pet level-up +
#     30-correct gacha ticket milestone
#   * ladder step +1 (prize doubles)
# The player may cash out after any correct answer; a wrong answer or
# timeout zeroes only the session prize and ends the run.
#
# Review mode (오답노트) is ported unchanged: SRS-graded, no prize.

extends Node

signal pack_loaded(meta: Dictionary, total: int)
signal question_changed(index: int, question: Dictionary)
signal feedback(correct: bool, explanation: String, info: Dictionary)
signal ladder_changed(step: int, prize: int, next_prize: int)
signal session_completed(record: Dictionary)

const DEFAULT_QUESTION_TIME: float = Ladder.QUESTION_TIME

var pack: Dictionary = {}
var pack_source: String = ""
# Index into the pack's question list of the *current* question. The per-pack
# resume cursor persists across runs so a 100-question pack is consumed over
# many ladder sessions (wraps around at the end).
var question_index: int = 0
var session_step: int = 0          # questions answered correctly this run
var session_questions_left: int = 0
var banked: bool = false
var correct_count: int = 0
# 오답/사다리 완주 후 '결과 보기'를 누르면 정산할 상금. -1 = 정산 대기 없음.
var _pending_result: int = -1
var session_started_at_unix: float = 0.0
var question_started_at_unix: float = 0.0
var phase: String = "IDLE"  # IDLE / IN_QUESTION / FEEDBACK / COMPLETED

var is_review_mode: bool = false
var review_hashes: Array[String] = []
var review_levels: Array[int] = []


func load_pack_from_path(path: String) -> Dictionary:
	var result := PackParser.parse_file(path)
	if not result.get("ok", false):
		return result
	is_review_mode = false
	review_hashes.clear()
	review_levels.clear()
	pack = result["pack"]
	pack_source = path
	_reset_session()
	var saved := ProgressStore.get_quiz_session(path)
	var cursor := int(saved.get("cursor", 0))
	question_index = cursor % maxi(1, questions_count())
	pack_loaded.emit(pack.get("meta", {}), questions_count())
	phase = "IN_QUESTION"
	question_started_at_unix = Time.get_unix_time_from_system()
	question_changed.emit(question_index, current_question())
	ladder_changed.emit(0, 0, Ladder.prize_for(1))
	return { "ok": true, "title": pack.get("meta", {}).get("title", "") }


func load_review_session(entries: Array) -> bool:
	var questions: Array = []
	var hashes: Array[String] = []
	var levels: Array[int] = []
	for e in entries:
		var snap = e.get("questionSnapshot", null)
		if typeof(snap) != TYPE_DICTIONARY or String(snap.get("q", "")).is_empty():
			continue
		questions.append(snap)
		hashes.append(String(e.get("questionHash", "")))
		levels.append(int(e.get("reviewLevel", 0)))
	if questions.is_empty():
		return false
	is_review_mode = true
	pack_source = ""
	review_hashes = hashes
	review_levels = levels
	pack = {
		"meta": {
			"title": "📚 오답 복습 (%d문항)" % questions.size(),
			"version": "review",
			"default_time": 30,
		},
		"questions": questions,
	}
	_reset_session()
	session_questions_left = questions.size()
	pack_loaded.emit(pack["meta"], questions.size())
	phase = "IN_QUESTION"
	question_started_at_unix = Time.get_unix_time_from_system()
	question_changed.emit(0, current_question())
	return true


func questions_count() -> int:
	var q = pack.get("questions", [])
	return (q as Array).size() if typeof(q) == TYPE_ARRAY else 0


func current_question() -> Dictionary:
	var qs = pack.get("questions", [])
	if typeof(qs) != TYPE_ARRAY:
		return {}
	var arr := qs as Array
	if is_review_mode:
		var review_idx := review_hashes.size() - session_questions_left
		if review_idx < 0 or review_idx >= arr.size():
			return {}
		return arr[review_idx]
	if arr.is_empty():
		return {}
	return arr[question_index % arr.size()]


func current_prize() -> int:
	return Ladder.prize_for(session_step)


func time_remaining_for_question() -> float:
	if phase != "IN_QUESTION":
		return 0.0
	var limit := question_time_limit()
	var elapsed := Time.get_unix_time_from_system() - question_started_at_unix
	return max(0.0, limit - elapsed)


func question_time_limit() -> float:
	var q := current_question()
	if q.has("time"):
		return float(q["time"])
	# 사다리/복습 모두 팩 meta.default_time을 존중하고, 없으면 기본값(30s).
	var meta = pack.get("meta", {})
	return float(meta.get("default_time", DEFAULT_QUESTION_TIME))


func submit_answer(answer) -> void:
	if phase != "IN_QUESTION":
		return
	var q := current_question()
	if q.is_empty():
		return
	var elapsed_for_q := Time.get_unix_time_from_system() - question_started_at_unix
	var is_correct := _check_answer(q, answer)
	var info := {
		"correct": is_correct,
		"elapsed": elapsed_for_q,
		"bonuses": [],
		"answer_label": _answer_label(q),   # 오답 피드백에서 정답 텍스트
		"correct_btn": _correct_btn_index(q),  # 정답 선택지 버튼 인덱스(하이라이트용)
		"user_btn": _user_btn_index(q, answer),  # 내가 고른 버튼 인덱스(-1=시간초과)
	}
	if is_correct:
		correct_count += 1
		ProgressStore.add_xp(Leveling.XP_PER_CORRECT)
		if not is_review_mode:
			session_step += 1
			var milestone := ProgressStore.record_correct_answer()
			if int(milestone.get("tickets", 0)) > 0:
				info["bonuses"].append("🎟️ %d번째 정답 — 가챠 티켓 +%d" % [ProgressStore.get_total_correct(), milestone["tickets"]])
			var leveled: Dictionary = milestone.get("leveled", {})
			if not leveled.is_empty():
				var def := Characters.get_def(String(leveled.get("id", "")))
				info["bonuses"].append("⬆️ %s Lv.%d" % [def.get("name", "?"), int(leveled.get("level", 1))])
			ladder_changed.emit(session_step, current_prize(), Ladder.prize_for(session_step + 1))
	else:
		if not is_review_mode:
			_register_wrong(q, answer)
			# 더블 오어 나씽: 오답은 세션 상금만 잃는다. 정답 보상은 유지.
			session_step = 0
			ladder_changed.emit(0, 0, Ladder.prize_for(1))
	if is_review_mode:
		var review_idx := review_hashes.size() - session_questions_left
		if review_idx >= 0 and review_idx < review_hashes.size():
			var hkey := review_hashes[review_idx]
			var prev_level := review_levels[review_idx]
			var next_state := SRS.grade_review(prev_level, is_correct)
			if next_state.is_empty():
				ProgressStore.remove_wrong_entry(hkey)
				info["bonuses"].append("🎓 졸업 — 오답노트에서 제거")
			else:
				ProgressStore.update_wrong_entry_srs(
					hkey,
					int(next_state.get("review_level", prev_level)),
					String(next_state.get("next_review_at", "")),
				)
	feedback.emit(is_correct, q.get("explanation", ""), info)
	phase = "FEEDBACK"
	if not is_review_mode:
		_advance_cursor()
		# 오답·사다리 완주는 즉시 정산하지 않는다. 정답/해설을 보여준 뒤 UI의
		# '결과 보기'(advance)에서 이 상금으로 정산한다. (-1 = 정산 대기 없음)
		if not is_correct:
			_pending_result = 0
		elif session_step >= Ladder.SESSION_SIZE:
			_pending_result = current_prize()  # 사다리 완주


# Bank the current prize and end the run. Only valid in FEEDBACK after a
# correct answer (UI shows the button then).
func cash_out() -> void:
	if is_review_mode or banked or session_step <= 0:
		return
	_complete_session(current_prize())


# Continue to the next question (after feedback). In review mode this walks
# the review list; in ladder mode it presents the next pack question.
func advance() -> void:
	if phase != "FEEDBACK":
		return
	if is_review_mode:
		session_questions_left -= 1
		if session_questions_left <= 0:
			_complete_review()
			return
		phase = "IN_QUESTION"
		question_started_at_unix = Time.get_unix_time_from_system()
		question_changed.emit(question_index, current_question())
		return
	if banked:
		return
	# 오답/완주 후 '결과 보기' — 대기 중이던 상금으로 정산.
	if _pending_result >= 0:
		var prize := _pending_result
		_pending_result = -1
		_complete_session(prize)
		return
	# 정답 진행 중 — 다음 문제.
	phase = "IN_QUESTION"
	question_started_at_unix = Time.get_unix_time_from_system()
	question_changed.emit(question_index, current_question())


func _advance_cursor() -> void:
	question_index = (question_index + 1) % maxi(1, questions_count())
	if not pack_source.is_empty():
		ProgressStore.save_quiz_session(pack_source, {
			"cursor": question_index,
			"packTitle": pack.get("meta", {}).get("title", ""),
			"savedAt": Time.get_datetime_string_from_system(true),
		})


func _reset_session() -> void:
	session_step = 0
	session_questions_left = Ladder.SESSION_SIZE
	banked = false
	correct_count = 0
	_pending_result = -1
	session_started_at_unix = Time.get_unix_time_from_system()
	question_started_at_unix = 0.0
	phase = "IDLE"


func _check_answer(q: Dictionary, answer) -> bool:
	match q.get("type", ""):
		"mcq":
			return int(answer) == int(q.get("answer", -1))
		"ox":
			# Strict bool check — UI signals a timeout as submit_answer(-1),
			# and bool(-1) would otherwise grade as a correct "O".
			return typeof(answer) == TYPE_BOOL and bool(answer) == bool(q.get("answer", false))
	return false


# 정답을 사람이 읽을 라벨로. mcq는 정답 선택지 텍스트, ox는 O/X.
func _answer_label(q: Dictionary) -> String:
	match q.get("type", ""):
		"mcq":
			var choices = q.get("choices", [])
			var idx := int(q.get("answer", -1))
			if typeof(choices) == TYPE_ARRAY and idx >= 0 and idx < (choices as Array).size():
				return String((choices as Array)[idx])
		"ox":
			return "O (참)" if bool(q.get("answer", false)) else "X (거짓)"
	return ""


# 정답 선택지의 버튼 인덱스. UI 버튼 순서: mcq=choices 순, ox=[O, X].
func _correct_btn_index(q: Dictionary) -> int:
	match q.get("type", ""):
		"mcq":
			return int(q.get("answer", -1))
		"ox":
			return 0 if bool(q.get("answer", false)) else 1
	return -1


# 사용자가 고른 버튼 인덱스. 시간초과(answer=-1 등 무효)면 -1.
func _user_btn_index(q: Dictionary, answer) -> int:
	match q.get("type", ""):
		"mcq":
			var n := (q.get("choices", []) as Array).size()
			var i := int(answer) if typeof(answer) == TYPE_INT else -1
			return i if i >= 0 and i < n else -1
		"ox":
			if typeof(answer) == TYPE_BOOL:
				return 0 if bool(answer) else 1
	return -1


func _register_wrong(q: Dictionary, user_answer) -> void:
	ProgressStore.add_wrong_entry({
		"packTitle": pack.get("meta", {}).get("title", ""),
		"questionHash": _hash_question(q),
		"questionSnapshot": q,
		"userAnswer": user_answer,
		"timesWrong": 1,
		"lastWrongAt": Time.get_datetime_string_from_system(true),
		"reviewLevel": 0,
		"nextReviewAt": SRS.initial_next_review_at(),
	})


func _complete_session(prize: int) -> void:
	banked = true
	phase = "COMPLETED"
	var granted := 0
	if prize > 0:
		granted = ProgressStore.add_quiz_coins(prize)
	ProgressStore.touch_streak()
	var record := {
		"startedAt": Time.get_datetime_string_from_unix_time(int(session_started_at_unix), true),
		"packTitle": pack.get("meta", {}).get("title", ""),
		"correct": correct_count,
		"steps": session_step,
		"prize": prize,
		"granted": granted,
		"durationMs": int((Time.get_unix_time_from_system() - session_started_at_unix) * 1000),
	}
	ProgressStore.record_session(record)
	session_completed.emit(record)


func _complete_review() -> void:
	phase = "COMPLETED"
	ProgressStore.touch_streak()
	var record := {
		"startedAt": Time.get_datetime_string_from_unix_time(int(session_started_at_unix), true),
		"packTitle": pack.get("meta", {}).get("title", ""),
		"correct": correct_count,
		"steps": 0,
		"prize": 0,
		"granted": 0,
		"review": true,
		"durationMs": int((Time.get_unix_time_from_system() - session_started_at_unix) * 1000),
	}
	ProgressStore.record_session(record)
	session_completed.emit(record)


func _hash_question(q: Dictionary) -> String:
	var key := "%s::%s" % [q.get("type", ""), q.get("q", "")]
	return str(key.hash())
