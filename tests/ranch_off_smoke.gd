extends SceneTree

const ProgressStoreScript = preload("res://scripts/autoload/progress_store.gd")

func _initialize() -> void:
	var progress_store: Node = ProgressStoreScript.new()
	progress_store.name = "ProgressStore"
	root.add_child(progress_store)
	for autoload in [
		["PackStore", load("res://scripts/autoload/pack_store.gd")],
		["GithubSync", load("res://scripts/autoload/github_sync.gd")],
		["ThemeSetup", load("res://scripts/autoload/theme_setup.gd")],
		["Sfx", load("res://scripts/autoload/sfx.gd")],
	]:
		var node: Node = (autoload[1] as Script).new()
		node.name = autoload[0]
		root.add_child(node)
	var original := bool(progress_store.call("is_farm_visible"))
	progress_store.call("set_farm_visible", false)
	var scene: Node = load("res://scenes/Ranch.tscn").instantiate()
	root.add_child(scene)
	assert(scene.get("_yard") == null)
	scene.call("_sort_sprites")
	assert(scene != null)
	scene.queue_free()
	progress_store.call("set_farm_visible", original)
	quit(0)
