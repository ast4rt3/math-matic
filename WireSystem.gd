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
		var center = wire_tile_to_pos(t)
		var d = wire_grid[t].dir
		
		var in_dir = d
		for test_dir in WIRE_DIRS:
			var neighbor = t - test_dir
			if wire_grid.has(neighbor) and wire_grid[neighbor].dir == test_dir:
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
			if grid_system.grid_data.has(cell) and (grid_system.grid_data[cell].type == "core" or grid_system.grid_data[cell].type == "miner" or grid_system.grid_data[cell].type == "adder"):
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

func tick_items(nodes: Array[Node]):
	# Pass 1: Generate items from Miners into adjacent wires
	for child in nodes:
		if child.has_node("OutputPort") and child.name != "Core":
			if child.has_method("can_output") and not child.can_output(): continue
			var is_miner = not child.has_method("can_receive")
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
					var next_t = t + w.dir
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
						wire_grid[t].item = { "value": val, "progress": 0.0, "visual": container }
						
						miner_round_robin[child] = (idx + 1) % valid_outputs.size()
						break

func process_items(delta: float):
	var speed = 64.0
	
	for t in wire_grid:
		var w = wire_grid[t]
		if w.item != null:
			w.item.progress += speed * delta
			if w.item.progress > 16.0:
				w.item.progress = 16.0
				
	var moved_any = true
	var max_cascades = 16
	while moved_any and max_cascades > 0:
		moved_any = false
		max_cascades -= 1
		for t in wire_grid:
			var w = wire_grid[t]
			if w.item != null and w.item.progress >= 16.0:
				var next_t = t + w.dir
				
				var hit_building = false
				var world_pos = wire_tile_to_pos(next_t)
				var cell_4x4 = grid_system.pos_to_cell(world_pos)
				
				if grid_system.grid_data.has(cell_4x4):
					var b = grid_system.grid_data[cell_4x4]
					if b.type == "core" or b.type == "miner" or b.type == "adder":
						var can_receive = true
						if b.ref.has_method("can_receive"):
							can_receive = b.ref.can_receive(t)
							
						if can_receive:
							hit_building = true
							if b.ref.has_method("receive"):
								b.ref.receive(w.item.value, t)
							if is_instance_valid(w.item.visual): w.item.visual.queue_free()
							w.item = null
							moved_any = true
						else:
							hit_building = true
						
				if not hit_building and wire_grid.has(next_t):
					var next_w = wire_grid[next_t]
					if next_w.item == null:
						next_w.item = w.item
						next_w.item.progress = 0.0
						w.item = null
						moved_any = true
						
	for t in wire_grid:
		var w = wire_grid[t]
		if w.item != null and is_instance_valid(w.item.visual):
			var start = wire_tile_to_pos(t) - Vector2(w.dir) * 8.0
			var end = wire_tile_to_pos(t) + Vector2(w.dir) * 8.0
			var frac = w.item.progress / 16.0
			w.item.visual.global_position = start.lerp(end, frac)
