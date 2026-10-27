extends Node
## LAN co-op networking over ENet (same Wi-Fi). Autoload name: `Net`.
## The whole game stays single-player unless `active` is true, so hosting/joining
## is purely additive — "Enter Ang Silid" in the lobby is still offline solo.

signal peers_changed        # someone joined/left the lobby
signal joined               # we (a client) connected to the host
signal join_failed          # could not reach the host
signal disconnected         # the host went away
signal start_game           # the host pressed Start — everyone load the house

const PORT := 24567
const MAX_PLAYERS := 4

var active := false
var spawn_index := {}       # peer_id -> 0,1,2,3 (used to offset spawn points)


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peers_changed)
	multiplayer.peer_disconnected.connect(_on_peers_changed)
	multiplayer.connected_to_server.connect(func() -> void: joined.emit())
	multiplayer.connection_failed.connect(func() -> void: _reset(); join_failed.emit())
	multiplayer.server_disconnected.connect(func() -> void: _reset(); disconnected.emit())


func host() -> bool:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(PORT, MAX_PLAYERS) != OK:
		return false
	multiplayer.multiplayer_peer = peer
	active = true
	_reindex()
	peers_changed.emit()
	return true


func join(ip: String) -> bool:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(ip, PORT) != OK:
		return false
	multiplayer.multiplayer_peer = peer
	active = true
	return true


func is_host() -> bool:
	return active and multiplayer.is_server()


func my_id() -> int:
	return multiplayer.get_unique_id() if active else 1


## Every player id (host is always 1), sorted — identical on every machine.
func peer_ids() -> Array:
	if not active:
		return [1]
	var ids := [1]
	for id in multiplayer.get_peers():
		ids.append(id)
	ids.sort()
	return ids


func start() -> void:
	if is_host():
		_do_start.rpc()


@rpc("authority", "call_local", "reliable")
func _do_start() -> void:
	start_game.emit()


func leave() -> void:
	_reset()
	peers_changed.emit()


func local_ip() -> String:
	for a in IP.get_local_addresses():
		if a.begins_with("192.168.") or a.begins_with("10.") or a.begins_with("172."):
			return a
	return "127.0.0.1"


func _reset() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	active = false
	spawn_index.clear()


func _on_peers_changed(_id: int) -> void:
	_reindex()
	peers_changed.emit()


func _reindex() -> void:
	spawn_index.clear()
	var i := 0
	for id in peer_ids():
		spawn_index[id] = i
		i += 1
