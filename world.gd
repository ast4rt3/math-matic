extends Node2D

@onready var ground_layer: TileMapLayer = $GroundLayer
@onready var core: Node2D = $Core

enum State { IDLE, PLACING_MINE, DRAWING_WIRE, DELETING }
var current_state: State = State.IDLE
var tick_accumulator: float = 0.0
var tick_rate: float = 0.4 

# 4x4 Grid for Buildings and AStar
var grid_data: Dictionary = {}

# 16x16 Grid for Wires
var wire_grid: Dictionary = {} # Vector2i -> { "dir": Vector2i, "item": Dictionary }

var mine_scene = preload("res://buildings/Mine.tscn")
var mine_preview: Sprite2D = null

var preview_points: Array[Vector2i] = []
var wire_renderer: Node2D

var cursor_highlight: ReferenceRect
var building_highlight: ReferenceRect

var astar = AStarGrid2D.new()

func _ready():
	wire_renderer = Node2D.new()
	wire_renderer.z_index = 10
	add_child(wire_renderer)
	wire_renderer.draw.connect(_on_wire_renderer_draw)
	
	cursor_highlight = ReferenceRect.new()
	cursor_highlight.border_color = Color(1.0, 1.0, 1.0, 0.8)
	cursor_highlight.border_width = 2.0
	cursor_highlight.editor_only = false
	cursor_highlight.z_index = 100
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
		var wire_btn = Button.new()
		wire_btn.text = "Draw Wire"
		wire_btn.name = "WireButton"
		wire_btn.position = Vector2(0, $UI/MineButton.size.y + 10) if $UI/MineButton.size.y > 0 else Vector2(0, 40)
		wire_btn.pressed.connect(start_drawing_wire)
		$UI.add_child(wire_btn)
	
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
	var top_left = building.global_position - Vector2(32, 32)
	var start_cell = _pos_to_cell(top_left)
	for x in range(16):
		for y in range(16):
			var c = start_cell + Vector2i(x, y)
			grid_data[c] = { "type": b_type, "ref": building }

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
		mine_preview.texture = preload("res://asset/Miner.png")
		mine_preview.modulate.a = 0.5
		add_child(mine_preview)

func _input(event: InputEvent):
	if event is InputEventMouseMotion:
		if current_state == State.DRAWING_WIRE and preview_points.size() > 0:
			var target_tile = _pos_to_wire_tile(get_global_mouse_position())
			var last_tile = preview_points[-1]
			
			if last_tile != target_tile:
				var dx = target_tile.x - last_tile.x
				var dy = target_tile.y - last_tile.y
				var current = last_tile
				var steps = 0
				while current != target_tile and steps < 50:
					steps += 1
					if abs(target_tile.x - current.x) > abs(target_tile.y - current.y):
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
			if current_state == State.DRAWING_WIRE:
				start_drawing_wire()
				return
				
			var cell_4x4 = _pos_to_cell(world_pos)
			if grid_data.has(cell_4x4) and grid_data[cell_4x4].type == "miner":
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
				var snapped_pos = _snap_to_grid(world_pos)
				if _can_place_building(snapped_pos):
					_place_mine(snapped_pos)
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
					var dir = Vector2i(1, 0)
					if i < preview_points.size() - 1:
						dir = preview_points[i+1] - p
					elif i > 0:
						dir = p - preview_points[i-1] # Keep last direction
						
					if not wire_grid.has(p):
						wire_grid[p] = { "dir": dir, "item": null }
					else:
						# Overwrite direction
						wire_grid[p].dir = dir
						
				preview_points.clear()
				wire_renderer.queue_redraw()

func _can_place_building(pos: Vector2) -> bool:
	for child in get_children():
		if child.name == "Core" or child.has_node("OutputPort"):
			if child.global_position.distance_to(pos) < 1.0: return false
	return true

func _place_mine(world_pos: Vector2):
	var mine = mine_scene.instantiate()
	mine.position = world_pos
	mine.linked_to = null
	add_child(mine)
	_add_building_to_grid(mine, "miner")
	_update_astar()

func _delete_building(building: Node2D):
	if building.name == "Core": return
	var cells_to_erase = []
	for c in grid_data:
		if grid_data[c].type == "miner" and grid_data[c].ref == building:
			cells_to_erase.append(c)
	for c in cells_to_erase:
		grid_data.erase(c)
	building.queue_free()
	_update_astar()

func _on_wire_renderer_draw():
	# Draw placed wires
	for t in wire_grid:
		var center = _wire_tile_to_pos(t)
		var d = wire_grid[t].dir
		wire_renderer.draw_rect(Rect2(center - Vector2(4, 4), Vector2(8, 8)), Color(0.2, 0.9, 1.0))
		wire_renderer.draw_line(center, center + Vector2(d) * 8.0, Color(1, 1, 1), 2.0)
		
	# Draw preview
	if preview_points.size() > 0:
		for i in range(preview_points.size()):
			var center = _wire_tile_to_pos(preview_points[i])
			wire_renderer.draw_rect(Rect2(center - Vector2(4, 4), Vector2(8, 8)), Color(0.2, 0.9, 1.0, 0.5))

func _process(delta: float):
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
					if b.type == "core" or b.type == "miner":
						hit_building = true
						if b.ref.has_method("receive"):
							b.ref.receive(w.item.value)
						if is_instance_valid(w.item.visual): w.item.visual.queue_free()
						w.item = null
						moved_any = true
						
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
			w.item.visual.global_position = start.lerp(end, frac) - Vector2(8, 12)
			
	# Update highlights
	var mouse_pos = get_global_mouse_position()
	cursor_highlight.global_position = _snap_to_grid(mouse_pos) - Vector2(8, 8)
	cursor_highlight.size = Vector2(16, 16)
	cursor_highlight.visible = true

func _on_tick():
	# Generate items from Miners into adjacent wires
	for child in get_children():
		if child.has_node("OutputPort") and child.name != "Core":
			var top_left = child.global_position - Vector2(32, 32)
			# Find an adjacent wire tile pointing AWAY from the miner
			var output_tiles = []
			for x in [-1, 4]:
				for y in range(4):
					output_tiles.append(_pos_to_wire_tile(top_left + Vector2(x * 16 + 8, y * 16 + 8)))
			for y in [-1, 4]:
				for x in range(4):
					output_tiles.append(_pos_to_wire_tile(top_left + Vector2(x * 16 + 8, y * 16 + 8)))
					
			for t in output_tiles:
				if wire_grid.has(t) and wire_grid[t].item == null:
					# Generate!
					var val = 1.0
					if "output_value" in child: val = child.output_value
					var lbl = Label.new()
					lbl.text = str(int(val)) if val == round(val) else str(val)
					lbl.add_theme_font_size_override("font_size", 12)
					lbl.z_index = 20
					add_child(lbl)
					wire_grid[t].item = { "value": val, "progress": 0.0, "visual": lbl }
					break # Only output 1 item per tick per miner
