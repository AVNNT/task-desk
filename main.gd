extends Control

enum SessionState { IDLE, RUNNING, PAUSED, FINISHED }

@onready var input_row: HBoxContainer = $main_layer/layout/input_row
@onready var controls_row: HBoxContainer = $main_layer/layout/controls_row
@onready var tasks_list: VBoxContainer = $main_layer/layout/task_scroll/tasks_list
@onready var new_task_input: LineEdit = $main_layer/layout/input_row/new_task_input
@onready var add_button: Button = $main_layer/layout/input_row/add_button
@onready var start_pause_button: Button = $main_layer/layout/controls_row/start_pause_button
@onready var time_label: Label = $main_layer/layout/stats_row/time_label
@onready var round_label: Label = $main_layer/layout/stats_row/round_label
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
	sync_ui()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	if state == SessionState.RUNNING:
		update_timer_label()

func _on_task_text_submitted(_text: String) -> void:
	add_task()

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

	var task := CheckBox.new()
	task.text = task_name
	task.toggled.connect(_on_task_toggled.bind(task))

	tasks_list.add_child(task)

	new_task_input.clear()
	new_task_input.release_focus()
	new_task_input.grab_focus()
	new_task_input.grab_click_focus()

func _on_task_toggled(is_checked: bool, task: CheckBox) -> void:
	if not is_checked:
		return

	task.disabled = true
	sfx_player.play()

	var tween: Tween = task.create_tween()
	tween.set_parallel(true)

	tween.tween_property(task, "scale", Vector2(1.8, 1.8), 0.15) \
		.set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_OUT)

	tween.tween_property(task, "rotation", deg_to_rad(12), 0.15)
	tween.tween_property(task, "modulate:a", 0.0, 0.15)

	await tween.finished
	task.queue_free()

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
