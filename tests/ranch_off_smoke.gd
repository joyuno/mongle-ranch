extends Node

const PROGRESS_PATHS := ["user://progress.json", "user://progress.json.bak", "user://progress.json.tmp"]

var _original_progress: Dictionary
var _original_files: Dictionary = {}
var _failures := 0
var _scene: Node
var _frames := 0


func _ready() -> void:
	print("ranch-off smoke start")
	_original_progress = ProgressStore.progress.duplicate(true)
	_snapshot_progress_files()
	ProgressStore.set_farm_visible(false)
	_scene = load("res://scenes/Ranch.tscn").instantiate()
	add_child(_scene)
	set_process(true)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < 20:
		return
	set_process(false)
	_check(_scene.get("_yard") == null, "Farm-OFF scene mounts without a yard")
	_scene.queue_free()
	_finish()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)


func _finish() -> void:
	ProgressStore.progress = _original_progress.duplicate(true)
	ProgressStore._persist()
	_check(_restore_progress_files() and _progress_files_match(), "progress files restore original bytes and existence")
	if _failures == 0:
		print("ranch-off smoke success")
	else:
		print("ranch-off smoke failure: %d" % _failures)


func _snapshot_progress_files() -> void:
	for path in PROGRESS_PATHS:
		var exists := FileAccess.file_exists(path)
		_original_files[path] = {
			"exists": exists,
			"bytes": FileAccess.get_file_as_bytes(path) if exists else PackedByteArray(),
		}


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


func _progress_files_match() -> bool:
	for path in PROGRESS_PATHS:
		var snapshot: Dictionary = _original_files[path]
		var exists := FileAccess.file_exists(path)
		if exists != bool(snapshot["exists"]):
			return false
		if exists and FileAccess.get_file_as_bytes(path) != snapshot["bytes"]:
			return false
	return ProgressStore.progress == _original_progress
