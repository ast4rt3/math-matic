# world.gd
extends Node2D

@onready var ground_layer: TileMapLayer = $GroundLayer
@onready var core: Node2D = $Core

# Building placement
var mine_scene = preload("res://Mine.tscn")
var placing_mine: bool = false
var mine_preview: Sprite2D = null

# Linking state
var link_source: Node = null  # the Mine we started linking from

# All drawn links (Line2D nodes)
var links: Array = []

func _ready():
	if has_node("UI/MineButton"):
		$UI/MineButton.pressed.connect(start_placing_mine)

func _process(delta: float):
	if placing_mine and mine_preview != null:
		mine_preview.global_position = get_global_mouse_position()

func _input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed:
		var world_pos = get_global_mouse_position()

		# --- RIGHT CLICK = cancel ---
		if event.button_index == MOUSE_BUTTON_RIGHT:
			placing_mine = false
			link_source = null
			if mine_preview:
				mine_preview.queue_free()
				mine_preview = null
			return

		# --- LEFT CLICK ---
		if event.button_index == MOUSE_BUTTON_LEFT:

			# If placing a mine, place it
			if placing_mine:
				_place_mine(world_pos)
				placing_mine = false
				if mine_preview:
					mine_preview.queue_free()
					mine_preview = null
				return

			# Otherwise, check if we clicked a Mine to start a link
			for child in get_children():
				# We identify a Mine by checking if it has an "OutputPort"
				if child.has_node("OutputPort") and child.name != "Core":
					if _clicked_node(child, world_pos):
						_create_link(child, core)
						return

func _place_mine(world_pos: Vector2):
	var mine = mine_scene.instantiate()
	mine.position = world_pos
	mine.linked_to = null
	add_child(mine)

func _create_link(mine: Node, target: Node):
	# Tell the mine who to send to
	mine.linked_to = target

	# Draw a Line2D between the two ports
	var line = Line2D.new()
	line.width = 3.0
	line.default_color = Color(0.2, 0.9, 1.0)  # cyan
	line.add_point(mine.get_node("OutputPort").global_position)
	line.add_point(target.get_node("InputPort").global_position)
	add_child(line)
	links.append(line)

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
