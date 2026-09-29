# buildings/Core.gd
extends Node2D

var currency: Dictionary = { 1.0: 50 }

@onready var label = $CounterLabel

func _ready():
	update_label()

func receive(value: float, source: Vector2i):
	if currency.has(value):
		currency[value] += 1
	else:
		currency[value] = 1
	update_label()

func spend(value: float, amount: int) -> bool:
	if currency.get(value, 0) >= amount:
		currency[value] -= amount
		update_label()
		return true
	return false

func update_label():
	var text = ""
	for val in currency.keys():
		var val_str = str(int(val)) if val == int(val) else str(val)
		text += val_str + "'s: " + str(currency[val]) + "\n"
	label.text = text.strip_edges()

func get_currency_text() -> String:
	return label.text
