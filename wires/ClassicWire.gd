extends WireBase
class_name ClassicWire

var dir: Vector2i = Vector2i.ZERO
var item = null

func get_type() -> String:
	return "wire"

func update_progress(delta: float, speed: float):
	if item != null:
		item.progress += speed * delta
		if item.progress > 16.0: item.progress = 16.0

func accept_item(itm: Dictionary, from_dir: Vector2i) -> bool:
	if item == null:
		item = itm
		item.progress = 0.0
		item.move_dir = from_dir
		return true
	return false

func push_items(moved_any: bool) -> bool:
	if item != null and item.progress >= 16.0:
		var next_t = tile + dir
		var b = system.get_building_at(next_t)
		if b != null:
			var can_receive = true
			if b.has_method("can_receive"):
				can_receive = b.can_receive(tile)
			if can_receive:
				if b.has_method("receive"): b.receive(item.value, tile)
				if is_instance_valid(item.visual): item.visual.queue_free()
				item = null
				return true
		else:
			if system.wire_grid.has(next_t):
				var next_w = system.wire_grid[next_t]
				if next_w.accept_item(item, dir):
					item = null
					return true
	return moved_any
	
func draw(center: Vector2):
	var in_dir = dir
	for test_dir in system.WIRE_DIRS:
		var neighbor = tile - test_dir
		if system.wire_grid.has(neighbor):
			var nw = system.wire_grid[neighbor]
			if (nw.get_type() == "wire" and nw.dir == test_dir) or (nw.get_type() == "junction" and test_dir in nw.dirs):
				in_dir = test_dir
				break
				
	if system.debug_mode:
		system.draw_rect(Rect2(center - Vector2(4, 4), Vector2(8, 8)), Color(0.2, 0.9, 1.0))
		system.draw_line(center, center + Vector2(dir) * 8.0, Color(1, 1, 1), 2.0)
	else:
		var p0 = center - Vector2(in_dir) * 8.0
		var p1 = center
		var p2 = center + Vector2(dir) * 8.0
		var pts = system.get_bezier_points(p0, p1, p2, 8)
		system.draw_polyline(pts, system.outline_color, system.outline_width, true)
		system.draw_polyline(pts, system.wire_color, system.wire_width, true)

func interpolate_items():
	if item != null and is_instance_valid(item.visual):
		var center = system.wire_tile_to_pos(tile)
		var start = center - Vector2(dir) * 8.0
		var end = center + Vector2(dir) * 8.0
		var frac = item.progress / 16.0
		item.visual.global_position = start.lerp(end, frac)

func on_remove():
	if item != null and is_instance_valid(item.visual):
		item.visual.queue_free()
