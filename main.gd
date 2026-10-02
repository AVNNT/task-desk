extends Control

const TASK_ROW := preload("res://task_row.tscn")
const StoreScript := preload("res://store.gd")
const TaskDataScript := preload("res://task_data.gd")
const FocusEntryScript := preload("res://focus_entry.gd")

const TIMER_IDLE := Color(0.901961, 0.909804, 0.941176, 1)
const TIMER_WARNING := Color(0.909804, 0.690196, 0.294118, 1)
const TIMER_URGENT := Color(0.878431, 0.360784, 0.360784, 1)

const WARNING_RATIO := 0.25
const URGENT_RATIO := 0.1

enum SessionState { IDLE, RUNNING, PAUSED, FINISHED }

@onready var input_row: HBoxContainer = $app_bg/layout/input_row
@onready var tasks_list: VBoxContainer = $app_bg/layout/task_area/task_scroll/tasks_list
@onready var task_scroll: ScrollContainer = $app_bg/layout/task_area/task_scroll
@onready var empty_label: Label = $app_bg/layout/task_area/empty_label
@onready var stats_bar: Label = $app_bg/layout/stats_bar
@onready var log_dir_input: LineEdit = $app_bg/layout/log_dir_row/log_dir_input
@onready var browse_button: Button = $app_bg/layout/log_dir_row/browse_button
@onready var folder_dialog: FileDialog = $folder_dialog
@onready var new_task_input: LineEdit = $app_bg/layout/input_row/new_task_input
@onready var start_pause_button: Button = $app_bg/layout/controls_row/start_pause_button
@onready var time_label: Label = $app_bg/layout/stats_row/time_label
@onready var round_label: Label = $app_bg/layout/stats_row/round_label
@onready var pomodoro_timer: Timer = $pomodoro_timer
@onready var sfx_player: AudioStreamPlayer = $sfx_player
@onready var tag_popup: VBoxContainer = $tag_popup
@onready var suggestions_list: VBoxContainer = $tag_popup/suggestion_scroll/suggestions

@export var work_seconds := 1500
@export_range(1, 12) var round_count := 4

var store := StoreScript.new()
var rounds := 0
var state: SessionState = SessionState.IDLE

# Accrual for the current round, so pausing banks progress instead of
# losing it, and so the log can say what the round actually cost.
var _round_focused := 0.0
var _round_started_unix := 0
var _round_tags: PackedStringArray = PackedStringArray()

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	store.load_from_disk()

	work_seconds = store.work_seconds
	round_count = store.round_count
	FocusLog.log_dir = store.log_dir
	log_dir_input.text = store.log_dir

	pomodoro_timer.set_wait_time(work_seconds)
	new_task_input.text_submitted.connect(_on_task_text_submitted)
	new_task_input.text_changed.connect(_on_task_text_changed)
	new_task_input.focus_exited.connect(_hide_suggestions)
	log_dir_input.text_submitted.connect(_on_log_dir_submitted)
	browse_button.pressed.connect(_on_browse_log_dir_pressed)
	folder_dialog.dir_selected.connect(_on_use_this_folder_pressed)
	tasks_list.child_entered_tree.connect(_on_task_added)

	for data in store.tasks:
		_add_row(data)

	update_task_area()
	sync_stats()
	sync_ui()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		store.save()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if state == SessionState.RUNNING:
		_round_focused += delta
		update_timer_label()

func _on_task_text_submitted(_text: String) -> void:
	add_task()

func _on_task_added(_node: Node) -> void:
	update_task_area()

func update_task_area() -> void:
	var has_tasks := tasks_list.get_child_count() > 0
	empty_label.visible = not has_tasks
	task_scroll.visible = has_tasks

func _on_task_removed() -> void:
	# child_exiting_tree fires before removal, so wait for the count to settle.
	await get_tree().process_frame
	update_task_area()

# Single place that decides what the UI looks like for the current state.
func sync_ui() -> void:
	match state:
		SessionState.IDLE:
			start_pause_button.text = "Start"
			input_row.show()
		SessionState.RUNNING:
			start_pause_button.text = "Pause"
			input_row.hide()
		SessionState.PAUSED:
			start_pause_button.text = "Resume"
			input_row.show()
		SessionState.FINISHED:
			start_pause_button.text = "Start"
			input_row.show()

	if state == SessionState.FINISHED:
		round_label.text = "DONE"
	else:
		round_label.text = "%d / %d" % [rounds, round_count]

	update_timer_label()

func sync_stats() -> void:
	var sessions := store.sessions_completed()
	stats_bar.text = "%dm focused · %d %s" % [
		store.total_minutes(),
		sessions,
		"session" if sessions == 1 else "sessions",
	]

func update_timer_label() -> void:
	var time_left := ceili(pomodoro_timer.time_left if pomodoro_timer.time_left > 0 else pomodoro_timer.get_wait_time())
	var minutes := time_left / 60
	var seconds := time_left % 60
	time_label.text = "%02d:%02d" % [minutes, seconds]
	time_label.add_theme_color_override("font_color", _timer_color())

# Green while there is time, amber under a quarter left, red near the end.
func _timer_color() -> Color:
	if state != SessionState.RUNNING:
		return TIMER_IDLE

	return _color_for_ratio(float(pomodoro_timer.time_left) / float(work_seconds))

func _color_for_ratio(ratio: float) -> Color:
	if ratio <= URGENT_RATIO:
		return TIMER_URGENT
	if ratio <= WARNING_RATIO:
		return TIMER_WARNING
	return TIMER_IDLE

# Called by both the timeout and the Complete button.
func record_round() -> void:
	var seconds := roundi(_round_focused)
	var completed_full_round := seconds >= work_seconds - 1

	store.add_entry(FocusEntryScript.new(
		_round_started_unix,
		seconds,
		_round_tags.duplicate(),
		completed_full_round
	))

	_round_focused = 0.0
	_round_tags = PackedStringArray()
	_round_started_unix = 0

	rounds += 1
	if rounds > round_count:
		rounds = round_count
		state = SessionState.FINISHED
	else:
		state = SessionState.IDLE

	sync_stats()
	sync_ui()
	persist()

func persist() -> void:
	FocusLog.log_dir = store.log_dir
	FocusLog.write_days(store.entries)
	store.save()

func stop_timer() -> void:
	pomodoro_timer.stop()
	pomodoro_timer.paused = false

func _add_row(data: TaskData) -> void:
	var row: PanelContainer = TASK_ROW.instantiate()
	row.completed.connect(_on_task_completed)

	tasks_list.add_child(row)
	row.setup(data)

func add_task() -> void:
	var data := TaskDataScript.parse_input(new_task_input.text)

	if data.get_title().is_empty():
		new_task_input.clear()
		_hide_suggestions()
		return

	store.add_task(data)
	_add_row(data)
	persist()

	new_task_input.clear()
	_hide_suggestions()
	new_task_input.release_focus()
	new_task_input.grab_focus()
	new_task_input.grab_click_focus()

func _on_task_completed(row: PanelContainer, data: TaskData) -> void:
	sfx_player.play()

	# Remove by identity, not position: row order and store order can diverge.
	var index := store.tasks.find(data)
	if index >= 0:
		store.tasks.remove_at(index)
	else:
		push_warning("Completed task not found in store: " + data.title)

	# Attribute this task's tags to the round in progress.
	for tag in data.tags:
		if not _round_tags.has(tag):
			_round_tags.append(tag)
	persist()

	var tween: Tween = row.create_tween()
	tween.set_parallel(true)

	tween.tween_property(row, "scale", Vector2(1.05, 1.05), 0.15) \
		.set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_OUT)

	tween.tween_property(row, "modulate:a", 0.0, 0.15)

	await tween.finished
	row.queue_free()
	_on_task_removed()

# ---- Tag autocomplete ----

func _on_task_text_changed(_text: String) -> void:
	var fragment: Variant = _partial_tag(new_task_input.text)

	if fragment == null:
		_hide_suggestions()
		return

	var query: String = fragment.get("query", "")
	var exclude: PackedStringArray = fragment.get("exclude", PackedStringArray())
	var matches := store.suggest_tags(query, exclude)

	if matches.is_empty():
		_hide_suggestions()
		return

	_show_suggestions(matches)

# Returns {query, exclude} for the #word being typed, or null when the caret
# is not inside a tag.
func _partial_tag(text: String) -> Variant:
	var caret := clampi(new_task_input.caret_column, 0, text.length())
	var head := text.substr(0, caret)
	var word_start := head.rfind(" ")

	# The word after the last space must start with '#' to be a tag.
	var word := head.substr(word_start + 1)
	if not word.begins_with("#"):
		return null

	var typed := word.substr(1).to_lower()

	# Suppress only an exact match on what is typed. A longer tag that merely
	# starts with the same letters ('#wo' vs 'work') is still a valid suggestion.
	var exclude: PackedStringArray = PackedStringArray()
	if not typed.is_empty() and store.all_tags().has(typed):
		exclude.append(typed)

	return {"query": typed, "exclude": exclude}

func _show_suggestions(tags: PackedStringArray) -> void:
	_clear_suggestions()

	for tag in tags:
		var button := Button.new()
		button.text = "#" + tag
		button.theme_type_variation = &"SuggestionRow"
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_on_suggestion_pressed.bind(tag))
		suggestions_list.add_child(button)

	tag_popup.visible = true

func _hide_suggestions() -> void:
	tag_popup.visible = false
	_clear_suggestions()

# queue_free() is deferred, so drop the children immediately to stop stale
# buttons lingering in the (now hidden) popup.
func _clear_suggestions() -> void:
	for child in suggestions_list.get_children():
		suggestions_list.remove_child(child)
		child.queue_free()

func _on_suggestion_pressed(tag: String) -> void:
	var text := new_task_input.text
	var caret := clampi(new_task_input.caret_column, 0, text.length())
	var head := text.substr(0, caret)
	var word_start := head.rfind(" ")
	var word := head.substr(word_start + 1)

	if not word.begins_with("#"):
		return

	var before := text.substr(0, word_start + 1)
	var after := text.substr(caret)

	# Keep a single space after the tag; don't add one if text already follows.
	var separator := " " if after.is_empty() or not after.begins_with(" ") else ""
	new_task_input.text = before + "#" + tag + separator + after
	new_task_input.caret_column = (before + "#" + tag + separator).length()

	_hide_suggestions()

# ---- Timer controls ----

func _on_start_pause_pressed() -> void:
	match state:
		SessionState.IDLE, SessionState.FINISHED:
			if state == SessionState.FINISHED:
				rounds = 0
			state = SessionState.RUNNING
			_round_started_unix = int(Time.get_unix_time_from_system())
			pomodoro_timer.start()
		SessionState.RUNNING:
			state = SessionState.PAUSED
			pomodoro_timer.paused = true
		SessionState.PAUSED:
			state = SessionState.RUNNING
			pomodoro_timer.paused = false

	sync_ui()

func _on_pomodoro_timeout() -> void:
	stop_timer()
	record_round()

func _on_reset_pressed() -> void:
	stop_timer()
	pomodoro_timer.set_wait_time(work_seconds)
	rounds = 0
	_round_focused = 0.0
	_round_tags = PackedStringArray()
	_round_started_unix = 0
	state = SessionState.IDLE

	sync_ui()
func _on_complete_pressed() -> void:
	if state != SessionState.RUNNING and state != SessionState.PAUSED:
		return

	stop_timer()
	record_round()

# ---- Settings ----

# The dialog starts in the current log folder, defaulting to user://.
func _on_browse_log_dir_pressed() -> void:
	folder_dialog.current_dir = _absolute_log_dir()
	folder_dialog.popup_centered_ratio(0.6)

# FileDialog cannot return a directory directly, so this button grabs
# whichever folder the user has navigated to.
func _on_use_this_folder_pressed() -> void:
	_apply_log_dir(folder_dialog.current_dir)

func _on_log_dir_submitted(text: String) -> void:
	var chosen := text.strip_edges()
	if chosen.is_empty():
		chosen = FocusLog.DEFAULT_DIR
	_apply_log_dir(chosen)

func _apply_log_dir(chosen: String) -> void:
	if chosen.is_empty():
		chosen = FocusLog.DEFAULT_DIR

	# The native picker hands back an absolute path; keep whatever form the
	# caller gave us, since only the user-typed path may be a user:// path.
	var absolute := ProjectSettings.globalize_path(chosen)
	if not DirAccess.dir_exists_absolute(absolute):
		var err := DirAccess.make_dir_recursive_absolute(absolute)
		if err != OK:
			push_warning("Could not create log folder %s (error %d)" % [chosen, err])
			log_dir_input.text = store.log_dir
			return

	store.log_dir = chosen
	log_dir_input.text = chosen

	# Re-render every day that has entries so the files land in the new place.
	persist()

func _absolute_log_dir() -> String:
	return ProjectSettings.globalize_path(store.log_dir)
