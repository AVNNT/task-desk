extends Control

@onready var add: Button = $PanelContainer/VBoxContainer/HBoxContainer/Add
@onready var new_task: LineEdit = $PanelContainer/VBoxContainer/HBoxContainer/New_Task
@onready var tasks_container: VBoxContainer = $PanelContainer/VBoxContainer/Tasks_Container
@onready var pomodoro: Timer = $Pomodoro
@onready var time_label: Label = $PanelContainer/VBoxContainer/HBoxContainer3/Time_Label
@onready var start_paused: Button = $PanelContainer/VBoxContainer/HBoxContainer2/Start_Paused
@onready var round_label: Label = $PanelContainer/VBoxContainer/HBoxContainer3/Round_Label

var wait_time := 1500
var rounds := 0
var round_left := 4

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	rounds = 0
	pomodoro.set_wait_time(wait_time)
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	if pomodoro.is_stopped():
		pomodoro.set_wait_time(wait_time)
		return
	else:
		update_timer_label()
		update_rounds()

func update_timer_label():
	var time_left := ceili(pomodoro.time_left if pomodoro.time_left > 0 else pomodoro.get_wait_time())
	var minutes := time_left / 60
	var seconds := time_left % 60
	time_label.text = "%02d:%02d" % [minutes, seconds]

func update_rounds():
	round_label.text = "%d / %d" % [rounds, round_left]

func add_round():
	if rounds < round_left:
		rounds += 1
		update_rounds()
	else:
		round_label.text = "DONE"
		return

func _on_add_pressed() -> void:
	var task_name = new_task.text

	if task_name.is_empty():
		return
		
	var task = CheckBox.new()
	task.text = task_name
	
	task.toggled.connect(_on_task_toggled.bind(task))
	
	tasks_container.add_child(task)
	print(task_name)
	new_task.clear()

func _on_task_toggled(is_checked: bool, task: CheckBox) -> void:
	if is_checked:
		task.disabled = true
		var tween = task.create_tween()
		tween.set_parallel(true)

		tween.tween_property(task, "scale", Vector2(1.8, 1.8), 0.5) \
			.set_trans(Tween.TRANS_BACK) \
			.set_ease(Tween.EASE_OUT)

		tween.tween_property(task, "rotation", deg_to_rad(12), 0.5)
		$AudioStreamPlayer2D.play()
		
		tween.tween_property(task, "modulate:a", 0.0, 0.5)

		await tween.finished
		task.queue_free()
	else:
		return
	
func _on_start_paused_pressed() -> void:
	if pomodoro.is_stopped():
		pomodoro.start()
		start_paused.text = "Pause"
		return
		
	pomodoro.paused = not pomodoro.paused
	start_paused.text = "Start" if pomodoro.paused else "Pause"	

func _on_pomodoro_timeout() -> void:
	add_round()
	
func _on_reset_pressed() -> void:
	pomodoro.stop()
	pomodoro.paused = false
	pomodoro.set_wait_time(wait_time)	
	start_paused.text = "Start"
	update_timer_label()

func _on_complete_pressed() -> void:
	if pomodoro.is_stopped():
		return
	else:
		add_round()
		_on_reset_pressed()
		
