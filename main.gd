extends Control

const TASK_ROW := preload("res://task_row.tscn")

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
@onready var new_task_input: LineEdit = $app_bg/layout/input_row/new_task_input
@onready var start_pause_button: Button = $app_bg/layout/controls_row/start_pause_button
@onready var time_label: Label = $app_bg/layout/stats_row/time_label
@onready var round_label: Label = $app_bg/layout/stats_row/round_label
@onready var pomodoro_timer: Timer = $pomodoro_timer
@onready var sfx_player: AudioStreamPlayer = $sfx_player

@export_range(60, 3600, 30) var work_seconds := 1500
@export_range(1, 12) var round_count := 4

var rounds := 0
var state: SessionState = SessionState.IDLE

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pomodoro_timer.set_wait_time(work_seconds)
	new_task_input.text_submitted.connect(_on_task_text_submitted)
	tasks_list.child_entered_tree.connect(_on_task_added)
	update_task_area()
	sync_ui()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	if state == SessionState.RUNNING:
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
	rounds += 1

	if rounds > round_count:
		rounds = round_count
		state = SessionState.FINISHED
	else:
		state = SessionState.IDLE

	sync_ui()

func stop_timer() -> void:
	pomodoro_timer.stop()
	pomodoro_timer.paused = false

func add_task() -> void:
	var task_name: String = new_task_input.text.strip_edges()

	if task_name.is_empty():
		return

	var row: PanelContainer = TASK_ROW.instantiate()
	row.completed.connect(_on_task_completed)

	tasks_list.add_child(row)
	row.setup(task_name)

	new_task_input.clear()
	new_task_input.release_focus()
	new_task_input.grab_focus()
	new_task_input.grab_click_focus()

func _on_task_completed(row: PanelContainer) -> void:
	sfx_player.play()

	var tween: Tween = row.create_tween()
	tween.set_parallel(true)

	tween.tween_property(row, "scale", Vector2(1.05, 1.05), 0.15) \
		.set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_OUT)

	tween.tween_property(row, "modulate:a", 0.0, 0.15)

	await tween.finished
	row.queue_free()
	_on_task_removed()

func _on_start_pause_pressed() -> void:
	match state:
		SessionState.IDLE, SessionState.FINISHED:
			if state == SessionState.FINISHED:
				rounds = 0
			state = SessionState.RUNNING
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
	state = SessionState.IDLE

	sync_ui()

func _on_complete_pressed() -> void:
	if state != SessionState.RUNNING and state != SessionState.PAUSED:
		return

	stop_timer()
	record_round()
