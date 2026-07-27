extends Node

const TEMP_PACK := "user://quiz_regression.json"
const PROGRESS_PATHS := ["user://progress.json", "user://progress.json.bak", "user://progress.json.tmp"]

var _original_progress: Dictionary
var _original_files: Dictionary = {}
var _failures := 0


func _ready() -> void:
	print("quiz regression start")
	_original_progress = ProgressStore.progress.duplicate(true)
	_snapshot_progress_files()

	var pack := {
		"meta": {"title": "Regression", "version": "1", "default_time": 30},
		"questions": [
			{"type": "mcq", "q": "2+2", "choices": ["4", "5"], "answer": 0, "explanation": ""},
			{"type": "mcq", "q": "3+3", "choices": ["5", "6"], "answer": 1, "explanation": ""},
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

	var loaded: Dictionary = PackStore.load_pack_from_path(path)
	_check(bool(loaded.get("ok", false)), "temporary pack loads through PackStore")
	if not bool(loaded.get("ok", false)):
		_finish()
		return
	PackStore.submit_answer(0)
	_check(PackStore.correct_count == 1, "correct answer increments correct_count")
	_check(PackStore.session_step == 1, "correct answer advances ladder")
	PackStore.advance()
	var wrong_before := ProgressStore.get_wrong_note().size()
	PackStore.submit_answer(0)
	_check(ProgressStore.get_wrong_note().size() == wrong_before + 1, "wrong answer creates a wrong-note entry")
	_check(PackStore.session_step == 0, "wrong answer resets ladder")

	var review_entry: Dictionary = ProgressStore.get_wrong_note().back()
	_check(PackStore.load_review_session([review_entry]), "review session loads through PackStore")
	PackStore.submit_answer(1)
	var reviewed: Dictionary = ProgressStore.get_wrong_note().back()
	_check(int(reviewed.get("reviewLevel", -1)) == 1, "review answer advances SRS")
	_check(PackStore.session_step == 0, "review answer leaves quiz ladder unchanged")
	PackStore.advance()
	_check(PackStore.phase == "COMPLETED", "review session completes through advance")

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
	ProgressStore.progress = _original_progress.duplicate(true)
	ProgressStore._persist()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PACK))
	_check(_restore_progress_files() and _progress_files_match(), "progress files restore original bytes and existence")
	if _failures == 0:
		print("quiz regression success")
	else:
		print("quiz regression failure: %d" % _failures)


func _snapshot_progress_files() -> void:
	for path in PROGRESS_PATHS:
		var exists := FileAccess.file_exists(path)
		_original_files[path] = {
			"exists": exists,
			"bytes": FileAccess.get_file_as_bytes(path) if exists else PackedByteArray(),
		}


func _progress_files_match() -> bool:
	for path in PROGRESS_PATHS:
		var snapshot: Dictionary = _original_files[path]
		var exists := FileAccess.file_exists(path)
		if exists != bool(snapshot["exists"]):
			return false
		if exists and FileAccess.get_file_as_bytes(path) != snapshot["bytes"]:
			return false
	return ProgressStore.progress == _original_progress


func _restore_progress_files() -> bool:
	for path in PROGRESS_PATHS:
		var snapshot: Dictionary = _original_files[path]
		if bool(snapshot["exists"]):
			var file := FileAccess.open(path, FileAccess.WRITE)
			if file == null:
				return false
			file.store_buffer(snapshot["bytes"])
			file.close()
		elif FileAccess.file_exists(path):
			if DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) != OK:
				return false
	return true
