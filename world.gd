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

# Auto-routing
var astar = AStarGrid2D.new()

# All drawn links (Line2D nodes)
var links: Array = []

func _ready():
	if has_node("UI"):
		$UI.offset = Vector2.ZERO
	if has_node("UI/MineButton"):
		$UI/MineButton.pressed.connect(start_placing_mine)
	
	astar.region = Rect2i(-400, -400, 800, 800) # Covers -6400 to +6400 pixels
	astar.cell_size = Vector2(16, 16)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()

func _set_building_solid(pos: Vector2, is_solid: bool):
	var top_left = pos - Vector2(32, 32)
	var start_cell = _pos_to_cell(top_left)
	# A 64x64 building takes up 4x4 cells on a 16x16 grid
	for x in range(4):
		for y in range(4):
			astar.set_point_solid(start_cell + Vector2i(x, y), is_solid)

func _update_astar():
	astar.fill_solid_region(astar.region, false)
	_set_building_solid(core.global_position, true)
	for child in get_children():
		if child.has_node("OutputPort") and child.name != "Core":
			_set_building_solid(child.global_position, true)
			
	# Make existing wires solid so we path around them
	for line in links:
		var pts = line.points
		for i in range(pts.size() - 1):
			var c1 = _pos_to_cell(pts[i])
			var c2 = _pos_to_cell(pts[i+1])
			var dist = max(abs(c2.x - c1.x), abs(c2.y - c1.y))
			if dist > 0:
				for t in range(dist + 1):
					var step = Vector2(c1).lerp(Vector2(c2), float(t)/dist)
					astar.set_point_solid(Vector2i(round(step.x), round(step.y)), true)
			else:
				astar.set_point_solid(c1, true)

func _pos_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(floor(pos.x / 16.0), floor(pos.y / 16.0))

func _cell_to_pos(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * 16.0 + 8.0, cell.y * 16.0 + 8.0)

func _snap_to_grid(pos: Vector2) -> Vector2:
	var tile_size = 16
	return Vector2(
		floor(pos.x / tile_size) * tile_size + tile_size / 2,
		floor(pos.y / tile_size) * tile_size + tile_size / 2
	)

func _process(delta: float):
	if placing_mine and mine_preview != null:
		var snapped = _snap_to_grid(get_global_mouse_position())
		mine_preview.global_position = snapped
		if _can_place_building(snapped):
			mine_preview.modulate = Color(1, 1, 1, 0.5)
		else:
			mine_preview.modulate = Color(1, 0, 0, 0.5)
	
	if linking and preview_line != null:
		_update_astar()
		var start_cell = _pos_to_cell(link_source.global_position)
		# We snap the mouse pos to grid to make end_cell align nicely
		var end_cell = _pos_to_cell(get_global_mouse_position())
		
		# Ensure start and end cells are NOT solid so A* can find a path
		_set_building_solid(link_source.global_position, false)
		_set_building_solid(core.global_position, false)
		
		var end_was_solid = astar.is_point_solid(end_cell)
		if end_was_solid:
			astar.set_point_solid(end_cell, false)
			
		var id_path = astar.get_id_path(start_cell, end_cell)
		
		if end_was_solid:
			astar.set_point_solid(end_cell, true)
		_set_building_solid(core.global_position, true)
		_set_building_solid(link_source.global_position, true)
			
		preview_line.clear_points()
		preview_line.add_point(link_source.get_node("OutputPort").global_position)
		
		if id_path.size() > 0:
			for i in range(1, id_path.size() - 1):
				preview_line.add_point(_cell_to_pos(id_path[i]))
			
			if _clicked_node(core, get_global_mouse_position()):
				preview_line.add_point(core.get_node("InputPort").global_position)
			else:
				# snap the wire end to the center of the grid tile when drawing
				preview_line.add_point(_cell_to_pos(end_cell))
		else:
			# Fallback if totally trapped
			preview_line.add_point(get_global_mouse_position())

func _input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed:
		var world_pos = get_global_mouse_position()

		# --- RIGHT CLICK = cancel ---
		if event.button_index == MOUSE_BUTTON_RIGHT:
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
			return

		# --- LEFT CLICK ---
		if event.button_index == MOUSE_BUTTON_LEFT:

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

			# If we are currently linking, check if we clicked the Core to finalize
			if linking:
				if _clicked_node(core, world_pos):
					# Finalize link
					preview_line.set_point_position(preview_line.get_point_count() - 1, core.get_node("InputPort").global_position)
					link_source.linked_to = core
					links.append(preview_line)
					
					linking = false
					link_source = null
					preview_line = null
				return

			# Otherwise, check if we clicked a Mine to start a link
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
