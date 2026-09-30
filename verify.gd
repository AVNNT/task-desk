extends SceneTree

func _init() -> void:
	var scene: PackedScene = load("res://main.tscn")
	if scene == null:
		print("FAIL: could not load main.tscn")
		quit(1)
		return

	var main: Control = scene.instantiate()
	root.add_child(main)
	await process_frame

	var failures: Array[String] = []

	# Structure
	for path in [
		"app_bg/layout/stats_row/time_label",
		"app_bg/layout/task_area/empty_label",
		"app_bg/layout/task_area/task_scroll/tasks_list",
		"app_bg/layout/input_row/new_task_input",
	]:
		if main.get_node_or_null(path) == null:
			failures.append("missing node: " + path)

	# Theme actually applied
	if main.theme == null:
		failures.append("root theme not assigned")
	else:
		var expected := Color(0.086275, 0.086275, 0.113725, 1)
		var bg: StyleBox = main.theme.get_stylebox("panel", &"AppBackground")
		if bg == null or (bg as StyleBoxFlat).bg_color != expected:
			failures.append("AppBackground stylebox not from theme")

	# Timer label uses the mono variation
	var tl: Label = main.get_node("app_bg/layout/stats_row/time_label")
	if tl.theme_type_variation != &"TimerLabel":
		failures.append("time_label not using TimerLabel variation")
	if tl.text != "25:00":
		failures.append("initial timer text wrong: " + tl.text)

	# Empty state visible with no tasks
	var empty: Label = main.get_node("app_bg/layout/task_area/empty_label")
	var scroll: ScrollContainer = main.get_node("app_bg/layout/task_area/task_scroll")
	if not empty.visible:
		failures.append("empty label hidden at start")
	if scroll.visible:
		failures.append("scroll visible with no tasks")

	# Add a task
	var input: LineEdit = main.get_node("app_bg/layout/input_row/new_task_input")
	var tasks: VBoxContainer = main.get_node("app_bg/layout/task_area/task_scroll/tasks_list")
	input.text = "  Write docs  "
	main.add_task()
	await process_frame

	if tasks.get_child_count() != 1:
		failures.append("task not added")
	if input.text != "":
		failures.append("input not cleared")
	if empty.visible:
		failures.append("empty label still visible after add")
	if not scroll.visible:
		failures.append("scroll not visible after add")

	var row: PanelContainer = tasks.get_child(0)
	if row.get_node("margin/content/label").text != "Write docs":
		failures.append("task name not trimmed: '" + row.get_node("margin/content/label").text + "'")

	# The checkbox must actually respond to a real mouse click.
	var check: CheckBox = row.get_node("margin/content/check")
	if check.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		failures.append("checkbox ignores mouse input, cannot be clicked")
	if check.size_flags_horizontal & Control.SIZE_EXPAND:
		failures.append("checkbox expands, stretching its background")

	var click := func(target: Control) -> void:
		var pos: Vector2 = target.get_global_rect().get_center()
		target.get_viewport().push_input(InputEventMouseMotion.new(), true)
		for pressed in [true, false]:
			var ev := InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_LEFT
			ev.pressed = pressed
			ev.global_position = pos
			ev.position = pos
			target.get_viewport().push_input(ev, true)
			await process_frame

	# Real click on the checkbox glyph
	await click.call(check)
	await create_timer(0.5).timeout
	if tasks.get_child_count() != 0:
		failures.append("real click on checkbox did not complete the task")
	if not empty.visible:
		failures.append("empty label did not return after task freed")

	# Real click on the label text should not complete anything
	input.text = "Second task"
	main.add_task()
	await process_frame
	var row2: PanelContainer = tasks.get_child(0)
	var lbl2: Label = row2.get_node("margin/content/label")
	await click.call(lbl2)
	await create_timer(0.4).timeout
	if tasks.get_child_count() != 1:
		failures.append("clicking label unexpectedly completed the task")
	row2.queue_free()
	await process_frame
	await process_frame

	# Empty input is rejected
	main.add_task()
	if tasks.get_child_count() != 0:
		failures.append("blank task was added")

	# ---- State machine ----
	var sp: Button = main.get_node("app_bg/layout/controls_row/start_pause_button")
	var input_row: HBoxContainer = main.get_node("app_bg/layout/input_row")
	var rl: Label = main.get_node("app_bg/layout/stats_row/round_label")
	var timer: Timer = main.get_node("pomodoro_timer")

	# IDLE -> RUNNING
	sp.emit_signal("pressed")
	await process_frame
	if main.state != 1:
		failures.append("expected RUNNING, got " + str(main.state))
	if sp.text != "Pause":
		failures.append("button text not 'Pause' while running")
	if input_row.visible:
		failures.append("input row still visible while running")

	# RUNNING -> PAUSED
	sp.emit_signal("pressed")
	await process_frame
	if main.state != 2:
		failures.append("expected PAUSED, got " + str(main.state))
	if sp.text != "Resume":
		failures.append("button text not 'Resume' while paused")
	if not input_row.visible:
		failures.append("input row not visible while paused")

	# PAUSED -> RUNNING
	sp.emit_signal("pressed")
	await process_frame
	if main.state != 1:
		failures.append("expected RUNNING after resume, got " + str(main.state))
	if sp.text != "Pause":
		failures.append("button text wrong after resume")

	# Timeout -> IDLE, round counted, UI must be consistent
	main._on_pomodoro_timeout()
	await process_frame
	if main.state != 0:
		failures.append("expected IDLE after timeout, got " + str(main.state))
	if sp.text != "Start":
		failures.append("button text not 'Start' after timeout")
	if not input_row.visible:
		failures.append("input row hidden after timeout")
	if rl.text != "1 / 4":
		failures.append("round label wrong after timeout: " + rl.text)
	if not timer.is_stopped():
		failures.append("timer still running after timeout")

	# The bug: pressing the button after timeout must start a fresh round,
	# not silently resume a stale one.
	sp.emit_signal("pressed")
	await process_frame
	if main.state != 1:
		failures.append("expected RUNNING after post-timeout start")
	# A fresh round means nearly the full wait time, not a stale remainder.
	if timer.time_left < main.work_seconds - 2.0:
		failures.append("post-timeout start did not reset the round: " + str(timer.time_left))

	# Complete -> IDLE, round 2
	main._on_complete_pressed()
	await process_frame
	if rl.text != "2 / 4":
		failures.append("round label wrong after complete: " + rl.text)
	if main.state != 0:
		failures.append("expected IDLE after complete")

	# Complete while stopped must be a no-op
	main._on_complete_pressed()
	await process_frame
	if rl.text != "2 / 4":
		failures.append("complete worked while stopped: " + rl.text)

	# Drive to FINISHED
	sp.emit_signal("pressed")
	main._on_complete_pressed()
	sp.emit_signal("pressed")
	main._on_complete_pressed()
	sp.emit_signal("pressed")
	main._on_complete_pressed()
	await process_frame
	if main.state != 3:
		failures.append("expected FINISHED, got " + str(main.state))
	if rl.text != "DONE":
		failures.append("round label not DONE: " + rl.text)

	# Start from FINISHED must clear the counter
	sp.emit_signal("pressed")
	await process_frame
	if rl.text != "0 / 4":
		failures.append("counter not cleared on new session: " + rl.text)
	if main.state != 1:
		failures.append("expected RUNNING after restart")

	# Reset
	main._on_reset_pressed()
	await process_frame
	if main.state != 0:
		failures.append("expected IDLE after reset")
	if sp.text != "Start":
		failures.append("button text not 'Start' after reset")
	if not timer.is_stopped():
		failures.append("timer not stopped after reset")

	# Timer color thresholds, derived from remaining time
	var color_for := func(ratio: float) -> Color:
		return Color("#e6e8f0") if ratio > 0.25 else (Color("#e8b04b") if ratio > 0.1 else Color("#e05c5c"))

	var got_full: Color = main._color_for_ratio(1.0)
	if got_full != Color(0.901961, 0.909804, 0.941176, 1):
		failures.append("timer not idle color when full: " + str(got_full))
	var got_warn: Color = main._color_for_ratio(0.2)
	if got_warn != Color(0.909804, 0.690196, 0.294118, 1):
		failures.append("timer not warning color at 20%: " + str(got_warn))
	var got_urgent: Color = main._color_for_ratio(0.05)
	if got_urgent != Color(0.878431, 0.360784, 0.360784, 1):
		failures.append("timer not urgent color at 5%: " + str(got_urgent))

	main.state = 0
	if main._timer_color() != main.TIMER_IDLE:
		failures.append("timer should be idle color when not running")

	main.queue_free()
	await process_frame

	if failures.is_empty():
		print("ALL CHECKS PASSED")
		quit(0)
	else:
		for f in failures:
			print("FAIL: " + f)
		quit(1)
