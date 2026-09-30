extends PanelContainer

@onready var check: CheckBox = $margin/content/check
@onready var label: Label = $margin/content/label

signal completed(row: PanelContainer)

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

func setup(task_name: String) -> void:
	label.text = task_name

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

	completed.emit(self)
