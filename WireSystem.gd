extends Node2D
class_name WireSystem

var wire_grid: Dictionary = {}
var preview_points: Array[Vector2i] = []
var debug_mode: bool = false
var current_wire_dir_index: int = 0

var grid_system # Reference to GridSystem
var miner_round_robin: Dictionary = {}

const WIRE_DIRS = [
	Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)
]

func _get_bezier_points(p0: Vector2, p1: Vector2, p2: Vector2, segments: int = 8) -> PackedVector2Array:
	var points = PackedVector2Array()
	for i in range(segments + 1):
		var t = float(i) / segments
		var q0 = p0.lerp(p1, t)
		var q1 = p1.lerp(p2, t)
		points.append(q0.lerp(q1, t))
	return points

func pos_to_wire_tile(pos: Vector2) -> Vector2i:
	return Vector2i(floor(pos.x / 16.0), floor(pos.y / 16.0))

func wire_tile_to_pos(tile: Vector2i) -> Vector2:
	return Vector2(tile.x * 16.0 + 8.0, tile.y * 16.0 + 8.0)

func snap_to_grid(pos: Vector2) -> Vector2:
	var tile_size = 16
	return Vector2(
		floor(pos.x / tile_size) * tile_size + tile_size / 2,
		floor(pos.y / tile_size) * tile_size + tile_size / 2
	)

func _draw():
	var wire_color = Color(0.3, 0.8, 1.0)
	var outline_color = Color(0.1, 0.1, 0.15)
	var wire_width = 4.0
	var outline_width = 8.0
	
	# Draw placed wires
	for t in wire_grid:
		var w = wire_grid[t]
		var center = wire_tile_to_pos(t)
		var is_junc = w.get("type", "wire") == "junction"
		
		if is_junc:
			if debug_mode:
				draw_rect(Rect2(center - Vector2(4, 4), Vector2(8, 8)), Color(0.9, 0.9, 0.2))
				for d in w.dirs:
					draw_line(center, center + Vector2(d) * 8.0, Color(1, 1, 1), 2.0)
			else:
				# Draw a 16x16 square for the junction
				draw_rect(Rect2(center - Vector2(8, 8), Vector2(16, 16)), outline_color)
				draw_rect(Rect2(center - Vector2(6, 6), Vector2(12, 12)), wire_color)
		else:
			var d = w.dir
			var in_dir = d
			for test_dir in WIRE_DIRS:
				var neighbor = t - test_dir
				if wire_grid.has(neighbor):
					var nw = wire_grid[neighbor]
					if (nw.get("type", "wire") == "wire" and nw.dir == test_dir) or (nw.get("type", "wire") == "junction" and test_dir in nw.dirs):
						in_dir = test_dir
						break
					
			if debug_mode:
				draw_rect(Rect2(center - Vector2(4, 4), Vector2(8, 8)), Color(0.2, 0.9, 1.0))
				draw_line(center, center + Vector2(d) * 8.0, Color(1, 1, 1), 2.0)
			else:
				var p0 = center - Vector2(in_dir) * 8.0
				var p1 = center
				var p2 = center + Vector2(d) * 8.0
				var pts = _get_bezier_points(p0, p1, p2, 8)
				draw_polyline(pts, outline_color, outline_width, true)
				draw_polyline(pts, wire_color, wire_width, true)
		
	# Draw preview
	if preview_points.size() > 0:
		for i in range(preview_points.size()):
			var p = preview_points[i]
			var center = wire_tile_to_pos(p)
			var cell = grid_system.pos_to_cell(center)
			
			var out_dir = WIRE_DIRS[current_wire_dir_index]
			if preview_points.size() > 1:
				if i < preview_points.size() - 1:
					out_dir = preview_points[i+1] - p
				elif i > 0:
					out_dir = p - preview_points[i-1]
					
			var in_dir = out_dir
			if i > 0:
				in_dir = p - preview_points[i-1]
				
			var is_blocked = false
			if grid_system.grid_data.has(cell) and grid_system.grid_data[cell].get("is_building", true):
				is_blocked = true
				
			if debug_mode:
				var c = Color(1.0, 0.0, 0.0, 0.5) if is_blocked else Color(0.2, 0.9, 1.0, 0.5)
				draw_rect(Rect2(center - Vector2(4, 4), Vector2(8, 8)), c)
				draw_line(center, center + Vector2(out_dir) * 8.0, Color(1, 1, 1, 0.5), 2.0)
			else:
				var c_wire = Color(1.0, 0.2, 0.2, 0.7) if is_blocked else Color(0.3, 0.8, 1.0, 0.7)
				var c_outline = Color(0.1, 0.0, 0.0, 0.5) if is_blocked else Color(0.1, 0.1, 0.15, 0.7)
				
				var p0 = center - Vector2(in_dir) * 8.0
				var p1 = center
				var p2 = center + Vector2(out_dir) * 8.0
				var pts = _get_bezier_points(p0, p1, p2, 8)
				
				draw_polyline(pts, c_outline, outline_width, true)
				draw_polyline(pts, c_wire, wire_width, true)

func tick_items(nodes: Array[Node], current_tick: int):
	# Pass 1: Generate items from Miners or Adders into adjacent wires
	for child in nodes:
		if child.has_node("OutputPort") and child.name != "Core":
			var is_miner = not child.has_method("can_receive")
			
			var ticks_per_gen = child.get("ticks_per_generation")
			if ticks_per_gen == null:
				ticks_per_gen = 5 if is_miner else 2 # Default: Miner=5 ticks (0.5s), Adder=2 ticks (0.2s)
				
			if current_tick % ticks_per_gen != 0:
				continue
			
			if child.has_method("can_output") and not child.can_output(): continue
			var size = 32 if is_miner else 64
			var top_left = child.global_position - Vector2(size/2, size/2)
			var wire_tiles = size / 16
			
			var output_tiles = []
			for x in [-1, wire_tiles]:
				for y in range(wire_tiles):
					output_tiles.append(pos_to_wire_tile(top_left + Vector2(x * 16 + 8, y * 16 + 8)))
			for y in [-1, wire_tiles]:
				for x in range(wire_tiles):
					output_tiles.append(pos_to_wire_tile(top_left + Vector2(x * 16 + 8, y * 16 + 8)))
					
			var valid_outputs = []
			for t in output_tiles:
				if wire_grid.has(t):
					var w = wire_grid[t]
					var is_junc = w.get("type", "wire") == "junction"
					var next_t = t + (w.dirs[0] if is_junc and w.dirs.size() > 0 else w.get("dir", Vector2i.ZERO))
					var next_pos = wire_tile_to_pos(next_t)
					var next_cell = grid_system.pos_to_cell(next_pos)
					
					var points_into_me = false
					if grid_system.grid_data.has(next_cell) and grid_system.grid_data[next_cell].ref == child:
						points_into_me = true
						
					if not points_into_me:
						valid_outputs.append(t)
					
			if valid_outputs.size() > 0:
				if not miner_round_robin.has(child):
					miner_round_robin[child] = 0
				
				var start_idx = miner_round_robin[child]
				for i in range(valid_outputs.size()):
					var idx = (start_idx + i) % valid_outputs.size()
					var t = valid_outputs[idx]
					
					if wire_grid[t].item == null:
						var val = 1.0
						if "output_value" in child: val = child.output_value
						if child.has_method("consume_output"): child.consume_output()
						
						var container = Node2D.new()
						container.z_index = 20
						var bg = Sprite2D.new()
						bg.texture = preload("res://asset/itemContainer.png")
						container.add_child(bg)
						var lbl = Label.new()
						lbl.text = str(int(val)) if val == round(val) else str(val)
						lbl.add_theme_font_size_override("font_size", 12)
						lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
						lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
						lbl.position = Vector2(-16, -16)
						lbl.size = Vector2(32, 32)
						container.add_child(lbl)
						
						get_parent().add_child(container)
						var mdir = wire_grid[t].dirs[0] if wire_grid[t].get("type", "wire") == "junction" and wire_grid[t].dirs.size() > 0 else wire_grid[t].get("dir", Vector2i.ZERO)
						wire_grid[t].item = { "value": val, "progress": 0.0, "visual": container, "move_dir": mdir }
						
						miner_round_robin[child] = (idx + 1) % valid_outputs.size()
						break

func process_items(delta: float, game_speed: float):
	var speed = 300.0 * game_speed
	
	for t in wire_grid:
		var w = wire_grid[t]
		if w.get("type", "wire") == "junction":
			for itm in w.get("items", []):
				itm.progress += speed * delta
				if itm.progress > 16.0: itm.progress = 16.0
		else:
			if w.get("item") != null:
				w.item.progress += speed * delta
				if w.item.progress > 16.0: w.item.progress = 16.0
				
	var moved_any = true
	var max_cascades = 16
	while moved_any and max_cascades > 0:
		moved_any = false
		max_cascades -= 1
		for t in wire_grid:
			var w = wire_grid[t]
			var is_junc = w.get("type", "wire") == "junction"
			
			var items_to_process = []
			if is_junc:
				items_to_process = w.get("items", [])
			elif w.get("item") != null:
				items_to_process = [w.item]
				
			var items_to_remove = []
			for itm_idx in range(items_to_process.size()):
				var itm = items_to_process[itm_idx]
				if itm.progress >= 16.0:
					var dirs_to_try = []
					var start_idx = 0
					
					if is_junc:
						var mdir = itm.get("move_dir", Vector2i.ZERO)
						if mdir != Vector2i.ZERO and mdir in w.dirs:
							dirs_to_try = [mdir]
						elif w.dirs.size() > 0:
							start_idx = w.get("rr_idx", 0)
							dirs_to_try = w.dirs
					else:
						dirs_to_try = [w.dir]
						
					var item_moved = false
					for i in range(dirs_to_try.size()):
						var idx = (start_idx + i) % dirs_to_try.size()
						var try_dir = dirs_to_try[idx]
						var next_t = t + try_dir
						
						var hit_building = false
						var world_pos = wire_tile_to_pos(next_t)
						var cell_4x4 = grid_system.pos_to_cell(world_pos)
						
						if grid_system.grid_data.has(cell_4x4):
							var b = grid_system.grid_data[cell_4x4]
							if b.type == "core" or b.type == "miner" or b.type == "adder" or b.type == "turret":
								var can_receive = true
								if b.ref.has_method("can_receive"):
									can_receive = b.ref.can_receive(t)
									
								if can_receive:
									hit_building = true
									if b.ref.has_method("receive"):
										b.ref.receive(itm.value, t)
									if is_instance_valid(itm.visual): itm.visual.queue_free()
									items_to_remove.append(itm)
									item_moved = true
									moved_any = true
									if is_junc and dirs_to_try.size() > 1: w.rr_idx = (idx + 1) % dirs_to_try.size()
									break
								else:
									hit_building = true
									
						if not hit_building and wire_grid.has(next_t):
							var next_w = wire_grid[next_t]
							var next_is_junc = next_w.get("type", "wire") == "junction"
							var can_enter = false
							
							if next_is_junc:
								var items_in_dir = 0
								for j_itm in next_w.get("items", []):
									if j_itm.get("move_dir") == try_dir:
										items_in_dir += 1
								if items_in_dir < 1:
									can_enter = true
							else:
								if next_w.get("item") == null:
									can_enter = true
									
							if can_enter:
								itm.progress = 0.0
								itm.move_dir = try_dir
								if next_is_junc:
									if not next_w.has("items"): next_w["items"] = []
									next_w.items.append(itm)
								else:
									next_w.item = itm
								items_to_remove.append(itm)
								item_moved = true
								moved_any = true
								if is_junc and dirs_to_try.size() > 1: w.rr_idx = (idx + 1) % dirs_to_try.size()
								break
								
					if item_moved and not is_junc:
						break
						
			if is_junc:
				for rem in items_to_remove:
					w.items.erase(rem)
			elif items_to_remove.size() > 0:
				w.item = null
						
	for t in wire_grid:
		var w = wire_grid[t]
		var is_junc = w.get("type", "wire") == "junction"
		
		var items_to_anim = []
		if is_junc:
			items_to_anim = w.get("items", [])
		elif w.get("item") != null:
			items_to_anim = [w.item]
			
		var center = wire_tile_to_pos(t)
		for itm in items_to_anim:
			if is_instance_valid(itm.visual):
				var anim_dir = itm.get("move_dir", Vector2i.ZERO) if is_junc else w.dir
				if anim_dir == Vector2i.ZERO: anim_dir = Vector2i(1, 0)
				var start = center - Vector2(anim_dir) * 8.0
				var end = center + Vector2(anim_dir) * 8.0
				var frac = itm.progress / 16.0
				itm.visual.global_position = start.lerp(end, frac)
