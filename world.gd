extends Node2D

@onready var ground_layer: TileMapLayer = $GroundLayer

func _ready():
	# Convert a world position (pixels) to a grid cell
	var cell = ground_layer.local_to_map(Vector2(128, 64))
	print("Tile at grid pos: ", cell)
	
	# Get what tile ID is at that cell
	var tile_data = ground_layer.get_cell_tile_data(cell)
	if tile_data:
		print("Tile exists here")
	else:
		print("Empty cell")
