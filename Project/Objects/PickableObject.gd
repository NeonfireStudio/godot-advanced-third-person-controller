extends StaticBody3D

@export_enum("Small", "Medium", "Large") var size := "Small"
@export var collision_shape : CollisionShape3D

func get_size() -> String:
	#Medium and Large size is in development.
	return size

func disabled_collisions():
	collision_shape.disabled = true
