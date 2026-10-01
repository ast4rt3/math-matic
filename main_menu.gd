extends Control

func _on_sandbox_pressed():
	get_tree().change_scene_to_file("res://world.tscn")

func _on_exit_pressed():
	get_tree().quit()
