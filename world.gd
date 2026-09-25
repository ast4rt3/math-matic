# world.gd
extends Node2D

@onready var ground_layer: TileMapLayer = $GroundLayer
@onready var core: Node2D = $Core

# Building placement
var mine_scene = preload("res://Mine.tscn")
var placing_mine: bool = false
var mine_preview: Sprite2D = null

# Linking state
var linking: bool = false
var link_source: Node = null  # the Mine we started linking from
var preview_line: Line2D = null
var deleting_wires: bool = false

# Auto-routing
var astar = AStarGrid2D.new()

# All drawn links (Line2D nodes)
var links: Array = []

func _ready():
	if has_node("UI"):
		$UI.offset = Vector2.ZERO
	if has_node("UI/MineButton"):
		$UI/MineButton.pressed.connect(start_placing_mine)
	
	astar.region = Rect2i(-1600, -1600, 3200, 3200) # Covers -6400 to +6400 pixels
	astar.cell_size = Vector2(4, 4)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()

func _set_building_solid(pos: Vector2, is_solid: bool):
	var top_left = pos - Vector2(32, 32)
	var start_cell = _pos_to_cell(top_left)
	# A 64x64 building takes up 16x16 cells on a 4x4 grid
	for x in range(16):
		for y in range(16):
			var cell = start_cell + Vector2i(x, y)
			if astar.is_in_bounds(cell.x, cell.y):
				astar.set_point_solid(cell, is_solid)

func _update_astar():
	astar.fill_solid_region(astar.region, false)
	_set_building_solid(core.global_position, true)
	for child in get_children():
		if child.has_node("OutputPort") and child.name != "Core":
			_set_building_solid(child.global_position, true)
			
	# Make existing wires solid so we path around them
	var valid_links = []
	for line in links:
		if is_instance_valid(line):
			valid_links.append(line)
			var pts = line.points
			for i in range(pts.size() - 1):
				var c1 = _pos_to_cell(pts[i])
				var c2 = _pos_to_cell(pts[i+1])
				var dist = max(abs(c2.x - c1.x), abs(c2.y - c1.y))
				if dist > 0:
					for t in range(dist + 1):
						var step = Vector2(c1).lerp(Vector2(c2), float(t)/dist)
						var cell = Vector2i(round(step.x), round(step.y))
						if astar.is_in_bounds(cell.x, cell.y):
							astar.set_point_solid(cell, true)
				else:
					if astar.is_in_bounds(c1.x, c1.y):
						astar.set_point_solid(c1, true)
	links = valid_links

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
	
	if abs(dx) > abs(dy):
		var edge_x = center.x + 32 if dx > 0 else center.x - 32
		var clamped_y = clamp(target.y, center.y - 32, center.y + 32)
		return Vector2(edge_x, clamped_y)
	else:
		var edge_y = center.y + 32 if dy > 0 else center.y - 32
		var clamped_x = clamp(target.x, center.x - 32, center.x + 32)
		return Vector2(clamped_x, edge_y)

func _is_cell_in_building(cell: Vector2i, building: Node2D) -> bool:
	var top_left = building.global_position - Vector2(32, 32)
	var start_cell = _pos_to_cell(top_left)
	return cell.x >= start_cell.x and cell.x < start_cell.x + 16 and cell.y >= start_cell.y and cell.y < start_cell.y + 16

func _process(delta: float):
	if deleting_wires:
		var mouse_pos = get_global_mouse_position()
		var to_remove = []
		for line in links:
			var pts = line.points
			var hit = false
			for i in range(pts.size() - 1):
				var closest = Geometry2D.get_closest_point_to_segment(mouse_pos, pts[i], pts[i+1])
				if closest.distance_to(mouse_pos) < 15.0:
					hit = true
					break
			if hit:
				to_remove.append(line)
				
		for line in to_remove:
			links.erase(line)
			for child in get_children():
				if child.has_node("OutputPort") and child.name != "Core":
					if child.global_position.distance_to(line.points[0]) < 40.0:
						child.linked_to = null
			line.queue_free()

	if placing_mine and mine_preview != null:
		mine_preview.global_position = _snap_to_grid(get_global_mouse_position())
		if _can_place_building(mine_preview.global_position):
			mine_preview.modulate = Color(1, 1, 1, 0.5)
		else:
			mine_preview.modulate = Color(1, 0, 0, 0.5)
	
	if linking and preview_line != null:
		_update_astar()
		var start_cell = _pos_to_cell(link_source.global_position)
		var end_cell = _pos_to_cell(get_global_mouse_position())
		
		_set_building_solid(link_source.global_position, false)
		_set_building_solid(core.global_position, false)
		
		var end_was_solid = false
		if astar.is_in_bounds(end_cell.x, end_cell.y):
			end_was_solid = astar.is_point_solid(end_cell)
			if end_was_solid:
				astar.set_point_solid(end_cell, false)
			
		var id_path = []
		if astar.is_in_bounds(start_cell.x, start_cell.y) and astar.is_in_bounds(end_cell.x, end_cell.y):
			id_path = astar.get_id_path(start_cell, end_cell)
		
		if end_was_solid and astar.is_in_bounds(end_cell.x, end_cell.y):
			astar.set_point_solid(end_cell, true)
		_set_building_solid(core.global_position, true)
		_set_building_solid(link_source.global_position, true)
			
		preview_line.clear_points()
		
		if id_path.size() > 0:
			var first_outside_idx = 0
			for i in range(id_path.size()):
				if not _is_cell_in_building(id_path[i], link_source):
					first_outside_idx = i
					break
			
			if first_outside_idx < id_path.size() and first_outside_idx > 0:
				var first_outside_pos = _cell_to_pos(id_path[first_outside_idx])
				var start_port = _get_closest_port(link_source, first_outside_pos)
				preview_line.add_point(start_port)
				
				var last_idx = id_path.size() - 1
				var clicked_core = _clicked_node(core, get_global_mouse_position())
				if clicked_core:
					for i in range(id_path.size() - 1, -1, -1):
						if not _is_cell_in_building(id_path[i], core):
							last_idx = i
							break
							
				for i in range(first_outside_idx, last_idx + 1):
					preview_line.add_point(_cell_to_pos(id_path[i]))
					
				if clicked_core:
					var end_target = preview_line.get_point_position(preview_line.get_point_count() - 1) if preview_line.get_point_count() > 0 else start_port
					preview_line.add_point(_get_closest_port(core, end_target))
				else:
					# snap the wire end to the center of the grid tile when drawing
					preview_line.add_point(_cell_to_pos(end_cell))
			else:
				# Mouse is still inside the start building or path is too short
				preview_line.add_point(link_source.global_position)
				preview_line.add_point(get_global_mouse_position())
		else:
			# Fallback if totally trapped
			preview_line.add_point(link_source.global_position)
			preview_line.add_point(get_global_mouse_position())

func _input(event: InputEvent):
	if event is InputEventMouseButton:
		var world_pos = get_global_mouse_position()

		# --- RIGHT CLICK ---
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				deleting_wires = true
				# Cancel any ongoing actions
				if placing_mine:
					placing_mine = false
					if mine_preview:
						mine_preview.queue_free()
						mine_preview = null
				if linking:
					linking = false
					link_source = null
					if preview_line:
						preview_line.queue_free()
						preview_line = null
			else:
				deleting_wires = false
			return

		# --- LEFT CLICK PRESSED ---
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# If placing a mine, place it
			if placing_mine:
				var snapped_pos = _snap_to_grid(world_pos)
				if _can_place_building(snapped_pos):
					_place_mine(snapped_pos)
					placing_mine = false
					if mine_preview:
						mine_preview.queue_free()
						mine_preview = null
				return

			# Check if we clicked a Mine to start a link
			for child in get_children():
				if child.has_node("OutputPort") and child.name != "Core":
					if _clicked_node(child, world_pos):
						linking = true
						link_source = child
						
						preview_line = Line2D.new()
						preview_line.width = 3.0
						preview_line.default_color = Color(0.2, 0.9, 1.0)
						preview_line.add_point(child.get_node("OutputPort").global_position)
						preview_line.add_point(world_pos)
						add_child(preview_line)
						return

		# --- LEFT CLICK RELEASED ---
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			if linking:
				# Finalize link
				if _clicked_node(core, world_pos):
					link_source.linked_to = core
				else:
					link_source.linked_to = null # Stays exactly where the user let go
					
				links.append(preview_line)
				
				linking = false
				link_source = null
				preview_line = null
				return

func _place_mine(world_pos: Vector2):
	var mine = mine_scene.instantiate()
	mine.position = world_pos
	mine.linked_to = null
	add_child(mine)

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
	placing_mine = true
	if mine_preview == null:
		mine_preview = Sprite2D.new()
		mine_preview.texture = preload("res://Miner.png")
		mine_preview.modulate.a = 0.5
		add_child(mine_preview)
