extends RefCounted
class_name WireBase

var tile: Vector2i
var system

func init(t: Vector2i, sys):
	tile = t
	system = sys

func get_type() -> String:
	return "base"
	
func update_progress(delta: float, speed: float):
	pass
	
func accept_item(itm: Dictionary, from_dir: Vector2i) -> bool:
	return false
	
func push_items(moved_any: bool) -> bool:
	return moved_any
	
func draw(center: Vector2):
	pass

func interpolate_items():
	pass

func on_remove():
	pass
