extends Node2D

const TILE_SIZE = 32

const LEVEL_SIZES = [
	Vector2(30, 30),
	Vector2(35, 35),
	Vector2(40, 40),
	Vector2(45, 45),
	Vector2(50, 50),
]
const LEVEL_ROOM_COUNTS = [5, 7, 9, 12, 15]
const LEVEL_ENEMY_COUNTS = [5, 8, 12, 18, 26]
const MIN_ROOM_DIMENSION = 5
const MAX_ROOM_DIMENSION = 8
const PLAYER_START_HP = 10

enum Tile { Wall, Ladder, Floor, Door, Stone }

const ImpScene = preload("res://ImpEnemy.tscn")

class ImpEnemy extends Reference:
	var sprite_node: Node2D
	var tile
	var max_hp
	var current_hp
	var dead = false
	
	func _init(root_node, enemy_level, coord_x, coord_y):
		max_hp = 1 + enemy_level * 2
		current_hp = max_hp
		tile = Vector2(coord_x, coord_y)
		sprite_node = ImpScene.instance()
		sprite_node.position = tile * TILE_SIZE
		root_node.add_child(sprite_node)
		
	func remove():
		sprite_node.queue_free()
		
	func take_damage(root_node, damage):
		if dead:
			return
		
		current_hp = max(0, current_hp - damage)
		sprite_node.get_node("HP").rect_size.x = TILE_SIZE * current_hp / max_hp
		
		if current_hp == 0:
			dead = true
			root_node.score += 10 * max_hp
			
	func act(root_node):
		var self_point = root_node.enemy_pathfinding.get_closest_point(Vector3(tile.x, tile.y, 0))
		var player_point = root_node.enemy_pathfinding.get_closest_point(Vector3(root_node.player_tile.x, root_node.player_tile.y, 0))
		var path = root_node.enemy_pathfinding.get_point_path(self_point, player_point)
		
		if path:
			assert(path.size() > 1)
			var move_tile = Vector2(path[1].x, path[1].y)
			
			if move_tile == root_node.player_tile:
				root_node.damage_player(1)
			else:
				var blocked = false
				for enemy in root_node.enemies:
					if enemy.tile == move_tile:
						blocked = true
						break
				
				if !blocked:
					tile = move_tile


# CURRENT LEVEL --------------------------------

var level_number = 0
var map = []
var rooms = []
var enemies = []
var level_size

# NODE REFERENCES --------------------------------

onready var tile_map = $TileMap
onready var visibility_map = $VisibilityMap
onready var player = $Player

# GAME STATE --------------------------------

var player_tile
var enemy_pathfinding
var score = 0
var player_hp = PLAYER_START_HP

# Called when the node enters the scene tree for the first time.
func _ready():
	OS.set_window_size(Vector2(1280, 720))
	randomize()
	build_level()

func _input(event):
	if !event.is_pressed():
		return
		
	if event.is_action("Up"):
		move_player(0, -1)
	elif event.is_action("Down"):
		move_player(0, 1)
	elif event.is_action("Left"):
		move_player(-1, 0)
	elif event.is_action("Right"):
		move_player(1, 0)
		
func move_player(dx, dy):
	var x = player_tile.x + dx
	var y = player_tile.y + dy
	var tile_type = Tile.Stone
	
	if x >= 0 && x < level_size.x && y >= 0 && y < level_size.y:
		tile_type = map[x][y]
		
	match tile_type:
		Tile.Floor:
			var blocked = false
			for enemy in enemies:
				if enemy.tile.x == x && enemy.tile.y == y:
					enemy.take_damage(self, 1)
					if enemy.dead:
						enemy.remove()
						enemies.erase(enemy)
					blocked = true
					break
			if !blocked:
				player_tile = Vector2(x, y)
		Tile.Door:
			set_tile(x, y, Tile.Floor)
		Tile.Ladder:
			level_number += 1
			score += 100
			if level_number < LEVEL_SIZES.size():
				build_level()
			else:
				score += 1000
				$CanvasLayer/Win.visible = true
	
	for enemy in enemies:
		enemy.act(self)
			
	call_deferred("update_visuals")

func build_level():
	clear_map()
	setup_map()


func clear_map():
	rooms.clear()
	map.clear()
	tile_map.clear()
	clear_enemies()
	
func clear_enemies():
	for enemy in enemies:
		enemy.remove()
	enemies.clear()

	enemy_pathfinding = AStar.new()
	
	
func clear_path(tile):
	var new_point = enemy_pathfinding.get_available_point_id()
	var points_to_connect = []
	
	enemy_pathfinding.add_point(new_point, Vector3(tile.x, tile.y, 0))
	
	if tile.x > 0 && map[tile.x - 1][tile.y] == Tile.Floor:
		points_to_connect.append(enemy_pathfinding.get_closest_point(Vector3(tile.x - 1, tile.y, 0)))
	if tile.y > 0 && map[tile.x][tile.y - 1] == Tile.Floor:
		points_to_connect.append(enemy_pathfinding.get_closest_point(Vector3(tile.x, tile.y - 1, 0)))
	if tile.x < level_size.x - 1 && map[tile.x + 1][tile.y] == Tile.Floor:
		points_to_connect.append(enemy_pathfinding.get_closest_point(Vector3(tile.x + 1, tile.y, 0)))
	if tile.y < level_size.y - 1 && map[tile.x][tile.y + 1] == Tile.Floor:
		points_to_connect.append(enemy_pathfinding.get_closest_point(Vector3(tile.x, tile.y + 1, 0)))
		
	for point in points_to_connect:
		enemy_pathfinding.connect_points(point, new_point)
	

func setup_map():
	level_size = LEVEL_SIZES[level_number]
	for x in range(level_size.x):
		map.append([])
		for y in range(level_size.y):
			map[x].append(Tile.Stone)
			tile_map.set_cell(x, y, Tile.Stone)
			visibility_map.set_cell(x, y, 0)

	var free_regions = [Rect2(Vector2(2, 2), level_size - Vector2(4, 4))]
	var num_rooms = LEVEL_ROOM_COUNTS[level_number]

	for _i in range(num_rooms):
		add_room(free_regions)
		if free_regions.empty():
			break

	connect_rooms()
	place_player()
	place_enemies()
	place_ladder()
	set_level_name()
	
func place_ladder():
	var end_room = rooms.back()
	var ladder_x = end_room.position.x + 1 + randi() % int(end_room.size.x - 2)
	var ladder_y = end_room.position.y + 1 + randi() % int(end_room.size.y - 2 )
	
	set_tile(ladder_x, ladder_y, Tile.Ladder)

func set_level_name():
	$CanvasLayer/Level.text = "Level: " + str(level_number)

func place_player():
	var start_room = rooms.front()
	var player_x = start_room.position.x + 1 + randi() % int(start_room.size.x - 2)
	var player_y = start_room.position.y + 1 + randi() % int(start_room.size.y - 2)
	
	player_tile = Vector2(player_x, player_y)
	call_deferred("update_visuals")
	
func place_enemies():
	var num_enemies =  LEVEL_ENEMY_COUNTS[level_number]
	for i in range(num_enemies):
		var room = rooms[1 + randi() % (rooms.size() - 1)]
		var x = room.position.x + 1 + randi() % int(room.size.x - 2)
		var y = room.position.y + 1 + randi() % int(room.size.y - 2)
		
		var blocked = false
		for enemy in enemies:
			if enemy.tile.x == x && enemy.tile.y == y:
				blocked = true
				break
				
		if !blocked:
			var imp = ImpEnemy.new(self, randi() % 2, x, y)
			enemies.append(imp)
	

func update_visuals():
	player.position = player_tile * TILE_SIZE
	var player_center = tile_to_pixel_center(player_tile.x, player_tile.y)
	# This has something to do with 'raycasting' gotta look up about this later
	var space_state = get_world_2d().direct_space_state
	
	for x in range(level_size.x):
		for y in range(level_size.y):
			if visibility_map.get_cell(x, y) == 0:
				var x_dir = 1 if x < player_tile.x else -1
				var y_dir = 1 if y < player_tile.y else -1
				var test_point = tile_to_pixel_center(x, y) + Vector2(x_dir, y_dir) * TILE_SIZE / 2
				var occlusion = space_state.intersect_ray(player_center, test_point)
				
				if !occlusion || (occlusion.position - test_point).length() < 1:
					 visibility_map.set_cell(x, y, -1)
	
	for enemy in enemies:
		enemy.sprite_node.position = enemy.tile * TILE_SIZE
	
	$CanvasLayer/HP.text = "HP: " + str(player_hp)
	$CanvasLayer/Score.text = "Score: " + str(score)
	
func tile_to_pixel_center(x, y):
	return Vector2((x + 0.5) * TILE_SIZE, (y + 0.5) * TILE_SIZE)


func connect_rooms():
	# Build an AStar graph of the area where we can add corridors
	var stone_graph = AStar.new()
	var point_id = 0

	for x in range(level_size.x):
		for y in range(level_size.y):
			if map[x][y] == Tile.Stone:
				stone_graph.add_point(point_id, Vector3(x, y, 0))

				# Connect to the left if also stone
				if x > 0 && map[x - 1][y] == Tile.Stone:
					var left_point = stone_graph.get_closest_point(Vector3(x - 1, y, 0))
					stone_graph.connect_points(point_id, left_point)

				# Connect above if also stone
				if y > 0 && map[x][y - 1] == Tile.Stone:
					var above_point = stone_graph.get_closest_point(Vector3(x, y - 1, 0))
					stone_graph.connect_points(point_id, above_point)

				point_id += 1

	# Build an AStar graph of room connections
	var room_graph = AStar.new()
	point_id = 0
	
	for room in rooms:
		var room_center = room.position + room.size * 2
		room_graph.add_point(point_id, Vector3(room_center.x, room_center.y, 0))
		point_id += 1

	# Add random connections until everything is connected
	while !is_everything_connected(room_graph):
		add_random_connection(stone_graph, room_graph)


func is_everything_connected(graph):
	var points = graph.get_points()
	var start = points.pop_back()

	for point in points:
		var path = graph.get_point_path(start, point)
		if !path:
			return false

	return true


func add_random_connection(stone_graph, room_graph):
	# Pick rooms to connect
	var start_room_id = get_least_connected_point(room_graph)
	var end_room_id = get_nearest_unconnected_point(room_graph, start_room_id)

	# Pick the door location
	var start_position = pick_random_door_location(rooms[start_room_id])
	var end_position = pick_random_door_location(rooms[end_room_id])

	# Find a path to connect the doors to each other
	var closest_start_point = stone_graph.get_closest_point(start_position)
	var closest_end_point = stone_graph.get_closest_point(end_position)

	var path = stone_graph.get_point_path(closest_start_point, closest_end_point)
	assert(path)

	# Add path to the map
	set_tile(start_position.x, start_position.y, Tile.Door)
	set_tile(end_position.x, end_position.y, Tile.Door)

	for position in path:
		set_tile(position.x, position.y, Tile.Floor)

	room_graph.connect_points(start_room_id, end_room_id)


func get_least_connected_point(graph):
	var point_ids = graph.get_points()
	var least
	var tied_for_least = []

	for point in point_ids:
		var count = graph.get_point_connections(point).size()
		if !least || count  < least:
			least = count
			tied_for_least = [point]
		elif count == least:
			tied_for_least.append(point)

	return tied_for_least[randi() % tied_for_least.size()]


func get_nearest_unconnected_point(graph, target_point):
	var target_position = graph.get_point_position(target_point)
	var point_ids = graph.get_points()
	var nearest
	var tied_for_nearest = []

	for point in point_ids:
		if point == target_point:
			continue

		var path = graph.get_point_path(point, target_point)
		if path:
			continue

		var dist = (graph.get_point_position(point) - target_position).length()
		if !nearest || dist < nearest:
			nearest = dist
			tied_for_nearest = [point]
		elif dist == nearest:
			tied_for_nearest.append(point)

	return tied_for_nearest[randi() % tied_for_nearest.size()]

func pick_random_door_location(room):
	var options = []
	
	# Top and bottom walls
	for x in range(room.position.x + 1, room.end.x - 2):
		options.append(Vector3(x, room.position.y, 0))
		options.append(Vector3(x, room.end.y - 1, 0))

	# Left and right walls
	for y in range(room.position.y + 1, room.end.y - 2):
		options.append(Vector3(room.position.x, y, 0))
		options.append(Vector3(room.end.x - 1, y, 0))

	return options[randi() % options.size()]



func add_room(free_regions):
	var region = free_regions[randi() % free_regions.size()]

	var size_x = MIN_ROOM_DIMENSION
	if region.size.x > MIN_ROOM_DIMENSION:
		size_x += randi() % int(region.size.x - MIN_ROOM_DIMENSION)

	var size_y = MIN_ROOM_DIMENSION
	if region.size.y > MIN_ROOM_DIMENSION:
		size_y += randi() % int(region.size.y - MIN_ROOM_DIMENSION)

	size_x = min(size_x, MAX_ROOM_DIMENSION)
	size_y = min(size_y, MAX_ROOM_DIMENSION)

	var start_x = region.position.x
	if region.size.x > size_x:
		start_x += randi() % int(region.size.x - size_x)

	var start_y = region.position.y
	if region.size.y > size_y:
		start_y += randi() % int(region.size.y - size_y)

	var room = Rect2(start_x, start_y, size_x, size_y)
	rooms.append(room)

	for x in range(start_x, start_x + size_x):
		set_tile(x, start_y, Tile.Wall)
		set_tile(x, start_y + size_y - 1, Tile.Wall)

	for y in range(start_y + 1, start_y + size_y - 1):
		set_tile(start_x, y, Tile.Wall)
		set_tile(start_x + size_x - 1, y, Tile.Wall)

		for x in range(start_x + 1, start_x + size_x - 1):
			set_tile(x, y, Tile.Floor)

	cut_regions(free_regions, room)


func set_tile(x, y, type):
	map[x][y] = type
	tile_map.set_cell(x, y, type)
	
	if type == Tile.Floor:
		clear_path(Vector2(x,y))


func cut_regions(free_regions, region_to_remove):
	var removal_queue = []
	var addition_queue = []

	for region in free_regions:
		if region.intersects(region_to_remove):
			removal_queue.append(region)

			var leftover_left = region_to_remove.position.x - region.position.x - 1
			var leftover_right = region.end.x - region_to_remove.end.x - 1
			var leftover_above = region_to_remove.position.y - region.position.y - 1
			var leftover_below = region.end.y - region_to_remove.end.y - 1

			if leftover_left >= MIN_ROOM_DIMENSION:
				addition_queue.append(Rect2(region.position, Vector2(leftover_left, region.size.y)))
			if leftover_right >= MIN_ROOM_DIMENSION:
				addition_queue.append(
					Rect2(
						Vector2(region_to_remove.end.x + 1, region.position.y),
						Vector2(leftover_right, region.size.y)
					)
				)
			if leftover_above >= MIN_ROOM_DIMENSION:
				addition_queue.append(
					Rect2(region.position, Vector2(region.size.x, leftover_above))
				)
			if leftover_below >= MIN_ROOM_DIMENSION:
				addition_queue.append(
					Rect2(
						Vector2(region.position.x, region_to_remove.end.y + 1),
						Vector2(region.size.x, leftover_below)
					)
				)

			for region in removal_queue:
				free_regions.erase(region)

			for region in addition_queue:
				free_regions.append(region)

func damage_player(damage):
	player_hp = max(0, player_hp - damage)
	if player_hp == 0:
		$CanvasLayer/Lose.visible = true

func _on_Restart_pressed():
	level_number = 0
	score = 0
	build_level()
	$CanvasLayer/Win.visible = false
	$CanvasLayer/Lose.visible = false
	player_hp = PLAYER_START_HP
