extends Node2D
class_name WireSystem

const TILE_SIZE = 16
const WIRE_DIRS = [
	Vector2i(0, -1),
	Vector2i(1, -1),
	Vector2i(1, 0),
	Vector2i(1, 1),
	Vector2i(0, 1),
	Vector2i(-1, 1),
	Vector2i(-1, 0),
	Vector2i(-1, -1)
]

var wire_grid = {} # Dictionary of Vector2i -> WireBase
var preview_points = []
var current_wire_dir_index = 2 # Default East

var debug_mode = false
var miner_round_robin = {}

var wire_color = Color(0.3, 0.8, 1.0)
var outline_color = Color(0.1, 0.1, 0.15)
var wire_width = 4.0
var outline_width = 8.0

@export var grid_system: Node

func _ready():
	z_index = 1

func pos_to_wire_tile(pos: Vector2) -> Vector2i:
	return Vector2i(floor(pos.x / 16.0), floor(pos.y / 16.0))
	
func wire_tile_to_pos(tile: Vector2i) -> Vector2:
	return Vector2(tile.x * 16.0 + 8.0, tile.y * 16.0 + 8.0)

func snap_to_grid(pos: Vector2) -> Vector2:
	return Vector2(floor(pos.x / 16.0) * 16.0 + 8.0, floor(pos.y / 16.0) * 16.0 + 8.0)

func get_building_at(next_t: Vector2i):
	var world_pos = wire_tile_to_pos(next_t)
	var cell_4x4 = grid_system.pos_to_cell(world_pos)
	if grid_system.grid_data.has(cell_4x4):
		var b = grid_system.grid_data[cell_4x4]
		if b.type in ["core", "miner", "adder", "turret"]:
			return b.ref
	return null

func _draw():
	# Draw placed wires
	for t in wire_grid:
		wire_grid[t].draw(wire_tile_to_pos(t))
		
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
				var pts = get_bezier_points(p0, p1, p2, 8)
				draw_polyline(pts, c_outline, outline_width, true)
				draw_polyline(pts, c_wire, wire_width, true)

func get_bezier_points(p0: Vector2, p1: Vector2, p2: Vector2, segments: int) -> PackedVector2Array:
	var pts = PackedVector2Array()
	for i in range(segments + 1):
		var t = float(i) / float(segments)
		var q0 = p0.lerp(p1, t)
		var q1 = p1.lerp(p2, t)
		pts.append(q0.lerp(q1, t))
	return pts

func tick_items(nodes: Array[Node], current_tick: int):
	for child in nodes:
		if child.has_node("OutputPort") and child.name != "Core":
			var is_miner = not child.has_method("can_receive")
			var ticks_per_gen = child.get("ticks_per_generation")
			if ticks_per_gen == null:
				ticks_per_gen = 5 if is_miner else 2
				
			if current_tick % ticks_per_gen != 0: continue
			if child.has_method("can_output") and not child.can_output(): continue
			
			var size = 32 if is_miner else 64
			var top_left = child.global_position - Vector2(size/2, size/2)
			var wire_tiles = size / 16
			
			var output_tiles = []
			for x in [-1, wire_tiles]:
				for y in range(wire_tiles): output_tiles.append(pos_to_wire_tile(top_left + Vector2(x * 16 + 8, y * 16 + 8)))
			for y in [-1, wire_tiles]:
				for x in range(wire_tiles): output_tiles.append(pos_to_wire_tile(top_left + Vector2(x * 16 + 8, y * 16 + 8)))
					
			var valid_outputs = []
			for t in output_tiles:
				if wire_grid.has(t):
					var w = wire_grid[t]
					var next_t = t + (w.dirs[0] if w.get_type() == "junction" and w.dirs.size() > 0 else w.dir)
					var points_into_me = false
					var b = get_building_at(next_t)
					if b != null and b == child: points_into_me = true
						
					if not points_into_me: valid_outputs.append(t)
					
			if valid_outputs.size() > 0:
				if not miner_round_robin.has(child): miner_round_robin[child] = 0
				
				var start_idx = miner_round_robin[child]
				for i in range(valid_outputs.size()):
					var idx = (start_idx + i) % valid_outputs.size()
					var t = valid_outputs[idx]
					
					var w = wire_grid[t]
					var mdir = w.dirs[0] if w.get_type() == "junction" and w.dirs.size() > 0 else w.dir
					
					var itm_check = { "value": 0, "progress": 0.0, "visual": null, "move_dir": mdir }
					if w.accept_item(itm_check, mdir):
						var val = 1
						if child.has_method("get_output_value"): val = child.get_output_value()
						
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
						itm_check.value = val
						itm_check.visual = container
						
						miner_round_robin[child] = (idx + 1) % valid_outputs.size()
						break

func process_items(delta: float, game_speed: float):
	var speed = 300.0 * game_speed
	
	for t in wire_grid:
		wire_grid[t].update_progress(delta, speed)
				
	var moved_any = true
	var max_cascades = 16
	while moved_any and max_cascades > 0:
		moved_any = false
		max_cascades -= 1
		for t in wire_grid:
			moved_any = wire_grid[t].push_items(moved_any)
			
	for t in wire_grid:
		wire_grid[t].interpolate_items()
