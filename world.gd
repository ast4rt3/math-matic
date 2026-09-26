# world.gd
extends Node2D

@onready var ground_layer: TileMapLayer = $GroundLayer
@onready var core: Node2D = $Core

# --- NEW STATE MACHINE ---
enum State { IDLE, PLACING_MINE, DRAWING_WIRE, DELETING }
var current_state: State = State.IDLE

# --- GRID ENTITY SYSTEM ---
# Dictionary mapping Vector2i grid coordinates to Entity data
# Entity format: { "type": "miner"|"core"|"wire", "ref": Node2D, "value": float, "next": Vector2i }
var grid_data: Dictionary = {}

# Placement / UI Previews
var mine_scene = preload("res://Mine.tscn")
var mine_preview: Sprite2D = null

# Wire Drawing State
var wire_start_cell: Vector2i
var wire_start_pos: Vector2
var link_source: Node2D = null
var preview_line: Line2D = null
var current_drawn_wire_cells: Array[Vector2i] = []

# All drawn links (Still using Line2D visually for now to maintain feel)
var links: Array = []

# Auto-routing
var astar = AStarGrid2D.new()

func _ready():
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

func _process(delta: float):
	if current_state == State.PLACING_MINE and mine_preview != null:
		mine_preview.global_position = _snap_to_grid(get_global_mouse_position())
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
				
			# If we are not placing or linking, try to delete a wire
			for i in range(links.size() - 1, -1, -1):
				var line = links[i]
				var pts = line.points
				var clicked = false
				for j in range(pts.size() - 1):
					var closest = Geometry2D.get_closest_point_to_segment(world_pos, pts[j], pts[j+1])
					if world_pos.distance_to(closest) < 8.0:
						clicked = true
						break
				if clicked:
					var source = line.get_meta("source")
					if is_instance_valid(source):
						source.linked_to = null
					line.queue_free()
					links.remove_at(i)
					_update_astar()
					return

		# --- LEFT CLICK PRESSED ---
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# If placing a mine, place it
			if current_state == State.PLACING_MINE:
				var snapped_pos = _snap_to_grid(world_pos)
				if _can_place_building(snapped_pos):
					_place_mine(snapped_pos)
					current_state = State.IDLE
					if mine_preview:
						mine_preview.queue_free()
						mine_preview = null
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
				# Finalize link
				if _clicked_node(core, world_pos):
					link_source.linked_to = core
				else:
					link_source.linked_to = null # Stays exactly where the user let go
					
				preview_line.set_meta("source", link_source)
				links.append(preview_line)
				
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
							grid_data[c] = { "type": "wire", "ref": preview_line }
				
				_update_astar()
				
				current_state = State.IDLE
				link_source = null
				preview_line = null
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
	current_state = State.PLACING_MINE
	if mine_preview == null:
		mine_preview = Sprite2D.new()
		mine_preview.texture = preload("res://asset/Miner.png")
		mine_preview.modulate.a = 0.5
		add_child(mine_preview)
