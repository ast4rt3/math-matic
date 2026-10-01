extends Control

func _ready():
	for btn in $CenterContainer/VBoxContainer/GridContainer.get_children():
		if btn is Button:
			btn.pivot_offset = btn.custom_minimum_size / 2.0
			btn.mouse_entered.connect(_on_btn_hover.bind(btn))
			btn.mouse_exited.connect(_on_btn_unhover.bind(btn))
			btn.button_down.connect(_on_btn_down.bind(btn))
			btn.button_up.connect(_on_btn_up.bind(btn))

func _on_btn_hover(btn: Button):
	var tween = create_tween().set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
	tween.tween_property(btn, "scale", Vector2(1.1, 1.1), 0.3)

func _on_btn_unhover(btn: Button):
	var tween = create_tween().set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
	tween.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.3)

func _on_btn_down(btn: Button):
	var tween = create_tween().set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
	tween.tween_property(btn, "scale", Vector2(0.9, 0.9), 0.1)

func _on_btn_up(btn: Button):
	var tween = create_tween().set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
	tween.tween_property(btn, "scale", Vector2(1.1, 1.1) if btn.is_hovered() else Vector2(1.0, 1.0), 0.3)

func _on_sandbox_pressed():
	get_tree().change_scene_to_file("res://world.tscn")

func _on_exit_pressed():
	get_tree().quit()
