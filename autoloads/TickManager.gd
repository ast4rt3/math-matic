# autoloads/TickManager.gd
extends Node

signal ticked  # everything listens to this

var tick_interval: float = 1.0  # seconds per tick

func _ready():
	var timer = Timer.new()
	timer.wait_time = tick_interval
	timer.autostart = true
	timer.timeout.connect(_on_tick)
	add_child(timer)

func _on_tick():
	emit_signal("ticked")
