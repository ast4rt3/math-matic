extends Node2D
const ClassicWire = preload("res://wires/ClassicWire.gd")
const Junction = preload("res://wires/Junction.gd")

@onready var ground_layer: TileMapLayer = $GroundLayer
@onready var core: Node2D = $Core
@onready var camera: Camera2D = $Camera2D

const GridSystemScript = preload("res://GridSystem.gd")
const WireSystemScript = preload("res://WireSystem.gd")

var grid_system
var wire_system
var building_system

enum State { IDLE, PLACING_MINE, PLACING_ADDER, PLACING_TURRET, DRAWING_WIRE, DELETING }
var current_state: State = State.IDLE

var global_game_speed: float = 1.0 # 0.0 = pause, 2.0 = fast forward, etc.
var base_tick_rate: float = 0.1 # Global time unit (10 ticks per second)
var tick_accumulator: float = 0.0
var current_tick: int = 0

var mine_scene = preload("res://buildings/Mine.tscn")
var mine_preview: Sprite2D = null
var adder_scene = preload("res://buildings/Adder.tscn")
var adder_preview: Sprite2D = null
var turret_scene = preload("res://buildings/Turret.tscn")
var turret_preview: Node2D = null

var cursor_highlight: Sprite2D
var building_highlight: ReferenceRect
var wire_hover_highlight: ColorRect
var building_hover_highlight: ReferenceRect

var target_zoom: Vector2 = Vector2(1, 1)
var cam_pan_speed: float = 600.0
var original_offsets = {}
var tray_collapsed = false
var categories = ["Miner", "Math", "Attack", "Wires"]
var current_category_idx = 0
var wire_button: Button = null


func _ready():
	grid_system = GridSystemScript.new()
	add_child(grid_system)
	
	wire_system = WireSystemScript.new()
	wire_system.z_index = 10
	add_child(wire_system)
	
	grid_system.wire_system = wire_system
	
	building_system = BuildingSystem.new()
	building_system.grid_system = grid_system
	building_system.wire_system = wire_system
	add_child(building_system)
	wire_system.grid_system = grid_system
	
	var bounds_node = get_node_or_null("MapBounds")
	if bounds_node and bounds_node is ReferenceRect:
		grid_system.limit_left = bounds_node.global_position.x
		grid_system.limit_top = bounds_node.global_position.y
		grid_system.limit_right = grid_system.limit_left + bounds_node.size.x
		grid_system.limit_bottom = grid_system.limit_top + bounds_node.size.y
		bounds_node.visible = false 
	elif ground_layer and ground_layer.tile_set:
		var rect = ground_layer.get_used_rect()
		if rect.size.x > 0 and rect.size.y > 0:
			grid_system.setup_bounds(rect, ground_layer.tile_set.tile_size)
			
	if camera:
		camera.limit_left = int(grid_system.limit_left)
		camera.limit_top = int(grid_system.limit_top)
		camera.limit_right = int(grid_system.limit_right)
		camera.limit_bottom = int(grid_system.limit_bottom)
		
	cursor_highlight = Sprite2D.new()
	cursor_highlight.texture = preload("res://asset/wire.png")
	cursor_highlight.modulate.a = 0.5
	cursor_highlight.z_index = 100
	add_child(cursor_highlight)
	
	building_highlight = ReferenceRect.new()
	building_highlight.border_color = Color(1.0, 1.0, 1.0, 0.5)
	building_highlight.border_width = 2.0
	building_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	building_highlight.editor_only = false
	building_highlight.z_index = 99
	var b_bg = ColorRect.new()
	b_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b_bg.color = Color(1.0, 1.0, 1.0, 0.1)
	b_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	building_highlight.add_child(b_bg)
	add_child(building_highlight)
	
	wire_hover_highlight = ColorRect.new()
	wire_hover_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wire_hover_highlight.color = Color(1.0, 1.0, 1.0, 0.2)
	wire_hover_highlight.size = Vector2(16, 16)
	wire_hover_highlight.z_index = 100
	add_child(wire_hover_highlight)
	
	building_hover_highlight = ReferenceRect.new()
	building_hover_highlight.border_color = Color(1.0, 1.0, 1.0, 0.8)
	building_hover_highlight.border_width = 2.0
	building_hover_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	building_hover_highlight.editor_only = false
	building_hover_highlight.z_index = 100
	add_child(building_hover_highlight)


	if has_node("UI/CategoryTab"):
		$UI/CategoryTab.gui_input.connect(_on_category_tab_input)
		
	wire_button = Button.new()
	wire_button.text = "Wire"
	wire_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	wire_button.expand_icon = true
	if has_node("UI/MineButton"):
		var ref = get_node("UI/MineButton")
		wire_button.position = ref.position
		wire_button.size = ref.size
		wire_button.anchors_preset = ref.anchors_preset
		wire_button.anchor_top = ref.anchor_top
		wire_button.anchor_bottom = ref.anchor_bottom
		wire_button.icon = preload("res://asset/wire.png")
		wire_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		wire_button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	if has_node("UI"):
		$UI.add_child(wire_button)
	wire_button.pressed.connect(start_drawing_wire)
	
	update_category_ui()
	if has_node("UI"):
		$UI.offset = Vector2.ZERO
	if has_node("UI/MineButton"):
		$UI/MineButton.pressed.connect(start_placing_mine)
	if has_node("UI/AdderButton"):
		$UI/AdderButton.pressed.connect(start_placing_adder)
	if has_node("UI/TurretButton"):
		$UI/TurretButton.pressed.connect(start_placing_turret)
	if has_node("UI/DropdownBtn"):
		$UI/DropdownBtn.pressed.connect(_on_dropdown_pressed)
		$UI/DropdownBtn.pivot_offset = $UI/DropdownBtn.size / 2.0
		
	var ui_nodes = ["UI/BuildingTray", "UI/CategoryTab", "UI/DropdownBtn", "UI/Slot1", "UI/Slot2", "UI/Slot3", "UI/MineButton", "UI/AdderButton", "UI/TurretButton"]
	if wire_button: ui_nodes.append(wire_button.get_path())
	for node_path in ui_nodes:
		if has_node(node_path):
			var n = get_node(node_path)
			original_offsets[node_path] = { "top": n.offset_top, "bottom": n.offset_bottom }

		
	# Spawn a dummy enemy
	var enemy_scene = preload("res://buildings/EnemyDummy.tscn")
	var enemy = enemy_scene.instantiate()
	enemy.global_position = Vector2(0, -300)
	add_child(enemy)
	
	grid_system.grid_data.clear()
	grid_system.add_building(core, "core")
	for child in get_children():
		if child.has_node("OutputPort") and child.name != "Core":
			grid_system.add_building(child, "miner")
			child.reparent(building_system)
			
func start_drawing_wire():
	if current_state == State.DRAWING_WIRE:
		current_state = State.IDLE
		wire_system.preview_points.clear()
		wire_system.queue_redraw()
		return
	current_state = State.DRAWING_WIRE
	wire_system.preview_points.clear()
	if mine_preview:
		mine_preview.queue_free()
		mine_preview = null
	if adder_preview:
		adder_preview.queue_free()
		adder_preview = null
	if turret_preview:
		turret_preview.queue_free()
		turret_preview = null

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
	if adder_preview:
		adder_preview.queue_free()
		adder_preview = null
	if turret_preview:
		turret_preview.queue_free()
		turret_preview = null
		
	wire_system.preview_points.clear()
	wire_system.queue_redraw()

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
	if mine_preview:
		mine_preview.queue_free()
		mine_preview = null
	if turret_preview:
		turret_preview.queue_free()
		turret_preview = null
		
	wire_system.preview_points.clear()
	wire_system.queue_redraw()

func start_placing_turret():
	if current_state == State.PLACING_TURRET:
		current_state = State.IDLE
		if turret_preview:
			turret_preview.queue_free()
			turret_preview = null
		return
	current_state = State.PLACING_TURRET
	if turret_preview == null:
		turret_preview = turret_scene.instantiate()
		turret_preview.modulate.a = 0.5
		add_child(turret_preview)
	if mine_preview:
		mine_preview.queue_free()
		mine_preview = null
	if adder_preview:
		adder_preview.queue_free()
		adder_preview = null
		
	wire_system.preview_points.clear()
	wire_system.queue_redraw()

func _unhandled_input(event: InputEvent):
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
		if event.keycode == KEY_1:
			start_placing_mine()
		elif event.keycode == KEY_2:
			start_placing_adder()
		elif event.keycode == KEY_3:
			start_placing_turret()
		elif event.keycode == KEY_F3:
			wire_system.debug_mode = not wire_system.debug_mode
			wire_system.queue_redraw()
		elif event.keycode == KEY_E or event.keycode == KEY_Q:
			var mouse_pos = get_global_mouse_position()
			var tile_pos = wire_system.pos_to_wire_tile(mouse_pos)
			
			if wire_system.wire_grid.has(tile_pos):
				var existing = wire_system.wire_grid[tile_pos]
				if existing.get_type() == "wire":
					var w_idx = wire_system.WIRE_DIRS.find(existing.dir)
					if w_idx != -1:
						if event.keycode == KEY_E:
							w_idx = (w_idx + 1) % 8
						else:
							w_idx = (w_idx - 1 + 8) % 8
						existing.dir = wire_system.WIRE_DIRS[w_idx]
					wire_system.current_wire_dir_index = w_idx
					wire_system.queue_redraw()
			else:
				if event.keycode == KEY_E:
					wire_system.current_wire_dir_index = (wire_system.current_wire_dir_index + 1) % 8
				elif event.keycode == KEY_Q:
					wire_system.current_wire_dir_index = (wire_system.current_wire_dir_index - 1 + 8) % 8
			
	if event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE) and camera:
			camera.position -= event.relative / camera.zoom
			
		if current_state == State.DRAWING_WIRE and wire_system.preview_points.size() > 0:
			var target_tile = wire_system.pos_to_wire_tile(get_global_mouse_position())
			var last_tile = wire_system.preview_points[-1]
			
			if last_tile != target_tile:
				var t_pos = wire_system.wire_tile_to_pos(target_tile)
				if t_pos.x < grid_system.limit_left or t_pos.y < grid_system.limit_top or t_pos.x > grid_system.limit_right or t_pos.y > grid_system.limit_bottom:
					return
					
				var idx = wire_system.preview_points.find(target_tile)
				if idx != -1:
					wire_system.preview_points.resize(idx + 1)
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
						if not wire_system.preview_points.has(current):
							wire_system.preview_points.append(current)
				wire_system.queue_redraw()

	if event is InputEventMouseButton:
		var world_pos = get_global_mouse_position()
		var tile_pos = wire_system.pos_to_wire_tile(world_pos)

		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if current_state == State.PLACING_MINE:
				start_placing_mine()
				return
			if current_state == State.PLACING_ADDER:
				start_placing_adder()
				return
			if current_state == State.PLACING_TURRET:
				start_placing_turret()
				return
			if current_state == State.DRAWING_WIRE:
				start_drawing_wire()
				return
				
			var cell_4x4 = grid_system.pos_to_cell(world_pos)
			if grid_system.grid_data.has(cell_4x4) and (grid_system.grid_data[cell_4x4].type in ["miner", "adder", "turret"]):
				grid_system.remove_building(grid_system.grid_data[cell_4x4].ref)
				return
				
			if wire_system.wire_grid.has(tile_pos):
				wire_system.wire_grid[tile_pos].on_remove()
				wire_system.wire_grid.erase(tile_pos)
				wire_system.queue_redraw()
				return

		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if current_state == State.PLACING_MINE:
				var snapped_pos = grid_system.snap_building(world_pos)
				if grid_system.can_place_building(snapped_pos, "miner") and core.spend(1.0, 10):
					var mine = mine_scene.instantiate()
					mine.position = snapped_pos
					mine.linked_to = null
					building_system.add_child(mine)
					grid_system.add_building(mine, "miner")
				return
			if current_state == State.PLACING_ADDER:
				var snapped_pos = grid_system.snap_building(world_pos)
				if grid_system.can_place_building(snapped_pos, "adder") and core.spend(1.0, 20):
					var adder = adder_scene.instantiate()
					adder.position = snapped_pos
					building_system.add_child(adder)
					grid_system.add_building(adder, "adder")
				return
			if current_state == State.PLACING_TURRET:
				var snapped_pos = grid_system.snap_building(world_pos)
				if grid_system.can_place_building(snapped_pos, "turret") and core.spend(1.0, 50):
					var turret = turret_scene.instantiate()
					turret.position = snapped_pos
					building_system.add_child(turret)
					grid_system.add_building(turret, "turret")
				return
			if current_state == State.IDLE:
				start_drawing_wire()
			if current_state == State.DRAWING_WIRE:
				wire_system.preview_points.clear()
				wire_system.preview_points.append(tile_pos)
				wire_system.queue_redraw()

		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			if current_state == State.DRAWING_WIRE and wire_system.preview_points.size() > 0:
				for i in range(wire_system.preview_points.size()):
					var p = wire_system.preview_points[i]
					var center = wire_system.wire_tile_to_pos(p)
					var cell = grid_system.pos_to_cell(center)
					
					var dir = wire_system.WIRE_DIRS[wire_system.current_wire_dir_index]
					if wire_system.preview_points.size() > 1:
						if i < wire_system.preview_points.size() - 1:
							dir = wire_system.preview_points[i+1] - p
						elif i > 0:
							dir = p - wire_system.preview_points[i-1] 
						
					if grid_system.grid_data.has(cell) and grid_system.grid_data[cell].get("is_building", true):
						continue 
						
					if not wire_system.wire_grid.has(p):
						var cw = ClassicWire.new()
						cw.init(p, wire_system)
						cw.dir = dir
						wire_system.wire_grid[p] = cw
					else:
						var existing = wire_system.wire_grid[p]
						if existing.get_type() == "wire" and existing.dir != dir:
							var is_middle = (i > 0 and i < wire_system.preview_points.size() - 1)
							var next_t = p + existing.dir
							var existing_connected = wire_system.wire_grid.has(next_t) or wire_system.get_building_at(next_t) != null
							
							if is_middle or existing_connected:
								var j = Junction.new()
								j.init(p, wire_system)
								j.dirs.append(existing.dir)
								j.dirs.append(dir)
								if existing.item != null:
									j.items.append(existing.item)
								wire_system.wire_grid[p] = j
							else:
								existing.dir = dir
						elif existing.get_type() == "junction":
							if not dir in existing.dirs:
								existing.dirs.append(dir)
						
				wire_system.preview_points.clear()
				wire_system.queue_redraw()

func _process(delta: float):
	if camera:
		var move_dir = Vector2.ZERO
		if Input.is_key_pressed(KEY_W): move_dir.y -= 1
		if Input.is_key_pressed(KEY_S): move_dir.y += 1
		if Input.is_key_pressed(KEY_A): move_dir.x -= 1
		if Input.is_key_pressed(KEY_D): move_dir.x += 1
		if move_dir != Vector2.ZERO:
			camera.position += move_dir.normalized() * cam_pan_speed * delta * (1.0 / camera.zoom.x)
			
		var map_w = grid_system.limit_right - grid_system.limit_left
		var map_h = grid_system.limit_bottom - grid_system.limit_top
		var vp_size = get_viewport_rect().size
		
		var half_w = (vp_size.x / camera.zoom.x) / 2.0
		var half_h = (vp_size.y / camera.zoom.y) / 2.0
		
		camera.position.x = clamp(camera.position.x, grid_system.limit_left + half_w, grid_system.limit_right - half_w)
		camera.position.y = clamp(camera.position.y, grid_system.limit_top + half_h, grid_system.limit_bottom - half_h)
		
		var min_zoom_x = vp_size.x / map_w if map_w > 0 else 0.2
		var min_zoom_y = vp_size.y / map_h if map_h > 0 else 0.2
		var min_zoom = max(max(min_zoom_x, min_zoom_y), 0.2)
		
		target_zoom.x = clamp(target_zoom.x, min_zoom, 3.0)
		target_zoom.y = clamp(target_zoom.y, min_zoom, 3.0)
		camera.zoom = camera.zoom.lerp(target_zoom, 10.0 * delta)

	tick_accumulator += delta * global_game_speed
	while tick_accumulator >= base_tick_rate:
		tick_accumulator -= base_tick_rate
		current_tick += 1
		building_system.tick_buildings(current_tick)

	wire_system.process_items(delta, global_game_speed)
			
	if has_node("UI/MineButton"):
		$UI/MineButton.modulate = Color(0.2, 0.9, 1.0) if current_state == State.PLACING_MINE else Color(1, 1, 1)
	if has_node("UI/AdderButton"):
		$UI/AdderButton.modulate = Color(0.2, 0.9, 1.0) if current_state == State.PLACING_ADDER else Color(1, 1, 1)
	if has_node("UI/TurretButton"):
		$UI/TurretButton.modulate = Color(0.2, 0.9, 1.0) if current_state == State.PLACING_TURRET else Color(1, 1, 1)
		
	if has_node("UI/CurrencyLabel") and is_instance_valid(core):
		$UI/CurrencyLabel.text = "Currency:\n" + core.get_currency_text()
		
	var mouse_pos = get_global_mouse_position()
	var snapped_pos = wire_system.snap_to_grid(mouse_pos)
	var tile_pos = wire_system.pos_to_wire_tile(mouse_pos)
	var cell_pos = grid_system.pos_to_cell(mouse_pos)
	
	cursor_highlight.visible = false
	wire_hover_highlight.visible = false
	building_hover_highlight.visible = false
	building_highlight.visible = false
	
	if current_state == State.PLACING_MINE or current_state == State.PLACING_ADDER or current_state == State.PLACING_TURRET:
		var b_type = "miner"
		if current_state == State.PLACING_ADDER: b_type = "adder"
		elif current_state == State.PLACING_TURRET: b_type = "turret"
		var size = grid_system.get_building_size(b_type)
		building_highlight.global_position = grid_system.snap_building(mouse_pos) - Vector2(size/2, size/2)
		building_highlight.size = Vector2(size, size)
		building_highlight.visible = true
		if mine_preview:
			mine_preview.global_position = grid_system.snap_building(mouse_pos)
		if adder_preview:
			adder_preview.global_position = grid_system.snap_building(mouse_pos)
		if turret_preview:
			turret_preview.global_position = grid_system.snap_building(mouse_pos)
	else:
		var hovered_building = null
		if grid_system.grid_data.has(cell_pos):
			hovered_building = grid_system.grid_data[cell_pos].ref
			
		if hovered_building != null:
			var b_type = grid_system.grid_data[cell_pos].type
			var size = grid_system.get_building_size(b_type)
			building_hover_highlight.global_position = hovered_building.global_position - Vector2(size/2, size/2)
			building_hover_highlight.size = Vector2(size, size)
			building_hover_highlight.visible = true
		elif wire_system.wire_grid.has(tile_pos):
			wire_hover_highlight.global_position = snapped_pos - Vector2(8, 8)
			wire_hover_highlight.visible = true
		else:
			cursor_highlight.global_position = snapped_pos
			
			if current_state == State.DRAWING_WIRE and wire_system.preview_points.size() > 1:
				var last_dir = wire_system.preview_points[-1] - wire_system.preview_points[-2]
				var w_idx = wire_system.WIRE_DIRS.find(last_dir)
				if w_idx != -1:
					wire_system.current_wire_dir_index = w_idx
					
			var current_dir_vec = wire_system.WIRE_DIRS[wire_system.current_wire_dir_index]
			cursor_highlight.rotation = Vector2(current_dir_vec).angle()
			cursor_highlight.visible = true


func _on_dropdown_pressed():
	tray_collapsed = !tray_collapsed
	var shift = 128.0 if tray_collapsed else 0.0
	var tween = create_tween()
	tween.set_parallel(true)
	for node_path in original_offsets:
		var n = get_node(node_path)
		tween.tween_property(n, "offset_top", original_offsets[node_path].top + shift, 0.2).set_trans(Tween.TRANS_SINE)
		tween.tween_property(n, "offset_bottom", original_offsets[node_path].bottom + shift, 0.2).set_trans(Tween.TRANS_SINE)
	tween.tween_property($UI/DropdownBtn, "rotation_degrees", 180.0 if tray_collapsed else 0.0, 0.2)


func _on_category_tab_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		current_category_idx = (current_category_idx + 1) % categories.size()
		update_category_ui()

func update_category_ui():
	var cat = categories[current_category_idx]
	if has_node("UI/CategoryTab/CategoryLabel"):
		$UI/CategoryTab/CategoryLabel.text = cat
		
	if has_node("UI/MineButton"): $UI/MineButton.visible = (cat == "Miner")
	if has_node("UI/AdderButton"): 
		$UI/AdderButton.visible = (cat == "Math")
		if cat == "Math":
			$UI/AdderButton.position = $UI/MineButton.position
	if has_node("UI/TurretButton"): 
		$UI/TurretButton.visible = (cat == "Attack")
		if cat == "Attack":
			$UI/TurretButton.position = $UI/MineButton.position
			
	if wire_button:
		wire_button.visible = (cat == "Wires")
		if cat == "Wires":
			wire_button.position = $UI/MineButton.position
