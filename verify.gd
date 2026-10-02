extends SceneTree

const StoreScript := preload("res://store.gd")
const TaskDataScript := preload("res://task_data.gd")
const FocusEntryScript := preload("res://focus_entry.gd")
const FocusLogScript := preload("res://focus_log.gd")

const TEST_PATH := "user://verify_test.json"

var failures: Array[String] = []

func _store() -> Store:
	var s := StoreScript.new()
	s.save_path = TEST_PATH
	return s

func _init() -> void:
	await _test_task_data()
	await _test_store_roundtrip()
	await _test_store_corrupt()
	await _test_scene()

	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))

	if failures.is_empty():
		print("ALL CHECKS PASSED")
		quit(0)
	else:
		for f in failures:
			print("FAIL: " + f)
		quit(1)

# ---- Model ----

func _test_task_data() -> void:
	var d := TaskDataScript.parse_input("write docs #work #urgent")
	if d.title != "write docs":
		failures.append("parse: title was '" + d.title + "'")
	if Array(d.tags) != ["work", "urgent"]:
		failures.append("parse: tags were " + str(d.tags))

	var dup := TaskDataScript.parse_input("x #a #A #b")
	if Array(dup.tags) != ["a", "b"]:
		failures.append("parse: duplicate tags not deduped/lowercased: " + str(dup.tags))

	var hash_only := TaskDataScript.parse_input("#work")
	if hash_only.get_title() != "":
		failures.append("parse: tag-only input should have empty title")
	if not hash_only.has_tags():
		failures.append("parse: tag-only input lost its tags")

	# '#' followed by non-tag characters is not a tag
	var punctuation := TaskDataScript.parse_input("call #bob about ##double #with.dot")
	if punctuation.title != "call about ##double #with.dot":
		failures.append("parse: mangled non-tag text: '" + punctuation.title + "'")
	if Array(punctuation.tags) != ["bob"]:
		failures.append("parse: only #bob should be a tag, got " + str(punctuation.tags))

	# hyphens and underscores are fine in tags
	var slug := TaskDataScript.parse_input("x #deep-work #a_b")
	if Array(slug.tags) != ["deep-work", "a_b"]:
		failures.append("parse: hyphen/underscore tags rejected: " + str(slug.tags))

	var empty := TaskDataScript.parse_input("   ")
	if empty.get_title() != "":
		failures.append("parse: whitespace input should be empty")

	# round trip through dict
	var rt := TaskDataScript.from_dict({"title": "t", "tags": ["A", "b"]})
	if rt.title != "t" or Array(rt.tags) != ["a", "b"]:
		failures.append("from_dict: got " + str(rt.to_dict()))

	var partial := TaskDataScript.from_dict({"title": "only"})
	if partial.has_tags():
		failures.append("from_dict: missing tags key should default to empty")

# ---- Persistence ----

func _test_store_roundtrip() -> void:
	var s := _store()
	s.add_task(TaskDataScript.parse_input("alpha #x"))
	s.add_task(TaskDataScript.parse_input("beta #y #x"))

	# Two full rounds is half a 4-round session.
	var base := int(Time.get_unix_time_from_system())
	s.add_entry(FocusEntryScript.new(base, 1500, PackedStringArray(["x"]), true))
	s.add_entry(FocusEntryScript.new(base + 60, 420, PackedStringArray(), false))

	if not s.save():
		failures.append("store: save() returned false")

	var loaded := _store()
	if not loaded.load_from_disk():
		failures.append("store: load_from_disk() returned false")

	if loaded.entries.size() != 2:
		failures.append("store: entry count was " + str(loaded.entries.size()))
	if loaded.entries[0].complete != true:
		failures.append("store: complete flag lost on a complete round")
	if loaded.entries[1].complete != false:
		failures.append("store: incomplete round flag lost")
	if loaded.entries[1].seconds != 420:
		failures.append("store: entry seconds wrong: " + str(loaded.entries[1].seconds))
	if loaded.total_seconds() != 1920:
		failures.append("store: total_seconds was " + str(loaded.total_seconds()))
	if loaded.total_minutes() != 32:
		failures.append("store: total_minutes was " + str(loaded.total_minutes()))
	if loaded.sessions_completed() != 0:
		failures.append("store: 2 of 4 rounds should not be a session, got " + str(loaded.sessions_completed()))
	if Array(loaded.entries[0].tags) != ["x"]:
		failures.append("store: entry tags lost: " + str(loaded.entries[0].tags))
	if loaded.work_seconds != 1500 or loaded.round_count != 4:
		failures.append("store: settings not persisted")
	if loaded.log_dir != FocusLog.DEFAULT_DIR:
		failures.append("store: log_dir not persisted, got " + str(loaded.log_dir))
	if loaded.tasks.size() != 2:
		failures.append("store: task count was " + str(loaded.tasks.size()))
	if loaded.tasks[0].title != "alpha" or Array(loaded.tasks[0].tags) != ["x"]:
		failures.append("store: first task wrong: " + str(loaded.tasks[0].to_dict()))
	if Array(loaded.tasks[1].tags) != ["y", "x"]:
		failures.append("store: second task tags wrong: " + str(loaded.tasks[1].tags))

	if Array(loaded.all_tags()) != ["x", "y"]:
		failures.append("store: all_tags should be sorted+unique, got " + str(loaded.all_tags()))

	# suggestions
	if Array(loaded.suggest_tags("")) != ["x", "y"]:
		failures.append("store: suggest_tags('') wrong: " + str(loaded.suggest_tags("")))
	if Array(loaded.suggest_tags("x")) != ["x"]:
		failures.append("store: suggest_tags('x') wrong: " + str(loaded.suggest_tags("x")))
	if Array(loaded.suggest_tags("", PackedStringArray(["x"]))) != ["y"]:
		failures.append("store: exclude not honoured: " + str(loaded.suggest_tags("", PackedStringArray(["x"]))))
	if not loaded.suggest_tags("zzz").is_empty():
		failures.append("store: suggest_tags matched a nonexistent prefix")

	# missing file is not an error
	var absent := StoreScript.new()
	absent.save_path = "user://verify_absent.json"
	if absent.load_from_disk():
		failures.append("store: load of missing file should return false")

func _test_store_corrupt() -> void:
	var path := "user://verify_corrupt.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{ this is not json ")
	f.close()

	var s := StoreScript.new()
	s.save_path = path
	if s.load_from_disk():
		failures.append("store: corrupt file should return false")
	if s.total_seconds() != 0 or not s.tasks.is_empty() or not s.entries.is_empty():
		failures.append("store: corrupt file left dirty state")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

# ---- Scene ----

func _test_scene() -> void:
	var scene: PackedScene = load("res://main.tscn")
	if scene == null:
		failures.append("could not load main.tscn")
		return

	# Redirect before _ready() runs, and start from an empty save file.
	StoreScript.default_path = TEST_PATH
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))

	var main: Control = scene.instantiate()
	root.add_child(main)
	await process_frame
	main.store.save_path = TEST_PATH
	main.store.clear()
	main.store.clear_entries()
	
	# Every @onready path must resolve: a stale path would silently null out
	# and only fail much later.
	for prop in main.get_property_list():
		var usage: int = prop.get("usage", 0)
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var value: Variant = main.get(prop.name)
		if value == null:
			failures.append("@onready " + prop.name + " did not resolve")

	var input: LineEdit = main.get_node("app_bg/layout/input_row/new_task_input")
	var tasks: VBoxContainer = main.get_node("app_bg/layout/task_area/task_scroll/tasks_list")
	var stats_bar: Label = main.get_node("app_bg/layout/stats_bar")
	var popup: VBoxContainer = main.get_node("tag_popup")
	var suggestions: VBoxContainer = main.get_node("tag_popup/suggestion_scroll/suggestions")

	# starts from disk
	main.store.clear()
	main.store.clear_entries()
	
	if stats_bar.text != "0m focused · 0 sessions":
		failures.append("stats initial text: " + stats_bar.text)

	# add a tagged task
	input.text = "write docs #work #urgent"
	main.add_task()
	await process_frame

	if tasks.get_child_count() != 1:
		failures.append("tagged task not added")

	var row: PanelContainer = tasks.get_child(0)
	var tags_row: HBoxContainer = row.get_node("margin/top/tags")
	if not tags_row.visible:
		failures.append("tags row hidden despite tags")
	var chip_count := tags_row.get_child_count()
	if chip_count != 2:
		failures.append("expected 2 tag chips, got " + str(chip_count))

	# tags sit to the right of the label, not below it
	var top_row: HBoxContainer = row.get_node("margin/top")
	if tags_row.get_parent() != top_row:
		failures.append("tags should be a sibling of the label")
	var siblings: Array[Node] = []
	for c in top_row.get_children():
		siblings.append(c)
	if siblings.find(tags_row) <= siblings.find(row.get_node("margin/top/label")):
		failures.append("tags should come after the label so they render right of it")

	# tags are parsed out of the title
	var row_label: Label = row.get_node("margin/top/label")
	if row_label.text != "write docs":
		failures.append("title should not include tags: '" + row_label.text + "'")
	if row_label.theme_type_variation != &"TaskLabel":
		failures.append("task label not using TaskLabel variation")
	if main.store.tasks[0].title != "write docs":
		failures.append("store title wrong: " + main.store.tasks[0].title)

	# second task reuses tags
	input.text = "ship it #work"
	main.add_task()
	await process_frame
	if Array(main.store.all_tags()) != ["urgent", "work"]:
		failures.append("all_tags after 2 tasks: " + str(main.store.all_tags()))

	# ---- autocomplete ----
	input.text = "review #"
	input.caret_column = input.text.length()
	main._on_task_text_changed(input.text)
	await process_frame
	if not popup.visible:
		failures.append("suggestions hidden while typing '#'")
	if suggestions.get_child_count() != 2:
		failures.append("expected 2 suggestions for '#', got " + str(suggestions.get_child_count()))

	# filtering by prefix
	input.text = "review #wo"
	input.caret_column = input.text.length()
	main._on_task_text_changed(input.text)
	await process_frame
	if suggestions.get_child_count() != 1:
		failures.append("prefix filter failed, got " + str(suggestions.get_child_count()))
	if suggestions.get_child(0).text != "#work":
		failures.append("filtered suggestion wrong: " + suggestions.get_child(0).text)

	# autocomplete must not suggest the tag being typed
	input.text = "review #work"
	input.caret_column = input.text.length()
	main._on_task_text_changed(input.text)
	await process_frame
	if suggestions.get_child_count() != 0 or popup.visible:
		failures.append("tag already typed should not be suggested")

	# not inside a tag -> no popup
	input.text = "plain text"
	input.caret_column = input.text.length()
	main._on_task_text_changed(input.text)
	await process_frame
	if popup.visible:
		failures.append("popup shown outside a tag")

	# accepting a suggestion rewrites the line
	input.text = "review #wo"
	input.caret_column = input.text.length()
	main._on_suggestion_pressed("work")
	await process_frame
	if input.text != "review #work ":
		failures.append("accepting suggestion gave: '" + input.text + "'")
	if popup.visible:
		failures.append("popup still visible after accepting")

	# caret mid-text: must not insert a second space
	input.text = "review #wo stuff"
	input.caret_column = 10
	main._on_suggestion_pressed("work")
	await process_frame
	if input.text != "review #work stuff":
		failures.append("accepting mid-text gave: '" + input.text + "'")
	if input.caret_column != 12:
		failures.append("caret after mid-text accept: " + str(input.caret_column))

	# ---- focus tracking ----
	main.store.clear_entries()
	main._round_focused = 0.0
	main._round_tags = PackedStringArray()
	main._round_started_unix = int(Time.get_unix_time_from_system())

	# a partial round credits the actual seconds, not a full block
	main.state = 1
	main._round_focused = 480.0
	main._on_complete_pressed()
	await process_frame
	if main.store.total_seconds() != 480:
		failures.append("partial round focus was " + str(main.store.total_seconds()))
	if main.store.entries.size() != 1:
		failures.append("partial round should log one entry")
	if main.store.entries[0].complete:
		failures.append("partial round should be marked incomplete")
	if main.store.sessions_completed() != 0:
		failures.append("partial round should not count as a session")

	# round label still advanced
	if main.round_label.text != "1 / 4":
		failures.append("round label after complete: " + main.round_label.text)

	# tags completed mid-round are attributed to the round in progress
	for child in tasks.get_children():
		child.queue_free()
	await process_frame
	input.text = "tagged work #deep-work #urgent"
	main.add_task()
	await process_frame
	# Seed the round before completing, so the tag lands on the round.
	main._round_tags = PackedStringArray()
	main._on_task_completed(tasks.get_child(0), main.store.tasks[main.store.tasks.size() - 1])
	await create_timer(0.4).timeout
	if main._round_tags != PackedStringArray(["deep-work", "urgent"]):
		failures.append("completing a task should attribute its tags to the round, got " + str(main._round_tags))

	main.state = 1
	main._round_focused = 1500.0
	main._round_started_unix = int(Time.get_unix_time_from_system())
	main._on_complete_pressed()
	await process_frame

	var tagged: FocusEntry = main.store.entries[main.store.entries.size() - 1]
	if Array(tagged.tags) != ["deep-work", "urgent"]:
		failures.append("round tags wrong: " + str(tagged.tags))

	# finish the remaining rounds -> FINISHED, one session.
	# The tagged round above was round 2, so three more reach 4 (IDLE) and a
	# fourth tips past round_count.
	for i in range(2):
		main.state = 1
		main._round_focused = 1500.0
		main._round_started_unix = int(Time.get_unix_time_from_system())
		main._on_complete_pressed()
	if main.state != 0:
		failures.append("should still be IDLE at 4/4, got " + str(main.state))

	main.state = 1
	main._round_focused = 1500.0
	main._round_started_unix = int(Time.get_unix_time_from_system())
	main._on_complete_pressed()
	await process_frame

	if main.state != 3:
		failures.append("expected FINISHED after full set, got " + str(main.state))
	if main.store.sessions_completed() != 1:
		failures.append("full set should count as 1 session, got " + str(main.store.sessions_completed()))
	if main.store.entries.size() != 5:
		failures.append("expected 5 entries, got " + str(main.store.entries.size()))
	if main.round_label.text != "DONE":
		failures.append("round label should be DONE")

	# stats bar reflects it, and singular wording for 1
	if not main.stats_bar.text.contains("1 session"):
		failures.append("stats bar singular wording: " + main.stats_bar.text)
	if not main.stats_bar.text.contains("108m"):
		failures.append("stats bar minutes wrong: " + main.stats_bar.text)

	# two sessions -> plural
	for i in range(4):
		main.store.add_entry(FocusEntryScript.new(int(Time.get_unix_time_from_system()), 1500, PackedStringArray(), true))
	main.sync_stats()
	if not main.stats_bar.text.contains("2 sessions"):
		failures.append("stats bar plural wording: " + main.stats_bar.text)

	# ---- markdown log ----
	var written: PackedStringArray = FocusLogScript.write_days(main.store.entries)
	if written.is_empty():
		failures.append("focus log: nothing written")
	else:
		var md_path: String = written[0]
		if not md_path.ends_with(".md"):
			failures.append("focus log: not a .md file: " + md_path)
		var md := FileAccess.get_file_as_string(md_path)
		if not md.begins_with("# "):
			failures.append("focus log: missing top-level heading")
		if not md.contains("## Rounds"):
			failures.append("focus log: missing Rounds section")
		if not md.contains("· %d rounds ·" % main.store.entries.size()):
			failures.append("focus log: round count wrong: " + md.substr(0, 120))
		if not md.contains("rounds complete"):
			failures.append("focus log: completion summary missing")
		if not md.contains("#deep-work #urgent"):
			failures.append("focus log: tags missing from markdown")
		if not md.contains("ended early"):
			failures.append("focus log: early round not marked")
		if not md.contains("`%02d:%02d`" % [Time.get_datetime_dict_from_unix_time(main.store.entries[0].started_unix).hour, Time.get_datetime_dict_from_unix_time(main.store.entries[0].started_unix).minute]):
			failures.append("focus log: round time missing")

		# regenerating must be byte-identical
		var before := md
		FocusLogScript.write_days(main.store.entries)
		if FileAccess.get_file_as_string(md_path) != before:
			failures.append("focus log: regeneration is not idempotent")

	# reset must not bank the in-progress time
	main.state = 1
	main._round_focused = 300.0
	main._on_reset_pressed()
	await process_frame
	if main._round_focused != 0.0:
		failures.append("reset left " + str(main._round_focused) + " banked")

	# ---- completing a task removes it from the store ----
	# The focus tests above removed tasks, so re-seed known ones.
	for child in tasks.get_children():
		child.queue_free()
	await process_frame
	main.store.tasks.clear()
	for title in ["write docs #work", "ship it #work", "third"]:
		input.text = title
		main.add_task()
	await process_frame

	var tasks_before: int = main.store.tasks.size()
	if tasks_before != 3:
		failures.append("re-seed should give 3 tasks, got " + str(tasks_before))

	var second_row: PanelContainer = tasks.get_child(1)
	main._on_task_completed(second_row, main.store.tasks[1])
	await create_timer(0.4).timeout
	if main.store.tasks.size() != 2:
		failures.append("completing a task did not remove it from the store: " + str(main.store.tasks.size()))
	else:
		var titles: Array[String] = []
		for t in main.store.tasks:
			titles.append(t.title)
		if titles != ["write docs", "third"]:
			failures.append("wrong task removed, left: " + str(titles))

	# ---- log folder selection ----
	var dialog: FileDialog = main.get_node("folder_dialog")
	var use_folder: Button = dialog.get_node("use_folder")
	if use_folder.text != "Use this folder":
		failures.append("dialog: 'Use this folder' button missing or mislabelled")
	if dialog.file_mode != FileDialog.FILE_MODE_OPEN_DIR:
		failures.append("dialog: not in directory-select mode")
	if not dialog.use_native_dialog:
		failures.append("dialog: should use the native picker")
	if dialog.access != FileDialog.ACCESS_FILESYSTEM:
		failures.append("dialog: should browse the whole filesystem, got " + str(dialog.access))

	# Browse starts from the current log folder
	main._on_browse_log_dir_pressed()
	await process_frame
	if dialog.current_dir != main._absolute_log_dir():
		failures.append("dialog: browse did not start in the current log folder")

	# Point the dialog at a real folder and confirm it becomes the log dir.
	var target := "user://verify_logdir"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target))
	dialog.current_dir = ProjectSettings.globalize_path(target)
	main._on_use_this_folder_pressed()
	await process_frame

	# The picker yields an absolute path, so compare in that form.
	if main.store.log_dir != ProjectSettings.globalize_path(target):
		failures.append("dialog: folder not applied, store.log_dir = " + str(main.store.log_dir))
	if main.log_dir_input.text != ProjectSettings.globalize_path(target):
		failures.append("dialog: input not updated, got " + main.log_dir_input.text)
	if FocusLog.log_dir != main.store.log_dir:
		failures.append("dialog: FocusLog.log_dir not synced with store")
	if not main.store.entries.is_empty():
		var expected_file := ProjectSettings.globalize_path(target).path_join(main.store.entries[0].day_key() + ".md")
		if not FileAccess.file_exists(expected_file):
			failures.append("dialog: existing days not re-rendered into the new folder")

	# Typing a path directly still works, and creates missing folders
	main.log_dir_input.text = "user://verify_logdir_typed"
	main._on_log_dir_submitted("  user://verify_logdir_typed  ")
	await process_frame
	if main.store.log_dir != "user://verify_logdir_typed":
		failures.append("typed path not applied: " + str(main.store.log_dir))
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("user://verify_logdir_typed")):
		failures.append("typed folder was not created")

	# Blank input falls back to the default rather than an empty path
	main._on_log_dir_submitted("   ")
	await process_frame
	if main.store.log_dir != FocusLog.DEFAULT_DIR:
		failures.append("blank input should fall back to default, got " + str(main.store.log_dir))

	# clean up the folders these tests created
	for d in [target, "user://verify_logdir_typed"]:
		var abs := ProjectSettings.globalize_path(d)
		var md := DirAccess.open(abs)
		if md:
			for f in md.get_files():
				md.remove(f)
		DirAccess.remove_absolute(abs)

	# ---- persistence across a restart ----
	main.store.save()
	await process_frame

	# Point the default save path at the scratch file *before* instantiating,
	# since _ready() reads from disk immediately.
	StoreScript.default_path = TEST_PATH

	var reopened: Control = (load("res://main.tscn") as PackedScene).instantiate()
	for child in main.get_children():
		main.remove_child(child)
		child.queue_free()
	root.add_child(reopened)
	await process_frame

	if reopened.store.save_path != TEST_PATH:
		failures.append("reopened scene did not use the test save path")

	var restored: VBoxContainer = reopened.get_node("app_bg/layout/task_area/task_scroll/tasks_list")
	if reopened.store.tasks.size() != main.store.tasks.size():
		failures.append("task count changed across reload: " + str(reopened.store.tasks.size()) + " vs " + str(main.store.tasks.size()))
	if reopened.store.total_seconds() != main.store.total_seconds():
		failures.append("focus not restored: " + str(reopened.store.total_seconds()))
	if reopened.store.sessions_completed() != main.store.sessions_completed():
		failures.append("sessions not restored: " + str(reopened.store.sessions_completed()))
	if restored.get_child_count() != reopened.store.tasks.size():
		failures.append("restored rows do not match stored tasks")

	reopened.queue_free()
	await process_frame
