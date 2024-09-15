extends CharacterBody3D
class_name Player

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
@export var fall_roll_height : float = 10

@export_group("Camera Settings")
@export var sensitivity : float = 0.005
@export var min_look_up : float = -90.0
@export var max_look_up : float = 90.0
@export var default_fov : float = 75.0
@export var zoomed_fov : float = 70.0
@export var zoom_speed : float = 0.25

@export_group("Other Settings")
@export var can_jump_while_crouch : bool = true
@export var lerp_speed : float = 10.0
@export var hand_palm : BoneAttachment3D

@onready var model: Node3D = $Model
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

@onready var camera_pivot: SpringArm3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera

@onready var movement_dir: Marker3D = $MovementDir

@onready var animation_tree: AnimationTree = $AnimationTree

@onready var footstep_sound: AudioStreamPlayer3D = $FootstepSound

@onready var object_detector: ShapeCast3D = $ObjectDetector
@onready var roof_detector: RayCast3D = $RoofDetector
@onready var floor_detector: RayCast3D = $FloorDetector

var current_speed : float = 5.0

var is_running : bool = false
var is_crouching : bool = false

var is_strafing : bool = false
var is_rolling : bool = false

var can_roll : bool = true

var previous_velocity : Vector3 = Vector3.ZERO
var last_input_dir : Vector2 = Vector2.ZERO

var previous_speed : float = 0.0

var is_picking_object : bool = false

var object : Node3D = null

func _enter_tree() -> void:
	set_multiplayer_authority(str(name).to_int())

func _ready() -> void:
	if not is_multiplayer_authority() and Global.multiplayer_type != "None": return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	position.y = 5
	camera.current = true

func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority() and Global.multiplayer_type != "None": return
	
	if event is InputEventMouseMotion:
		camera_pivot.rotate_y(-event.relative.x * sensitivity)
		camera_pivot.rotation.x += -event.relative.y * sensitivity
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, deg_to_rad(min_look_up), deg_to_rad(max_look_up))

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority() and Global.multiplayer_type != "None": return
	
	if Input.is_action_just_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().change_scene_to_file("res://Menu/menu.tscn")
		return
	
	movement_dir.rotation = camera_pivot.rotation
	movement_dir.rotation.x = 0
	
	is_strafing = Input.is_action_pressed("right_mouse")
	
	camera.fov = lerpf(camera.fov, zoomed_fov if Input.is_action_pressed("right_mouse") else default_fov, delta*10.0)
	
	if is_on_floor() and previous_velocity.y < -fall_roll_height:
		slide(delta)
	
	previous_velocity = velocity
	
	if not is_on_floor():
		velocity += get_gravity() * delta
	
	if Input.is_action_pressed("jump") and is_on_floor() and (can_jump_while_crouch or !is_crouching) and !is_rolling:
		velocity.y = jump_force
		set_animation("parameters/Jumping/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE, delta, -1)
	
	if Input.is_action_pressed("sprint") and not is_strafing:
		current_speed = running_speed
	else:
		current_speed = walking_speed
	
	if Input.is_action_just_pressed("crouch") and is_on_floor() and !roof_detector.is_colliding():
		is_crouching = !is_crouching
	
	if is_crouching: current_speed = crouching_speed
	
	if is_crouching or is_rolling:
		collision_shape.shape.size.y = 1.732
		collision_shape.position.y = -0.074
	else:
		collision_shape.shape.size.y = 2.035
		collision_shape.position.y = 0.077
	
	if Input.is_action_just_pressed("roll"):
		if !single_slide_type: slide_type = "Roll"
		slide(delta)
	elif Input.is_action_just_pressed("slide") and not single_slide_type:
		slide_type = "Slide"
		slide(delta)
	
	if is_rolling:
		is_running = false
		current_speed = sliding_speed
		is_strafing = false
	
	var input_dir := Input.get_vector("left", "right", "forward", "backward")
	
	if is_rolling:
		input_dir = last_input_dir if last_input_dir != Vector2.ZERO else Vector2.UP
	else:
		if input_dir != Vector2.ZERO: last_input_dir = input_dir
	
	var direction := (movement_dir.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		if current_speed >= running_speed-2 and (current_speed != sliding_speed and !is_rolling): is_running = true
		if current_speed == walking_speed and velocity.length() > 6.75: is_running = false
		velocity.x = direction.x * current_speed / (backward_speed_divide_by if input_dir.y == 1 else 1.0)
		velocity.z = direction.z * current_speed / (backward_speed_divide_by if input_dir.y == 1 else 1.0)
		
		set_animation("parameters/EmotesState/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT, delta, -1)
		set_animation("parameters/JustStop/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT, delta, -1)
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)
		
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
	
		if is_running:
			is_running = false
			if !is_rolling: set_animation("parameters/JustStop/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE, delta, -1)
	
	if !is_picking_object:
		if is_strafing:
			model.rotation.y = lerp_angle(model.rotation.y, movement_dir.rotation.y, delta * 10.0)
		else:
			if direction: model.rotation.y = lerp_angle(model.rotation.y, atan2(-velocity.x, -velocity.z), delta * 10.0)
	
	if is_picking_object:
		velocity.x = 0
		if velocity.y > 0: velocity.y = 0
		velocity.z = 0
		
		if object != null: object.position = lerp(object.position, Vector3.ZERO, delta*10.0)
	
	move_and_slide()
	
	if input_dir and !is_strafing and !is_crouching and !is_picking_object:
		model.rotation.z = lerp_angle(model.rotation.z, atan2(-velocity.x, -velocity.z) - model.rotation.y, delta*lerp_speed)
		
		if Input.is_action_pressed("sprint"):
			model.rotation.z = clampf(model.rotation.z, deg_to_rad(-run_lean_amount), deg_to_rad(run_lean_amount))
		else:
			model.rotation.z = clampf(model.rotation.z, deg_to_rad(-walk_lean_amount), deg_to_rad(walk_lean_amount))
	else:
		model.rotation.z = lerp_angle(model.rotation.z, 0.0, delta*lerp_speed)
	
	var blend = input_dir.normalized()
	
	if blend.x > 0.1:
		blend.x = 1
	elif blend.x < -0.1:
		blend.x = -1
	if blend.y > 0.1:
		blend.y = -1
	elif blend.y < -0.1:
		blend.y = 1
	
	if is_strafing:
		set_animation("parameters/StrafeMovement/blend_position", blend, delta, 0)
	
	if is_crouching: set_animation("parameters/Crouch/blend_position", blend, delta, 0)
	
	set_animation("parameters/Movement/blend_amount", -1 if blend.length() < 0.01 else (1 if current_speed == running_speed else 0), delta, 1)
	
	set_animation("parameters/MovementType/blend_amount", (float(!is_strafing)-1) if !is_crouching else 1.0, delta, 1)
	
	set_animation("parameters/OnAir/blend_amount", int(!is_on_floor()), delta, 1)
	
	if Input.is_action_just_pressed("scroll_up"):
		camera_pivot.spring_length -= zoom_speed
	elif Input.is_action_just_pressed("scroll_down"):
		camera_pivot.spring_length += zoom_speed
	
	camera_pivot.spring_length = clampf(camera_pivot.spring_length, 1, 10)
	
	if Input.is_action_just_pressed("interact") and !is_picking_object and is_on_floor():
		for i in object_detector.get_collision_count():
			var body = object_detector.get_collider(i) as Node3D
			if body.is_in_group("Pickable"):
				is_picking_object = true
				$PickupTimer.start()
				set_animation("parameters/PickObject/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE, delta, -1)
				body.disabled_collisions()
				await get_tree().create_timer(1).timeout
				body.reparent(hand_palm)
				object = body
				break
	
	if is_strafing and current_speed == walking_speed:
		footstep_sound.pitch_scale = 0.3
	else:
		match current_speed:
			walking_speed:
				footstep_sound.pitch_scale = 0.1925
			running_speed:
				footstep_sound.pitch_scale = 0.35
			crouching_speed:
				footstep_sound.pitch_scale = 0.2
	
	if floor_detector.is_colliding():
		var floor_body = floor_detector.get_collider() as Node3D
		if floor_body.is_in_group("Grass"):
			if footstep_sound.stream != load("res://Assets/Audios/footstep_grass_000.ogg"):
				footstep_sound.stop()
				footstep_sound.stream = load("res://Assets/Audios/footstep_grass_000.ogg")
			footstep_sound.pitch_scale += 1.2 if current_speed != running_speed else 2.0
		elif floor_body.is_in_group("Concrete"):
			if footstep_sound.stream != load("res://Assets/Audios/footstep_concrete_001.ogg"):
				footstep_sound.stop()
				footstep_sound.stream = load("res://Assets/Audios/footstep_concrete_001.ogg")
	
	if footstep_sound.playing == false and !is_rolling and is_on_floor() and input_dir != Vector2.ZERO and !is_picking_object:
		footstep_sound.play()

func set_animation(path, value, delta, lerp_type) -> void:
	match lerp_type:
		-1:
			animation_tree.set(path, value)
		0:
			animation_tree.set(path, lerp(animation_tree.get(path), value, delta*10.0))
		1:
			animation_tree.set(path, lerpf(animation_tree.get(path), value, delta*10.0))
	
	rpc("set_anim_multiplayer", path, value, delta, lerp_type)

@rpc() func set_anim_multiplayer(path, value, delta, lerp_type):
	if !is_multiplayer_authority():
		match lerp_type:
			-1:
				animation_tree.set(path, value)
			0:
				animation_tree.set(path, lerp(animation_tree.get(path), value, delta*10.0))
			1:
				animation_tree.set(path, lerpf(animation_tree.get(path), value, delta*10.0))

func _on_roll_timer_timeout() -> void:
	is_rolling = false
	if roof_detector.is_colliding():
		is_crouching = true
	
	await get_tree().create_timer(slide_delay).timeout
	can_roll = true


func _on_pickup_timer_timeout() -> void:
	is_picking_object = false
	object.queue_free()
	object = null


func slide(delta: float):
	if not (can_roll and is_on_floor()): return
	can_roll = false
	is_rolling = true
	set_animation("parameters/GroundMoves/transition_request", slide_type, delta, -1)
	set_animation("parameters/GroundState/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE, delta, -1)
	$RollTimer.start()
