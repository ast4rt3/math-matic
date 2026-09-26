# buildings/Mine.gd
extends Node2D

var output_value: float = 1.0
var linked_to: Node = null  # reference to Core (or any building)

@onready var output_port = $OutputPort
