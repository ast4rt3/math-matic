extends Node2D
class_name BuildingSystem

@export var grid_system: Node
@export var wire_system: Node2D

var miner_round_robin = {}

func tick_buildings(current_tick: int):
	for child in get_children():
		if child.has_node("OutputPort") and child.name != "Core":
			var is_miner = not child.has_method("can_receive")
			var ticks_per_gen = child.get("ticks_per_generation")
			if ticks_per_gen == null:
				ticks_per_gen = 5 if is_miner else 2
				
			if current_tick % ticks_per_gen != 0: continue
			if child.has_method("can_output") and not child.can_output(): continue
			
			var size = 32 if is_miner else 64
			var top_left = child.global_position - Vector2(size/2, size/2)
			var wire_tiles = size / 16
			
			var output_tiles = []
			for x in [-1, wire_tiles]:
				for y in range(wire_tiles): output_tiles.append(wire_system.pos_to_wire_tile(top_left + Vector2(x * 16 + 8, y * 16 + 8)))
			for y in [-1, wire_tiles]:
				for x in range(wire_tiles): output_tiles.append(wire_system.pos_to_wire_tile(top_left + Vector2(x * 16 + 8, y * 16 + 8)))
					
			var valid_outputs = []
			for t in output_tiles:
				if wire_system.wire_grid.has(t):
					var w = wire_system.wire_grid[t]
					var next_t = t + (w.dirs[0] if w.get_type() == "junction" and w.dirs.size() > 0 else w.dir)
					var points_into_me = false
					var b = wire_system.get_building_at(next_t)
					if b != null and b == child: points_into_me = true
						
					if not points_into_me: valid_outputs.append(t)
					
			if valid_outputs.size() > 0:
				if not miner_round_robin.has(child): miner_round_robin[child] = 0
				
				var start_idx = miner_round_robin[child]
				for i in range(valid_outputs.size()):
					var idx = (start_idx + i) % valid_outputs.size()
					var t = valid_outputs[idx]
					
					var w = wire_system.wire_grid[t]
					var mdir = w.dirs[0] if w.get_type() == "junction" and w.dirs.size() > 0 else w.dir
					
					var itm_check = { "value": 0, "progress": 0.0, "visual": null, "move_dir": mdir }
					if w.accept_item(itm_check, mdir):
						var val = 1
						if child.has_method("get_output_value"): val = child.get_output_value()
						if child.has_method("consume_output"): child.consume_output()
						
						var container = wire_system.get_item_visual(val)
						itm_check.value = val
						itm_check.visual = container
						
						miner_round_robin[child] = (idx + 1) % valid_outputs.size()
						
						# Bouncy feedback for the building
						if is_instance_valid(child):
							var tw = create_tween().set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
							tw.tween_property(child, "scale", Vector2(1.1, 1.1), 0.1)
							tw.tween_property(child, "scale", Vector2(1.0, 1.0), 0.3)
							
						break
