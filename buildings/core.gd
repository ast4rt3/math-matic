# buildings/Core.gd
extends Node2D

var total: float = 0.0

@onready var label = $CounterLabel

func receive(value: float):
	total += value
	label.text = str(total)
