extends PanelContainer

@onready var check: CheckBox = $margin/top/check
@onready var label: Label = $margin/top/label
@onready var tags_row: HBoxContainer = $margin/top/tags

signal completed(row: PanelContainer, data: TaskData)

var data: TaskData
var _done := false
var _card_style: StyleBox
var _hover_style: StyleBox

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_card_style = get_theme_stylebox("panel", &"TaskCard")
	_hover_style = get_theme_stylebox("panel", &"TaskCardHover")

	check.toggled.connect(_on_check_toggled)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func setup(task_data: TaskData) -> void:
	data = task_data
	label.text = task_data.title
	_build_tags(task_data.tags)

func _build_tags(tags: PackedStringArray) -> void:
	for child in tags_row.get_children():
		tags_row.remove_child(child)
		child.queue_free()

	tags_row.visible = not tags.is_empty()

	for tag in tags:
		var chip := Label.new()
		chip.text = tag
		chip.theme_type_variation = &"TagChip"
		chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tags_row.add_child(chip)

func _on_mouse_entered() -> void:
	if not _done:
		add_theme_stylebox_override("panel", _hover_style)

func _on_mouse_exited() -> void:
	if not _done:
		add_theme_stylebox_override("panel", _card_style)

func _on_check_toggled(is_checked: bool) -> void:
	if not is_checked or _done:
		return

	_done = true
	check.disabled = true
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	add_theme_stylebox_override("panel", _card_style)

	label.add_theme_color_override("font_color", Color(0.443137, 0.443137, 0.521569, 1))
	tags_row.modulate = Color(0.6, 0.6, 0.6, 0.6)

	completed.emit(self, data)
