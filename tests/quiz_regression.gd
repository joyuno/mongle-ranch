extends SceneTree

const ProgressStoreScript = preload("res://scripts/autoload/progress_store.gd")
const TEMP_PACK := "user://quiz_regression.json"

var _progress_store: Node
var _pack_store: Node
var _original_progress: Dictionary
var _failures := 0


func _initialize() -> void:
	print("quiz regression start")
	_progress_store = ProgressStoreScript.new()
	_progress_store.name = "ProgressStore"
	root.add_child(_progress_store)
	_pack_store = (load("res://scripts/autoload/pack_store.gd") as Script).new()
	_pack_store.name = "PackStore"
	root.add_child(_pack_store)
	_original_progress = (_progress_store.get("progress") as Dictionary).duplicate(true)

	var pack := {
		"meta": {"title": "Regression", "version": "1", "default_time": 30},
		"questions": [
			{"type": "mcq", "q": "2+2", "choices": ["4", "5"], "answer_index": 0, "answer": 0, "explanation": ""},
			{"type": "mcq", "q": "3+3", "choices": ["5", "6"], "answer_index": 1, "answer": 1, "explanation": ""},
		],
	}
	var path := ProjectSettings.globalize_path(TEMP_PACK)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("temporary pack opens")
		_finish()
		return
	file.store_string(JSON.stringify(pack))
	file.close()

	var loaded: Dictionary = _pack_store.call("load_pack_from_path", path)
	_check(bool(loaded.get("ok", false)), "temporary pack loads through PackStore")
	_pack_store.call("submit_answer", 0)
	_check(int(_pack_store.get("correct_count")) == 1, "correct answer increments correct_count")
	_check(int(_pack_store.get("session_step")) == 1, "correct answer advances ladder")
	_pack_store.call("advance")
	var wrong_before := (_progress_store.call("get_wrong_note") as Array).size()
	_pack_store.call("submit_answer", 0)
	_check((_progress_store.call("get_wrong_note") as Array).size() == wrong_before + 1, "wrong answer creates a wrong-note entry")
	_check(int(_pack_store.get("session_step")) == 0, "wrong answer resets ladder")

	var review_entry: Dictionary = (_progress_store.call("get_wrong_note") as Array).back()
	var streak_before: Dictionary = (_progress_store.call("get_streak") as Dictionary).duplicate(true)
	_check(bool(_pack_store.call("load_review_session", [review_entry])), "review session loads through PackStore")
	_pack_store.call("submit_answer", 1)
	var reviewed: Dictionary = (_progress_store.call("get_wrong_note") as Array).back()
	_check(int(reviewed.get("reviewLevel", -1)) == 1, "review answer advances SRS")
	_check(_progress_store.call("get_streak") == streak_before, "review grading leaves quiz streak unchanged")

	_finish()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		_fail(label)


func _fail(label: String) -> void:
	_failures += 1
	push_error("FAIL: %s" % label)


func _finish() -> void:
	_progress_store.set("progress", _original_progress)
	_progress_store.call("_persist")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PACK))
	quit(0 if _failures == 0 else 1)
