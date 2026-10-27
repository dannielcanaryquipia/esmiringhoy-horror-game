extends Area3D
## A spot the player can climb into (under the bed, under a table, inside a cabinet)
## to break the Esmiringhoy's line of sight. Built by room.gd.
##
## The player reparents the camera to `cam_pos` / `look_target` while hidden and cannot
## move. Walking in unseen keeps you safe; the demon can still drag you out if it
## SAW you hide, if you RUN in while it hunts, or if you don't hold your breath when
## it comes to check. Physics layer 6 (bit value 32), detected by the player's ray.

@export var spot_name := ""
@export var spot_kind := "cabinet"   # "under_bed", "under_table", "cabinet"

var cam_pos := Vector3.ZERO          # world position of the hidden viewpoint
var look_target := Vector3.ZERO      # world point the hidden camera faces
var yaw_limit := deg_to_rad(70.0)    # how far you may turn your head while hidden
var pitch_limit := deg_to_rad(28.0)
var occupied := false


func _ready() -> void:
	collision_layer = 32   # layer 6: hiding spots
	collision_mask = 0
	monitoring = false
	add_to_group("hiding_spots")
	set_meta("hide_spot", self)
