extends Node
class_name GridSystem

var grid_data: Dictionary = {}
var astar: AStarGrid2D = AStarGrid2D.new()
var _solid_cells = []

var wire_system # Will be set by World
var limit_left = -2000
var limit_top = -2000
var limit_right = 2000
var limit_bottom = 2000

func _init():
	astar.region = Rect2i(-1600, -1600, 3200, 3200)
	astar.cell_size = Vector2(4, 4)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()

func setup_bounds(rect: Rect2, tile_size: Vector2):
	limit_left = rect.position.x * tile_size.x
	limit_top = rect.position.y * tile_size.y
	limit_right = (rect.position.x + rect.size.x) * tile_size.x
	limit_bottom = (rect.position.y + rect.size.y) * tile_size.y

func update_astar():
	for cell in _solid_cells:
		if astar.is_in_boundsv(cell):
			astar.set_point_solid(cell, false)
	_solid_cells.clear()
	for cell in grid_data:
		if astar.is_in_boundsv(cell):
			astar.set_point_solid(cell, true)
			_solid_cells.append(cell)

func add_building(building: Node2D, b_type: String):
	var size = get_building_size(b_type)
	var top_left = building.global_position - Vector2(size/2, size/2)
	var start_cell = pos_to_cell(top_left)
	var cells = size / 4
	for x in range(cells):
		for y in range(cells):
			var c = start_cell + Vector2i(x, y)
			var is_b = true
			grid_data[c] = { "type": b_type, "ref": building, "is_building": is_b }
			
	if wire_system:
		var wire_tiles = size / 16
		for wx in range(wire_tiles):
			for wy in range(wire_tiles):
				var tile = wire_system.pos_to_wire_tile(top_left + Vector2(wx * 16 + 8, wy * 16 + 8))
				if wire_system.wire_grid.has(tile):
					if wire_system.wire_grid[tile].item != null and is_instance_valid(wire_system.wire_grid[tile].item.visual):
						wire_system.wire_grid[tile].item.visual.queue_free()
					wire_system.wire_grid.erase(tile)
		wire_system.queue_redraw()
	update_astar()

func remove_building(building: Node2D):
	if building.name == "Core": return
	var cells_to_erase = []
	for c in grid_data:
		if (grid_data[c].type == "miner" or grid_data[c].type == "adder") and grid_data[c].ref == building:
			cells_to_erase.append(c)
	for c in cells_to_erase:
		grid_data.erase(c)
	building.queue_free()
	update_astar()

func get_building_size(b_type: String) -> int:
	if b_type == "miner": return 32
	if b_type == "adder" or b_type == "turret" or b_type == "core": return 64
	return 32

func can_place_building(pos: Vector2, b_type: String) -> bool:
	var size = get_building_size(b_type)
	var top_left = pos - Vector2(size/2, size/2)
	
	if top_left.x < limit_left or top_left.y < limit_top or (top_left.x + size) > limit_right or (top_left.y + size) > limit_bottom:
		return false
		
	var start_cell = pos_to_cell(top_left)
	var cells = size / 4
	for x in range(cells):
		for y in range(cells):
			var c = start_cell + Vector2i(x, y)
			if grid_data.has(c):
				return false
	return true

func pos_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(floor(pos.x / 4.0), floor(pos.y / 4.0))

func snap_building(pos: Vector2) -> Vector2:
	var tile_size = 16
	return Vector2(
		round(pos.x / tile_size) * tile_size,
		round(pos.y / tile_size) * tile_size
	)
