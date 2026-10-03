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

func process_items(delta: float, game_speed: float):
	var speed = 1500.0 * game_speed
	
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
