extends Node2D

var ammo: int = 0
var fire_rate_buff: float = 0.0
var damage_buff: float = 0.0

var base_fire_rate: float = 1.0 # 1 shot per second
var base_damage: float = 1.0

var time_since_last_shot: float = 0.0
var target: Node2D = null

@onready var head = $Head
@onready var muzzle = $Head/Muzzle

var bullet_scene = preload("res://buildings/Bullet.tscn")

func _ready():
	add_to_group("turrets")

func _process(delta: float):
	if target == null or not is_instance_valid(target):
		_find_target()
		
	if target != null and is_instance_valid(target):
		var dir = (target.global_position - head.global_position).normalized()
		var target_angle = dir.angle() + PI / 2.0
		head.rotation = lerp_angle(head.rotation, target_angle, 10.0 * delta)
		
		var current_fire_rate = max(0.1, base_fire_rate - fire_rate_buff)
		time_since_last_shot += delta
		
		if time_since_last_shot >= current_fire_rate and ammo > 0:
			shoot()

func _find_target():
	var enemies = get_tree().get_nodes_in_group("enemies")
	if enemies.size() > 0:
		target = enemies[0] # Just grab the first one for now

func shoot():
	ammo -= 1
	time_since_last_shot = 0.0
	
	var bullet = bullet_scene.instantiate()
	bullet.global_position = muzzle.global_position
	bullet.rotation = head.rotation - PI / 2.0
	bullet.damage = base_damage + damage_buff
	get_tree().current_scene.add_child(bullet)

func can_receive(source: Vector2i) -> bool:
	return true # Can always receive items

func receive(val: float, source: Vector2i):
	if val == 1.0:
		ammo += 1
	elif val < 0:
		fire_rate_buff += abs(val) * 0.1 # Example buff scaling
	elif val > 1:
		damage_buff += val
