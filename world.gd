# world.gd
extends Node2D

@onready var ground_layer: TileMapLayer = $GroundLayer
@onready var core: Node2D = $Core

# --- NEW STATE MACHINE ---
enum State { IDLE, PLACING_MINE, DRAWING_WIRE, DELETING }
var current_state: State = State.IDLE
var tick_accumulator: float = 0.0
var tick_rate: float = 0.4 # seconds per tick

# --- GRID ENTITY SYSTEM ---
# Dictionary mapping Vector2i grid coordinates to Entity data
# Entity format: { "type": "miner"|"core"|"wire", "ref": Node2D, "value": float, "next": Vector2i }
var grid_data: Dictionary = {}

# Placement / UI Previews
var mine_scene = preload("res://buildings/Mine.tscn")
var mine_preview: Sprite2D = null

# Wire Drawing State
var wire_start_cell: Vector2i
var wire_start_pos: Vector2
var link_source: Node2D = null
var preview_line: Line2D = null
var current_drawn_wire_cells: Array[Vector2i] = []
var wire_renderer: Node2D

# Hover Highlight
var cursor_highlight: ReferenceRect
var building_highlight: ReferenceRect
var hovered_wire_id: int = -1

# All drawn links (Stored as data to be rendered in _draw)
var wire_paths: Dictionary = {} # wire_id -> { "points": Array, "source": Node2D, "color": Color }
var next_wire_id: int = 0
var miner_round_robin: Dictionary = {} # source_node -> current_wire_index

# Auto-routing
var astar = AStarGrid2D.new()

func _ready():
	wire_renderer = Node2D.new()
	wire_renderer.z_index = 10
	add_child(wire_renderer)
	wire_renderer.draw.connect(_on_wire_renderer_draw)
	
	# Create the cursor highlight visually
	cursor_highlight = ReferenceRect.new()
	cursor_highlight.border_color = Color(1.0, 1.0, 1.0, 0.8)
	cursor_highlight.border_width = 2.0
	cursor_highlight.editor_only = false
	cursor_highlight.z_index = 100 # Ensure it draws on top of everything
	
	var bg = ColorRect.new()
	bg.color = Color(1.0, 1.0, 1.0, 0.2)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	cursor_highlight.add_child(bg)
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

	if has_node("UI"):
		$UI.offset = Vector2.ZERO
	if has_node("UI/MineButton"):
		$UI/MineButton.pressed.connect(start_placing_mine)
	
	astar.region = Rect2i(-1600, -1600, 3200, 3200) # Covers -6400 to +6400 pixels
	astar.cell_size = Vector2(4, 4)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	
	# Initialize Grid Data with buildings
	grid_data.clear()
	_add_building_to_grid(core, "core")
	for child in get_children():
		if child.has_node("OutputPort") and child.name != "Core":
			_add_building_to_grid(child, "miner")
			
	_update_astar()

func _add_building_to_grid(building: Node2D, b_type: String):
	var top_left = building.global_position - Vector2(32, 32)
	var start_cell = _pos_to_cell(top_left)
	for x in range(16):
		for y in range(16):
			var c = start_cell + Vector2i(x, y)
			grid_data[c] = { "type": b_type, "ref": building }

var _solid_cells = []

func _mark_building_solid(pos: Vector2, is_solid: bool, track: bool = false):
	var top_left = pos - Vector2(32, 32)
	var start_cell = _pos_to_cell(top_left)
	# A 64x64 building takes up 16x16 cells on a 4x4 grid
	for x in range(16):
		for y in range(16):
			var c = start_cell + Vector2i(x, y)
			if astar.is_in_boundsv(c):
				astar.set_point_solid(c, is_solid)
				if track and is_solid:
					_solid_cells.append(c)

func _update_astar():
	for cell in _solid_cells:
		if astar.is_in_boundsv(cell):
			astar.set_point_solid(cell, false)
	_solid_cells.clear()
	
	# The grid_data is the single source of truth for collisions!
	for cell in grid_data:
		if astar.is_in_boundsv(cell):
			astar.set_point_solid(cell, true)
			_solid_cells.append(cell)

func _pos_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(floor(pos.x / 4.0), floor(pos.y / 4.0))

func _cell_to_pos(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * 4.0 + 2.0, cell.y * 4.0 + 2.0)

func _snap_to_grid(pos: Vector2) -> Vector2:
	var tile_size = 16
	return Vector2(
		floor(pos.x / tile_size) * tile_size + tile_size / 2,
		floor(pos.y / tile_size) * tile_size + tile_size / 2
	)

func _get_closest_port(building: Node2D, target: Vector2) -> Vector2:
	var center = building.global_position
	var dx = target.x - center.x
	var dy = target.y - center.y
	
	var is_core = building.name == "Core"
	var num_ports = 9 if is_core else 7
	
	var offsets = []
	for i in range(num_ports):
		offsets.append(-32.0 + (64.0 / (num_ports - 1)) * i)
	
	if abs(dx) > abs(dy):
		var edge_x = center.x + 32 if dx > 0 else center.x - 32
		var target_offset = target.y - center.y
		var closest = offsets[0]
		for offset in offsets:
			if abs(target_offset - offset) < abs(target_offset - closest):
				closest = offset
		return Vector2(edge_x, center.y + closest)
	else:
		var edge_y = center.y + 32 if dy > 0 else center.y - 32
		var target_offset = target.x - center.x
		var closest = offsets[0]
		for offset in offsets:
			if abs(target_offset - offset) < abs(target_offset - closest):
				closest = offset
		return Vector2(center.x + closest, edge_y)

func _is_cell_in_building(cell: Vector2i, building: Node2D) -> bool:
	var top_left = building.global_position - Vector2(32, 32)
	var start_cell = _pos_to_cell(top_left)
	return cell.x >= start_cell.x and cell.x < start_cell.x + 16 and cell.y >= start_cell.y and cell.y < start_cell.y + 16

func _get_wire_in_tile(pos: Vector2) -> int:
	var snapped = _snap_to_grid(pos)
	var top_left = snapped - Vector2(8, 8)
	var start_cell = _pos_to_cell(top_left)
	for x in range(4):
		for y in range(4):
			var c = start_cell + Vector2i(x, y)
			if grid_data.has(c) and grid_data[c].type == "wire":
				return grid_data[c].wire_id
	return -1

func _process(delta: float):
	# Handle deterministic factory ticks
	tick_accumulator += delta
	while tick_accumulator >= tick_rate:
		tick_accumulator -= tick_rate
		_on_tick()
		
	# Update visual hover feedback
	var mouse_pos = get_global_mouse_position()
	var cell = _pos_to_cell(mouse_pos)
	
	# Reset previous wire highlight
	var needs_redraw = false
	if hovered_wire_id != -1 and wire_paths.has(hovered_wire_id):
		wire_paths[hovered_wire_id].color = Color(0.2, 0.9, 1.0)
		needs_redraw = true
	hovered_wire_id = -1
	
	# Always update 16x16 cursor
	var snapped = _snap_to_grid(mouse_pos)
	cursor_highlight.global_position = snapped - Vector2(8, 8)
	cursor_highlight.size = Vector2(16, 16)
	cursor_highlight.visible = true
	
	# Reset building highlight
	building_highlight.visible = false
	
	if grid_data.has(cell) and (grid_data[cell].type == "miner" or grid_data[cell].type == "core"):
		var building = grid_data[cell].ref
		if is_instance_valid(building):
			building_highlight.global_position = building.global_position - Vector2(32, 32)
			building_highlight.size = Vector2(64, 64)
			building_highlight.visible = true
			cursor_highlight.modulate = Color(1.0, 1.0, 1.0, 0.15) # Lower opacity on building
	else:
		var wire_id = _get_wire_in_tile(mouse_pos)
		if wire_id != -1 and current_state == State.IDLE:
			cursor_highlight.modulate = Color(1.0, 1.0, 1.0, 0.3) # Lower opacity on wire
			hovered_wire_id = wire_id
			if wire_paths.has(hovered_wire_id):
				wire_paths[hovered_wire_id].color = Color(1.0, 1.0, 1.0) # Bright White
			needs_redraw = true
		else:
			cursor_highlight.modulate = Color(1.0, 1.0, 1.0, 1.0)
			
	if needs_redraw:
		wire_renderer.queue_redraw()
		
	# Move items along the wire
	var speed = 300.0 # pixels per second
	for wire_id in wire_paths:
		var w = wire_paths[wire_id]
		var total_length = _get_wire_length(w.points)
		
		# Process from oldest (index 0) to newest (index size-1) to handle traffic
		for i in range(w.items.size()):
			var item = w.items[i]
			var max_progress = total_length
			
			var can_enter = is_instance_valid(w.destination)
			
			if not can_enter:
				# Stack up at the end if not connected
				max_progress = total_length - (i * 16.0)
				
			# Don't overlap with the item ahead of us
			if i > 0:
				var item_ahead = w.items[i-1]
				max_progress = min(max_progress, item_ahead.progress - 16.0)
				
			if item.progress < max_progress:
				item.progress = min(item.progress + speed * delta, max_progress)
			
			if item.progress >= total_length and can_enter:
				# Item reached the end and can enter the building!
				w.destination.receive(item.value)
				if is_instance_valid(item.visual):
					item.visual.queue_free()
				item.queued_for_deletion = true
			else:
				# Update visual position
				if is_instance_valid(item.visual):
					item.visual.global_position = _get_pos_along_wire(w.points, item.progress) - Vector2(8, 12)
					
		# Remove deleted items
		for i in range(w.items.size() - 1, -1, -1):
			if w.items[i].has("queued_for_deletion") and w.items[i].queued_for_deletion:
				w.items.remove_at(i)
		
	if current_state == State.PLACING_MINE and mine_preview != null:
		mine_preview.global_position = _snap_to_grid(mouse_pos)
		if _can_place_building(mine_preview.global_position):
			mine_preview.modulate = Color(1, 1, 1, 0.5)
		else:
			mine_preview.modulate = Color(1, 0, 0, 0.5)

func _notification(what):
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if current_state == State.DRAWING_WIRE:
			current_state = State.IDLE
			link_source = null
			if preview_line:
				preview_line.queue_free()
				preview_line = null
		elif current_state == State.PLACING_MINE:
			current_state = State.IDLE
			if mine_preview:
				mine_preview.queue_free()
				mine_preview = null

func _input(event: InputEvent):
	if event is InputEventMouseMotion:
		if current_state == State.DRAWING_WIRE and preview_line != null:
			var last_point = preview_line.get_point_position(preview_line.get_point_count() - 1)
			var target_pos = _snap_to_grid(get_global_mouse_position())
			
			if last_point != target_pos:
				var dx = target_pos.x - last_point.x
				var dy = target_pos.y - last_point.y
				var angle = atan2(dy, dx)
				
				# Snap angle to nearest 45 degrees
				var snapped_angle = round(angle / (PI / 4.0)) * (PI / 4.0)
				
				var step_x = round(cos(snapped_angle)) * 16.0
				var step_y = round(sin(snapped_angle)) * 16.0
				var step_vec = Vector2(step_x, step_y)
				
				var current = last_point
				var steps = 0
				
				# Catch up to the mouse if dragged fast
				while steps < 50:
					steps += 1
					var next = current + step_vec
					
					# Prevent infinite oscillation if we overshoot the target axis
					if next.distance_squared_to(target_pos) >= current.distance_squared_to(target_pos):
						break
						
					var cell = _pos_to_cell(next)
					var hit_building = false
					var hit_self = false
					
					if grid_data.has(cell):
						if grid_data[cell].type == "core" or grid_data[cell].type == "miner":
							hit_building = true
					
					for i in range(preview_line.get_point_count()):
						if preview_line.get_point_position(i).distance_to(next) < 1.0:
							hit_self = true
							break
							
					if hit_building or hit_self:
						break
						
					preview_line.add_point(next)
					current = next

	if event is InputEventMouseButton:
		var world_pos = get_global_mouse_position()

		# --- RIGHT CLICK = cancel or delete ---
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if current_state == State.PLACING_MINE:
				current_state = State.IDLE
				if mine_preview:
					mine_preview.queue_free()
					mine_preview = null
				return
			if current_state == State.DRAWING_WIRE:
				current_state = State.IDLE
				link_source = null
				if preview_line:
					preview_line.queue_free()
					preview_line = null
				return
				
			# If we are not placing or linking, try to delete a building or wire
			var clicked_cell = _pos_to_cell(world_pos)
			if grid_data.has(clicked_cell) and grid_data[clicked_cell].type == "miner":
				_delete_building(grid_data[clicked_cell].ref)
				return
				
			var wire_id = _get_wire_in_tile(world_pos)
			if wire_id != -1:
				_delete_wire(wire_id, world_pos)
				return

		# --- LEFT CLICK PRESSED ---
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# If placing a mine, place it
			if current_state == State.PLACING_MINE:
				var snapped_pos = _snap_to_grid(world_pos)
				if _can_place_building(snapped_pos):
					_place_mine(snapped_pos)
					# Intentionally DO NOT reset state to IDLE here, allowing for multiple placements!
				return

			# Check if we clicked a Mine to start a link
			if current_state == State.IDLE:
				for child in get_children():
					if child.has_node("OutputPort") and child.name != "Core":
						if _clicked_node(child, world_pos):
							current_state = State.DRAWING_WIRE
							link_source = child
							
							preview_line = Line2D.new()
							preview_line.width = 8.0
							preview_line.default_color = Color(0.2, 0.9, 1.0)
							preview_line.texture_mode = Line2D.LINE_TEXTURE_TILE
							
							# Lock starting point to port
							wire_start_pos = _get_closest_port(child, world_pos)
							preview_line.add_point(wire_start_pos)
							add_child(preview_line)
							return

		# --- LEFT CLICK RELEASED ---
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			if current_state == State.DRAWING_WIRE:
				# Finalize link by checking what building is at the end cell
				var end_cell = _pos_to_cell(world_pos)
				var destination = null
				if grid_data.has(end_cell) and (grid_data[end_cell].type == "core" or grid_data[end_cell].type == "miner"):
					destination = grid_data[end_cell].ref
					
				# Save wire to dictionary
				var wire_id = next_wire_id
				next_wire_id += 1
				
				var wire_data = {
					"points": preview_line.points.duplicate(),
					"source": link_source,
					"destination": destination,
					"color": Color(0.2, 0.9, 1.0),
					"items": []
				}
				wire_paths[wire_id] = wire_data
				
				# Commit wire to GridManager
				var pts = preview_line.points
				for j in range(pts.size() - 1):
					var c1 = _pos_to_cell(pts[j])
					var c2 = _pos_to_cell(pts[j+1])
					var dist = max(abs(c2.x - c1.x), abs(c2.y - c1.y))
					if dist > 0:
						for t in range(dist + 1):
							var step = Vector2(c1).lerp(Vector2(c2), float(t)/dist)
							var c = Vector2i(round(step.x), round(step.y))
							grid_data[c] = { "type": "wire", "wire_id": wire_id }
				
				preview_line.queue_free()
				preview_line = null
				
				_update_astar()
				wire_renderer.queue_redraw()
				
				current_state = State.IDLE
				link_source = null
				return

func _place_mine(world_pos: Vector2):
	var mine = mine_scene.instantiate()
	mine.position = world_pos
	mine.linked_to = null
	add_child(mine)
	_add_building_to_grid(mine, "miner")
	_update_astar()

func _can_place_building(pos: Vector2) -> bool:
	var buildings = []
	for child in get_children():
		if child.name == "Core" or child.has_node("OutputPort"):
			# Block if completely overlapping (same exact position)
			if child.global_position.distance_to(pos) < 1.0:
				return false
			buildings.append(child.global_position)
	
	buildings.append(pos)
	
	# Prevent placing if it causes any building to be 100% covered by buildings ON TOP of it
	for i in range(buildings.size()):
		var b_pos = buildings[i]
		var top_left = b_pos - Vector2(32, 32)
		var completely_covered = true
		
		# A building has 16 cells of 16x16
		for x in range(4):
			for y in range(4):
				var cell_center = top_left + Vector2(x * 16.0 + 8.0, y * 16.0 + 8.0)
				var cell_covered = false
				
				# Only buildings placed AFTER this one (higher index) can cover it
				for j in range(i + 1, buildings.size()):
					var other_pos = buildings[j]
					var other_rect = Rect2(other_pos - Vector2(32, 32), Vector2(64, 64))
					if other_rect.has_point(cell_center):
						cell_covered = true
						break
				
				if not cell_covered:
					completely_covered = false
					break
			if not completely_covered:
				break
				
		if completely_covered:
			return false
			
	return true

func _clicked_node(node: Node2D, world_pos: Vector2) -> bool:
	# Simple distance check — within 40px of the node center
	return node.global_position.distance_to(world_pos) < 40.0

# Call this from your UI toolbar button
func start_placing_mine():
	if current_state == State.PLACING_MINE:
		# Toggle OFF
		current_state = State.IDLE
		if mine_preview:
			mine_preview.queue_free()
			mine_preview = null
		return
		
	# Toggle ON
	current_state = State.PLACING_MINE
	if mine_preview == null:
		mine_preview = Sprite2D.new()
		mine_preview.texture = preload("res://asset/Miner.png")
		mine_preview.modulate.a = 0.5
		add_child(mine_preview)

func _delete_building(building: Node2D):
	if building.name == "Core": return # Cannot delete core
	
	# Clean up any connected wires
	var wires_to_remove = []
	for wire_id in wire_paths:
		var w = wire_paths[wire_id]
		if w.source == building or w.destination == building:
			wires_to_remove.append(wire_id)
			
	for w_id in wires_to_remove:
		_delete_wire(w_id)
		
	# Clean up building from grid
	var cells_to_erase = []
	for c in grid_data:
		if grid_data[c].type == "miner" and grid_data[c].ref == building:
			cells_to_erase.append(c)
	for c in cells_to_erase:
		grid_data.erase(c)
		
	building.queue_free()
	_update_astar()

func _delete_wire(wire_id: int, cut_pos: Vector2 = Vector2.ZERO):
	if not wire_paths.has(wire_id): return
	var line_data = wire_paths[wire_id]
	var pts = line_data.points
	
	# 1. Erase old grid data
	var cells_to_erase = []
	for c in grid_data:
		if grid_data[c].type == "wire" and grid_data[c].wire_id == wire_id:
			cells_to_erase.append(c)
	for c in cells_to_erase:
		grid_data.erase(c)
		
	# 2. Check if this is a split
	var cut_idx = -1
	if cut_pos != Vector2.ZERO:
		var snapped_cut = _snap_to_grid(cut_pos)
		for i in range(pts.size()):
			if pts[i].distance_to(snapped_cut) < 8.0:
				cut_idx = i
				break
				
	if cut_idx != -1 and pts.size() > 2:
		# Splitting
		var pts_A = pts.slice(0, cut_idx)
		var pts_B = pts.slice(cut_idx + 1)
		
		var dist_A = _get_wire_length(pts_A) if pts_A.size() > 0 else 0.0
		var gap = _get_wire_length(pts.slice(0, cut_idx+1))
		
		var items_A = []
		var items_B = []
		
		for item in line_data.items:
			if item.progress <= dist_A:
				items_A.append(item)
			elif item.progress > gap:
				item.progress -= gap
				items_B.append(item)
			else:
				if is_instance_valid(item.visual): item.visual.queue_free()
				
		if pts_A.size() > 1:
			var wire_a_id = next_wire_id
			next_wire_id += 1
			wire_paths[wire_a_id] = {
				"points": pts_A, "source": line_data.source, "destination": null,
				"color": line_data.color, "items": items_A
			}
			for p in pts_A:
				grid_data[_pos_to_cell(p)] = { "type": "wire", "wire_id": wire_a_id }
		else:
			for item in items_A:
				if is_instance_valid(item.visual): item.visual.queue_free()
				
		if pts_B.size() > 1:
			var wire_b_id = next_wire_id
			next_wire_id += 1
			wire_paths[wire_b_id] = {
				"points": pts_B, "source": null, "destination": line_data.destination,
				"color": line_data.color, "items": items_B
			}
			for p in pts_B:
				grid_data[_pos_to_cell(p)] = { "type": "wire", "wire_id": wire_b_id }
		else:
			for item in items_B:
				if is_instance_valid(item.visual): item.visual.queue_free()
				
	else:
		# Full delete (or wire too short to split)
		for item in line_data.items:
			if is_instance_valid(item.visual):
				item.visual.queue_free()
				
	wire_paths.erase(wire_id)
	_update_astar()
	wire_renderer.queue_redraw()

func _on_wire_renderer_draw():
	for wire_id in wire_paths:
		var w = wire_paths[wire_id]
		if w.points.size() > 1:
			wire_renderer.draw_polyline(w.points, w.color, 8.0, false)

func _on_tick():
	# Group wires by their source Miner
	var source_wires = {}
	for wire_id in wire_paths:
		var w = wire_paths[wire_id]
		if w.source != null and is_instance_valid(w.source):
			if "output_value" in w.source:
				if not source_wires.has(w.source):
					source_wires[w.source] = []
				source_wires[w.source].append(wire_id)

	# Generate items using round-robin distribution
	for source in source_wires:
		var connected_wires = source_wires[source]
		
		if not miner_round_robin.has(source):
			miner_round_robin[source] = 0
			
		var idx = miner_round_robin[source] % connected_wires.size()
		var chosen_wire_id = connected_wires[idx]
		
		# Advance index for next tick
		miner_round_robin[source] = (idx + 1) % connected_wires.size()
		
		var w = wire_paths[chosen_wire_id]
		var val = 1.0
		if "output_value" in source:
			val = source.output_value
			
		var val_str = str(val)
		if val == round(val):
			val_str = str(int(val))
		
		var lbl = Label.new()
		lbl.text = val_str
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", Color(1, 1, 1))
		lbl.z_index = 20
		add_child(lbl)
		
		var new_item = {
			"value": val,
			"progress": 0.0,
			"visual": lbl
		}
		w.items.append(new_item)

func _get_wire_length(pts: PackedVector2Array) -> float:
	var total = 0.0
	for i in range(pts.size() - 1):
		total += pts[i].distance_to(pts[i+1])
	return total

func _get_pos_along_wire(pts: PackedVector2Array, distance: float) -> Vector2:
	if pts.size() == 0: return Vector2.ZERO
	if pts.size() == 1: return pts[0]
	
	var current_dist = 0.0
	for i in range(pts.size() - 1):
		var p1 = pts[i]
		var p2 = pts[i+1]
		var seg_len = p1.distance_to(p2)
		if current_dist + seg_len >= distance:
			var t = (distance - current_dist) / seg_len
			return p1.lerp(p2, t)
		current_dist += seg_len
	return pts[pts.size() - 1]
