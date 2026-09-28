extends Node2D

var speed: float = 400.0
var damage: float = 1.0

func _process(delta: float):
	position += Vector2.RIGHT.rotated(rotation) * speed * delta
	
	# Clean up after traveling a distance
	if position.length() > 3000:
		queue_free()

func _on_area_2d_area_entered(area: Area2D):
	if area.get_parent().is_in_group("enemies"):
		if area.get_parent().has_method("take_damage"):
			area.get_parent().take_damage(damage)
		queue_free()
