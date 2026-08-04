extends LoopPlayableScene

## 芽芽家园：纵向切片的可走动家园壳层。
## 正常启动先进入家园；自动化参数会透传到既有数据花园场景。

const VIEW_SIZE := Vector2(1280.0, 720.0)
const PLAYER_SPEED := 220.0
const PLAYER_START := Vector2(640.0, 560.0)
const LEGACY_ADVENTURE_SCENE_ID := "legacy_data_garden"
const SAVE_PATH := "user://data_garden_progress_v2.json"

const ROOM_TILESET_PATH := "res://theme/tileset/room/level_one_room.tres"
const TILE_ATLAS_PATH := "res://assets/sprites/tiles/tilemap_packed.png"
const PORTAL_TEXTURE_PATH := "res://assets/sprites/Dimensional_Portal.png"
const ROOM_GRID_SIZE := Vector2i(25, 15)
const ROOM_TILE_ORIGIN := Vector2(140.0, 80.0)
const ROOM_TILE_SCALE := Vector2(2.5, 2.5)
const ROOM_WALK_BOUNDS := Rect2(220.0, 198.0, 840.0, 402.0)
const FLOOR_TILE := Vector2i(10, 3)
const WALL_TOP_TILE := Vector2i(1, 0)
const WALL_MIDDLE_TILE := Vector2i(1, 2)
const WALL_BOTTOM_TILE := Vector2i(1, 3)
const WALL_LEFT_TILE := Vector2i(0, 1)
const WALL_RIGHT_TILE := Vector2i(2, 1)
const DOOR_ATLAS_REGION := Rect2(240.0, 80.0, 48.0, 48.0)
const CENTRAL_RUG_REGION := Rect2(80.0, 80.0, 48.0, 48.0)
const CENTRAL_TABLE_REGION := Rect2(160.0, 80.0, 48.0, 48.0)
const ARCHIVE_SHELF_REGION := Rect2(208.0, 176.0, 32.0, 32.0)
const CENTRAL_OBSTACLE := Rect2(576.0, 316.0, 128.0, 104.0)
const INTERACTION_RADIUS := 94.0

const PORTAL_POSITION := Vector2(640.0, 210.0)
const FARM_POSITION := Vector2(230.0, 300.0)
const GROWTH_POSITION := Vector2(1050.0, 300.0)
const ARCHIVE_POSITION := Vector2(1050.0, 460.0)
const WORKSHOP_POSITION := Vector2(230.0, 460.0)
const YAYA_POSITION := Vector2(820.0, 444.0)
const FACILITY_POSITIONS := {
	"portal": PORTAL_POSITION,
	"farm": FARM_POSITION,
	"growth": GROWTH_POSITION,
	"archive": ARCHIVE_POSITION,
	"workshop": WORKSHOP_POSITION,
	"yaya": YAYA_POSITION,
}
const FACILITY_SCENE_TARGETS := {
	"portal": {
		"scene_id": "theme_map",
		"scene_path": "res://scenes/demo/loop_oasis/multi_scene/theme_map.tscn",
	},
	"farm": {
		"scene_id": "farm",
		"scene_path": "res://scenes/demo/loop_oasis/multi_scene/farm.tscn",
	},
	"growth": {
		"scene_id": "growth",
		"scene_path": "res://scenes/demo/loop_oasis/multi_scene/growth_chamber.tscn",
	},
	"archive": {
		"scene_id": "archive",
		"scene_path": "res://scenes/demo/loop_oasis/multi_scene/archive_star_map.tscn",
	},
	"workshop": {
		"scene_id": "workshop",
		"scene_path": "res://scenes/demo/loop_oasis/multi_scene/workshop_range.tscn",
	},
}

const COLOR_BG := Color("#080a13")
const COLOR_PANEL := Color("#171925ed")
const COLOR_TEXT := Color("#fff8e8")
const COLOR_MUTED := Color("#c9c3cf")
const COLOR_CYAN := Color("#72e6dc")
const COLOR_MINT := Color("#79d894")
const COLOR_GOLD := Color("#f4c35b")
const COLOR_CORAL := Color("#ed8269")
const COLOR_PURPLE := Color("#a186d4")

var player_position := PLAYER_START
var player_sprite: Sprite2D
var companion_sprite: Sprite2D
var yaya_sprite: Sprite2D
var portal_sprite: AnimatedSprite2D
var workshop_sprite: Sprite2D
var farm_seed_sprites: Array[Sprite2D] = []
var farm_seed_base_scales: Array[Vector2] = []
var door_sprites: Dictionary = {}
var character_sprites: Array[Sprite2D] = []
var tile_atlas_texture: Texture2D
var ui_root: Control
var prompt_label: Label
var progress_label: Label
var route_panel: Panel
var facility_panel: Panel
var facility_title: Label
var facility_body: Label
var elapsed := 0.0
var home_test_mode := false
var home_capture_mode := false
var garden_restored := false
var walnut_level := 1
var content_version := "0.8.1"
var content_hash := ""
var legacy_progress_loaded := false
var home_inventory: Dictionary = {
	"water_seed": 0,
	"law_fragment": 0,
	"crop": 0,
	"pulse_module": 0,
}
var home_flags: Dictionary = {
	"farm": false,
	"growth": false,
	"archive": false,
	"workshop": false,
}

@onready var floor_layer: TileMapLayer = $World/RoomTiles/Floor
@onready var walls_layer: TileMapLayer = $World/RoomTiles/Walls
@onready var doorway_layer: Node2D = $World/Doorways
@onready var decor_layer: Node2D = $World/Decor
@onready var facilities_layer: Node2D = $World/Facilities
@onready var actors_layer: Node2D = $World/Actors
@onready var world_labels_layer: Node2D = $World/WorldLabels


func _ready() -> void:
	Cursor.sprite.texture = null
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var user_args := OS.get_cmdline_user_args()
	for passthrough in ["--demo-test", "--demo-ai-test", "--demo-capture", "--demo-capture-flow"]:
		if passthrough in user_args:
			call_deferred("_open_legacy_adventure")
			return
	home_test_mode = "--home-test" in user_args
	home_capture_mode = "--home-capture" in user_args
	RenderingServer.set_default_clear_color(COLOR_BG)
	if not home_test_mode and not home_capture_mode:
		_load_progress()
	_build_world()
	_build_ui()
	_refresh_progress_visuals()
	queue_redraw()
	if not home_test_mode and not home_capture_mode:
		MusicPlayer.play(load("res://assets/sounds/Bg Music.mp3"), true)
	if home_test_mode:
		call_deferred("_run_home_smoke_test")
	elif home_capture_mode:
		call_deferred("_capture_home_states")


func collect_completion_evidence() -> Dictionary:
	return {}


func _process(delta: float) -> void:
	elapsed += delta
	if not route_panel or not facility_panel:
		return
	_update_player(delta)
	_update_companion(delta)
	_update_prompt()
	_update_door_feedback()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.physical_keycode == KEY_ESCAPE and (route_panel.visible or facility_panel.visible):
		_close_overlays()
		return
	if route_panel.visible or facility_panel.visible:
		return
	if event.physical_keycode in [KEY_E, KEY_ENTER]:
		_interact()
	elif event.physical_keycode == KEY_M:
		_open_route_map()


func _draw() -> void:
	# The visible room is assembled from the source project's TileSet and assets.
	draw_rect(Rect2(Vector2.ZERO, VIEW_SIZE), COLOR_BG)
	draw_rect(Rect2(104.0, 82.0, 1072.0, 574.0), Color("#03040a88"), true)


func _build_world() -> void:
	tile_atlas_texture = load(TILE_ATLAS_PATH) as Texture2D
	assert(tile_atlas_texture != null, "家园大厅缺少源项目 TileMap 图集：%s" % TILE_ATLAS_PATH)
	_build_room_tiles()
	_build_doorways()
	_build_central_anchor()
	_build_farm_corner()
	_build_growth_corner()
	_build_archive_corner()
	_build_workshop_corner()
	_build_player_party()
	_build_world_labels()


func _build_room_tiles() -> void:
	var room_tileset := load(ROOM_TILESET_PATH) as TileSet
	assert(room_tileset != null, "家园大厅缺少源项目房间 TileSet：%s" % ROOM_TILESET_PATH)
	floor_layer.clear()
	walls_layer.clear()
	for layer in [floor_layer, walls_layer]:
		layer.tile_set = room_tileset
		layer.position = ROOM_TILE_ORIGIN
		layer.scale = ROOM_TILE_SCALE
		layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for y in range(ROOM_GRID_SIZE.y):
		for x in range(ROOM_GRID_SIZE.x):
			floor_layer.set_cell(Vector2i(x, y), 0, FLOOR_TILE)
	for x in range(ROOM_GRID_SIZE.x):
		if x < 11 or x > 13:
			walls_layer.set_cell(Vector2i(x, 0), 0, WALL_TOP_TILE)
			walls_layer.set_cell(Vector2i(x, 1), 0, WALL_MIDDLE_TILE)
			walls_layer.set_cell(Vector2i(x, 2), 0, WALL_BOTTOM_TILE)
		walls_layer.set_cell(Vector2i(x, ROOM_GRID_SIZE.y - 3), 0, WALL_TOP_TILE)
		walls_layer.set_cell(Vector2i(x, ROOM_GRID_SIZE.y - 2), 0, WALL_MIDDLE_TILE)
		walls_layer.set_cell(Vector2i(x, ROOM_GRID_SIZE.y - 1), 0, WALL_BOTTOM_TILE)
	for y in range(3, ROOM_GRID_SIZE.y - 3):
		if not _is_side_door_row(y):
			walls_layer.set_cell(Vector2i(0, y), 0, WALL_LEFT_TILE)
			walls_layer.set_cell(Vector2i(1, y), 0, WALL_RIGHT_TILE)
			walls_layer.set_cell(Vector2i(ROOM_GRID_SIZE.x - 2, y), 0, WALL_LEFT_TILE)
			walls_layer.set_cell(Vector2i(ROOM_GRID_SIZE.x - 1, y), 0, WALL_RIGHT_TILE)
	assert(floor_layer.get_used_cells().size() == ROOM_GRID_SIZE.x * ROOM_GRID_SIZE.y)


func _is_side_door_row(row: int) -> bool:
	return (row >= 4 and row <= 6) or (row >= 8 and row <= 10)


func _build_doorways() -> void:
	_make_door("portal", Vector2(640.0, 140.0), 0.0)
	_make_door("farm", Vector2(160.0, 300.0), -PI * 0.5)
	_make_door("growth", Vector2(1120.0, 300.0), PI * 0.5)
	_make_door("workshop", Vector2(160.0, 460.0), -PI * 0.5)
	_make_door("archive", Vector2(1120.0, 460.0), PI * 0.5)
	_build_portal()


func _make_door(facility: String, position: Vector2, rotation: float) -> void:
	var door := _make_atlas_sprite(
		"%sDoor" % facility.capitalize(),
		DOOR_ATLAS_REGION,
		position,
		Vector2(2.5, 2.5),
		doorway_layer
	)
	door.rotation = rotation
	door.z_index = 3
	door_sprites[facility] = door


func _build_portal() -> void:
	var portal_texture := load(PORTAL_TEXTURE_PATH) as Texture2D
	assert(portal_texture != null, "星光传送门贴图缺失：%s" % PORTAL_TEXTURE_PATH)
	assert(portal_texture.get_size() == Vector2(96.0, 64.0), "星光传送门序列帧尺寸异常")
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	frames.add_animation(&"idle")
	frames.set_animation_loop(&"idle", true)
	frames.set_animation_speed(&"idle", 8.0)
	for row in range(2):
		for column in range(3):
			var frame_texture := AtlasTexture.new()
			frame_texture.atlas = portal_texture
			frame_texture.region = Rect2(float(column * 32), float(row * 32), 32.0, 32.0)
			frames.add_frame(&"idle", frame_texture)
	portal_sprite = AnimatedSprite2D.new()
	portal_sprite.name = "StarlightPortal"
	portal_sprite.sprite_frames = frames
	portal_sprite.animation = &"idle"
	portal_sprite.autoplay = "idle"
	portal_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portal_sprite.position = Vector2(640.0, 200.0)
	portal_sprite.scale = Vector2(3.25, 3.25)
	portal_sprite.z_index = int(portal_sprite.position.y)
	facilities_layer.add_child(portal_sprite)
	portal_sprite.play(&"idle")


func _build_central_anchor() -> void:
	var rug := _make_atlas_sprite(
		"CentralRug",
		CENTRAL_RUG_REGION,
		Vector2(640.0, 369.0),
		Vector2(3.5, 3.5),
		decor_layer
	)
	rug.z_index = int(rug.position.y) - 3
	var table := _make_atlas_sprite(
		"CentralTable",
		CENTRAL_TABLE_REGION,
		Vector2(640.0, 366.0),
		Vector2(2.6, 2.6),
		decor_layer
	)
	table.z_index = int(table.position.y) + 1
	var hero_specs := [
		["res://assets/sprites/players/tile_0000.png", Vector2(548.0, 324.0)],
		["res://assets/sprites/players/tile_0004.png", Vector2(732.0, 324.0)],
		["res://assets/sprites/players/tile_0008.png", Vector2(548.0, 424.0)],
		["res://assets/sprites/players/tile_0012.png", Vector2(732.0, 424.0)],
	]
	for index in range(hero_specs.size()):
		var spec: Array = hero_specs[index]
		var hero_position: Vector2 = spec[1]
		var hero := _make_texture_sprite(
			"LobbyHero%d" % index,
			str(spec[0]),
			hero_position,
			62.0,
			decor_layer
		)
		hero.z_index = int(hero.position.y)
		character_sprites.append(hero)


func _build_farm_corner() -> void:
	var plant_specs := [
		["res://scenes/props/plant/plant_2.tscn", Vector2(254.0, 202.0), Vector2(2.1, 2.1)],
		["res://scenes/props/plant/plant_1.tscn", Vector2(305.0, 230.0), Vector2(2.4, 2.4)],
		["res://scenes/props/plant/plant_3.tscn", Vector2(276.0, 326.0), Vector2(2.4, 2.4)],
		["res://scenes/props/plant/plant_4.tscn", Vector2(326.0, 350.0), Vector2(2.5, 2.5)],
	]
	for index in range(plant_specs.size()):
		var spec: Array = plant_specs[index]
		var plant_position: Vector2 = spec[1]
		var plant_scale: Vector2 = spec[2]
		_spawn_plant(str(spec[0]), "FarmPlant%d" % index, plant_position, plant_scale)
	var seed_positions := [
		Vector2(214.0, 224.0),
		Vector2(214.0, 262.0),
		Vector2(214.0, 300.0),
		Vector2(214.0, 338.0),
	]
	for index in range(seed_positions.size()):
		var seed_position: Vector2 = seed_positions[index]
		var seed := _make_texture_sprite(
			"FarmSeed%d" % index,
			"res://assets/sprites/items/data_garden_light_seed.png",
			seed_position,
			30.0,
			facilities_layer
		)
		seed.z_index = int(seed.position.y)
		farm_seed_sprites.append(seed)
		farm_seed_base_scales.append(seed.scale)


func _build_growth_corner() -> void:
	_spawn_plant(
		"res://scenes/props/plant/plant_2.tscn",
		"GrowthPlantTall",
		Vector2(1000.0, 210.0),
		Vector2(2.1, 2.1)
	)
	_spawn_plant(
		"res://scenes/props/plant/plant_3.tscn",
		"GrowthPlantSmall",
		Vector2(994.0, 346.0),
		Vector2(2.5, 2.5)
	)
	var growth_heroes := [
		["res://assets/sprites/players/tile_0004.png", Vector2(1040.0, 242.0)],
		["res://assets/sprites/players/tile_0012.png", Vector2(1040.0, 316.0)],
	]
	for index in range(growth_heroes.size()):
		var spec: Array = growth_heroes[index]
		var hero_position: Vector2 = spec[1]
		var hero := _make_texture_sprite(
			"GrowthHero%d" % index,
			str(spec[0]),
			hero_position,
			58.0,
			facilities_layer
		)
		hero.z_index = int(hero.position.y)


func _build_archive_corner() -> void:
	var shelf := _make_atlas_sprite(
		"ArchiveShelf",
		ARCHIVE_SHELF_REGION,
		Vector2(1006.0, 480.0),
		Vector2(3.0, 3.0),
		facilities_layer
	)
	shelf.z_index = int(shelf.position.y)
	for index in range(3):
		var item_path := "res://assets/sprites/items/Item_White%d.png" % (10 + index)
		var item := _make_texture_sprite(
			"ArchiveItem%d" % index,
			item_path,
			Vector2(1038.0 + float(index) * 36.0, 406.0),
			34.0,
			facilities_layer
		)
		item.z_index = int(item.position.y)
	_spawn_plant(
		"res://scenes/props/plant/plant_1.tscn",
		"ArchivePlant",
		Vector2(982.0, 540.0),
		Vector2(2.3, 2.3)
	)


func _build_workshop_corner() -> void:
	workshop_sprite = _make_texture_sprite(
		"WorkshopConsole",
		"res://assets/sprites/items/data_garden_console.png",
		Vector2(252.0, 464.0),
		70.0,
		facilities_layer
	)
	workshop_sprite.z_index = int(workshop_sprite.position.y)
	var weapon_paths := [
		"res://assets/sprites/weapons/tiles/weapon_pistol.png",
		"res://assets/sprites/weapons/tiles/tile_0008.png",
		"res://assets/sprites/weapons/tiles/tile_0016.png",
	]
	for index in range(weapon_paths.size()):
		var weapon := _make_texture_sprite(
			"WorkshopWeapon%d" % index,
			weapon_paths[index],
			Vector2(318.0, 408.0 + float(index) * 58.0),
			46.0,
			facilities_layer
		)
		weapon.z_index = int(weapon.position.y)
	_spawn_plant(
		"res://scenes/props/plant/plant_4.tscn",
		"WorkshopPlant",
		Vector2(282.0, 548.0),
		Vector2(2.4, 2.4)
	)


func _build_player_party() -> void:
	player_sprite = _make_texture_sprite(
		"Player",
		"res://assets/sprites/players/tile_0004.png",
		player_position,
		66.0,
		actors_layer
	)
	player_sprite.z_index = int(player_sprite.position.y)
	companion_sprite = _make_texture_sprite(
		"Companion",
		"res://assets/sprites/players/tile_0012.png",
		player_position + Vector2(42.0, -4.0),
		50.0,
		actors_layer
	)
	companion_sprite.z_index = int(companion_sprite.position.y)
	yaya_sprite = _make_texture_sprite(
		"Yaya",
		"res://assets/sprites/players/tile_0008.png",
		YAYA_POSITION,
		64.0,
		actors_layer
	)
	yaya_sprite.z_index = int(yaya_sprite.position.y)
	_spawn_plant(
		"res://scenes/props/plant/plant_3.tscn",
		"YayaPlant",
		YAYA_POSITION + Vector2(58.0, 26.0),
		Vector2(2.3, 2.3)
	)


func _build_world_labels() -> void:
	_make_world_label("星光传送门", Vector2(565.0, 74.0), Vector2(150.0, 28.0), COLOR_CYAN, 17)
	_make_world_label("编程农场", Vector2(150.0, 184.0), Vector2(132.0, 28.0), COLOR_GOLD, 16)
	_make_world_label("成长舱", Vector2(997.0, 184.0), Vector2(132.0, 28.0), COLOR_PURPLE, 16)
	_make_world_label("装备工坊", Vector2(150.0, 528.0), Vector2(132.0, 28.0), COLOR_CORAL, 16)
	_make_world_label("知识档案馆", Vector2(986.0, 528.0), Vector2(146.0, 28.0), COLOR_GOLD, 16)
	_make_world_label("芽芽", Vector2(772.0, 480.0), Vector2(96.0, 24.0), COLOR_MINT, 15)


func _spawn_plant(path: String, node_name: String, position: Vector2, scale_value: Vector2) -> Node2D:
	var packed_scene := load(path) as PackedScene
	assert(packed_scene != null, "家园植物场景缺失：%s" % path)
	var plant := packed_scene.instantiate() as Node2D
	assert(plant != null, "家园植物实例化失败：%s" % path)
	plant.name = node_name
	plant.position = position
	plant.scale = scale_value
	plant.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	plant.z_index = int(plant.position.y)
	if plant is Area2D:
		var plant_area := plant as Area2D
		plant_area.monitoring = false
		plant_area.monitorable = false
	decor_layer.add_child(plant)
	return plant


func _make_atlas_sprite(
	node_name: String,
	region: Rect2,
	position: Vector2,
	scale_value: Vector2,
	parent: Node
) -> Sprite2D:
	assert(tile_atlas_texture != null, "TileMap 图集尚未载入")
	assert(
		Rect2(Vector2.ZERO, tile_atlas_texture.get_size()).encloses(region),
		"TileMap 图集裁切越界：%s" % region
	)
	var atlas_texture := AtlasTexture.new()
	atlas_texture.atlas = tile_atlas_texture
	atlas_texture.region = region
	var sprite := Sprite2D.new()
	sprite.name = node_name
	sprite.texture = atlas_texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position = position
	sprite.scale = scale_value
	parent.add_child(sprite)
	return sprite


func _make_texture_sprite(
	node_name: String,
	path: String,
	position: Vector2,
	longest_side: float,
	parent: Node
) -> Sprite2D:
	var texture := load(path) as Texture2D
	assert(texture != null, "家园可视资源缺失：%s" % path)
	var sprite := Sprite2D.new()
	sprite.name = node_name
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position = position
	_fit_sprite(sprite, longest_side)
	parent.add_child(sprite)
	return sprite


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	ui_root = Control.new()
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui_root)

	var header := _make_panel(Rect2(18.0, 16.0, 398.0, 62.0), COLOR_PANEL, Color("#57556b"), 8, 2)
	var title := _make_label("芽芽家园", 20, COLOR_TEXT)
	title.position = Vector2(16.0, 7.0)
	title.size = Vector2(150.0, 26.0)
	header.add_child(title)
	progress_label = _make_label("", 15, COLOR_CYAN)
	progress_label.position = Vector2(16.0, 34.0)
	progress_label.size = Vector2(366.0, 22.0)
	header.add_child(progress_label)

	var map_button := _make_button("M  星光传送门", Color("#403b58"), 15)
	map_button.position = Vector2(1114.0, 20.0)
	map_button.size = Vector2(148.0, 42.0)
	map_button.pressed.connect(_open_route_map)
	ui_root.add_child(map_button)

	prompt_label = _make_label("", 17, COLOR_TEXT)
	prompt_label.position = Vector2(380.0, 628.0)
	prompt_label.size = Vector2(520.0, 42.0)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt_label.add_theme_stylebox_override("normal", _style_box(Color("#11131de8"), COLOR_CYAN, 8, 2))
	ui_root.add_child(prompt_label)
	var controls := _make_label("WASD / 方向键移动  ·  E 交互  ·  M 星光传送门", 15, COLOR_MUTED)
	controls.position = Vector2(18.0, 688.0)
	controls.size = Vector2(390.0, 24.0)
	ui_root.add_child(controls)

	_build_route_panel()
	_build_facility_panel()


func _build_route_panel() -> void:
	# M and the physical world gate both transition directly through SceneFlow.
	# Keep a hidden control for the established overlay/input contract.
	route_panel = Panel.new()
	route_panel.name = "RoutePassthrough"
	route_panel.size = Vector2.ONE
	route_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(route_panel)
	route_panel.hide()


func _build_facility_panel() -> void:
	facility_panel = _make_panel(Rect2(260.0, 524.0, 760.0, 132.0), Color("#11131df5"), COLOR_GOLD, 9, 3)
	facility_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	facility_title = _make_label("", 18, COLOR_TEXT)
	facility_title.position = Vector2(18.0, 13.0)
	facility_title.size = Vector2(180.0, 30.0)
	facility_panel.add_child(facility_title)
	facility_body = _make_label("", 15, COLOR_MUTED)
	facility_body.position = Vector2(204.0, 10.0)
	facility_body.size = Vector2(426.0, 106.0)
	facility_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	facility_body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	facility_panel.add_child(facility_body)
	var close_button := _make_button("关闭  Esc", Color("#3e3a52"), 14)
	close_button.position = Vector2(640.0, 42.0)
	close_button.size = Vector2(104.0, 46.0)
	close_button.pressed.connect(_close_overlays)
	facility_panel.add_child(close_button)
	facility_panel.hide()


func _update_player(delta: float) -> void:
	var direction := Vector2.ZERO
	if not route_panel.visible and not facility_panel.visible and not home_test_mode and not home_capture_mode:
		direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var previous := player_position
	if direction.length() > 0.05:
		var candidate := player_position + direction.normalized() * PLAYER_SPEED * delta
		player_position = _resolve_room_motion(previous, candidate)
		player_sprite.flip_h = direction.x < -0.05
	var bob := sin(elapsed * 11.0) * 1.5 if direction.length() > 0.05 else 0.0
	player_sprite.position = player_position + Vector2(0.0, bob)
	player_sprite.z_index = int(player_position.y)


func _resolve_room_motion(previous: Vector2, candidate: Vector2) -> Vector2:
	candidate.x = clampf(candidate.x, ROOM_WALK_BOUNDS.position.x, ROOM_WALK_BOUNDS.end.x)
	candidate.y = clampf(candidate.y, ROOM_WALK_BOUNDS.position.y, ROOM_WALK_BOUNDS.end.y)
	var obstacle := CENTRAL_OBSTACLE.grow(18.0)
	if not obstacle.has_point(candidate):
		return candidate
	var x_only := Vector2(candidate.x, previous.y)
	if not obstacle.has_point(x_only):
		return x_only
	var y_only := Vector2(previous.x, candidate.y)
	if not obstacle.has_point(y_only):
		return y_only
	return previous


func _update_companion(delta: float) -> void:
	var side := -42.0 if player_sprite.flip_h else 42.0
	var target := player_position + Vector2(side, -3.0 + sin(elapsed * 3.0) * 4.0)
	companion_sprite.position = companion_sprite.position.lerp(target, minf(1.0, delta * 6.0))
	companion_sprite.z_index = int(companion_sprite.position.y)


func _update_prompt() -> void:
	if route_panel.visible or facility_panel.visible:
		prompt_label.hide()
		return
	var facility := _nearest_facility()
	if facility.is_empty():
		prompt_label.hide()
		return
	var prompts := {
		"portal": "E  前往转转绿洲岛",
		"farm": "E  进入四格编程农场",
		"growth": "E  进入小核桃成长舱",
		"archive": "E  进入知识档案星图",
		"workshop": "E  进入装备工坊试射场",
		"yaya": "E  与芽芽查看生产目标",
	}
	prompt_label.text = prompts[facility]
	prompt_label.show()


func _update_door_feedback() -> void:
	var nearest := _nearest_facility()
	for facility in door_sprites:
		var door := door_sprites[facility] as Sprite2D
		var base_color := Color.WHITE
		if facility != "portal" and not _home_flag(str(facility)):
			base_color = Color("#c3bdca")
		if str(facility) == nearest:
			var pulse := 0.13 + (sin(elapsed * 5.0) + 1.0) * 0.08
			base_color = base_color.lerp(COLOR_CYAN, pulse)
		door.modulate = base_color


func _nearest_facility() -> String:
	var nearest := ""
	var best := INTERACTION_RADIUS
	for key in FACILITY_POSITIONS:
		var distance := player_position.distance_to(FACILITY_POSITIONS[key])
		if distance < best:
			best = distance
			nearest = key
	return nearest


func _interact() -> void:
	var facility := _nearest_facility()
	match facility:
		"portal":
			_open_route_map()
		"farm", "growth", "archive", "workshop":
			_go_to_facility(facility)
		"yaya":
			_show_npc_dialog("芽芽 · 家园核心", _yaya_status_text())


func _open_route_map() -> Dictionary:
	facility_panel.hide()
	return _go_to_facility("portal")


func _go_to_facility(facility: String) -> Dictionary:
	assert(FACILITY_SCENE_TARGETS.has(facility), "未知家园场景门：%s" % facility)
	var target: Dictionary = FACILITY_SCENE_TARGETS[facility]
	return navigate_to(str(target.scene_id))


func _open_legacy_adventure() -> void:
	navigate_to(LEGACY_ADVENTURE_SCENE_ID)


func _yaya_status_text() -> String:
	var seed_count := _inventory_count("water_seed")
	var crop_count := _inventory_count("crop")
	if _home_flag("farm"):
		return "四格土地已经按你的程序工作。仓库里有作物 ×%d；下一步可以去成长舱，也可以再次进入农场练习。" % crop_count
	if seed_count > 0:
		return "仓库里有清泉种子 ×%d。走进编程农场，把冒险里的 Repeat 结构迁移到 4 格新土地。" % seed_count
	if legacy_progress_loaded:
		return "旧版冒险修复记录仍然保留；新的多场景冒险会单独发放可投入农场的清泉种子，不会自动打开设施门禁。"
	return "先从星光传送门前往转转绿洲岛。带回清泉种子后，再到编程农场完成 5→4 的新目标迁移。"


func _show_npc_dialog(title_text: String, body_text: String) -> void:
	route_panel.hide()
	facility_title.text = title_text
	facility_body.text = body_text
	facility_panel.show()


func _close_overlays() -> void:
	route_panel.hide()
	facility_panel.hide()


func _load_progress() -> void:
	home_inventory = LoopRunState.inventory.duplicate(true)
	home_flags = LoopRunState.home_flags.duplicate(true)
	walnut_level = maxi(1, int(LoopRunState.walnut_level))
	garden_restored = bool(LoopRunState.settlement_committed)
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		push_error("HOME_LEGACY_SAVE_OPEN_FAILED: %s" % SAVE_PATH)
		return
	var raw_text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(raw_text)
	if parsed is Dictionary:
		legacy_progress_loaded = bool(parsed.get("garden_restored", false))
		garden_restored = garden_restored or legacy_progress_loaded
		walnut_level = maxi(walnut_level, int(parsed.get("walnut_level", 1)))
		content_version = str(parsed.get("content_version", content_version))
		content_hash = str(parsed.get("content_hash", ""))
	else:
		push_error("HOME_LEGACY_SAVE_PARSE_FAILED: %s" % SAVE_PATH)


func _inventory_count(key: String) -> int:
	return maxi(0, int(home_inventory.get(key, 0)))


func _home_flag(key: String) -> bool:
	return bool(home_flags.get(key, false))


func _completed_facility_count() -> int:
	var completed := 0
	for key in ["farm", "growth", "archive", "workshop"]:
		if _home_flag(key):
			completed += 1
	return completed


func _refresh_progress_visuals() -> void:
	var farm_complete := _home_flag("farm")
	var seed_available := _inventory_count("water_seed") > 0
	for index in range(farm_seed_sprites.size()):
		var seed := farm_seed_sprites[index]
		if farm_complete:
			seed.modulate = Color.WHITE
			seed.scale = farm_seed_base_scales[index] * 1.08
		elif seed_available:
			seed.modulate = Color("#ffd87a")
			seed.scale = farm_seed_base_scales[index] * 0.94
		else:
			seed.modulate = Color("#9b91b5")
			seed.scale = farm_seed_base_scales[index] * 0.82
	if workshop_sprite:
		workshop_sprite.modulate = Color.WHITE if _home_flag("workshop") else Color("#b59bc7")
	if progress_label:
		var legacy_tag := " · 旧版记录" if legacy_progress_loaded and not bool(LoopRunState.settlement_committed) else ""
		progress_label.text = "种子 ×%d · 作物 ×%d · 模块 ×%d · 设施 %d/4 · Lv.%d%s" % [
			_inventory_count("water_seed"),
			_inventory_count("crop"),
			_inventory_count("pulse_module"),
			_completed_facility_count(),
			walnut_level,
			legacy_tag,
		]
	queue_redraw()


func _run_home_smoke_test() -> void:
	assert(player_sprite and companion_sprite and yaya_sprite and portal_sprite and workshop_sprite)
	assert(farm_seed_sprites.size() == 4)
	assert(character_sprites.size() == 4)
	assert(door_sprites.size() == FACILITY_SCENE_TARGETS.size())
	assert(floor_layer.get_used_cells().size() == ROOM_GRID_SIZE.x * ROOM_GRID_SIZE.y)
	assert(walls_layer.get_used_cells().size() > 0)
	assert(portal_sprite.sprite_frames.get_frame_count(&"idle") == 6)
	assert(not route_panel.visible)
	var resolved := _resolve_room_motion(Vector2(540.0, 366.0), Vector2(640.0, 366.0))
	assert(not CENTRAL_OBSTACLE.grow(18.0).has_point(resolved))
	var seen_paths := {}
	for facility in ["portal", "farm", "growth", "archive", "workshop"]:
		player_position = FACILITY_POSITIONS[facility]
		player_sprite.position = player_position
		_interact()
		var target: Dictionary = FACILITY_SCENE_TARGETS[facility]
		var request: Dictionary = SceneFlow.get_last_request()
		assert(bool(request.get("ok", false)))
		assert(str(request.get("scene_id", "")) == str(target.scene_id))
		assert(str(request.get("scene_path", "")) == str(target.scene_path))
		assert(not seen_paths.has(str(request.scene_path)), "家园设施不能共用目标场景：%s" % str(request.scene_path))
		seen_paths[str(request.scene_path)] = true
	assert(seen_paths.size() == FACILITY_SCENE_TARGETS.size())
	_open_route_map()
	var map_request: Dictionary = SceneFlow.get_last_request()
	assert(str(map_request.get("scene_id", "")) == "theme_map")
	assert(str(map_request.get("scene_path", "")) == str(FACILITY_SCENE_TARGETS.portal.scene_path))
	var last_facility_request := map_request.duplicate(true)
	player_position = YAYA_POSITION
	player_sprite.position = player_position
	_interact()
	assert(facility_panel.visible and "芽芽" in facility_title.text)
	assert(SceneFlow.get_last_request() == last_facility_request)
	_close_overlays()
	print("HOME_BASE_SMOKE_OK")
	get_tree().quit(0)


func _capture_home_states() -> void:
	var qa_dir := ProjectSettings.globalize_path("res://qa/home-base")
	DirAccess.make_dir_recursive_absolute(qa_dir)
	await _save_capture(qa_dir.path_join("01-home-base.png"))
	player_position = PORTAL_POSITION
	player_sprite.position = player_position
	_update_prompt()
	await _save_capture(qa_dir.path_join("02-portal-approach.png"))
	_open_route_map()
	var map_request: Dictionary = SceneFlow.get_last_request()
	assert(bool(map_request.get("ok", false)))
	assert(str(map_request.get("scene_id", "")) == "theme_map")
	assert(str(map_request.get("scene_path", "")) == str(FACILITY_SCENE_TARGETS.portal.scene_path))
	garden_restored = true
	home_inventory.water_seed = 1
	content_hash = "9d68a4cda7f1"
	player_position = PLAYER_START
	player_sprite.position = player_position
	_refresh_progress_visuals()
	await _save_capture(qa_dir.path_join("03-home-return.png"))
	print("HOME_BASE_CAPTURE=", qa_dir)
	get_tree().quit(0)


func _save_capture(path: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		push_error("Home capture requires a rendering display: %s" % path)
		get_tree().quit(2)
		return
	var viewport_texture := get_viewport().get_texture()
	if viewport_texture == null:
		push_error("Home capture requires a rendering display: %s" % path)
		get_tree().quit(2)
		return
	var image := viewport_texture.get_image()
	if image == null or image.is_empty():
		push_error("Home capture returned an empty image: %s" % path)
		get_tree().quit(2)
		return
	var error := image.save_png(path)
	if error != OK:
		push_error("Failed to save home capture: %s" % path)
		get_tree().quit(2)


func _make_world_label(text_value: String, position: Vector2, size: Vector2, color: Color, font_size: int) -> void:
	var label := _make_label(text_value, font_size, color)
	label.position = position
	label.size = size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_outline_color", Color("#090a10"))
	label.add_theme_constant_override("outline_size", 4)
	label.z_index = 10
	world_labels_layer.add_child(label)


func _fit_sprite(sprite: Sprite2D, longest_side: float) -> void:
	if not sprite.texture:
		return
	var source_side := maxf(sprite.texture.get_size().x, sprite.texture.get_size().y)
	if source_side > 0.0:
		var factor := longest_side / source_side
		sprite.scale = Vector2(factor, factor)


func _make_panel(rect: Rect2, color: Color, border: Color, radius: int, border_width: int = 2) -> Panel:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.add_theme_stylebox_override("panel", _style_box(color, border, radius, border_width))
	ui_root.add_child(panel)
	return panel


func _style_box(color: Color, border: Color, radius: int, border_width: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


func _make_label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _make_button(text_value: String, color: Color, font_size: int) -> Button:
	var button := Button.new()
	button.text = text_value
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_stylebox_override("normal", _style_box(color, color.lightened(0.2), 13, 2))
	button.add_theme_stylebox_override("hover", _style_box(color.lightened(0.12), COLOR_CYAN, 13, 3))
	button.add_theme_stylebox_override("pressed", _style_box(color.darkened(0.12), COLOR_GOLD, 13, 2))
	return button
