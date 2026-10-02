extends Node

const PORT: int = 31415
const MAX_PLAYERS: int = 4
const ChessRules = preload("res://scripts/Chess.gd")
const Locale = preload("res://scripts/Locale.gd")

signal lobby_changed(players: Array, status: String)
signal game_changed(board: Array, turn_slot: int, status: String, move_text: String)
signal network_message(text: String)
signal connection_state(text: String)

var language: String = "ru"
var is_host: bool = false
var players: Array = []
var my_slot: int = -1
var pending_slot: int = 0
var my_name: String = ""
var started: bool = false
var board: Array = []
var turn_slot: int = 0
var turn_team: int = ChessRules.WHITE
var castling: Dictionary = {"K": true, "Q": true, "k": true, "q": true}
var en_passant := Vector2i(-1, -1)
var game_status: String = ""
var move_text: String = ""
var network_mode: int = 4

func _ready() -> void:
    multiplayer.peer_connected.connect(_on_peer_connected)
    multiplayer.peer_disconnected.connect(_on_peer_disconnected)
    multiplayer.connected_to_server.connect(_on_connected)
    multiplayer.connection_failed.connect(_on_connection_failed)
    multiplayer.server_disconnected.connect(_on_server_disconnected)
    _reset_state()

func set_language(value: String) -> void:
    language = "en" if value == "en" else "ru"

func set_network_mode(mode: int) -> void:
    network_mode = 4 if mode == 4 else 2
    if not started:
        pending_slot = pending_slot if pending_slot in _active_slots() else _first_empty_slot()

func T(key: String) -> String:
    return Locale.t(key, language)

func set_pending_slot(slot: int) -> void:
    var active: Array[int] = _active_slots()
    if slot in active:
        pending_slot = slot

func _reset_state() -> void:
    board = ChessRules.initial_board()
    turn_slot = 0
    turn_team = ChessRules.WHITE
    castling = {"K": true, "Q": true, "k": true, "q": true}
    en_passant = Vector2i(-1, -1)
    move_text = ""

func host_game(player_name: String, mode: int = 4, requested_slot: int = 0) -> Error:
    _disconnect()
    is_host = true
    network_mode = 4 if mode == 4 else 2
    my_name = player_name.strip_edges()
    if my_name.is_empty():
        my_name = "desu"
    var active: Array[int] = _active_slots()
    pending_slot = requested_slot if requested_slot in active else active[0]
    players = [null, null, null, null]
    my_slot = pending_slot
    players[my_slot] = {
        "peer_id": 1,
        "name": my_name,
        "team": _team_for_slot(my_slot)
    }
    started = false
    _reset_state()
    var peer := ENetMultiplayerPeer.new()
    var err: Error = peer.create_server(PORT, MAX_PLAYERS - 1)
    if err != OK:
        is_host = false
        my_slot = -1
        players = [null, null, null, null]
        pending_slot = 0
        return err
    multiplayer.multiplayer_peer = peer
    _update_lobby_status()
    _broadcast_lobby()
    connection_state.emit(_host_addresses_text())
    return OK

func join_game(ip: String, player_name: String, mode: int = 4, requested_slot: int = 0) -> Error:
    _disconnect()
    is_host = false
    network_mode = 4 if mode == 4 else 2
    my_name = player_name.strip_edges()
    if my_name.is_empty():
        my_name = "desu"
    var active: Array[int] = _active_slots()
    pending_slot = requested_slot if requested_slot in active else active[0]
    ip = ip.strip_edges()
    if ip.is_empty():
        return ERR_INVALID_PARAMETER
    var peer := ENetMultiplayerPeer.new()
    var err: Error = peer.create_client(ip, PORT)
    if err != OK:
        return err
    multiplayer.multiplayer_peer = peer
    connection_state.emit("Connecting…" if language == "en" else "Подключение к %s:%d…" % [ip, PORT])
    return OK

func change_slot(slot: int) -> Error:
    if started:
        return ERR_BUSY
    if slot not in _active_slots():
        return ERR_INVALID_PARAMETER
    if is_host:
        _host_change_slot(slot)
    elif multiplayer.multiplayer_peer != null:
        server_change_slot.rpc_id(1, slot, my_name)
    else:
        pending_slot = slot
    return OK

func _host_change_slot(slot: int) -> void:
    if my_slot == slot:
        return
    if players.size() != MAX_PLAYERS:
        players = [null, null, null, null]
    if players[slot] != null:
        network_message.emit(T("slot_taken"))
        return
    var old_slot: int = my_slot
    if old_slot < 0 or players[old_slot] == null:
        return
    players[slot] = players[old_slot]
    players[slot].team = _team_for_slot(slot)
    players[old_slot] = null
    my_slot = slot
    _update_lobby_status()
    _broadcast_lobby()

func start_game() -> void:
    if not is_host:
        return
    var needed: int = 4 if network_mode == 4 else 2
    var count: int = _player_count()
    if count < needed:
        network_message.emit(T("need_4") if network_mode == 4 else T("need_2"))
        return
    started = true
    _reset_state()
    turn_slot = _active_slots()[0]
    turn_team = _team_for_slot(turn_slot)
    game_status = _turn_status_for_slot(turn_slot)
    move_text = T("game_started")
    _broadcast_state()

func request_move(from: Vector2i, to: Vector2i, promotion: int = ChessRules.QUEEN) -> void:
    if not started or my_slot < 0 or players.size() != MAX_PLAYERS:
        return
    if my_slot != turn_slot:
        network_message.emit(T("other_player"))
        return
    var my_team: int = int(players[my_slot].team)
    if my_team != turn_team:
        network_message.emit(T("other_team"))
        return
    if is_host:
        _server_move(1, from.x, from.y, to.x, to.y, promotion)
    else:
        server_move.rpc_id(1, from.x, from.y, to.x, to.y, promotion)

@rpc("any_peer", "reliable")
func server_join(player_name: String, requested_mode: int, requested_slot: int) -> void:
    if not multiplayer.is_server() or started:
        return
    var id: int = multiplayer.get_remote_sender_id()
    if requested_mode != network_mode:
        rpc_id(id, "client_error", T("wrong_game_type"))
        return
    for p: Variant in players:
        if p != null and int(p.peer_id) == id:
            return
    var active: Array[int] = _active_slots()
    var slot: int = requested_slot if requested_slot in active else -1
    if network_mode == 2 and (slot < 0 or players[slot] != null):
        slot = _first_empty_slot()
    if slot < 0 or players[slot] != null:
        rpc_id(id, "client_error", T("slot_taken"))
        return
    players[slot] = {
        "peer_id": id,
        "name": (player_name.strip_edges() if not player_name.strip_edges().is_empty() else "Player"),
        "team": _team_for_slot(slot)
    }
    _update_lobby_status()
    _broadcast_lobby()

@rpc("any_peer", "reliable")
func server_change_slot(requested_slot: int, player_name: String) -> void:
    if not multiplayer.is_server() or started:
        return
    var id: int = multiplayer.get_remote_sender_id()
    var old_slot: int = _slot_for_peer(id)
    if old_slot < 0:
        if requested_slot in _active_slots() and players[requested_slot] == null:
            players[requested_slot] = {
                "peer_id": id,
                "name": player_name,
                "team": _team_for_slot(requested_slot)
            }
            _update_lobby_status()
            _broadcast_lobby()
        else:
            rpc_id(id, "client_error", T("slot_taken"))
        return
    if requested_slot not in _active_slots() or (players[requested_slot] != null and requested_slot != old_slot):
        rpc_id(id, "client_error", T("slot_taken"))
        return
    if requested_slot == old_slot:
        return
    players[requested_slot] = players[old_slot]
    players[requested_slot].team = _team_for_slot(requested_slot)
    players[old_slot] = null
    _broadcast_lobby()

@rpc("any_peer", "reliable")
func server_move(fx: int, fy: int, tx: int, ty: int, promotion: int) -> void:
    if not multiplayer.is_server():
        return
    var id: int = multiplayer.get_remote_sender_id()
    _server_move(id, fx, fy, tx, ty, promotion)

func _server_move(peer_id: int, fx: int, fy: int, tx: int, ty: int, promotion: int) -> void:
    if not started:
        return
    var slot: int = _slot_for_peer(peer_id)
    if slot < 0 or slot != turn_slot:
        if peer_id == 1:
            network_message.emit(T("other_player"))
        else:
            rpc_id(peer_id, "client_error", T("other_player"))
        return
    var current_team: int = _team_for_slot(turn_slot)
    if current_team != turn_team:
        turn_team = current_team
    var mv: Dictionary = ChessRules.find_move(board, turn_team, Vector2i(fx, fy), Vector2i(tx, ty), promotion, castling, en_passant)
    if mv.is_empty():
        if peer_id == 1:
            network_message.emit(T("invalid"))
        else:
            rpc_id(peer_id, "client_error", T("invalid"))
        return
    var result: Dictionary = ChessRules.make_move(board, mv, castling, en_passant)
    board = result.board
    castling = result.castling
    en_passant = result.en_passant
    var moving_player: String = str(players[slot].name)
    move_text = "%s: %s–%s" % [moving_player, ChessRules.algebraic(Vector2i(fx, fy)), ChessRules.algebraic(Vector2i(tx, ty))]

    var next_slot: int = _next_turn_slot(turn_slot)
    turn_slot = next_slot
    turn_team = _team_for_slot(turn_slot)
    var st: Dictionary = ChessRules.status(board, turn_team, castling, en_passant)
    if st.mate:
        started = false
        game_status = T("mate_white") if turn_team == ChessRules.BLACK else T("mate_black")
    elif st.stalemate:
        started = false
        game_status = T("stalemate")
    elif st.check:
        game_status = (T("check_white") if turn_team == ChessRules.WHITE else T("check_black")) + " • " + _turn_status_for_slot(turn_slot)
    else:
        game_status = _turn_status_for_slot(turn_slot)
    _broadcast_state()

@rpc("authority", "reliable")
func client_lobby_sync(data: Array, status_text: String, mode: int) -> void:
    players = data
    network_mode = mode
    my_slot = _slot_for_peer(multiplayer.get_unique_id())
    game_status = status_text
    lobby_changed.emit(players, game_status)

@rpc("authority", "reliable")
func client_state_sync(new_board: Array, new_turn_slot: int, new_castling: Dictionary, new_ep: Vector2i, new_started: bool, status_text: String, last_move: String) -> void:
    board = new_board
    turn_slot = new_turn_slot
    turn_team = _team_for_slot(turn_slot)
    castling = new_castling
    en_passant = new_ep
    started = new_started
    game_status = status_text
    move_text = last_move
    game_changed.emit(board, turn_slot, game_status, move_text)

@rpc("authority", "reliable")
func client_error(text: String) -> void:
    network_message.emit(text)

func _broadcast_lobby() -> void:
    client_lobby_sync.rpc(players, game_status, network_mode)
    lobby_changed.emit(players, game_status)

func _broadcast_state() -> void:
    client_state_sync.rpc(board, turn_slot, castling, en_passant, started, game_status, move_text)
    game_changed.emit(board, turn_slot, game_status, move_text)

func _on_peer_connected(_id: int) -> void:
    if multiplayer.is_server():
        _update_lobby_status()
        _broadcast_lobby()

func _on_peer_disconnected(id: int) -> void:
    var slot: int = _slot_for_peer(id)
    if slot < 0:
        return
    if multiplayer.is_server():
        players[slot] = null
        started = false
        _reset_state()
        _update_lobby_status()
        _broadcast_lobby()

func _on_connected() -> void:
    connection_state.emit(T("connected"))
    server_join.rpc_id(1, my_name, network_mode, pending_slot)

func _on_connection_failed() -> void:
    connection_state.emit("Connection failed." if language == "en" else "Не удалось подключиться. Проверьте IP и Wi‑Fi/точку доступа.")

func _on_server_disconnected() -> void:
    _close_network_peer()
    is_host = false
    started = false
    my_slot = -1
    pending_slot = 0
    players = [null, null, null, null]
    _reset_state()
    game_status = T("host_disconnected")
    connection_state.emit(game_status)

func _active_slots() -> Array[int]:
    var active: Array[int] = []
    if network_mode == 4:
        active.assign([0, 1, 2, 3])
    else:
        active.assign([0, 2])
    return active

func _team_for_slot(slot: int) -> int:
    return ChessRules.WHITE if slot < 2 else ChessRules.BLACK

func _next_turn_slot(current_slot: int) -> int:
    # In 2x2 mode the turn alternates colors exactly like normal chess,
    # while the two teammates take turns on their color: Player 1 (White),
    # Player 3 (Black), Player 2 (White), Player 4 (Black), then repeat.
    if network_mode == 4:
        var team_order: Array[int] = []
        team_order.append(0)
        team_order.append(2)
        team_order.append(1)
        team_order.append(3)
        var team_index: int = team_order.find(current_slot)
        if team_index < 0:
            return team_order[0]
        return team_order[(team_index + 1) % team_order.size()]

    var active: Array[int] = _active_slots()
    var active_index: int = active.find(current_slot)
    if active_index < 0:
        return active[0]
    return active[(active_index + 1) % active.size()]

func _turn_status_for_slot(slot: int) -> String:
    if slot < 0 or slot >= players.size() or players[slot] == null:
        return T("waiting")
    var team_name: String = T("white_team") if _team_for_slot(slot) == ChessRules.WHITE else T("black_team")
    return T("turn_player") % [slot + 1, team_name]

func _first_empty_slot() -> int:
    for slot: int in _active_slots():
        if slot >= players.size() or players[slot] == null:
            return slot
    return -1

func _slot_for_peer(id: int) -> int:
    for i: int in range(MAX_PLAYERS):
        if players.size() > i and players[i] != null and int(players[i].peer_id) == id:
            return i
    return -1

func _player_count() -> int:
    var count: int = 0
    for slot: int in _active_slots():
        if players[slot] != null:
            count += 1
    return count

func _update_lobby_status() -> void:
    var count: int = _player_count()
    if network_mode == 4:
        game_status = T("lobby_full") if count == 4 else Locale.format("lobby_wait_4", count, language)
    else:
        game_status = T("lobby_full") if count == 2 else Locale.format("lobby_wait_2", count, language)

func _close_network_peer() -> void:
    var old_peer: MultiplayerPeer = multiplayer.multiplayer_peer
    multiplayer.multiplayer_peer = null
    if old_peer != null and old_peer is ENetMultiplayerPeer:
        (old_peer as ENetMultiplayerPeer).close()

func _disconnect() -> void:
    _close_network_peer()
    is_host = false
    started = false
    my_slot = -1
    pending_slot = 0
    players = [null, null, null, null]
    _reset_state()

func stop_host() -> void:
    _close_network_peer()
    is_host = false
    started = false
    players = [null, null, null, null]
    my_slot = -1
    pending_slot = 0
    _reset_state()
    game_status = ""

func _host_addresses_text() -> String:
    if not is_host:
        return ""
    var found: Array[String] = []
    for addr: String in IP.get_local_addresses():
        if addr.contains(":") or addr == "127.0.0.1":
            continue
        var parts: PackedStringArray = addr.split(".")
        if parts.size() == 4:
            var a: int = int(parts[0])
            var b: int = int(parts[1])
            var private_ip: bool = (a == 10) or (a == 192 and b == 168) or (a == 172 and b >= 16 and b <= 31)
            if private_ip and addr not in found:
                found.append(addr)
    if found.is_empty():
        for addr: String in IP.get_local_addresses():
            if not addr.contains(":") and addr != "127.0.0.1" and addr not in found:
                found.append(addr)
    if found.is_empty():
        return "PORT: %d" % PORT
    var list_text: Array[String] = []
    for addr: String in found:
        list_text.append("%s:%d" % [addr, PORT])
    var prefix: String = "Host address for connection:" if language == "en" else "Адрес хоста для подключения:"
    return prefix + "\n" + "\n".join(list_text)
