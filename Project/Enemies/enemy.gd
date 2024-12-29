extends CharacterBody3D

var health: int = 80
var alive: bool = true

func _physics_process(delta: float) -> void:
	if !alive: return
	
	if not is_on_floor():
		velocity += get_gravity() * delta
	
	move_and_slide()


func take_damage(value):
	if !alive: return
	
	$AnimationPlayer.play("hurt")
	
	health -= value
	if health <= 0: die()


func die():
	$AnimationPlayer.play("die")
	await $AnimationPlayer.animation_finished
	queue_free()
