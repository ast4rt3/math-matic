extends Node2D

@onready var ground_layer: TileMapLayer = $GroundLayer
@onready var core: Node2D = $Core

enum State { IDLE, PLACING_MINE, PLACING_ADDER, DRAWING_WIRE, DELETING }
var current_state: State = State.IDLE
var tick_accumulator: float = 0.0
var tick_rate: float = 0.4 

# 4x4 Grid for Buildings and AStar
var grid_data: Dictionary = {}

var miner_round_robin: Dictionary = {} # Node2D -> int

# 16x16 Grid for Wires
var wire_grid: Dictionary = {} # Vector2i -> { "dir": Vector2i, "item": Dictionary }

var mine_scene = preload("res://buildings/Mine.tscn")
var mine_preview: Sprite2D = null

var adder_scene = preload("res://buildings/Adder.tscn")
var adder_preview: Sprite2D = null

var preview_points: Array[Vector2i] = []
var wire_renderer: Node2D

var wire_texture = preload("res://asset/wiring/tubeH.png")
var tube90_texture = preload("res://asset/wiring/tube90.png")
var tube90flip_texture = preload("res://asset/wiring/tube90flip.png")
var tube45_texture = preload("res://asset/wiring/tube45.png")
var tube45corner_texture = preload("res://asset/wiring/tube45corner.png")
var tube45corner_flip_texture = preload("res://asset/wiring/tube45corner_flip.png")
var current_wire_frame: int = 0
var wire_frame_timer: float = 0.0

var cursor_highlight: Sprite2D
var building_highlight: ReferenceRect
var wire_hover_highlight: ColorRect
var building_hover_highlight: ReferenceRect
var WIRE_DIRS = [
	Vector2i(1, 0),
	Vector2i(1, 1),
	Vector2i(0, 1),
	Vector2i(-1, 1),
	Vector2i(-1, 0),
	Vector2i(-1, -1),
	Vector2i(0, -1),
	Vector2i(1, -1)
]
var current_wire_dir_index: int = 0
var astar = AStarGrid2D.new()

@onready var camera: Camera2D = $Camera2D
var target_zoom: Vector2 = Vector2(1, 1)
var cam_pan_speed: float = 600.0

var limit_left: float = -2000
var limit_top: float = -2000
var limit_right: float = 2000
var limit_bottom: float = 2000

var debug_mode: bool = false

func _ready():
	var bounds_node = get_node_or_null("MapBounds")
	if bounds_node and bounds_node is ReferenceRect:
		limit_left = bounds_node.global_position.x
		limit_top = bounds_node.global_position.y
		limit_right = limit_left + bounds_node.size.x
		limit_bottom = limit_top + bounds_node.size.y
		# Hide it in game since we draw our own cyan border
		bounds_node.visible = false 
	elif ground_layer and ground_layer.tile_set:
		var rect = ground_layer.get_used_rect()
		if rect.size.x > 0 and rect.size.y > 0:
			var tile_size = ground_layer.tile_set.tile_size
			limit_left = rect.position.x * tile_size.x
			limit_top = rect.position.y * tile_size.y
			limit_right = (rect.position.x + rect.size.x) * tile_size.x
			limit_bottom = (rect.position.y + rect.size.y) * tile_size.y
			
	if camera:
		camera.limit_left = int(limit_left)
		camera.limit_top = int(limit_top)
		camera.limit_right = int(limit_right)
		camera.limit_bottom = int(limit_bottom)
		
	wire_renderer = Node2D.new()
	wire_renderer.z_index = 10
	add_child(wire_renderer)
	wire_renderer.draw.connect(_on_wire_renderer_draw)
	
	cursor_highlight = Sprite2D.new()
	cursor_highlight.texture = preload("res://asset/wire.png")
	cursor_highlight.modulate.a = 0.5
	cursor_highlight.z_index = 100
	add_child(cursor_highlight)
	
	building_highlight = ReferenceRect.new()
	building_highlight.border_color = Color(1.0, 1.0, 1.0, 0.5)
	building_highlight.border_width = 2.0
	building_highlight.editor_only = false
	building_highlight.z_index = 99
	var b_bg = ColorRect.new()
	b_bg.color = Color(1.0, 1.0, 1.0, 0.1)
	b_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	building_highlight.add_child(b_bg)
	add_child(building_highlight)
	
	wire_hover_highlight = ColorRect.new()
	wire_hover_highlight.color = Color(1.0, 1.0, 1.0, 0.2)
	wire_hover_highlight.size = Vector2(16, 16)
	wire_hover_highlight.z_index = 100
	add_child(wire_hover_highlight)
	
	building_hover_highlight = ReferenceRect.new()
	building_hover_highlight.border_color = Color(1.0, 1.0, 1.0, 0.8)
	building_hover_highlight.border_width = 2.0
	building_hover_highlight.editor_only = false
	building_hover_highlight.z_index = 100
	add_child(building_hover_highlight)

	if has_node("UI"):
		$UI.offset = Vector2.ZERO
	if has_node("UI/MineButton"):
		$UI/MineButton.pressed.connect(start_placing_mine)
	if has_node("UI/AdderButton"):
		$UI/AdderButton.pressed.connect(start_placing_adder)
	
	astar.region = Rect2i(-1600, -1600, 3200, 3200)
	astar.cell_size = Vector2(4, 4)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	
	grid_data.clear()
	_add_building_to_grid(core, "core")
	for child in get_children():
		if child.has_node("OutputPort") and child.name != "Core":
			_add_building_to_grid(child, "miner")
	_update_astar()

func _add_building_to_grid(building: Node2D, b_type: String):
	var size = 32 if b_type == "miner" else 64
	var top_left = building.global_position - Vector2(size/2, size/2)
	var start_cell = _pos_to_cell(top_left)
	var cells = size / 4
	for x in range(cells):
		for y in range(cells):
			var c = start_cell + Vector2i(x, y)
			grid_data[c] = { "type": b_type, "ref": building }
			
	# Bulldoze any wires underneath the new building
	var wire_tiles = size / 16
	for wx in range(wire_tiles):
		for wy in range(wire_tiles):
			var tile = _pos_to_wire_tile(top_left + Vector2(wx * 16 + 8, wy * 16 + 8))
			if wire_grid.has(tile):
				if wire_grid[tile].item != null and is_instance_valid(wire_grid[tile].item.visual):
					wire_grid[tile].item.visual.queue_free()
				wire_grid.erase(tile)
	
	if wire_renderer:
		wire_renderer.queue_redraw()

var _solid_cells = []
func _update_astar():
	for cell in _solid_cells:
		if astar.is_in_boundsv(cell):
			astar.set_point_solid(cell, false)
	_solid_cells.clear()
	for cell in grid_data:
		if astar.is_in_boundsv(cell):
			astar.set_point_solid(cell, true)
			_solid_cells.append(cell)

func _pos_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(floor(pos.x / 4.0), floor(pos.y / 4.0))

func _pos_to_wire_tile(pos: Vector2) -> Vector2i:
	return Vector2i(floor(pos.x / 16.0), floor(pos.y / 16.0))
	
func _wire_tile_to_pos(tile: Vector2i) -> Vector2:
	return Vector2(tile.x * 16.0 + 8.0, tile.y * 16.0 + 8.0)

func _snap_to_grid(pos: Vector2) -> Vector2:
	var tile_size = 16
	return Vector2(
		floor(pos.x / tile_size) * tile_size + tile_size / 2,
		floor(pos.y / tile_size) * tile_size + tile_size / 2
	)

func _snap_building(pos: Vector2) -> Vector2:
	var tile_size = 16
	return Vector2(
		round(pos.x / tile_size) * tile_size,
		round(pos.y / tile_size) * tile_size
	)

func start_drawing_wire():
	if current_state == State.DRAWING_WIRE:
		current_state = State.IDLE
		preview_points.clear()
		wire_renderer.queue_redraw()
		return
	current_state = State.DRAWING_WIRE
	preview_points.clear()
	if mine_preview:
		mine_preview.queue_free()
		mine_preview = null

func start_placing_mine():
	if current_state == State.PLACING_MINE:
		current_state = State.IDLE
		if mine_preview:
			mine_preview.queue_free()
			mine_preview = null
		return
	current_state = State.PLACING_MINE
	if mine_preview == null:
		mine_preview = Sprite2D.new()
		mine_preview.texture = preload("res://asset/miner32.png")
		mine_preview.modulate.a = 0.5
		add_child(mine_preview)

func start_placing_adder():
	if current_state == State.PLACING_ADDER:
		current_state = State.IDLE
		if adder_preview:
			adder_preview.queue_free()
			adder_preview = null
		return
	current_state = State.PLACING_ADDER
	if adder_preview == null:
		adder_preview = Sprite2D.new()
		adder_preview.texture = preload("res://asset/adder.png")
		adder_preview.modulate.a = 0.5
		add_child(adder_preview)

func _input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			target_zoom *= 1.2
			target_zoom.x = min(target_zoom.x, 3.0)
			target_zoom.y = min(target_zoom.y, 3.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			target_zoom /= 1.2
			target_zoom.x = max(target_zoom.x, 0.2)
			target_zoom.y = max(target_zoom.y, 0.2)
			
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			debug_mode = not debug_mode
			if wire_renderer: wire_renderer.queue_redraw()
		elif event.keycode == KEY_E or event.keycode == KEY_Q:
			var mouse_pos = get_global_mouse_position()
			var tile_pos = _pos_to_wire_tile(mouse_pos)
			
			if wire_grid.has(tile_pos):
				var w_idx = WIRE_DIRS.find(wire_grid[tile_pos].dir)
				if w_idx != -1:
					if event.keycode == KEY_E:
						w_idx = (w_idx + 1) % 8
					else:
						w_idx = (w_idx - 1 + 8) % 8
					wire_grid[tile_pos].dir = WIRE_DIRS[w_idx]
					current_wire_dir_index = w_idx
					if wire_renderer: wire_renderer.queue_redraw()
			else:
				if event.keycode == KEY_E:
					current_wire_dir_index = (current_wire_dir_index + 1) % 8
				elif event.keycode == KEY_Q:
					current_wire_dir_index = (current_wire_dir_index - 1 + 8) % 8
			
	if event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE) and camera:
			camera.position -= event.relative / camera.zoom
			
		if current_state == State.DRAWING_WIRE and preview_points.size() > 0:
			var target_tile = _pos_to_wire_tile(get_global_mouse_position())
			var last_tile = preview_points[-1]
			
			if last_tile != target_tile:
				var t_pos = _wire_tile_to_pos(target_tile)
				if t_pos.x < limit_left or t_pos.y < limit_top or t_pos.x > limit_right or t_pos.y > limit_bottom:
					return
					
				var idx = preview_points.find(target_tile)
				if idx != -1:
					preview_points.resize(idx + 1)
				else:
					var current = last_tile
					var steps = 0
					while current != target_tile and steps < 50:
						steps += 1
						if abs(target_tile.x - current.x) > 0 and abs(target_tile.y - current.y) > 0:
							current.x += sign(target_tile.x - current.x)
							current.y += sign(target_tile.y - current.y)
						elif abs(target_tile.x - current.x) > 0:
							current.x += sign(target_tile.x - current.x)
						else:
							current.y += sign(target_tile.y - current.y)
						if not preview_points.has(current):
							preview_points.append(current)
				wire_renderer.queue_redraw()

	if event is InputEventMouseButton:
		var world_pos = get_global_mouse_position()
		var tile_pos = _pos_to_wire_tile(world_pos)

		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if current_state == State.PLACING_MINE:
				start_placing_mine()
				return
			if current_state == State.PLACING_ADDER:
				start_placing_adder()
				return
			if current_state == State.DRAWING_WIRE:
				start_drawing_wire()
				return
				
			var cell_4x4 = _pos_to_cell(world_pos)
			if grid_data.has(cell_4x4) and (grid_data[cell_4x4].type == "miner" or grid_data[cell_4x4].type == "adder"):
				_delete_building(grid_data[cell_4x4].ref)
				return
				
			if wire_grid.has(tile_pos):
				if wire_grid[tile_pos].item != null and is_instance_valid(wire_grid[tile_pos].item.visual):
					wire_grid[tile_pos].item.visual.queue_free()
				wire_grid.erase(tile_pos)
				wire_renderer.queue_redraw()
				return

		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if current_state == State.PLACING_MINE:
				var snapped_pos = _snap_building(world_pos)
				if _can_place_building(snapped_pos, "miner"):
					_place_mine(snapped_pos)
				return
			if current_state == State.PLACING_ADDER:
				var snapped_pos = _snap_building(world_pos)
				if _can_place_building(snapped_pos, "adder"):
					_place_adder(snapped_pos)
				return
			if current_state == State.IDLE:
				start_drawing_wire()
			if current_state == State.DRAWING_WIRE:
				preview_points = [tile_pos]
				wire_renderer.queue_redraw()

		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			if current_state == State.DRAWING_WIRE and preview_points.size() > 0:
				for i in range(preview_points.size()):
					var p = preview_points[i]
					var center = _wire_tile_to_pos(p)
					var cell = _pos_to_cell(center)
					
					var dir = WIRE_DIRS[current_wire_dir_index]
					if preview_points.size() > 1:
						if i < preview_points.size() - 1:
							dir = preview_points[i+1] - p
						elif i > 0:
							dir = p - preview_points[i-1] # Keep last direction
						
					if grid_data.has(cell) and (grid_data[cell].type == "core" or grid_data[cell].type == "miner" or grid_data[cell].type == "adder"):
						continue # Don't place wires inside buildings!
						
					if not wire_grid.has(p):
						wire_grid[p] = { "dir": dir, "item": null }
					else:
						# Overwrite direction
						wire_grid[p].dir = dir
						
				preview_points.clear()
				wire_renderer.queue_redraw()

func _can_place_building(pos: Vector2, b_type: String) -> bool:
	var size = 32 if b_type == "miner" else 64
	var top_left = pos - Vector2(size/2, size/2)
	
	if top_left.x < limit_left or top_left.y < limit_top or (top_left.x + size) > limit_right or (top_left.y + size) > limit_bottom:
		return false
		
	var start_cell = _pos_to_cell(top_left)
	var cells = size / 4
	for x in range(cells):
		for y in range(cells):
			var c = start_cell + Vector2i(x, y)
			if grid_data.has(c):
				return false
	return true

func _place_mine(world_pos: Vector2):
	var mine = mine_scene.instantiate()
	mine.position = world_pos
	mine.linked_to = null
	add_child(mine)
	_add_building_to_grid(mine, "miner")
	_update_astar()

func _place_adder(world_pos: Vector2):
	var adder = adder_scene.instantiate()
	adder.position = world_pos
	add_child(adder)
	_add_building_to_grid(adder, "adder")
	_update_astar()

func _delete_building(building: Node2D):
	if building.name == "Core": return
	var cells_to_erase = []
	for c in grid_data:
		if (grid_data[c].type == "miner" or grid_data[c].type == "adder") and grid_data[c].ref == building:
			cells_to_erase.append(c)
	for c in cells_to_erase:
		grid_data.erase(c)
	building.queue_free()
	_update_astar()

func _get_bezier_points(p0: Vector2, p1: Vector2, p2: Vector2, segments: int = 8) -> PackedVector2Array:
	var points = PackedVector2Array()
	for i in range(segments + 1):
		var t = float(i) / segments
		var q0 = p0.lerp(p1, t)
		var q1 = p1.lerp(p2, t)
		points.append(q0.lerp(q1, t))
	return points

func _on_wire_renderer_draw():
	var wire_color = Color(0.3, 0.8, 1.0)
	var outline_color = Color(0.1, 0.1, 0.15)
	var wire_width = 4.0
	var outline_width = 8.0
	
	# Draw placed wires
	for t in wire_grid:
		var center = _wire_tile_to_pos(t)
		var d = wire_grid[t].dir
		
		var in_dir = d
		for test_dir in WIRE_DIRS:
			var neighbor = t - test_dir
			if wire_grid.has(neighbor) and wire_grid[neighbor].dir == test_dir:
				in_dir = test_dir
				break
				
		if debug_mode:
			wire_renderer.draw_rect(Rect2(center - Vector2(4, 4), Vector2(8, 8)), Color(0.2, 0.9, 1.0))
			wire_renderer.draw_line(center, center + Vector2(d) * 8.0, Color(1, 1, 1), 2.0)
		else:
			var p0 = center - Vector2(in_dir) * 8.0
			var p1 = center
			var p2 = center + Vector2(d) * 8.0
			var pts = _get_bezier_points(p0, p1, p2, 8)
			wire_renderer.draw_polyline(pts, outline_color, outline_width, true)
			wire_renderer.draw_polyline(pts, wire_color, wire_width, true)
		
	# Draw preview
	if preview_points.size() > 0:
		for i in range(preview_points.size()):
			var p = preview_points[i]
			var center = _wire_tile_to_pos(p)
			var cell = _pos_to_cell(center)
			
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
			if grid_data.has(cell) and (grid_data[cell].type == "core" or grid_data[cell].type == "miner" or grid_data[cell].type == "adder"):
				is_blocked = true
				
			if debug_mode:
				var c = Color(1.0, 0.0, 0.0, 0.5) if is_blocked else Color(0.2, 0.9, 1.0, 0.5)
				wire_renderer.draw_rect(Rect2(center - Vector2(4, 4), Vector2(8, 8)), c)
				wire_renderer.draw_line(center, center + Vector2(out_dir) * 8.0, Color(1, 1, 1, 0.5), 2.0)
			else:
				var c_wire = Color(1.0, 0.2, 0.2, 0.7) if is_blocked else Color(0.3, 0.8, 1.0, 0.7)
				var c_outline = Color(0.1, 0.0, 0.0, 0.5) if is_blocked else Color(0.1, 0.1, 0.15, 0.7)
				
				var p0 = center - Vector2(in_dir) * 8.0
				var p1 = center
				var p2 = center + Vector2(out_dir) * 8.0
				var pts = _get_bezier_points(p0, p1, p2, 8)
				
				wire_renderer.draw_polyline(pts, c_outline, outline_width, true)
				wire_renderer.draw_polyline(pts, c_wire, wire_width, true)

func _process(delta: float):
	if camera:
		var move_dir = Vector2.ZERO
		if Input.is_key_pressed(KEY_W): move_dir.y -= 1
		if Input.is_key_pressed(KEY_S): move_dir.y += 1
		if Input.is_key_pressed(KEY_A): move_dir.x -= 1
		if Input.is_key_pressed(KEY_D): move_dir.x += 1
		if move_dir != Vector2.ZERO:
			camera.position += move_dir.normalized() * cam_pan_speed * delta * (1.0 / camera.zoom.x)
			
		# Enforce zoom limits to strictly prevent seeing beyond map boundaries
		var map_w = limit_right - limit_left
		var map_h = limit_bottom - limit_top
		var vp_size = get_viewport_rect().size
		
		var half_w = (vp_size.x / camera.zoom.x) / 2.0
		var half_h = (vp_size.y / camera.zoom.y) / 2.0
		
		camera.position.x = clamp(camera.position.x, limit_left + half_w, limit_right - half_w)
		camera.position.y = clamp(camera.position.y, limit_top + half_h, limit_bottom - half_h)
		
		var min_zoom_x = vp_size.x / map_w if map_w > 0 else 0.2
		var min_zoom_y = vp_size.y / map_h if map_h > 0 else 0.2
		var min_zoom = max(max(min_zoom_x, min_zoom_y), 0.2)
		
		target_zoom.x = clamp(target_zoom.x, min_zoom, 3.0)
		target_zoom.y = clamp(target_zoom.y, min_zoom, 3.0)
		camera.zoom = camera.zoom.lerp(target_zoom, 10.0 * delta)

	tick_accumulator += delta
	while tick_accumulator >= tick_rate:
		tick_accumulator -= tick_rate
		_on_tick()

	var speed = 64.0
	
	# Pass 1: Move items forward
	for t in wire_grid:
		var w = wire_grid[t]
		if w.item != null:
			w.item.progress += speed * delta
			if w.item.progress > 16.0:
				w.item.progress = 16.0
				
	# Pass 2: Transfer (Cascade backward essentially, resolves jams instantly)
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
				var world_pos = _wire_tile_to_pos(next_t)
				var cell_4x4 = _pos_to_cell(world_pos)
				
				if grid_data.has(cell_4x4):
					var b = grid_data[cell_4x4]
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
							# If buffer is full, treat it as a blockage and keep the item on the wire
							hit_building = true
						
				if not hit_building and wire_grid.has(next_t):
					var next_w = wire_grid[next_t]
					if next_w.item == null:
						next_w.item = w.item
						next_w.item.progress = 0.0
						w.item = null
						moved_any = true
						
	# Pass 3: Update Visuals
	for t in wire_grid:
		var w = wire_grid[t]
		if w.item != null and is_instance_valid(w.item.visual):
			var start = _wire_tile_to_pos(t) - Vector2(w.dir) * 8.0
			var end = _wire_tile_to_pos(t) + Vector2(w.dir) * 8.0
			var frac = w.item.progress / 16.0
			w.item.visual.global_position = start.lerp(end, frac)
			
	# Update UI Button highlights
	if has_node("UI/MineButton"):
		$UI/MineButton.modulate = Color(0.2, 0.9, 1.0) if current_state == State.PLACING_MINE else Color(1, 1, 1)
	if has_node("UI/AdderButton"):
		$UI/AdderButton.modulate = Color(0.2, 0.9, 1.0) if current_state == State.PLACING_ADDER else Color(1, 1, 1)
		
	# Update highlights
	var mouse_pos = get_global_mouse_position()
	var snapped_pos = _snap_to_grid(mouse_pos)
	var tile_pos = _pos_to_wire_tile(mouse_pos)
	var cell_pos = _pos_to_cell(mouse_pos)
	
	cursor_highlight.visible = false
	wire_hover_highlight.visible = false
	building_hover_highlight.visible = false
	building_highlight.visible = false
	
	if current_state == State.PLACING_MINE or current_state == State.PLACING_ADDER:
		var size = 32 if current_state == State.PLACING_MINE else 64
		building_highlight.global_position = _snap_building(mouse_pos) - Vector2(size/2, size/2)
		building_highlight.size = Vector2(size, size)
		building_highlight.visible = true
		if mine_preview:
			mine_preview.global_position = _snap_building(mouse_pos)
		if adder_preview:
			adder_preview.global_position = _snap_building(mouse_pos)
	else:
		var hovered_building = null
		if grid_data.has(cell_pos):
			hovered_building = grid_data[cell_pos].ref
			
		if hovered_building != null:
			var is_miner = (grid_data[cell_pos].type == "miner")
			var size = 32 if is_miner else 64
			building_hover_highlight.global_position = hovered_building.global_position - Vector2(size/2, size/2)
			building_hover_highlight.size = Vector2(size, size)
			building_hover_highlight.visible = true
		elif wire_grid.has(tile_pos):
			wire_hover_highlight.global_position = snapped_pos - Vector2(8, 8)
			wire_hover_highlight.visible = true
		else:
			cursor_highlight.global_position = snapped_pos
			
			if current_state == State.DRAWING_WIRE and preview_points.size() > 1:
				var last_dir = preview_points[-1] - preview_points[-2]
				var w_idx = WIRE_DIRS.find(last_dir)
				if w_idx != -1:
					current_wire_dir_index = w_idx
					
			cursor_highlight.rotation = current_wire_dir_index * PI / 4.0
			cursor_highlight.visible = true

func _on_tick():
	# Generate items from Miners into adjacent wires
	for child in get_children():
		if child.has_node("OutputPort") and child.name != "Core":
			if child.has_method("can_output") and not child.can_output(): continue
			var is_miner = not child.has_method("can_receive")
			var size = 32 if is_miner else 64
			var top_left = child.global_position - Vector2(size/2, size/2)
			var wire_tiles = size / 16
			# Find an adjacent wire tile pointing AWAY from the miner
			var output_tiles = []
			for x in [-1, wire_tiles]:
				for y in range(wire_tiles):
					output_tiles.append(_pos_to_wire_tile(top_left + Vector2(x * 16 + 8, y * 16 + 8)))
			for y in [-1, wire_tiles]:
				for x in range(wire_tiles):
					output_tiles.append(_pos_to_wire_tile(top_left + Vector2(x * 16 + 8, y * 16 + 8)))
					
			var valid_outputs = []
			for t in output_tiles:
				if wire_grid.has(t):
					var w = wire_grid[t]
					var next_t = t + w.dir
					var next_pos = _wire_tile_to_pos(next_t)
					var next_cell = _pos_to_cell(next_pos)
					
					var points_into_me = false
					if grid_data.has(next_cell) and grid_data[next_cell].ref == child:
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
						# Generate!
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
						
						add_child(container)
						wire_grid[t].item = { "value": val, "progress": 0.0, "visual": container }
						
						miner_round_robin[child] = (idx + 1) % valid_outputs.size()
						break # Only output 1 item per tick per miner
