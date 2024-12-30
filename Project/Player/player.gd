extends CharacterBody3D
class_name Player

# Movement Settings
@export_group("Movement Settings")
@export var walking_speed : float = 5.0
@export var running_speed : float = 8.0
@export var crouching_speed : float = 2.5
@export var backward_speed_divide_by : float = 1.25
@export var sliding_speed : float = 10.0
@export var jump_force : float = 4.5
@export_range(0, 35) var walk_lean_amount : float = 5.0
@export_range(0, 35) var run_lean_amount : float = 15.0
@export var single_slide_type : bool = false
@export_enum("Roll", "Slide") var slide_type = "Roll"
@export_range(0.05, 9999) var slide_delay = 0.5
@export var rolling_duration : float = 1.35 #0.8
@export var sliding_duration : float = 1.5
@export var fall_roll_height : float = 10

# Camera Settings
@export_group("Camera Settings")
@export var sensitivity : float = 0.005
@export var min_look_up : float = -90.0
@export var max_look_up : float = 90.0
@export var default_fov : float = 75.0
@export var zoomed_fov : float = 70.0
@export var zoom_speed : float = 0.25

# Action Settings
@export_group("Action Settings")
@export var can_jump_while_crouched: bool = true
@export var lerp_speed: float = 10.0
@export var melee_power: int = 20
@export var attack_cooldown: float = 1.1
@export_enum("Roll", "HardLand") var fall_action: String = "HardLand"
@export var hard_land_delay: float = 1.2

# Other Settings
@export_group("Other Settings")
@export var hand_attachment: BoneAttachment3D

# OnReady Variables (Initial setup)
@onready var model: Node3D = $Model

@onready var collision_shape: CollisionShape3D = $NormalCollision
@onready var crouched_collision: CollisionShape3D = $CrouchedCollision
@onready var sliding_collision: CollisionShape3D = $SlidingCollision

@onready var camera_pivot: SpringArm3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera

@onready var movement_dir: Marker3D = $MovementDir

@onready var animation_tree: AnimationTree = $AnimationTree

@onready var footstep_sound: AudioStreamPlayer3D = $FootstepSound

@onready var object_detector: ShapeCast3D = $ObjectDetector
@onready var roof_detector: RayCast3D = $RoofDetector
@onready var floor_detector: RayCast3D = $FloorDetector

@onready var enemy_detector: ShapeCast3D = $EnemyDetector

@onready var sliding_timer: Timer = $SlidingTimer
@onready var pickup_timer: Timer = $PickupTimer
@onready var combo_timer: Timer = $ComboTimer

# Movement Variables
var current_speed : float = 5.0

#Different States of Movement (Variables)
var is_running : bool = false
var is_crouching : bool = false
var is_strafing : bool = false

# Action Variables
var is_rolling : bool = false
var is_picking_object : bool = false
var is_hard_landing : bool = false

# Additional Variables
var can_roll : bool = true
var can_attack : bool = true

var previous_velocity : Vector3 = Vector3.ZERO  # Previous velocity for movement calculations
var last_input_dir : Vector2 = Vector2.ZERO # Last input direction for movement

var previous_speed : float = 0.0 # Previous speed

var object : Node3D = null # Object the character is interacting with

var initial_rotation : float = 0  # Initial character rotation in y-axis
var combo_count : int = 0 # Combo counter for attacks

# Multiplayer authority setup
func _enter_tree() -> void:
	set_multiplayer_authority(str(name).to_int())

func _ready() -> void:
	# Store the initial rotation value
	initial_rotation = rotation.y
	
	# Adjust the model and camera pivot rotation to match the initial rotation
	model.rotation.y += initial_rotation
	camera_pivot.rotation.y += initial_rotation
	
	# Reset the player's rotation on the Y-axis
	rotation.y = 0
	
	# Exit the function if this is not the multiplayer authority and multiplayer is active
	if not is_multiplayer_authority() and Global.multiplayer_type != "None":
		return
	
	# Set the mouse mode to captured for gameplay
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Set the initial Y position
	position.y = 5
	
	# Set this camera as the active camera
	camera.current = true

func _input(event: InputEvent) -> void:
	# Exit early if not the multiplayer authority and multiplayer is active
	if not is_multiplayer_authority() and Global.multiplayer_type != "None":
		return
	
	# Handle mouse motion events
	if event is InputEventMouseMotion:
		# Rotate the camera pivot around the Y-axis based on horizontal mouse movement
		camera_pivot.rotate_y(-event.relative.x * sensitivity)
	
		# Adjust the camera pivot's X-axis rotation based on vertical mouse movement
		camera_pivot.rotation.x += -event.relative.y * sensitivity
	
		# Clamp the X-axis rotation to ensure it stays within the allowed look-up/down range
		camera_pivot.rotation.x = clamp(
			camera_pivot.rotation.x, 
			deg_to_rad(min_look_up), 
			deg_to_rad(max_look_up)
		)

func _physics_process(delta: float) -> void:
	# Early exit for non-authority clients in multiplayer
	if not is_multiplayer_authority() and Global.multiplayer_type != "None": return
	
	# Handle menu return action
	if Input.is_action_just_pressed("ui_text_completion_replace"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		#get_tree().change_scene_to_file("res://Menu/menu.tscn")
		return
	
	# Update movement direction to match the camera
	movement_dir.rotation = camera_pivot.rotation
	movement_dir.rotation.x = 0
	
	# Check if strafing
	is_strafing = Input.is_action_pressed("right_mouse")
	
	# Smoothly adjust the camera's field of view for zooming
	camera.fov = lerpf(camera.fov, zoomed_fov if Input.is_action_pressed("right_mouse") else default_fov, delta*10.0)
	
	# Handle landing after a fall
	if is_on_floor() and previous_velocity.y < -fall_roll_height:
		if fall_action == "HardLand":
			hard_land()
		else:
			slide(delta)
	
	# Save the previous velocity
	previous_velocity = velocity
	
	# Apply gravity if in the air
	if not is_on_floor():
		velocity += get_gravity() * delta
	
	# Handle jumping
	if Input.is_action_pressed("jump") and is_on_floor() and (can_jump_while_crouched or !is_crouching) and !is_rolling and !is_hard_landing:
		velocity.y = jump_force
		set_animation("parameters/Jumping/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE, delta, -1)
	
	# Determine current speed based on sprinting
	if Input.is_action_pressed("sprint") and not is_strafing:
		current_speed = running_speed
	else:
		current_speed = walking_speed
	
	# Toggle crouching
	if Input.is_action_just_pressed("crouch") and is_on_floor() and !roof_detector.is_colliding():
		is_crouching = !is_crouching
	
	# Adjust speed and collision shape for crouching or rolling
	if is_crouching: current_speed = crouching_speed
	
	crouched_collision.disabled = !is_crouching
	sliding_collision.disabled = !is_rolling
	if !crouched_collision.disabled and is_rolling:
		crouched_collision.disabled = true
	elif !sliding_collision.disabled and is_crouching:
		sliding_collision.disabled = true
	
	collision_shape.disabled = is_crouching or is_rolling
	
	# Handle rolling or sliding actions
	if Input.is_action_just_pressed("roll"):
		if !single_slide_type: slide_type = "Roll"
		slide(delta)
	elif Input.is_action_just_pressed("slide") and not single_slide_type:
		slide_type = "Slide"
		slide(delta)
	
	# Adjust speed and animation during rolling
	if is_rolling:
		is_running = false
		current_speed = sliding_speed
		is_strafing = false
	
	# Get input direction vector
	var input_dir := Input.get_vector("left", "right", "forward", "backward")
	
	# Ignore input while hard landing
	if is_hard_landing:
		input_dir = Vector2.ZERO
	
	# Update input direction for rolling or normal state
	if is_rolling:
		input_dir = last_input_dir if last_input_dir != Vector2.ZERO else Vector2.UP
	else:
		if input_dir != Vector2.ZERO: last_input_dir = input_dir
	
	# Calculate movement direction
	var direction := (movement_dir.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		# Adjust velocity based on speed and direction
		if current_speed >= running_speed-0.1 and (current_speed != sliding_speed and !is_rolling): is_running = true
		if current_speed == walking_speed and velocity.length() > 6.75: is_running = false
		velocity.x = direction.x * current_speed / (backward_speed_divide_by if input_dir.y == 1 else 1.0)
		velocity.z = direction.z * current_speed / (backward_speed_divide_by if input_dir.y == 1 else 1.0)
		
		# Reset certain animations
		set_animation("parameters/EmotesState/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT, delta, -1)
		set_animation("parameters/JustStop/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT, delta, -1)
	else:
		# Gradually stop velocity when no input
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)
		
		# Handle emote animations
		if Input.is_action_just_pressed("emote_1"):
			set_animation("parameters/Emotes/transition_request", "Yes", delta, -1)
			set_animation("parameters/EmotesState/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE, delta, -1)
		elif Input.is_action_just_pressed("emote_2"):
			set_animation("parameters/Emotes/transition_request", "No", delta, -1)
			set_animation("parameters/EmotesState/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE, delta, -1)
		elif Input.is_action_just_pressed("emote_3"):
			set_animation("parameters/Emotes/transition_request", "Wave", delta, -1)
			set_animation("parameters/EmotesState/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE, delta, -1)
		elif Input.is_action_just_pressed("emote_4"):
			set_animation("parameters/Emotes/transition_request", "WaveBH", delta, -1)
			set_animation("parameters/EmotesState/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE, delta, -1)
		
		# Play just stop animation when character stops after running
		if is_running:
			is_running = false
			if !is_rolling and !is_picking_object: set_animation("parameters/JustStop/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE, delta, -1)
	
	# Handle strafing and character rotation
	if !is_picking_object:
		if is_strafing:
			model.rotation.y = lerp_angle(model.rotation.y, movement_dir.rotation.y, delta * 10.0)
			model.rotation.x = lerp_angle(model.rotation.x, input_dir.y * 0.125, delta * 10.0)
			#model.rotation.z = lerp_angle(model.rotation.z, input_dir.x * 0.35, delta * 10.0)
		else:
			model.rotation.x = lerp_angle(model.rotation.x, 0.0, delta * 10.0)
			if direction: model.rotation.y = lerp_angle(model.rotation.y, atan2(-velocity.x, -velocity.z), delta * 10.0)
	
	# Update enemy detector position
	if direction: enemy_detector.position = lerp(enemy_detector.position, Vector3(1.315 * direction.x, 0, 1.315 * direction.z), delta*10.0)
	
	# Handle object picking
	if is_picking_object:
		velocity.x = 0
		if velocity.y > 0: velocity.y = 0
		velocity.z = 0
		
		if object != null: object.position = lerp(object.position, Vector3.ZERO, delta*10.0)
	
	# Apply movement
	move_and_slide()
	
	# Handle model lean while moving
	if input_dir and !is_strafing and !is_crouching and !is_picking_object:
		model.rotation.z = lerp_angle(model.rotation.z, atan2(-velocity.x, -velocity.z) - model.rotation.y, delta*lerp_speed)
		
		if Input.is_action_pressed("sprint"):
			model.rotation.z = clampf(model.rotation.z, deg_to_rad(-run_lean_amount), deg_to_rad(run_lean_amount))
		else:
			model.rotation.z = clampf(model.rotation.z, deg_to_rad(-walk_lean_amount), deg_to_rad(walk_lean_amount))
	else:
		model.rotation.z = lerp_angle(model.rotation.z, 0.0, delta*lerp_speed)
	
	# Update animation blend positions
	var blend = input_dir.normalized()
	
	if blend.x > 0.1:
		blend.x = 1
	elif blend.x < -0.1:
		blend.x = -1
	if blend.y > 0.1:
		blend.y = -1
	elif blend.y < -0.1:
		blend.y = 1
	
	# Apply animation blend for strafing
	if is_strafing:
		set_animation("parameters/StrafeMovement/blend_position", blend, delta, 0)
	
	# Apply animation blend for crouching
	if is_crouching: set_animation("parameters/Crouch/blend_position", blend, delta, 0)
	
	# Apply animation blend based on speed
	set_animation("parameters/Movement/blend_amount", -1 if blend.length() < 0.01 else (1 if current_speed == running_speed else 0), delta, 1)
	
	# Set movement type animation blend (based on whether crouching or not)
	set_animation("parameters/MovementType/blend_amount", (float(!is_strafing)-1) if !is_crouching else 1.0, delta, 1)
	
	# Set the animation for the "OnAir" state based on whether the character is on the floor or not
	set_animation("parameters/OnAir/blend_amount", int(!is_on_floor()), delta, 1)
	
	# Handle camera zoom
	if Input.is_action_just_pressed("scroll_up"):
		camera_pivot.spring_length -= zoom_speed
	elif Input.is_action_just_pressed("scroll_down"):
		camera_pivot.spring_length += zoom_speed
	
	# Clamp the zoom level
	camera_pivot.spring_length = clampf(camera_pivot.spring_length, 1, 10)
	
	# Handle interaction with objects
	if Input.is_action_just_pressed("interact") and !is_picking_object and is_on_floor():
		for i in object_detector.get_collision_count():
			var body = object_detector.get_collider(i) as Node3D
			if body.is_in_group("Pickable"):
				is_picking_object = true
				pickup_timer.start()
				set_animation("parameters/PickObject/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE, delta, -1)
				body.disabled_collisions()
				await get_tree().create_timer(0.2).timeout
				body.reparent(hand_attachment)
				object = body
				break
	
	# Adjust the footstep sound pitch based on the current speed and whether strafing is happening
	if is_strafing and current_speed == walking_speed:
		footstep_sound.pitch_scale = 0.3
	else:
		match current_speed:
			walking_speed:
				footstep_sound.pitch_scale = 0.1925
			running_speed:
				footstep_sound.pitch_scale = 0.26
			crouching_speed:
				footstep_sound.pitch_scale = 0.185
	
	# Check if the player is colliding with a floor surface
	if floor_detector.is_colliding():
		var floor_body = floor_detector.get_collider() as Node3D
		
		# If the surface is grass, change the footstep sound to grass sound
		if floor_body.is_in_group("Grass"):
			if footstep_sound.stream != load("res://Assets/Audios/footstep_grass_000.ogg"):
				footstep_sound.stop()
				footstep_sound.stream = load("res://Assets/Audios/footstep_grass_000.ogg")
			
			# Adjust footstep pitch based on movement speed
			footstep_sound.pitch_scale += 1.2 if current_speed != running_speed else 2.0
		
		# If the surface is concrete, change the footstep sound to concrete sound
		elif floor_body.is_in_group("Concrete"):
			if footstep_sound.stream != load("res://Assets/Audios/footstep_concrete_001.ogg"):
				footstep_sound.stop()
				footstep_sound.stream = load("res://Assets/Audios/footstep_concrete_001.ogg")
		else:
			#As default footstep sound
			if footstep_sound.stream != load("res://Assets/Audios/footstep_concrete_001.ogg"):
				footstep_sound.stop()
				footstep_sound.stream = load("res://Assets/Audios/footstep_concrete_001.ogg")
	
	# Play footstep sound if it's not playing, not rolling, on the floor, moving, and not picking up an object
	if footstep_sound.playing == false and !is_rolling and is_on_floor() and input_dir != Vector2.ZERO and !is_picking_object:
		footstep_sound.play()
	
	# Trigger an attack if the attack action is pressed and the player can attack
	if Input.is_action_pressed("attack") and can_attack:
		attack()


# Sets the animation based on the path and value, with a linear interpolation (lerp)
func set_animation(path, value, delta, lerp_type) -> void:
	match lerp_type:
		# No interpolation, directly set the value
		-1:
			animation_tree.set(path, value)
		
		# Linear interpolation between current and target value with delta
		0:
			animation_tree.set(path, lerp(animation_tree.get(path), value, delta*10.0))
		
		# Smooth interpolation with ease, using lerpf
		1:
			animation_tree.set(path, lerpf(animation_tree.get(path), value, delta*10.0))
	
	# RPC call to sync animation across multiplayer
	rpc("set_anim_multiplayer", path, value, delta, lerp_type)


# Remote procedure call (RPC) to sync animation in multiplayer
@rpc() func set_anim_multiplayer(path: String, value, delta: float, lerp_type: int) -> void:
	# Check if the player has multiplayer authority
	if !is_multiplayer_authority():
		match lerp_type:
			# No interpolation, directly set the value
			-1:
				animation_tree.set(path, value)
			
			# Linear interpolation between current and target value with delta
			0:
				animation_tree.set(path, lerp(animation_tree.get(path), value, delta*10.0))
			
			# Smooth interpolation with ease, using lerpf
			1:
				animation_tree.set(path, lerpf(animation_tree.get(path), value, delta*10.0))


# Called when the roll timer times out (ends)
func _on_sliding_timer_timeout() -> void:
	is_rolling = false
	
	# Check if the character is colliding with a roof, then crouch
	if roof_detector.is_colliding():
		is_crouching = true
	
	# Create a delay before allowing another roll
	await get_tree().create_timer(slide_delay).timeout
	can_roll = true


# Called when the pickup timer times out (ends)
func _on_pickup_timer_timeout() -> void:
	is_picking_object = false
	
	# Free the object and reset reference
	object.queue_free()
	object = null #... Just be sure


# Handles the character sliding action
func slide(delta: float) -> void:
	 # Only allow sliding if the character can roll and is on the floor
	if not (can_roll and is_on_floor()): return
	
	can_roll = false
	is_rolling = true
	
	# Trigger animations for sliding and ground state change
	set_animation("parameters/GroundMoves/transition_request", slide_type, delta, -1)
	set_animation("parameters/GroundState/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE, delta, -1)
	
	# Start the roll timer
	sliding_timer.wait_time = sliding_duration if slide_type == "Slide" else rolling_duration
	sliding_timer.start()


# Initiates the character's attack
func attack() -> void:
	# Reset combo count if it exceeds 1
	if combo_count > 1: combo_count = 0
	
	# Set the appropriate animation for the attack based on combo count
	set_animation("parameters/Melee/transition_request", ("Punch1" if combo_count == 0 else "Punch2"), 0.0, -1)
	set_animation("parameters/Attack/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE, 0.0, -1)
	
	# Increment combo count and start the combo timer
	combo_count += 1
	combo_timer.start()
	
	# Disable attack until cooldown finishes
	can_attack = false
	await get_tree().create_timer(attack_cooldown).timeout
	can_attack = true


# Triggers an attack if the player collides with an enemy
func trigger_attack() -> void:
	# Check if the enemy detector is colliding
	if enemy_detector.is_colliding():
		for i in range(enemy_detector.get_collision_count()):
			var body = enemy_detector.get_collider(i)
			
			# If the collider is an enemy, apply damage
			if body != null: if body.is_in_group("Enemy"): body.take_damage(20)


# Returns the player's rotation
func get_player_rotation() -> Vector3:
	return model.rotation


func set_player_rotation(rot) -> void:
	initial_rotation = rot

# Triggers a hard landing animation
func hard_land() -> void:
	animation_tree.set("parameters/HardLand/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	is_hard_landing = true
	await get_tree().create_timer(hard_land_delay).timeout
	is_hard_landing = false


# Resets combo count when the combo timer times out
func _on_combo_timer_timeout() -> void:
	combo_count = 0
