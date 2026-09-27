extends Node2D

var input_queue: Array = []
var output_value = null
var output_ready: bool = false

@onready var value_label = Label.new()

func _ready():
	value_label.text = ""
	value_label.add_theme_font_size_override("font_size", 14)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	value_label.position = Vector2(-32, -32)
	value_label.size = Vector2(64, 64)
	value_label.z_index = 20
	add_child(value_label)

func receive(val: float):
	input_queue.append(val)
	_update_label()

func _process(delta: float):
	if not output_ready and input_queue.size() >= 2:
		var a = input_queue.pop_front()
		var b = input_queue.pop_front()
		output_value = a + b
		output_ready = true
		_update_label()

func can_receive() -> bool:
	return input_queue.size() < 10

func can_output() -> bool:
	return output_ready

func consume_output():
	output_ready = false
	output_value = null
	_update_label()

func _update_label():
	if output_ready:
		value_label.text = str(int(output_value)) if output_value == round(output_value) else str(output_value)
	elif input_queue.size() == 1:
		var v = input_queue[0]
		var s = str(int(v)) if v == round(v) else str(v)
		value_label.text = s + " + ?"
	else:
		value_label.text = ""
