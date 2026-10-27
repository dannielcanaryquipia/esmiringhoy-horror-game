@tool
extends Node3D
## Ang Silid — the master bedroom of the abandoned bahay na bato, plus the hallway.
## Everything is built from code so it matches design board 01 exactly.
## It's a @tool script, so the room also shows up in the editor viewport.
##
## Layout (1 unit = 1 m): room interior x -6..6, z -4..4, floor y 0, ceiling 3.4.
## North (-z) has the two capiz windows, south (+z) the door to the hallway.
##
## South of the bedroom (z > 4) a narrow wing fans out on two floors:## a tight corridor (x -1.6..1.6) branches west into the stair hall and east
## into the kitchen, then ends at a back room. A ramp in the stair hall climbs
## to a narrower second floor with two rooms, and a second ramp climbs from the
## upstairs bedroom through the roof to the azotea (the flat roof deck).
## Hiding spots (kitchen counter + pantry nook, a crate in the back room, an
## upstairs wardrobe, the tapayan jar and a curtain, and a water drum on the
## azotea) let a crouching player break the demon's line of sight.

const TEX := "res://assets/textures/"
const SHADER_CAPIZ := preload("res://assets/shaders/sh_capiz.gdshader")
const HideSpotScript := preload("res://scripts/hiding_spot.gd")
const SwitchScript := preload("res://scripts/light_switch.gd")
const NoisemakerScript := preload("res://scripts/noisemaker.gd")

const ROOM_H := 3.4
const HALL_H := 2.6
const T := 0.2    # wall thickness
const FLR2 := 3.0  # top surface of the second floor / ceiling of the wing
const H2 := 2.4    # second-floor wall height above FLR2

# --- anchor points other scripts read -------------------------------------
var player_spawn := Vector3(0.6, 0.0, 5.4)
var demon_lurk := Vector3(-5.2, 0.0, 3.1)
var candle_spots := {
	"A": Vector3(5.42, 0.96, 0.45),   # on the Ang Silid altar
	"B": Vector3(4.55, 0.81, 3.42),   # on the vanity
	"C": Vector3(7.3, 0.95, 6.9),     # on the kitchen counter
	"D": Vector3(-4.8, 0.96, 17.0),   # on the oratorio (chapel) altar — needs the key
}
## Quest item pools. Each run, main.gd spawns every kind at ONE random spot from
## its pool (Granny-style — search the house every night). Matches gate
## candle-lighting; the key opens the chapel; the blessed salt is what the
## chapel candle burns on.
var item_pools := {
	"matches": [
		Vector3(4.6, 0.96, 4.6),    # on the kitchen north counter
		Vector3(3.6, 0.86, 3.5),    # on the bedroom vanity
		Vector3(-4.8, 0.14, -3.5),  # inside the aparador, on its base
		Vector3(-1.2, 6.14, 10.6),  # on the azotea crate
		Vector3(1.2, 0.48, 15.6),   # on the sala coffee table
	],
	"key": [
		Vector3(-5.2, 1.06, 11.1),  # on a crate in the back room
		Vector3(-3.6, 3.56, 10.6),  # on the second-floor lamp crate
		Vector3(-1.8, 3.06, 6.0),   # storage-room floor, by the wardrobe
		Vector3(1.2, 0.78, 17.15),  # on the sala TV cabinet
	],
	"salt": [
		Vector3(2.7, 1.36, 9.6),    # on the kitchen pantry shelf
		Vector3(6.4, 1.47, 11.2),   # on the tapayan rim, back room
		Vector3(-2.8, 6.04, 7.8),   # on the azotea bench
		Vector3(4.95, 0.9, 13.1),   # in the CR sink
	],
}
## Ritual candle spawn pool. Each run, candles A, B and C land on random
## surfaces from this list, never two in the same room, so the player has to search
## the house. Candle D always stays on the oratorio altar (candle_spots["D"]).
## Positions are surface tops (a candle's origin is the base of its dish) and sit
## clear of every quest-item spot above.
var candle_pool := [
	{"room": "silid", "pos": Vector3(5.42, 0.96, 0.45)},    # Ang Silid altar
	{"room": "silid", "pos": Vector3(4.55, 0.81, 3.42)},    # Ang Silid vanity
	{"room": "kusina", "pos": Vector3(7.5, 0.9, 7.8)},      # kitchen east counter
	{"room": "kusina", "pos": Vector3(5.6, 0.9, 4.6)},      # kitchen north counter, past the pots
	{"room": "bodega", "pos": Vector3(-4.2, 0.8, 11.3)},    # back room, the smaller crate
	{"room": "sala", "pos": Vector3(0.45, 0.75, 17.15)},    # sala TV cabinet, beside the set
	{"room": "sala", "pos": Vector3(0.75, 0.45, 15.75)},    # sala coffee table
	{"room": "kuarto", "pos": Vector3(7.25, 0.92, 17.25)},  # second bedroom dresser
	{"room": "azotea", "pos": Vector3(-3.2, 6.04, 7.8)},    # azotea bench
]

## Pick a spot for each label, each in a different room. Returns {label: Vector3}.
func roll_candle_spots(labels: Array) -> Dictionary:
	var by_room := {}
	for entry in candle_pool:
		if not by_room.has(entry["room"]):
			by_room[entry["room"]] = []
		by_room[entry["room"]].append(entry["pos"])
	var rooms: Array = by_room.keys()
	rooms.shuffle()
	var out := {}
	for i in labels.size():
		var room_name = rooms[i % rooms.size()]
		out[labels[i]] = by_room[room_name].pick_random()
	return out

var battery_spots: Array[Vector3] = [
	Vector3(4.2, FLR2, 6.6),   # second floor, beside the bed
	Vector3(4.5, 0.0, 7.5),    # on the kitchen floor
	Vector3(-1.4, 6.14, 10.3), # azotea, on the crate
	Vector3(3.5, 1.03, 15.5),  # CR, on the toilet tank (desperate places)
]
var dark_points: Array[Vector3] = [
	Vector3(-5.2, 0, 3.1), Vector3(-5.0, 0, -1.6), Vector3(-0.4, 0, -3.3),
	Vector3(2.6, 0, 1.4), Vector3(-0.2, 0, 2.6), Vector3(-3.0, 0, -0.4),
	Vector3(5.0, 0, -0.6), Vector3(2.0, 0, 3.2),
	# the new wing, ground floor
	Vector3(0.0, 0, 7.5), Vector3(5.2, 0, 6.5), Vector3(6.6, 0, 8.5),
	Vector3(-5.0, 0, 6.0), Vector3(0.0, 0, 11.0), Vector3(-5.5, 0, 11.0),
	# the second floor
	Vector3(5.5, 3.0, 6.0), Vector3(3.0, 3.0, 10.5),
	Vector3(-2.8, 3.0, 5.5), Vector3(-5.8, 3.0, 10.6),
	# the azotea (roof deck)
	Vector3(0.4, 5.6, 9.0), Vector3(-4.0, 5.6, 7.5), Vector3(-6.3, 5.6, 10.5),
	# the south rooms: sala, CR, second bedroom
	Vector3(-1.0, 0, 16.0), Vector3(1.0, 0, 14.0), Vector3(4.2, 0, 15.5),
	Vector3(6.7, 0, 13.5), Vector3(6.7, 0, 16.5),
]

# --- live props other scripts animate --------------------------------------
var nav_region: NavigationRegion3D
var bulb_light: OmniLight3D
var bulb_material: StandardMaterial3D
var bulb_audio: AudioStreamPlayer3D
var rocking_chair: Node3D
var kulambo: MeshInstance3D
var aparador_doors: Array[Node3D] = []
var balcony_door: Node3D
var hole_area: Area3D
var hiding_spots: Array = []
var light_switches: Array = []  # [{"sw": light_switch, "bounds": AABB}] — main.gd's light logic
var lures: Array = []           # noisemakers (radio/pipes/musicbox); main.gd wires the demon in
var chapel_door: Node3D         # the locked oratorio door (main.gd swings it open)
var chapel_door_area: Area3D    # senses the player at the chapel door (unlocks with key)

var _mats := {}


func _ready() -> void:
	for c in get_children():
		c.queue_free()
	build()


func build() -> void:
	nav_region = NavigationRegion3D.new()
	nav_region.name = "Nav"
	add_child(nav_region)
	_build_shell()
	_build_wing()
	_build_stairs()
	_build_second_floor()
	_build_azotea()
	_build_upstairs_light()
	_build_windows()
	_build_bulb()
	_build_aparador()
	_build_bed()
	_build_altar()
	_build_vanity()
	_build_rocking_chair()
	_build_floor_hole()
	_build_doors()
	_build_moon_blockers()
	_build_hiding_spots()
	_build_furniture_and_spots()
	_build_extension()
	_build_south_rooms()
	_build_atmosphere()
	if not Engine.is_editor_hint():
		_bake_navigation()


# =========================================================== materials
func _pbr(key: String, albedo: String, uv_scale: float, tint := Color.WHITE, normal := "", rough := "") -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(TEX + albedo)
	m.albedo_color = tint
	if normal != "":
		m.normal_enabled = true
		m.normal_texture = load(TEX + normal)
	if rough != "":
		m.roughness_texture = load(TEX + rough)
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * uv_scale
	_mats[key] = m
	return m


func _plain(key: String, color: Color, rough := 0.9, metal := 0.0) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	_mats[key] = m
	return m


func m_floor() -> StandardMaterial3D:
	return _pbr("floor", "tex_wood_narra_floor_albedo.png", 0.6, Color.WHITE,
		"tex_wood_narra_floor_normal.png", "tex_wood_narra_floor_rough.png")


func m_wall() -> StandardMaterial3D:
	return _pbr("wall", "tex_wall_plaster_albedo.png", 0.33, Color(0.85, 0.82, 0.78),
		"tex_wall_plaster_normal.png", "tex_wall_plaster_rough.png")


func m_wood() -> StandardMaterial3D:
	return _pbr("wood", "tex_wood_dark_albedo.png", 0.9, Color.WHITE,
		"tex_wood_dark_normal.png", "tex_wood_dark_rough.png")


func m_wood_red() -> StandardMaterial3D:
	return _pbr("wood_red", "tex_wood_dark_albedo.png", 0.9, Color(1.4, 0.75, 0.65),
		"tex_wood_dark_normal.png", "tex_wood_dark_rough.png")


# =========================================================== builders
func box(parent: Node, size: Vector3, pos: Vector3, mat: Material, collide := true, node_name := "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	if node_name != "":
		mi.name = node_name
	parent.add_child(mi)
	if collide:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		sb.add_child(cs)
		mi.add_child(sb)
	return mi


func cyl(parent: Node, radius: float, height: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 10
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


## Wall running along x (north/south walls).
func wall_x(x0: float, x1: float, y0: float, y1: float, z: float, mat: Material) -> void:
	box(nav_region, Vector3(x1 - x0, y1 - y0, T), Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, z), mat)


## Wall running along z (east/west walls).
func wall_z(z0: float, z1: float, y0: float, y1: float, x: float, mat: Material) -> void:
	box(nav_region, Vector3(T, y1 - y0, z1 - z0), Vector3(x, (y0 + y1) * 0.5, (z0 + z1) * 0.5), mat)


# =========================================================== room shell
func _build_shell() -> void:
	var w := m_wall()
	box(nav_region, Vector3(12.4, 0.2, 8.4), Vector3(0, -0.1, 0), m_floor(), true, "Floor")
	box(nav_region, Vector3(12.4, 0.2, 8.4), Vector3(0, ROOM_H + 0.1, 0), w, false, "Ceiling")
	# North wall with two window openings (x -3.5..-1.5 and 1.5..3.5, sill 1.0, head 2.4)
	var zn := -4.0 - T * 0.5
	wall_x(-6.2, -3.5, 0, ROOM_H, zn, w)
	wall_x(-1.5, 1.5, 0, ROOM_H, zn, w)
	wall_x(3.5, 6.2, 0, ROOM_H, zn, w)
	for wx in [-2.5, 2.5]:
		wall_x(wx - 1.0, wx + 1.0, 0, 1.0, zn, w)
		wall_x(wx - 1.0, wx + 1.0, 2.4, ROOM_H, zn, w)
	# South wall with the hallway door (x -0.7..0.7, height 2.1)
	var zs := 4.0 + T * 0.5
	wall_x(-6.2, -0.7, 0, ROOM_H, zs, w)
	wall_x(0.7, 6.2, 0, ROOM_H, zs, w)
	wall_x(-0.7, 0.7, 2.1, ROOM_H, zs, w)
	# East / west walls
	wall_z(-4.2, 4.2, 0, ROOM_H, -6.0 - T * 0.5, w)
	wall_z(-4.2, 4.2, 0, ROOM_H, 6.0 + T * 0.5, w)
	# Exposed ceiling beams
	for bx in [-3.0, 0.0, 3.0]:
		box(nav_region, Vector3(0.25, 0.3, 8.0), Vector3(bx, ROOM_H - 0.15, 0), m_wood(), false)
	# Door frame trim
	box(nav_region, Vector3(0.1, 2.2, 0.26), Vector3(-0.75, 1.1, 4.1), m_wood(), false)
	box(nav_region, Vector3(0.1, 2.2, 0.26), Vector3(0.75, 1.1, 4.1), m_wood(), false)
	box(nav_region, Vector3(1.6, 0.1, 0.26), Vector3(0, 2.15, 4.1), m_wood(), false)


## The ground floor of the wing: one slab of floor, the exterior shell, a narrow
## corridor spine off the bedroom door, and the kitchen / stair hall / back room.
func _build_wing() -> void:
	var w := m_wall()
	# one floor slab under the whole wing (x -7.5..8, z 4..12)
	box(nav_region, Vector3(15.9, 0.2, 8.4), Vector3(0.25, -0.1, 8.0), m_floor(), true, "WingFloor")

	# --- exterior shell (ground floor rises to the second-floor slab at FLR2) ---
	wall_x(-7.7, -6.0, 0, FLR2, 4.0, w)          # north, west of the bedroom
	wall_x(6.0, 8.2, 0, FLR2, 4.0, w)            # north, east of the bedroom
	# south wall with the oratorio door and three doorways into the south rooms
	# (sala x -1.6..0.0 · CR x 3.6..5.0 · second bedroom x 6.0..7.4)
	wall_x(-7.7, -5.8, 0, FLR2, 12.1, w)
	wall_x(-4.2, -1.6, 0, FLR2, 12.1, w)         # also seals the old sala-door leak into the chapel
	wall_x(0.0, 3.6, 0, FLR2, 12.1, w)
	wall_x(5.0, 6.0, 0, FLR2, 12.1, w)
	wall_x(7.4, 8.2, 0, FLR2, 12.1, w)
	wall_x(-5.8, -4.2, 2.1, FLR2, 12.1, w)       # lintel over the chapel door
	wall_x(-1.6, 0.0, 2.1, FLR2, 12.1, w)        # lintel over the sala door
	wall_x(3.6, 5.0, 2.1, FLR2, 12.1, w)         # lintel over the CR door
	wall_x(6.0, 7.4, 2.1, FLR2, 12.1, w)         # lintel over the bedroom door
	for jx in [-1.6, 0.0, 3.6, 5.0, 6.0, 7.4]:   # jambs for the south-room doors
		box(nav_region, Vector3(0.1, 2.2, 0.26), Vector3(jx, 1.1, 12.1), m_wood(), false)
	wall_z(4.0, 12.2, 0, FLR2, -7.6, w)          # west
	wall_z(4.0, 12.2, 0, FLR2, 8.1, w)           # east

	# --- narrow corridor spine, x -1.6..1.6, with a door each side ---
	# east wall (into the kitchen), doorway z 5.6..7.2
	wall_z(4.0, 5.6, 0, FLR2, 1.6, w)
	wall_z(7.2, 10.0, 0, FLR2, 1.6, w)
	wall_z(5.6, 7.2, 2.1, FLR2, 1.6, w)          # lintel over the kitchen door
	# west wall (into the stair hall), doorway z 5.6..7.2
	wall_z(4.0, 5.6, 0, FLR2, -1.6, w)
	wall_z(7.2, 10.0, 0, FLR2, -1.6, w)
	wall_z(5.6, 7.2, 2.1, FLR2, -1.6, w)         # lintel over the stair-hall door
	_door_trim(1.6, 6.4, true)
	_door_trim(-1.6, 6.4, true)

	# --- walls splitting the kitchen / stair hall from the back room (z 10) ---
	# kitchen south wall with a doorway (x 4.2..5.8) → a LOOP: corridor→kitchen→back room→corridor
	wall_x(1.6, 4.2, 0, FLR2, 10.0, w)
	wall_x(5.8, 8.0, 0, FLR2, 10.0, w)
	wall_x(4.2, 5.8, 2.1, FLR2, 10.0, w)         # lintel over the kitchen↔back-room door
	box(nav_region, Vector3(0.1, 2.2, 0.26), Vector3(4.2, 1.1, 10.0), m_wood(), false)  # jamb
	box(nav_region, Vector3(0.1, 2.2, 0.26), Vector3(5.8, 1.1, 10.0), m_wood(), false)  # jamb
	wall_x(-7.5, -1.6, 0, FLR2, 10.0, w)         # stair-hall south


## A plain wood door frame around a 1.6 m-tall opening centred on (x, z).
func _door_trim(x: float, z: float, along_z: bool) -> void:
	if along_z:
		box(nav_region, Vector3(0.1, 2.2, 0.26), Vector3(x, 1.1, z - 0.8), m_wood(), false)
		box(nav_region, Vector3(0.1, 2.2, 0.26), Vector3(x, 1.1, z + 0.8), m_wood(), false)
		box(nav_region, Vector3(0.12, 0.1, 1.86), Vector3(x, 2.15, z), m_wood(), false)


## A ramp of planks in the stair hall, climbing from the ground to the second floor.
func _build_stairs() -> void:
	var z_bottom := 4.3
	var z_top := 9.7
	var dz := z_top - z_bottom
	var length := sqrt(dz * dz + FLR2 * FLR2)
	var angle := atan2(FLR2, dz)
	var ramp := box(nav_region, Vector3(2.4, 0.2, length),
		Vector3(-6.0, FLR2 * 0.5, (z_bottom + z_top) * 0.5), m_wood(), true, "Stairs")
	ramp.rotation.x = -angle
	# tread lip on each plank seam, just for looks
	var treads := 9
	for i in treads:
		var t := float(i) / float(treads - 1)
		var lip := box(nav_region, Vector3(2.4, 0.04, 0.05),
			Vector3(-6.0, lerpf(0.0, FLR2, t) + 0.12, lerpf(z_bottom, z_top, t)), m_wood_red(), false)
		lip.rotation.x = -angle
	# side stringers so it reads as a staircase
	for sx in [-7.15, -4.85]:
		var s := box(nav_region, Vector3(0.12, 0.5, length),
			Vector3(sx, FLR2 * 0.5, (z_bottom + z_top) * 0.5), m_wood(), false)
		s.rotation.x = -angle


## The second floor: a split slab (an open stairwell over the ramp), the upper
## shell, two rooms divided by a wall, a landing, a ceiling and a safety railing.
func _build_second_floor() -> void:
	var w := m_wall()
	var y_top := FLR2 + H2
	# floor slab, leaving the stairwell open (x -7.5..-4.6, z 4..9.6)
	box(nav_region, Vector3(12.8, 0.2, 8.2), Vector3(1.7, FLR2 - 0.1, 8.0), m_floor(), true, "Floor2E")
	box(nav_region, Vector3(3.1, 0.2, 2.6), Vector3(-6.05, FLR2 - 0.1, 10.8), m_floor(), true, "Floor2W")
	# --- roof slab over the wing: the azotea deck. It opens (x 2.4..8.2, z 9.8..12.1)
	# where the ramp from the upstairs bedroom climbs through (see _build_azotea).
	box(nav_region, Vector3(10.4, 0.2, 8.1), Vector3(-2.5, y_top + 0.1, 8.05), m_floor(), true, "RoofW")
	box(nav_region, Vector3(5.8, 0.2, 5.8), Vector3(5.3, y_top + 0.1, 6.9), m_floor(), true, "RoofE")

	# --- upper exterior shell ---
	wall_x(-7.7, 8.2, FLR2, y_top, 4.0, w)       # north
	wall_x(-7.7, 8.2, FLR2, y_top, 12.1, w)      # south
	wall_z(4.0, 12.2, FLR2, y_top, -7.6, w)      # west
	wall_z(4.0, 12.2, FLR2, y_top, 8.1, w)       # east

	# --- divider between the storage room (west) and the bedroom (east) ---
	wall_z(4.0, 7.0, FLR2, y_top, 1.6, w)
	wall_z(8.6, 12.0, FLR2, y_top, 1.6, w)
	wall_z(7.0, 8.6, FLR2 + 2.0, y_top, 1.6, w)  # lintel
	_door_trim_at(1.6, 7.8, FLR2)

	# --- railing so you don't walk off into the stairwell (east edge of the hole) ---
	wall_z(4.0, 9.6, FLR2, FLR2 + 0.9, -4.6, w)
	for pz in [4.4, 5.6, 6.8, 8.0, 9.2]:
		cyl(nav_region, 0.025, 0.9, Vector3(-4.6, FLR2 + 0.45, pz), m_wood())


## The azotea: the flat roof deck over the wing. A wooden ramp climbs from the
## second-floor bedroom through the opening in the roof slab (built as RoofW/RoofE
## in _build_second_floor), and a waist-high parapet rings the edge so nobody falls.
## Games ending up there get a water-drum hiding spot, a laundry line, dead plants,
## a lone pool of moonlight — and their own share of the randomized item spots.
const AZ := FLR2 + H2 + 0.2   # top surface of the azotea deck (5.6)
func _build_azotea() -> void:
	var w := m_wall()
	var wd := m_wood()
	var iron := _plain("iron", Color(0.1, 0.1, 0.11), 0.55, 0.6)

	# --- parapet ringing the deck, one metre above its floor ---
	wall_x(-7.7, 8.2, AZ, AZ + 1.0, 4.0, w)
	wall_x(-7.7, 8.2, AZ, AZ + 1.0, 12.1, w)
	wall_z(4.0, 12.1, AZ, AZ + 1.0, -7.6, w)
	wall_z(4.0, 12.1, AZ, AZ + 1.0, 8.1, w)

	# --- the ramp up from the upstairs bedroom (floor FLR2, climb 2.6 m over 5.0 m) ---
	var rise := AZ - FLR2          # 2.6
	var run := 5.0
	var length := sqrt(rise * rise + run * run)
	var ang := atan2(rise, run)
	var ramp := box(nav_region, Vector3(length, 0.2, 2.0), Vector3(5.1, (FLR2 + AZ) * 0.5, 10.9), m_wood(), true, "AzoteaRamp")
	ramp.rotation.z = -ang
	for i in 10:                   # tread lips, so it reads as a staircase
		var t := float(i) / 9.0
		var lip := box(nav_region, Vector3(0.05, 0.04, 2.0),
			Vector3(lerpf(7.6, 2.6, t), lerpf(FLR2 + 0.12, AZ + 0.12, t), 10.9), m_wood_red(), false)
		lip.rotation.z = -ang
	for rz in [9.85, 11.95]:       # guard rails on both flanks (they collide — a fall kills the night)
		var rail := box(nav_region, Vector3(length, 0.6, 0.08), Vector3(5.1, (FLR2 + AZ) * 0.5 + 0.3, rz), m_wood(), true)
		rail.rotation.z = -ang

	# --- a galvanized water drum you can climb into ---
	var drum := Vector3(0.4, AZ, 6.0)
	cyl(nav_region, 0.55, 1.05, drum + Vector3(0, 0.525, 0), iron).name = "WaterDrum"
	cyl(nav_region, 0.5, 0.05, drum + Vector3(0, 1.075, 0), iron)
	_hide_spot("HideDrum", "cabinet",
		drum + Vector3(0, 0.62, 0), Vector3(0.95, 1.0, 0.95),
		drum + Vector3(0, 0.95, 0), drum + Vector3(0, 0.5, 3.6))

	# --- laundry line: two posts, a wire, and some hanging cloth ---
	for px in [-4.6, 1.6]:
		cyl(nav_region, 0.05, 1.9, Vector3(px, AZ + 0.95, 5.2), wd)
		box(nav_region, Vector3(0.05, 0.05, 0.6), Vector3(px, AZ + 1.72, 5.2), wd, false)
	for lz in [4.95, 5.45]:
		box(nav_region, Vector3(6.3, 0.02, 0.02), Vector3(-1.5, AZ + 1.7, lz), wd, false)
	var cloth_cols := [Color(0.45, 0.16, 0.14), Color(0.2, 0.26, 0.3), Color(0.5, 0.44, 0.32)]
	for i in cloth_cols.size():
		var cx := -3.4 + float(i) * 1.5
		var cloth := box(nav_region, Vector3(0.6, 0.7, 0.03), Vector3(cx, AZ + 1.25, 5.2), _plain("cloth%d" % i, cloth_cols[i]), false)
		cloth.rotation.z = deg_to_rad(randf_range(-3.0, 3.0))
		box(nav_region, Vector3(0.62, 0.03, 0.025), Vector3(cx, AZ + 1.62, 5.2), wd, false)

	# --- dead potted plants and a crate with everything dropped on it ---
	for p in [Vector3(-6.3, AZ, 10.6), Vector3(-5.5, AZ, 11.0)]:
		cyl(nav_region, 0.18, 0.3, p + Vector3(0, 0.15, 0), _plain("pot", Color(0.3, 0.22, 0.15), 0.85))
		var br := cyl(nav_region, 0.02, 0.5, p + Vector3(0.02, 0.5, -0.02), wd)
		br.rotation.z = deg_to_rad(14.0)
		var br2 := cyl(nav_region, 0.015, 0.4, p + Vector3(-0.02, 0.45, 0.04), wd)
		br2.rotation.x = deg_to_rad(-18.0)
	# a low wooden bench, another quest-item landing pad
	box(nav_region, Vector3(1.2, 0.4, 0.4), Vector3(-2.8, AZ + 0.2, 7.8), wd, true, "RoofBench")
	box(nav_region, Vector3(0.7, 0.5, 0.7), Vector3(-1.3, AZ + 0.25, 10.45), wd, true, "RoofCrate")

	# --- a lone pool of moonlight over the drum, otherwise open sky ---
	var moon := SpotLight3D.new()
	moon.name = "AzoteaMoon"
	moon.light_color = Color("7c9cc9")
	moon.light_energy = 4.0
	moon.spot_range = 10.0
	moon.spot_angle = 30.0
	moon.shadow_enabled = true
	moon.light_volumetric_fog_energy = 1.5
	var from := Vector3(1.6, 9.5, 7.5)
	var to := drum
	moon.transform = Transform3D(Basis.looking_at(to - from, Vector3.UP), from)
	add_child(moon)


## A found oil lamp on a crate near the top of the stairs — the one steady light
## up here, so the second floor isn't lit only by the flashlight.
func _build_upstairs_light() -> void:
	box(nav_region, Vector3(0.5, 0.5, 0.5), Vector3(-3.6, FLR2 + 0.25, 10.6), m_wood(), true, "LampCrate")
	# brass base
	var base := cyl(nav_region, 0.08, 0.04, Vector3(-3.6, FLR2 + 0.52, 10.6),
		_plain("brass", Color(0.35, 0.27, 0.12), 0.4, 0.8))
	base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# glowing glass chimney
	var glass := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.07
	cm.height = 0.18
	glass.mesh = cm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(1.0, 0.72, 0.38, 0.6)
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.emission_enabled = true
	gm.emission = Color("ffb45e")
	gm.emission_energy_multiplier = 2.8
	glass.material_override = gm
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glass.position = Vector3(-3.6, FLR2 + 0.63, 10.6)
	nav_region.add_child(glass)
	var lamp := OmniLight3D.new()
	lamp.name = "UpstairsLamp"
	lamp.light_color = Color("ffb45e")
	lamp.light_energy = 1.4
	lamp.omni_range = 6.0
	lamp.shadow_enabled = true
	lamp.light_volumetric_fog_energy = 1.0
	lamp.position = Vector3(-3.6, FLR2 + 0.66, 10.6)
	add_child(lamp)


## Door frame for a 2 m-tall opening on the second floor, centred on (x, z) at floor y.
func _door_trim_at(x: float, z: float, y: float) -> void:
	box(nav_region, Vector3(0.1, 2.0, 0.26), Vector3(x, y + 1.0, z - 0.8), m_wood(), false)
	box(nav_region, Vector3(0.1, 2.0, 0.26), Vector3(x, y + 1.0, z + 0.8), m_wood(), false)
	box(nav_region, Vector3(0.12, 0.1, 1.86), Vector3(x, y + 2.0, z), m_wood(), false)


## Solid, waist-high and enclosed furniture a crouching player can hide behind or
## inside. The demon raycasts to the camera, so these break its line of sight.
func _build_hiding_spots() -> void:
	var wd := m_wood()

	# --- kitchen: an L of counter (crouch behind it) + a pantry nook to duck into ---
	box(nav_region, Vector3(0.7, 0.9, 5.2), Vector3(7.55, 0.45, 6.9), wd, true, "CounterE")
	box(nav_region, Vector3(4.0, 0.9, 0.6), Vector3(4.0, 0.45, 4.6), wd, true, "CounterN")
	# a cast-iron stove sitting on the north counter
	box(nav_region, Vector3(0.9, 0.5, 0.55), Vector3(3.0, 1.15, 4.6), _plain("iron", Color(0.1, 0.1, 0.11), 0.5, 0.7), false)
	# --- a "KUSINA" sign over the doorway + a hanging pot rack, so the room reads as a kitchen ---
	box(nav_region, Vector3(1.2, 0.4, 0.05), Vector3(1.52, 2.33, 6.4), m_wood_red(), false, "KusinaSign")
	var kusina_sign := Label3D.new()
	kusina_sign.name = "KusinaLabel"
	kusina_sign.text = "KUSINA"
	kusina_sign.font_size = 96
	kusina_sign.pixel_size = 0.003
	kusina_sign.modulate = Color(0.96, 0.86, 0.62)
	kusina_sign.outline_size = 16
	kusina_sign.outline_modulate = Color(0.08, 0.06, 0.04)
	kusina_sign.rotation.y = -PI / 2.0        # face west, into the corridor the player comes down
	kusina_sign.position = Vector3(1.48, 2.33, 6.4)
	nav_region.add_child(kusina_sign)
	# a rod of hanging copper pots above the north counter, beside the stove
	var copper := _plain("copper", Color(0.5, 0.28, 0.14), 0.35, 0.8)
	box(nav_region, Vector3(1.6, 0.05, 0.05), Vector3(4.6, 1.78, 4.35),
		_plain("potrack", Color(0.12, 0.12, 0.13), 0.5, 0.7), false)
	for px in [4.0, 4.6, 5.2]:
		cyl(nav_region, 0.09, 0.2, Vector3(px, 1.6, 4.35), copper)
	# pantry nook, open to the north, in the kitchen's back corner
	wall_z(8.6, 9.8, 0, FLR2, 2.0, m_wall())
	wall_z(8.6, 9.8, 0, FLR2, 3.4, m_wall())
	wall_x(2.0, 3.4, 0, FLR2, 9.8, m_wall())
	box(nav_region, Vector3(1.3, 0.05, 0.4), Vector3(2.7, 1.3, 9.6), wd, false)  # a shelf

	# --- back room: stacked crates to crouch behind ---
	box(nav_region, Vector3(1.0, 1.0, 1.0), Vector3(-5.2, 0.5, 11.1), wd, true, "Crate")
	box(nav_region, Vector3(0.8, 0.8, 0.8), Vector3(-4.2, 0.4, 11.3), wd, true, "Crate2")

	# --- second floor: a step-in wardrobe (storage room) and a bed (bedroom) ---
	var y := FLR2
	# wardrobe against the storage room's north wall, open to the south
	box(nav_region, Vector3(1.2, 1.9, 0.1), Vector3(-2.5, y + 0.95, 4.2), wd, true, "WardrobeBack")
	box(nav_region, Vector3(0.1, 1.9, 1.2), Vector3(-3.1, y + 0.95, 4.8), wd, true)
	box(nav_region, Vector3(0.1, 1.9, 1.2), Vector3(-1.9, y + 0.95, 4.8), wd, true)
	box(nav_region, Vector3(1.2, 0.1, 1.2), Vector3(-2.5, y + 1.9, 4.8), wd, false)
	# upstairs bed — raised on legs so you can crawl underneath (HideBed2)
	box(nav_region, Vector3(1.6, 0.26, 2.0), Vector3(5.5, y + 0.62, 6.2), wd, true, "Bed2")
	box(nav_region, Vector3(1.5, 0.2, 1.9), Vector3(5.5, y + 0.85, 6.2), _plain("mattress", Color(0.33, 0.3, 0.26)), false)
	box(nav_region, Vector3(1.3, 0.1, 0.4), Vector3(5.5, y + 1.0, 5.4), _plain("pillow", Color(0.42, 0.39, 0.34)), false)
	for lx in [-0.72, 0.72]:
		for lz in [-0.9, 0.9]:
			cyl(nav_region, 0.05, 0.5, Vector3(5.5 + lx, y + 0.25, 6.2 + lz), wd)


# =========================================================== enterable hiding
## A spot the player can climb into. `center`/`size` is the trigger box the crosshair
## must land on; `cam_pos`/`look_target` place the low peep-out camera.
func _hide_spot(nm: String, kind: String, center: Vector3, size: Vector3, cam_pos: Vector3, look_target: Vector3) -> void:
	var a := HideSpotScript.new()
	a.name = nm
	a.spot_name = nm
	a.spot_kind = kind
	a.cam_pos = cam_pos
	a.look_target = look_target
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	a.add_child(cs)
	a.position = center
	add_child(a)
	hiding_spots.append(a)


## A low dining table (legs + overhang the demon can't path under) and a slatted
## paminggalan cabinet in the kitchen, plus the enter-triggers for the bed, the
## upstairs wardrobe, the table and the cabinet.
func _build_furniture_and_spots() -> void:
	var wd := m_wood()

	# --- kitchen dining table: crawl under it, two open sides ---
	var tc := Vector3(4.0, 0.0, 7.5)
	box(nav_region, Vector3(1.8, 0.1, 1.0), tc + Vector3(0, 0.74, 0), wd, true, "Table")
	for lx in [-0.8, 0.8]:
		for lz in [-0.4, 0.4]:
			cyl(nav_region, 0.05, 0.74, tc + Vector3(lx, 0.37, lz), wd)

	# --- kitchen paminggalan (slatted cabinet), open toward +x ---
	var co := Vector3(2.3, 0.0, 8.6)
	box(nav_region, Vector3(0.05, 1.9, 0.9), co + Vector3(0.0, 0.95, 0), wd, true, "Cabinet")
	box(nav_region, Vector3(0.7, 1.9, 0.05), co + Vector3(0.34, 0.95, -0.42), wd, true)
	box(nav_region, Vector3(0.7, 1.9, 0.05), co + Vector3(0.34, 0.95, 0.42), wd, true)
	box(nav_region, Vector3(0.75, 0.05, 0.95), co + Vector3(0.34, 1.9, 0), wd, false)
	box(nav_region, Vector3(0.75, 0.05, 0.95), co + Vector3(0.34, 0.03, 0), wd, false)
	for sy in [0.45, 0.8, 1.15, 1.5]:  # slats across the open front — peek through the gaps
		box(nav_region, Vector3(0.04, 0.06, 0.78), co + Vector3(0.69, sy, 0), wd, false)

	# --- the enter-triggers ---
	# under the four-poster bed in Ang Silid (the signature scare)
	_hide_spot("HideUnderBed", "under_bed",
		Vector3(4.68, 0.38, -2.46), Vector3(1.5, 1.0, 2.0),
		Vector3(4.68, 0.33, -2.3), Vector3(2.0, 0.2, 0.4))
	# under the kitchen table
	_hide_spot("HideUnderTable", "under_table",
		Vector3(tc.x, 0.42, tc.z), Vector3(1.5, 0.85, 0.85),
		Vector3(tc.x, 0.34, tc.z + 0.1), Vector3(1.8, 0.2, 6.2))
	# inside the kitchen cabinet
	_hide_spot("HideCabinet", "cabinet",
		co + Vector3(0.34, 1.0, 0), Vector3(0.55, 1.6, 0.75),
		co + Vector3(0.34, 1.05, 0), co + Vector3(2.6, 0.95, 0))
	# inside the upstairs wardrobe (storage room), open to the south
	_hide_spot("HideWardrobe", "cabinet",
		Vector3(-2.5, FLR2 + 1.0, 4.8), Vector3(1.0, 1.6, 0.9),
		Vector3(-2.5, FLR2 + 1.05, 4.7), Vector3(-2.5, FLR2 + 0.95, 6.5))
	# inside the Ang Silid aparador (now hollow), doors open to the south
	_hide_spot("HideAparador", "cabinet",
		Vector3(-4.8, 1.0, -3.42), Vector3(1.7, 1.8, 0.45),
		Vector3(-4.8, 1.1, -3.42), Vector3(-4.8, 1.0, -1.2))
	# under the upstairs bed in the second-floor bedroom
	_hide_spot("HideBed2", "under_bed",
		Vector3(5.5, FLR2 + 0.38, 6.2), Vector3(1.4, 1.0, 1.8),
		Vector3(5.5, FLR2 + 0.33, 6.45), Vector3(5.5, FLR2 + 0.2, 8.5))


# =========================================================== extension (loop + chapel)
## The oratorio (chapel): a locked reward room south of the back room holding the
## final candle, plus two more hiding spots (a tapayan jar and a curtain) and the
## matches/key the task chain needs. The kitchen↔back-room doorway (cut in
## _build_wing) adds the loop the player can run the demon around.
func _build_extension() -> void:
	var w := m_wall()
	var wd := m_wood()

	# --- chapel shell, z 12.1..17.6, x -7.6..-2.0 (opens north through the door) ---
	box(nav_region, Vector3(5.8, 0.2, 5.6), Vector3(-4.8, -0.1, 14.85), m_floor(), true, "ChapelFloor")
	box(nav_region, Vector3(5.8, 0.2, 5.6), Vector3(-4.8, FLR2 + 0.1, 14.85), w, false, "ChapelCeil")
	wall_z(12.1, 17.6, 0, FLR2, -7.6, w)         # west
	wall_z(12.1, 17.6, 0, FLR2, -2.0, w)         # east
	wall_x(-7.6, -2.0, 0, FLR2, 17.6, w)         # south

	# --- the locked oratorio door, hinged, swings open when you have the key ---
	chapel_door = Node3D.new()
	chapel_door.name = "ChapelDoor"
	chapel_door.position = Vector3(-5.8, 0, 12.1)
	nav_region.add_child(chapel_door)
	box(chapel_door, Vector3(1.6, 2.08, 0.08), Vector3(0.8, 1.04, 0), m_wood_red())
	box(chapel_door, Vector3(0.05, 0.3, 0.06), Vector3(1.45, 1.0, 0.07),
		_plain("brass", Color(0.35, 0.27, 0.12), 0.4, 0.8), false)
	chapel_door_area = Area3D.new()
	chapel_door_area.name = "ChapelDoorSense"
	chapel_door_area.collision_layer = 0
	chapel_door_area.collision_mask = 4   # players
	var das := CollisionShape3D.new()
	var dash := BoxShape3D.new()
	dash.size = Vector3(2.2, 2.2, 2.2)
	das.shape = dash
	chapel_door_area.add_child(das)
	chapel_door_area.position = Vector3(-5.0, 1.1, 12.1)
	add_child(chapel_door_area)

	# --- chapel altar (candle "D" sits here) + a faint sanctuary lamp ---
	box(nav_region, Vector3(1.4, 0.9, 0.5), Vector3(-4.8, 0.45, 17.1), wd, true, "ChapelAltar")
	box(nav_region, Vector3(1.5, 0.02, 0.6), Vector3(-4.8, 0.91, 17.1),
		_plain("altar_cloth", Color(0.5, 0.44, 0.38)), false)
	var lamp := OmniLight3D.new()
	lamp.name = "ChapelLamp"
	lamp.light_color = Color("c48cff")
	lamp.light_energy = 0.8
	lamp.omni_range = 5.0
	lamp.shadow_enabled = true
	lamp.position = Vector3(-4.8, 2.4, 14.8)
	add_child(lamp)

	# --- back room: a big tapayan (clay jar) you can climb into ---
	var jar := Vector3(6.4, 0, 11.2)
	cyl(nav_region, 0.55, 1.3, jar + Vector3(0, 0.65, 0), _plain("tapayan", Color(0.28, 0.2, 0.14), 0.8)).name = "Tapayan"
	cyl(nav_region, 0.42, 0.2, jar + Vector3(0, 1.35, 0), _plain("tapayan", Color(0.28, 0.2, 0.14), 0.8))  # rim
	_hide_spot("HideJar", "cabinet",
		jar + Vector3(0, 0.7, 0), Vector3(1.0, 1.1, 1.0),
		jar + Vector3(0, 1.0, 0), jar + Vector3(0, 0.6, -2.0))

	# --- second-floor bedroom: a heavy curtain to slip behind ---
	var cur := Vector3(7.4, FLR2, 5.2)
	var cloth := _plain("curtain", Color(0.24, 0.1, 0.12), 0.95)
	box(nav_region, Vector3(0.08, 2.1, 1.6), cur + Vector3(0, 1.05, 0), cloth, true, "Curtain")
	_hide_spot("HideCurtain", "cabinet",
		cur + Vector3(-0.3, 1.0, 0), Vector3(0.7, 1.8, 1.4),
		cur + Vector3(-0.4, 1.0, 0), cur + Vector3(-2.4, 0.9, 0))


# =========================================================== south rooms (sala · CR · bedroom 2)
## Three furnished rooms south of the back room, entered from z=12.1 doorways cut
## in _build_wing: a sala (sofa, coffee table, radio, old TV), a CR (toilet, sink,
## a tub you can wedge into, the clanking pipes) and a second bedroom (crawl-under
## bed, dresser, music box). Each gets a ceiling lamp + a wall switch: flip it and
## any Esmiringhoy caught inside the lit room recoils and keeps its distance.
func _build_south_rooms() -> void:
	var w := m_wall()
	var wd := m_wood()

	# --- shell: one floor slab + ceiling over all three rooms, shared walls ---
	box(nav_region, Vector3(10.2, 0.2, 5.6), Vector3(3.1, -0.1, 14.85), m_floor(), true, "SouthFloor")
	box(nav_region, Vector3(10.2, 0.2, 5.6), Vector3(3.1, FLR2 + 0.1, 14.85), w, false, "SouthCeil")
	wall_x(-2.0, 8.2, 0, FLR2, 17.6, w)          # south exterior
	wall_z(12.1, 17.7, 0, FLR2, 8.1, w)          # east exterior
	wall_z(12.1, 17.6, 0, FLR2, 3.1, w)          # sala | CR divider
	wall_z(12.1, 17.6, 0, FLR2, 5.3, w)          # CR | bedroom divider

	# --------------------------------------------------------------------- sala
	# a roomy living room; the north-west doorway (x -1.6..0.0) stays clear.
	# sofa centred in the room, back to the north, facing the TV on the south wall
	var sofa := Vector3(1.2, 0.0, 14.2)
	box(nav_region, Vector3(2.2, 0.95, 0.18), sofa + Vector3(0, 0.475, -0.42), wd, true)   # back
	box(nav_region, Vector3(2.2, 0.35, 0.7), sofa + Vector3(0, 0.235, 0), wd, true)        # seat box
	box(nav_region, Vector3(2.0, 0.16, 0.62), sofa + Vector3(0, 0.44, 0.02),
		_plain("sofa_cloth", Color(0.3, 0.15, 0.16)), false)                               # cushion
	for arm_x in [-1.05, 1.05]:
		box(nav_region, Vector3(0.16, 0.55, 0.8), sofa + Vector3(arm_x, 0.275, 0), wd, true)  # arms
	# a low coffee table between the sofa and the TV
	var ct := Vector3(1.2, 0.0, 15.6)
	box(nav_region, Vector3(1.2, 0.06, 0.9), ct + Vector3(0, 0.42, 0), wd, true)
	for l in [Vector3(-0.52, 0.19, -0.38), Vector3(0.52, 0.19, -0.38),
				Vector3(-0.52, 0.19, 0.38), Vector3(0.52, 0.19, 0.38)]:
		cyl(nav_region, 0.04, 0.38, ct + l, wd)
	# side table with the radio on it, and a rug
	box(nav_region, Vector3(0.5, 0.66, 0.5), Vector3(2.5, 0.33, 14.2), wd, true, "SideTable")
	box(nav_region, Vector3(2.4, 0.02, 2.6), Vector3(1.2, 0.012, 15.0),
		_plain("rug", Color(0.26, 0.14, 0.14)), false)
	# an old TV cabinet with the television on top, on the south wall facing the sofa
	box(nav_region, Vector3(1.8, 0.75, 0.5), Vector3(1.2, 0.375, 17.15), wd, true, "TVCabinet")
	box(nav_region, Vector3(1.1, 0.75, 0.35), Vector3(1.2, 1.13, 17.05),
		_plain("iron", Color(0.08, 0.08, 0.09), 0.4, 0.6), false)                           # TV shell
	var screen := MeshInstance3D.new()
	var sq := QuadMesh.new()
	sq.size = Vector2(0.85, 0.6)
	screen.mesh = sq
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.05, 0.05, 0.06)
	smat.emission_enabled = true
	smat.emission = Color(0.12, 0.16, 0.2)
	smat.emission_energy_multiplier = 0.35
	screen.material_override = smat
	screen.position = Vector3(1.2, 1.13, 16.85)
	screen.rotation.y = PI                       # face north, toward the sofa
	nav_region.add_child(screen)

	# ---------------------------------------------------------------------- CR
	# toilet against the west wall, toward the back
	var porcelain := _plain("porcelain", Color(0.75, 0.74, 0.7), 0.3)
	cyl(nav_region, 0.22, 0.38, Vector3(3.55, 0.19, 15.5), porcelain)
	box(nav_region, Vector3(0.5, 0.55, 0.22), Vector3(3.5, 0.72, 15.5), wd, false)    # tank
	box(nav_region, Vector3(0.5, 0.04, 0.24), Vector3(3.5, 1.01, 15.5),
		_plain("tank_lid", Color(0.68, 0.66, 0.62), 0.35), false)                     # lid
	# sink on a pedestal, by the east wall near the door
	cyl(nav_region, 0.11, 0.75, Vector3(4.95, 0.375, 13.1), porcelain)
	cyl(nav_region, 0.24, 0.09, Vector3(4.95, 0.82, 13.1), porcelain)                 # basin
	# a tub along the south wall — walls 0.7 high so a wedged-in head stays below the rim
	var tub := Vector3(4.2, 0.0, 16.8)
	box(nav_region, Vector3(1.4, 0.08, 1.2), tub + Vector3(0, 0.04, 0), wd, true, "TubFloor")
	box(nav_region, Vector3(1.4, 0.7, 0.1), tub + Vector3(0, 0.35, -0.6), wd, true)   # north rim
	box(nav_region, Vector3(1.4, 0.7, 0.1), tub + Vector3(0, 0.35, 0.6), wd, true)    # south rim
	box(nav_region, Vector3(0.1, 0.7, 1.2), tub + Vector3(-0.65, 0.35, 0), wd, true)  # west rim
	box(nav_region, Vector3(0.1, 0.7, 1.2), tub + Vector3(0.65, 0.35, 0), wd, true)   # east rim
	_hide_spot("HideTub", "cabinet",
		tub + Vector3(0, 0.32, 0), Vector3(1.1, 0.5, 1.05),
		tub + Vector3(0, 0.45, 0), tub + Vector3(0, 0.35, -2.4))

	# --------------------------------------------------------- second bedroom
	# a bed you can crawl under (the hide camera sits in the crawl gap)
	box(nav_region, Vector3(1.6, 0.26, 2.0), Vector3(6.7, 0.62, 15.6), wd, true, "Bed3")
	box(nav_region, Vector3(1.5, 0.2, 1.9), Vector3(6.7, 0.85, 15.6),
		_plain("mattress", Color(0.33, 0.3, 0.26)), false)
	box(nav_region, Vector3(1.3, 0.1, 0.4), Vector3(6.7, 1.0, 14.75),
		_plain("pillow", Color(0.42, 0.39, 0.34)), false)
	for lx in [-0.72, 0.72]:
		for lz in [-0.9, 0.9]:
			cyl(nav_region, 0.05, 0.5, Vector3(6.7 + lx, 0.25, 15.6 + lz), wd)
	_hide_spot("HideBed3", "under_bed",
		Vector3(6.7, 0.38, 15.6), Vector3(1.4, 1.0, 1.8),
		Vector3(6.7, 0.33, 14.85), Vector3(6.7, 0.25, 13.0))
	# a dresser holding the music box
	box(nav_region, Vector3(0.9, 0.92, 0.45), Vector3(7.6, 0.46, 17.2), wd, true, "Dresser")

	# ------------------------------------------------------------ lights + lures
	_room_light("kitchen", Vector3(5.0, 2.85, 7.0), Vector3(7.6, 1.3, 4.12),
		Vector3(1.7, 0, 4.2), Vector3(8.0, 3, 9.9), 0.0)
	_room_light("bodega", Vector3(0.0, 2.85, 11.0), Vector3(7.6, 1.3, 10.15),
		Vector3(-7.5, 0, 10.05), Vector3(8.0, 3, 12.05), 0.0)
	_room_light("sala", Vector3(0.5, 2.8, 14.8), Vector3(0.2, 1.3, 12.35),
		Vector3(-1.95, 0, 12.2), Vector3(2.95, 3, 17.55), 0.0)
	_room_light("CR", Vector3(4.2, 2.8, 14.8), Vector3(3.3, 1.3, 12.35),
		Vector3(3.25, 0, 12.2), Vector3(5.25, 3, 17.55), 0.0)
	_room_light("kuarto", Vector3(6.7, 2.8, 14.8), Vector3(5.7, 1.3, 12.35),
		Vector3(5.45, 0, 12.2), Vector3(8.05, 3, 17.55), 0.0)

	var lure_defs := {
		"radio": Vector3(2.5, 0.66, 14.2),     # the sala side table
		"pipes": Vector3(5.1, 0.0, 15.0),      # the CR east wall, past the sink
		"musicbox": Vector3(7.6, 0.92, 17.2),  # on the bedroom dresser
	}
	for nm in lure_defs:
		var lure = NoisemakerScript.new()
		lure.name = "Lure_" + nm               # deterministic, so co-op can sync
		lure.label = nm
		lure.kind = nm
		add_child(lure)
		lure.position = lure_defs[nm]
		lures.append(lure)


## A ceiling bulb (starts dark) + a wall switch, registered for main.gd.
## `face_rot` points the switch plate into the room it controls.
func _room_light(nm: String, bulb: Vector3, switch_pos: Vector3, bmin: Vector3, bmax: Vector3, face_rot: float) -> void:
	var lamp := OmniLight3D.new()
	lamp.name = "Lamp_" + nm
	lamp.light_color = Color("ffd9a0")
	lamp.light_energy = 0.0
	lamp.omni_range = 6.5
	lamp.shadow_enabled = true
	lamp.position = bulb
	add_child(lamp)
	cyl(nav_region, 0.06, 0.35, bulb + Vector3(0, 0.22, 0), _plain("cord", Color(0.05, 0.04, 0.04)))
	var sw = SwitchScript.new()
	sw.name = "Switch_" + nm       # deterministic node path, so co-op can sync the flip
	sw.label = nm
	sw.light = lamp
	sw.bounds = AABB(bmin, bmax - bmin)
	add_child(sw)
	sw.position = switch_pos
	sw.rotation.y = face_rot
	# face plate + a nub that faintly glows so you can find it in the dark
	box(sw, Vector3(0.15, 0.24, 0.035), Vector3(0, 0, 0.02), m_wood(), false)
	var nub_mat := StandardMaterial3D.new()
	nub_mat.albedo_color = Color(0.85, 0.8, 0.7)
	nub_mat.roughness = 0.35
	nub_mat.emission_enabled = true
	nub_mat.emission = Color(1.0, 0.95, 0.8)
	nub_mat.emission_energy_multiplier = 0.4
	var nub := box(sw, Vector3(0.06, 0.09, 0.035), Vector3(0, -0.02, 0.05), nub_mat, false)
	nub.name = "Nub"
	light_switches.append({"sw": sw, "bounds": sw.bounds})


# =========================================================== windows + moon
func _build_windows() -> void:
	var cap := ShaderMaterial.new()
	cap.shader = SHADER_CAPIZ
	cap.set_shader_parameter("capiz_tex", load(TEX + "tex_capiz_shell.png"))
	cap.set_shader_parameter("tiling", Vector2(1.5, 1.05))
	for wx in [-2.5, 2.5]:
		var pane := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(2.0, 1.4)
		pane.mesh = q
		pane.material_override = cap
		pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pane.position = Vector3(wx, 1.7, -4.05)
		nav_region.add_child(pane)
		# frame + mullion
		box(nav_region, Vector3(2.1, 0.08, 0.14), Vector3(wx, 2.4, -4.05), m_wood(), false)
		box(nav_region, Vector3(2.1, 0.08, 0.14), Vector3(wx, 1.0, -4.05), m_wood(), false)
		box(nav_region, Vector3(0.06, 1.4, 0.1), Vector3(wx, 1.7, -4.05), m_wood(), false)
		# moonlight from outside, through the shell panes
		var moon := SpotLight3D.new()
		moon.name = "Moonlight"
		moon.light_color = Color("7c9cc9")
		moon.light_energy = 9.0
		moon.spot_range = 13.0
		moon.spot_angle = 24.0
		moon.shadow_enabled = true
		moon.light_volumetric_fog_energy = 2.0
		var from := Vector3(wx * 1.15, 4.6, -7.5)
		var to := Vector3(wx, 0.0, -1.8)
		moon.transform = Transform3D(Basis.looking_at(to - from, Vector3.UP), from)
		add_child(moon)


func _build_bulb() -> void:
	var cord := cyl(nav_region, 0.008, 0.7, Vector3(0, ROOM_H - 0.35, 0), _plain("cord", Color(0.05, 0.04, 0.04)))
	cord.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bulb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.06
	sm.height = 0.13
	bulb.mesh = sm
	bulb_material = StandardMaterial3D.new()
	bulb_material.albedo_color = Color("ffb45e")
	bulb_material.emission_enabled = true
	bulb_material.emission = Color("ffb45e")
	bulb_material.emission_energy_multiplier = 3.0
	bulb.material_override = bulb_material
	bulb.position = Vector3(0, ROOM_H - 0.76, 0)
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	nav_region.add_child(bulb)
	bulb_light = OmniLight3D.new()
	bulb_light.name = "Bulb"
	bulb_light.light_color = Color("ffb45e")
	bulb_light.light_energy = 2.0
	bulb_light.omni_range = 5.0
	bulb_light.shadow_enabled = true
	bulb_light.position = Vector3(0, ROOM_H - 0.85, 0)
	add_child(bulb_light)
	if not Engine.is_editor_hint():
		bulb_audio = AudioStreamPlayer3D.new()
		var s: AudioStreamOggVorbis = load("res://assets/audio/sfx_bulb_buzz.ogg")
		s.loop = true
		bulb_audio.stream = s
		bulb_audio.volume_db = -14.0
		bulb_audio.unit_size = 2.0
		bulb_audio.autoplay = true
		bulb_audio.position = bulb_light.position
		add_child(bulb_audio)


# =========================================================== props
func _build_aparador() -> void:
	var root := Node3D.new()
	root.name = "Aparador"
	root.position = Vector3(-4.8, 0, -3.5)
	nav_region.add_child(root)
	# hollow shell (open at the front, +z) so you can climb inside and hide
	box(root, Vector3(2.0, 2.2, 0.08), Vector3(0, 1.1, -0.26), m_wood())    # back
	box(root, Vector3(0.08, 2.2, 0.6), Vector3(-0.96, 1.1, 0), m_wood())    # left
	box(root, Vector3(0.08, 2.2, 0.6), Vector3(0.96, 1.1, 0), m_wood())     # right
	box(root, Vector3(2.0, 0.08, 0.6), Vector3(0, 2.16, 0), m_wood(), false)  # top
	box(root, Vector3(2.0, 0.08, 0.6), Vector3(0, 0.04, 0), m_wood(), false)  # bottom
	box(root, Vector3(2.12, 0.12, 0.7), Vector3(0, 2.26, 0), m_wood(), false)  # cornice
	for side in [-1, 1]:
		var hinge := Node3D.new()
		hinge.position = Vector3(side * 1.0, 0, 0.31)
		root.add_child(hinge)
		box(hinge, Vector3(0.98, 2.0, 0.04), Vector3(-side * 0.49, 1.1, 0.02), m_wood(), false)
		hinge.rotation.y = deg_to_rad(side * 4.0)
		aparador_doors.append(hinge)


func _build_bed() -> void:
	var root := Node3D.new()
	root.name = "Bed"
	root.position = Vector3(4.68, 0, -2.46)
	nav_region.add_child(root)
	# raised frame on short legs: a dark gap underneath you can crawl into
	box(root, Vector3(1.8, 0.26, 2.2), Vector3(0, 0.62, 0), m_wood())
	box(root, Vector3(1.7, 0.2, 2.1), Vector3(0, 0.85, 0), _plain("mattress", Color(0.33, 0.3, 0.26)), false)
	box(root, Vector3(1.4, 0.12, 0.4), Vector3(0, 1.01, -0.82), _plain("pillow", Color(0.42, 0.39, 0.34)), false)
	for lx in [-0.82, 0.82]:
		for lz in [-1.0, 1.0]:
			cyl(root, 0.05, 0.5, Vector3(lx, 0.25, lz), m_wood())
	for px in [-0.86, 0.86]:
		for pz in [-1.06, 1.06]:
			cyl(root, 0.05, 2.3, Vector3(px, 1.15, pz), m_wood())
	box(root, Vector3(1.8, 0.06, 0.06), Vector3(0, 2.28, -1.06), m_wood(), false)
	box(root, Vector3(1.8, 0.06, 0.06), Vector3(0, 2.28, 1.06), m_wood(), false)
	box(root, Vector3(0.06, 0.06, 2.2), Vector3(-0.86, 2.28, 0), m_wood(), false)
	box(root, Vector3(0.06, 0.06, 2.2), Vector3(0.86, 2.28, 0), m_wood(), false)
	# kulambo (mosquito net) hanging from the canopy
	var net := StandardMaterial3D.new()
	net.albedo_texture = load(TEX + "tex_fabric_net.png")
	net.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	net.cull_mode = BaseMaterial3D.CULL_DISABLED
	net.uv1_scale = Vector3(3, 2, 1)
	net.roughness = 1.0
	kulambo = MeshInstance3D.new()
	var nb := BoxMesh.new()
	nb.size = Vector3(1.86, 1.55, 2.26)
	kulambo.mesh = nb
	kulambo.material_override = net
	kulambo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	kulambo.position = Vector3(0, 1.5, 0)
	root.add_child(kulambo)


func _build_altar() -> void:
	var root := Node3D.new()
	root.name = "Altar"
	root.position = Vector3(5.55, 0, 0.9)
	nav_region.add_child(root)
	box(root, Vector3(0.65, 0.95, 1.7), Vector3(0, 0.475, 0), m_wood())
	box(root, Vector3(0.7, 0.02, 1.75), Vector3(0, 0.96, 0), _plain("altar_cloth", Color(0.52, 0.47, 0.4)), false)
	# the faceless santo
	var stone := _plain("santo", Color(0.62, 0.58, 0.5), 0.65)
	box(root, Vector3(0.26, 0.1, 0.26), Vector3(0.05, 1.02, 0.35), m_wood(), false)
	var body := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.09
	cm.height = 0.52
	body.mesh = cm
	body.material_override = stone
	body.position = Vector3(0.05, 1.33, 0.35)
	root.add_child(body)
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.075
	hm.height = 0.17
	head.mesh = hm
	head.material_override = stone
	head.position = Vector3(0.05, 1.66, 0.35)
	root.add_child(head)


func _build_vanity() -> void:
	var root := Node3D.new()
	root.name = "Vanity"
	root.position = Vector3(4.14, 0, 3.54)
	nav_region.add_child(root)
	box(root, Vector3(1.7, 0.8, 0.6), Vector3(0, 0.4, 0), m_wood())
	box(root, Vector3(1.0, 1.2, 0.05), Vector3(0, 1.5, 0.3), m_wood(), false)
	var glass := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.84, 1.04)
	glass.mesh = q
	glass.material_override = _plain("mirror", Color(0.12, 0.13, 0.14), 0.06, 1.0)
	glass.position = Vector3(0, 1.5, 0.27)
	glass.rotation.y = PI  # face into the room (-z)
	root.add_child(glass)


func _build_rocking_chair() -> void:
	var root := Node3D.new()
	root.name = "TumbaTumba"
	root.position = Vector3(-3.64, 0, 1.75)
	root.rotation.y = deg_to_rad(35)
	nav_region.add_child(root)
	# collider stays still; only the visual rocks
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.6, 1.1, 0.8)
	cs.shape = sh
	cs.position = Vector3(0, 0.55, 0)
	sb.add_child(cs)
	root.add_child(sb)
	rocking_chair = Node3D.new()
	rocking_chair.name = "Rock"
	root.add_child(rocking_chair)
	var wd := m_wood()
	for sx in [-0.26, 0.26]:
		box(rocking_chair, Vector3(0.05, 0.05, 0.9), Vector3(sx, 0.03, 0), wd, false)
		cyl(rocking_chair, 0.025, 0.42, Vector3(sx, 0.24, -0.2), wd)
		cyl(rocking_chair, 0.025, 0.42, Vector3(sx, 0.24, 0.2), wd)
		var post := cyl(rocking_chair, 0.025, 0.75, Vector3(sx, 0.82, 0.24), wd)
		post.rotation.x = deg_to_rad(-12)
	box(rocking_chair, Vector3(0.56, 0.05, 0.5), Vector3(0, 0.46, 0), _plain("rattan", Color(0.36, 0.28, 0.18)), false)
	var back := box(rocking_chair, Vector3(0.52, 0.6, 0.03), Vector3(0, 0.85, 0.27), _plain("rattan", Color(0.36, 0.28, 0.18)), false)
	back.rotation.x = deg_to_rad(-12)


func _build_floor_hole() -> void:
	var c := Vector3(-1.07, 0, -0.64)
	var void_mat := StandardMaterial3D.new()
	void_mat.albedo_color = Color.BLACK
	void_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	box(nav_region, Vector3(1.3, 0.01, 0.9), c + Vector3(0, 0.006, 0), void_mat, false)
	var plank := m_wood()
	var p1 := box(nav_region, Vector3(0.14, 0.04, 0.8), c + Vector3(-0.35, 0.02, 0.1), plank, false)
	p1.rotation = Vector3(deg_to_rad(8), deg_to_rad(12), 0)
	var p2 := box(nav_region, Vector3(0.14, 0.04, 0.6), c + Vector3(0.4, 0.0, -0.1), plank, false)
	p2.rotation = Vector3(deg_to_rad(-14), deg_to_rad(-20), deg_to_rad(6))
	hole_area = Area3D.new()
	hole_area.name = "BrokenFloor"
	hole_area.collision_layer = 0
	hole_area.collision_mask = 4 | 8  # players and demons
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.3, 0.6, 0.9)
	cs.shape = sh
	hole_area.add_child(cs)
	hole_area.position = c + Vector3(0, 0.3, 0)
	add_child(hole_area)


func _build_doors() -> void:
	# open hallway door, swung into the room
	var hinge := Node3D.new()
	hinge.position = Vector3(-0.7, 0, 3.95)
	hinge.rotation.y = deg_to_rad(80)
	nav_region.add_child(hinge)
	box(hinge, Vector3(1.38, 2.08, 0.05), Vector3(0.69, 1.04, 0), m_wood())
	# locked balcony door on the west wall
	balcony_door = Node3D.new()
	balcony_door.name = "BalconyDoor"
	balcony_door.position = Vector3(-5.95, 0, 0.07)
	nav_region.add_child(balcony_door)
	box(balcony_door, Vector3(0.07, 2.1, 1.2), Vector3(0, 1.05, 0), m_wood_red(), false)
	box(balcony_door, Vector3(0.04, 0.3, 0.06), Vector3(0.05, 1.0, 0.45), _plain("brass", Color(0.35, 0.27, 0.12), 0.4, 0.8), false)


## Invisible blockers over the moonlit floor patches. They sit on physics layer 2,
## which players ignore but the navigation bake includes, so the demon paths around them.
func _build_moon_blockers() -> void:
	for wx in [-2.5, 2.5]:
		var sb := StaticBody3D.new()
		sb.name = "MoonPatch"
		sb.collision_layer = 2
		sb.collision_mask = 0
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(1.6, 2.0, 1.2)
		cs.shape = sh
		sb.add_child(cs)
		sb.position = Vector3(wx, 1.0, -3.2)
		nav_region.add_child(sb)


func _build_atmosphere() -> void:
	# thicker fog pooling in the dark corners
	for p in [Vector3(-5.0, 1.2, 3.0), Vector3(-5.0, 1.2, -3.0), Vector3(5.0, 1.0, 3.2)]:
		var fv := FogVolume.new()
		fv.size = Vector3(2.5, 2.8, 2.5)
		var fm := FogMaterial.new()
		fm.density = 0.12
		fm.albedo = Color(0.45, 0.47, 0.52)
		fm.edge_fade = 0.6
		fv.material = fm
		fv.position = p
		add_child(fv)
	# dust on the floor
	var dust: Texture2D = load(TEX + "tex_decal_dust.png")
	var spots := [Vector3(-2.0, 0, 2.0), Vector3(1.5, 0, -1.0), Vector3(-4.5, 0, -1.0), Vector3(2.8, 0, 2.4), Vector3(0.5, 0, 5.4)]
	for i in spots.size():
		var d := Decal.new()
		d.texture_albedo = dust
		d.size = Vector3(1.8, 0.6, 1.8)
		d.position = spots[i] + Vector3(0, 0.1, 0)
		d.rotation.y = i * 1.3
		d.modulate = Color(1, 1, 1, 0.8)
		add_child(d)


func _bake_navigation() -> void:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.cell_size = 0.1      # must match navigation/3d/default_cell_size in project.godot
	nm.cell_height = 0.1
	nm.agent_radius = 0.4  # 4 cells: fits through the 1.4 m doorway
	nm.agent_height = 1.8
	nm.agent_max_climb = 0.3
	nm.agent_max_slope = 45.0  # lets the bake include the ~29° stair ramp to the 2nd floor
	nav_region.navigation_mesh = nm
	nav_region.bake_navigation_mesh(false)
