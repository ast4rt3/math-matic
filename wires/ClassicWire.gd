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
		var time = Time.get_ticks_msec() / 1000.0
		var phase = (tile.x * dir.x + tile.y * dir.y) * 1.5 - time * 10.0
		var flash = max(0.0, sin(phase))
		var flash_color = system.wire_color.lerp(Color.WHITE, flash * 0.7)
		
		var p0 = center - Vector2(in_dir) * 8.0
		var p1 = center
		var p2 = center + Vector2(dir) * 8.0
		var pts = system.get_bezier_points(p0, p1, p2, 8)
		system.draw_polyline(pts, system.outline_color, system.outline_width, true)
		system.draw_polyline(pts, flash_color, system.wire_width, true)
		
		if flash > 0.01:
			var arr_color = Color(1.0, 1.0, 1.0, flash)
			var arrow_pos = p0 * 0.25 + p1 * 0.5 + p2 * 0.25
			var angle = (p2 - p0).angle()
			system.draw_set_transform(arrow_pos, angle, Vector2(1,1))
			var ts = system.arrow_tex.get_size()
			# Scale arrow down if it's large, assuming we want it to fit ~16x16
			var scale_factor = min(16.0 / ts.x, 16.0 / ts.y)
			var render_size = ts * scale_factor
			system.draw_texture_rect(system.arrow_tex, Rect2(-render_size/2, render_size), false, arr_color)
			system.draw_set_transform(Vector2.ZERO, 0, Vector2(1,1))

func interpolate_items():
	if item != null and is_instance_valid(item.visual):
		var in_dir = item.get("move_dir", dir)
		if in_dir == Vector2i.ZERO:
			in_dir = dir
			
		var center = system.wire_tile_to_pos(tile)
		var p0 = center - Vector2(in_dir) * 8.0
		var p1 = center
		var p2 = center + Vector2(dir) * 8.0
		var frac = item.progress / 16.0
		
		# Quadratic bezier interpolation
		var q0 = p0.lerp(p1, frac)
		var q1 = p1.lerp(p2, frac)
		item.visual.global_position = q0.lerp(q1, frac)

func on_remove():
	if item != null and is_instance_valid(item.visual):
		item.visual.queue_free()
