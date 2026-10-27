extends Node

signal changed

var mouse_sens: float = 0.0022
var invert_y: bool = false
var fov: float = 72.0
var master_volume: float = 1.0
var brightness: float = 1.0

func _ready() -> void:
	load_cfg()
	apply_audio()

func set_sens(v: float) -> void:
	mouse_sens = v
	save_cfg()
	changed.emit()

func set_invert(v: bool) -> void:
	invert_y = v
	save_cfg()
	changed.emit()

func set_fov(v: float) -> void:
	fov = clampf(v, 60.0, 90.0)
	save_cfg()
	changed.emit()

func set_master(v: float) -> void:
	master_volume = clampf(v, 0.0, 1.0)
	apply_audio()
	save_cfg()
	changed.emit()

func set_brightness(v: float) -> void:
	brightness = clampf(v, 0.5, 1.5)
	save_cfg()
	changed.emit()

func apply_audio() -> void:
	var bus_idx: int = AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus_idx, linear_to_db(maxf(master_volume, 0.0001)))

func save_cfg() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("settings", "mouse_sens", mouse_sens)
	cfg.set_value("settings", "invert_y", invert_y)
	cfg.set_value("settings", "fov", fov)
	cfg.set_value("settings", "master_volume", master_volume)
	cfg.set_value("settings", "brightness", brightness)
	cfg.save("user://settings.cfg")

func load_cfg() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	var err: int = cfg.load("user://settings.cfg")
	if err != OK:
		return
	mouse_sens = cfg.get_value("settings", "mouse_sens", mouse_sens)
	invert_y = cfg.get_value("settings", "invert_y", invert_y)
	fov = cfg.get_value("settings", "fov", fov)
	master_volume = cfg.get_value("settings", "master_volume", master_volume)
	brightness = cfg.get_value("settings", "brightness", brightness)
