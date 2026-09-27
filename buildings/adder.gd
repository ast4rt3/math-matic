extends Node2D

var pending_inputs: Dictionary = {} # Vector2i -> float
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

func receive(val: float, source: Vector2i):
	pending_inputs[source] = val
	_update_label()

func _process(delta: float):
	if not output_ready and pending_inputs.size() >= 2:
		var keys = pending_inputs.keys()
		var a = pending_inputs[keys[0]]
		var b = pending_inputs[keys[1]]
		pending_inputs.erase(keys[0])
		pending_inputs.erase(keys[1])
		output_value = a + b
		output_ready = true
		_update_label()

func can_receive(source: Vector2i) -> bool:
	if output_ready: return false
	if pending_inputs.has(source): return false
	if pending_inputs.size() >= 2: return false
	return true

func can_output() -> bool:
	return output_ready

func consume_output():
	output_ready = false
	output_value = null
	_update_label()

func _update_label():
	if output_ready:
		value_label.text = str(int(output_value)) if output_value == round(output_value) else str(output_value)
	elif pending_inputs.size() == 1:
		var keys = pending_inputs.keys()
		var v = pending_inputs[keys[0]]
		var s = str(int(v)) if v == round(v) else str(v)
		value_label.text = s + " + ?"
	else:
		value_label.text = ""
