extends WireBase
class_name Junction

var dirs: Array[Vector2i] = []
var items: Array = []
var rr_idx: int = 0

func get_type() -> String:
	return "junction"

func update_progress(delta: float, speed: float):
	for itm in items:
		itm.progress += speed * delta
		if itm.progress > 16.0: itm.progress = 16.0

func accept_item(itm: Dictionary, from_dir: Vector2i) -> bool:
	var items_in_dir = 0
	for j_itm in items:
		if j_itm.get("move_dir") == from_dir:
			items_in_dir += 1
	if items_in_dir < 1:
		itm.progress = 0.0
		itm.move_dir = from_dir
		items.append(itm)
		system.active_wires[tile] = true
		return true
	return false

func push_items(moved_any: bool) -> bool:
	var items_to_remove = []
	var locally_moved = false
	
	for itm_idx in range(items.size()):
		var itm = items[itm_idx]
		if itm.progress >= 16.0:
			var dirs_to_try = []
			var start_idx = 0
			var mdir = itm.get("move_dir", Vector2i.ZERO)
			
			if mdir != Vector2i.ZERO and mdir in dirs:
				dirs_to_try = [mdir]
			elif dirs.size() > 0:
				start_idx = rr_idx
				dirs_to_try = dirs
				
			for i in range(dirs_to_try.size()):
				var idx = (start_idx + i) % dirs_to_try.size()
				var try_dir = dirs_to_try[idx]
				var next_t = tile + try_dir
				
				var b = system.get_building_at(next_t)
				if b != null:
					var can_receive = true
					if b.has_method("can_receive"):
						can_receive = b.can_receive(tile)
					if can_receive:
						if b.has_method("receive"): b.receive(itm.value, tile)
						if is_instance_valid(itm.visual): system.recycle_item_visual(itm.visual)
						items_to_remove.append(itm)
						locally_moved = true
						if dirs_to_try.size() > 1: rr_idx = (idx + 1) % dirs_to_try.size()
						break
				else:
					if system.wire_grid.has(next_t):
						var next_w = system.wire_grid[next_t]
						if next_w.accept_item(itm, try_dir):
							items_to_remove.append(itm)
							locally_moved = true
							if dirs_to_try.size() > 1: rr_idx = (idx + 1) % dirs_to_try.size()
							break
	
	for rem in items_to_remove:
		items.erase(rem)
		
	if items.size() == 0:
		system.active_wires.erase(tile)
		
	return moved_any or locally_moved

func draw_outline(center: Vector2):
	system.draw_rect(Rect2(center - Vector2(8, 8), Vector2(16, 16)), system.outline_color)

func draw_wire(center: Vector2):
	var time = Time.get_ticks_msec() / 1000.0
	var d = dirs[0] if dirs.size() > 0 else Vector2i(1, 0)
	var phase = (tile.x * d.x + tile.y * d.y) * 1.5 - time * 10.0
	var flash = max(0.0, sin(phase))
	var flash_color = system.wire_color.lerp(Color.WHITE, flash * 0.7)
	system.draw_rect(Rect2(center - Vector2(6, 6), Vector2(12, 12)), flash_color)
	
func draw_arrow(center: Vector2):
	var time = Time.get_ticks_msec() / 1000.0
	var d = dirs[0] if dirs.size() > 0 else Vector2i(1, 0)
	var phase = (tile.x * d.x + tile.y * d.y) * 1.5 - time * 10.0
	var flash = max(0.0, sin(phase))
	if flash > 0.01:
		var arr_color = Color(1.0, 1.0, 1.0, flash)
		var angle = Vector2(d).angle()
		system.draw_set_transform(center, angle, Vector2(1,1))
		system.draw_texture_rect(system.arrow_tex, Rect2(-system.arrow_render_size/2, system.arrow_render_size), false, arr_color)
		system.draw_set_transform(Vector2.ZERO, 0, Vector2(1,1))

func interpolate_items():
	var center = system.wire_tile_to_pos(tile)
	for itm in items:
		if is_instance_valid(itm.visual):
			var anim_dir = itm.get("move_dir", Vector2i.ZERO)
			if anim_dir == Vector2i.ZERO: anim_dir = Vector2i(1, 0)
			var start = center - Vector2(anim_dir) * 8.0
			var end = center + Vector2(anim_dir) * 8.0
			var frac = itm.progress / 16.0
			itm.visual.global_position = start.lerp(end, frac)

func on_remove():
	for itm in items:
		if is_instance_valid(itm.visual):
			system.recycle_item_visual(itm.visual)
