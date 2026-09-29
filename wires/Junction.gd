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
						if is_instance_valid(itm.visual): itm.visual.queue_free()
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
		
	return moved_any or locally_moved

func draw(center: Vector2):
	system.draw_rect(Rect2(center - Vector2(8, 8), Vector2(16, 16)), system.outline_color)
	system.draw_rect(Rect2(center - Vector2(6, 6), Vector2(12, 12)), system.wire_color)

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
			itm.visual.queue_free()
