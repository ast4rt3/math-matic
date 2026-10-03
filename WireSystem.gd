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

var arrow_tex = preload("res://asset/wireArrow.png")
var arrow_render_size: Vector2

var item_visual_pool: Array[Node2D] = []
var active_wires = {}
var grid_version: int = 0

@export var grid_system: Node

func get_item_visual(val) -> Node2D:
	var container: Node2D
	var lbl: Label
	if item_visual_pool.size() > 0:
		container = item_visual_pool.pop_back()
		container.show()
		lbl = container.get_child(1) as Label
	else:
		container = Node2D.new()
		container.z_index = 20
		var bg = Sprite2D.new()
		bg.texture = preload("res://asset/itemContainer.png")
		container.add_child(bg)
		lbl = Label.new()
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.position = Vector2(-16, -16)
		lbl.size = Vector2(32, 32)
		container.add_child(lbl)
		get_parent().add_child(container)
	
	lbl.text = str(int(val)) if val == round(val) else str(val)
	return container

func recycle_item_visual(vis: Node2D):
	if is_instance_valid(vis) and not item_visual_pool.has(vis):
		vis.hide()
		item_visual_pool.append(vis)

func notify_grid_changed(t: Vector2i):
	if wire_grid.has(t):
		wire_grid[t].trigger_cache_update()
	for dir in WIRE_DIRS:
		var neighbor = t + dir
		if wire_grid.has(neighbor):
			wire_grid[neighbor].trigger_cache_update()

func _ready():
	z_index = 1
	var ts = arrow_tex.get_size()
	var scale_factor = min(16.0 / ts.x, 16.0 / ts.y)
	arrow_render_size = ts * scale_factor

func _process(delta):
	queue_redraw()

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
	var camera = get_viewport().get_camera_2d()
	var on_screen = []
	if camera:
		var vp_size = get_viewport_rect().size / camera.zoom
		var center_pos = camera.get_screen_center_position()
		
		var min_pos = center_pos - vp_size / 2.0 - Vector2(32, 32)
		var max_pos = center_pos + vp_size / 2.0 + Vector2(64, 64)
		var view_rect = Rect2(min_pos, max_pos - min_pos)
		
		for t in wire_grid:
			var center = Vector2(t.x * 16.0 + 8.0, t.y * 16.0 + 8.0)
			if view_rect.has_point(center):
				on_screen.append(t)
	else:
		on_screen = wire_grid.keys()
		
	# Draw outlines first (batched)
	for t in on_screen:
		wire_grid[t].draw_outline(wire_tile_to_pos(t))
		
	# Draw wire fill colors (batched)
	for t in on_screen:
		wire_grid[t].draw_wire(wire_tile_to_pos(t))
		
	# Draw arrows last
	for t in on_screen:
		wire_grid[t].draw_arrow(wire_tile_to_pos(t))
		
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
				draw_multiline(pts, c_outline, outline_width)
				draw_multiline(pts, c_wire, wire_width)

func get_bezier_points(p0: Vector2, p1: Vector2, p2: Vector2, segments: int) -> PackedVector2Array:
	var pts = PackedVector2Array()
	var prev_pt = p0.lerp(p1, 0.0).lerp(p1.lerp(p2, 0.0), 0.0)
	for i in range(1, segments + 1):
		var t = float(i) / float(segments)
		var q0 = p0.lerp(p1, t)
		var q1 = p1.lerp(p2, t)
		var current_pt = q0.lerp(q1, t)
		pts.append(prev_pt)
		pts.append(current_pt)
		prev_pt = current_pt
	return pts

func process_items(delta: float, game_speed: float):
	var speed = 1500.0 * game_speed
	
	for t in active_wires.keys():
		if wire_grid.has(t):
			wire_grid[t].update_progress(delta, speed)
				
	var moved_any = true
	var max_cascades = 16
	while moved_any and max_cascades > 0:
		moved_any = false
		max_cascades -= 1
		for t in active_wires.keys():
			if wire_grid.has(t):
				moved_any = wire_grid[t].push_items(moved_any)
			
	for t in active_wires.keys():
		if wire_grid.has(t):
			wire_grid[t].interpolate_items()
