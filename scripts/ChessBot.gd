class_name ChessBot
extends RefCounted

const ChessRules = preload("res://scripts/Chess.gd")

const VALUES: Dictionary = {
    1: 100,
    2: 320,
    3: 330,
    4: 500,
    5: 900,
    6: 20000
}

# Piece-square bonuses. Values are centipawns and mirrored for Black.
const PAWN_TABLE: Array[int] = [
    0, 0, 0, 0, 0, 0, 0, 0,
    55, 60, 45, 35, 35, 45, 60, 55,
    18, 18, 22, 28, 28, 22, 18, 18,
    10, 10, 14, 22, 22, 14, 10, 10,
    8, 8, 10, 18, 18, 10, 8, 8,
    10, 10, 12, -8, -8, 12, 10, 10,
    12, 12, 12, -14, -14, 12, 12, 12,
    0, 0, 0, 0, 0, 0, 0, 0
]
const KNIGHT_TABLE: Array[int] = [
    -50, -35, -25, -25, -25, -25, -35, -50,
    -35, -10, 0, 8, 8, 0, -10, -35,
    -25, 0, 12, 18, 18, 12, 0, -25,
    -25, 8, 18, 24, 24, 18, 8, -25,
    -25, 8, 18, 24, 24, 18, 8, -25,
    -25, 0, 12, 18, 18, 12, 0, -25,
    -35, -10, 0, 8, 8, 0, -10, -35,
    -50, -35, -25, -25, -25, -25, -35, -50
]
const BISHOP_TABLE: Array[int] = [
    -20, -10, -10, -10, -10, -10, -10, -20,
    -10, 5, 0, 5, 5, 0, 5, -10,
    -10, 10, 12, 12, 12, 12, 10, -10,
    -10, 5, 12, 16, 16, 12, 5, -10,
    -10, 5, 12, 16, 16, 12, 5, -10,
    -10, 10, 12, 12, 12, 12, 10, -10,
    -10, 5, 0, 5, 5, 0, 5, -10,
    -20, -10, -10, -10, -10, -10, -10, -20
]
const ROOK_TABLE: Array[int] = [
    0, 0, 5, 8, 8, 5, 0, 0,
    -5, 0, 0, 0, 0, 0, 0, -5,
    -5, 0, 0, 0, 0, 0, 0, -5,
    -5, 0, 0, 0, 0, 0, 0, -5,
    -5, 0, 0, 0, 0, 0, 0, -5,
    -5, 0, 0, 0, 0, 0, 0, -5,
    8, 12, 12, 14, 14, 12, 12, 8,
    0, 0, 5, 8, 8, 5, 0, 0
]
const QUEEN_TABLE: Array[int] = [
    -20, -10, -10, 0, 0, -10, -10, -20,
    -10, 0, 5, 5, 5, 5, 0, -10,
    -10, 5, 5, 8, 8, 5, 5, -10,
    0, 5, 8, 10, 10, 8, 5, 0,
    0, 5, 8, 10, 10, 8, 5, 0,
    -10, 5, 5, 8, 8, 5, 5, -10,
    -10, 0, 5, 5, 5, 5, 0, -10,
    -20, -10, -10, 0, 0, -10, -10, -20
]
const KING_TABLE: Array[int] = [
    -45, -55, -55, -65, -65, -55, -55, -45,
    -45, -55, -55, -65, -65, -55, -55, -45,
    -35, -45, -45, -55, -55, -45, -45, -35,
    -25, -35, -35, -45, -45, -35, -35, -25,
    -10, -20, -20, -25, -25, -20, -20, -10,
    20, 15, 10, 0, 0, 10, 15, 20,
    30, 35, 25, 10, 10, 25, 35, 30,
    30, 35, 25, 10, 10, 25, 35, 30
]

var transposition: Dictionary = {}
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var difficulty: int = 3
var search_deadline_us: int = 0
var search_aborted: bool = false

func _init(level: int = 3) -> void:
    rng.randomize()
    difficulty = clampi(level, 1, 5)

func choose_move(board: Array, color: int, castling: Dictionary, en_passant: Vector2i) -> Dictionary:
    var moves: Array = ChessRules.legal_moves(board, color, castling, en_passant)
    if moves.is_empty():
        return {}

    # Fast levels: no deep search, so response is effectively immediate.
    if difficulty == 1:
        if rng.randf() < 0.90:
            return moves[rng.randi_range(0, moves.size() - 1)]
        return _best_of(moves, board, color, castling, en_passant, 1)

    if difficulty == 2:
        var scored: Array = []
        for mv: Dictionary in moves:
            var result: Dictionary = ChessRules.make_move(board, mv, castling, en_passant)
            var score: int = _evaluate_for(result.board, color, result.castling, result.en_passant)
            score += rng.randi_range(-65, 65)
            scored.append({"move": mv, "score": score})
        scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.score) > int(b.score))
        return scored[rng.randi_range(0, min(2, scored.size() - 1))].move

    # Stronger levels use iterative deepening. Because this runs on a worker
    # thread, the UI stays responsive while the engine searches.
    var target_depth: int
    var budget_ms: int
    match difficulty:
        3:
            target_depth = 3
            budget_ms = 450
        4:
            target_depth = 4
            budget_ms = 850
        _:
            target_depth = 5
            budget_ms = 1400

    transposition.clear()
    var best_move: Dictionary = _fallback_move(moves, board, color, castling, en_passant)
    search_deadline_us = Time.get_ticks_usec() + budget_ms * 1000

    for depth: int in range(1, target_depth + 1):
        search_aborted = false
        var result: Dictionary = _search_root(moves, board, color, castling, en_passant, depth)
        if bool(result.get("completed", false)) and result.get("move", {}).size() > 0:
            best_move = result.move
        else:
            break

    search_deadline_us = 0
    search_aborted = false
    return best_move

func _fallback_move(moves: Array, board: Array, color: int, castling: Dictionary, en_passant: Vector2i) -> Dictionary:
    var best: Dictionary = moves[0]
    var best_score: int = -1000000000
    for mv: Dictionary in moves:
        var result: Dictionary = ChessRules.make_move(board, mv, castling, en_passant)
        var score: int = _evaluate_for(result.board, color, result.castling, result.en_passant)
        score += rng.randi_range(-8, 8)
        if score > best_score:
            best_score = score
            best = mv
    return best

func _search_root(moves: Array, board: Array, color: int, castling: Dictionary, en_passant: Vector2i, depth: int) -> Dictionary:
    var best_score: int = -1000000000
    var best_move: Dictionary = {}
    var ordered: Array = _order_moves(moves, board)
    for mv: Dictionary in ordered:
        if _time_up():
            search_aborted = true
            return {"completed": false, "move": best_move}
        var result: Dictionary = ChessRules.make_move(board, mv, castling, en_passant)
        var score: int = _search(result.board, -color, result.castling, result.en_passant, depth - 1, -1000000000, 1000000000, color)
        if search_aborted:
            return {"completed": false, "move": best_move}
        if score > best_score or best_move.is_empty():
            best_score = score
            best_move = mv
    return {"completed": true, "move": best_move}

func _best_of(moves: Array, board: Array, color: int, castling: Dictionary, en_passant: Vector2i, depth: int) -> Dictionary:
    var best_score: int = -1000000000
    var best: Array = []
    for mv: Dictionary in moves:
        var result: Dictionary = ChessRules.make_move(board, mv, castling, en_passant)
        var score: int = _search(result.board, -color, result.castling, result.en_passant, depth - 1, -1000000000, 1000000000, color)
        if score > best_score:
            best_score = score
            best.clear()
            best.append(mv)
        elif score == best_score:
            best.append(mv)
    if best.is_empty():
        return moves[0]
    return best[rng.randi_range(0, best.size() - 1)]

func _search(board: Array, side: int, castling: Dictionary, en_passant: Vector2i, depth: int, alpha: int, beta: int, root_color: int) -> int:
    if _time_up():
        search_aborted = true
        return 0

    var key: String = _position_key(board, side, castling, en_passant, depth)
    var alpha_original: int = alpha
    var beta_original: int = beta
    if transposition.has(key):
        var entry: Dictionary = transposition[key]
        var flag: String = str(entry.get("flag", ""))
        var cached: int = int(entry.get("value", 0))
        if flag == "exact":
            return cached
        if flag == "lower" and cached >= beta:
            return cached
        if flag == "upper" and cached <= alpha:
            return cached

    var state: Dictionary = ChessRules.status(board, side, castling, en_passant)
    if state.mate:
        return (-900000 - depth) if side == root_color else (900000 + depth)
    if state.stalemate:
        return 0
    if depth <= 0:
        var q: int = _quiescence(board, side, castling, en_passant, alpha, beta, root_color, 2)
        transposition[key] = {"value": q, "flag": "exact"}
        return q

    var moves: Array = ChessRules.legal_moves(board, side, castling, en_passant)
    if moves.is_empty():
        return _static_evaluate(board, root_color)

    var maximizing: bool = side == root_color
    var best: int = -1000000000 if maximizing else 1000000000
    var ordered: Array = _order_moves(moves, board)
    for mv: Dictionary in ordered:
        if _time_up():
            search_aborted = true
            return 0
        var result: Dictionary = ChessRules.make_move(board, mv, castling, en_passant)
        var score: int = _search(result.board, -side, result.castling, result.en_passant, depth - 1, alpha, beta, root_color)
        if search_aborted:
            return 0
        if maximizing:
            if score > best:
                best = score
            if best > alpha:
                alpha = best
        else:
            if score < best:
                best = score
            if best < beta:
                beta = best
        if beta <= alpha:
            break

    var store_flag: String = "exact"
    if best <= alpha_original:
        store_flag = "upper"
    elif best >= beta_original:
        store_flag = "lower"
    transposition[key] = {"value": best, "flag": store_flag}
    return best

func _quiescence(board: Array, side: int, castling: Dictionary, en_passant: Vector2i, alpha: int, beta: int, root_color: int, remaining: int) -> int:
    if _time_up():
        search_aborted = true
        return 0
    var stand_pat: int = _static_evaluate(board, root_color)
    var maximizing: bool = side == root_color
    if remaining <= 0:
        return stand_pat
    if maximizing and stand_pat >= beta:
        return stand_pat
    if not maximizing and stand_pat <= alpha:
        return stand_pat
    if maximizing:
        alpha = max(alpha, stand_pat)
    else:
        beta = min(beta, stand_pat)

    var all_moves: Array = ChessRules.legal_moves(board, side, castling, en_passant)
    var tactical: Array = []
    for mv: Dictionary in all_moves:
        var target: int = abs(int(board[mv.to.y][mv.to.x]))
        var moving_piece: int = abs(int(board[mv.from.y][mv.from.x]))
        var pawn_promotion: bool = moving_piece == ChessRules.PAWN and mv.to.y in [0,7]
        var en_passant_capture: bool = mv.to == en_passant and mv.from.x != mv.to.x and target == ChessRules.EMPTY
        if target != ChessRules.EMPTY or pawn_promotion or en_passant_capture:
            tactical.append(mv)
    for mv: Dictionary in _order_moves(tactical, board):
        var result: Dictionary = ChessRules.make_move(board, mv, castling, en_passant)
        var score: int = _quiescence(result.board, -side, result.castling, result.en_passant, alpha, beta, root_color, remaining - 1)
        if search_aborted:
            return 0
        if maximizing:
            if score > alpha:
                alpha = score
            if alpha >= beta:
                return alpha
        else:
            if score < beta:
                beta = score
            if beta <= alpha:
                return beta
    return alpha if maximizing else beta

func _position_key(board: Array, side: int, castling: Dictionary, en_passant: Vector2i, depth: int) -> String:
    var key: String = str(side) + ":" + str(depth) + ":" + str(en_passant.x) + "," + str(en_passant.y)
    key += ":" + ("1" if bool(castling.get("K", false)) else "0")
    key += ("1" if bool(castling.get("Q", false)) else "0")
    key += ("1" if bool(castling.get("k", false)) else "0")
    key += ("1" if bool(castling.get("q", false)) else "0")
    for y in range(8):
        for x in range(8):
            key += String.chr(int(board[y][x]) + 97)
    return key

func _time_up() -> bool:
    return search_deadline_us > 0 and Time.get_ticks_usec() >= search_deadline_us

func _order_moves(moves: Array, board: Array) -> Array:
    var scored: Array = []
    for mv: Dictionary in moves:
        var capture: int = abs(int(board[mv.to.y][mv.to.x]))
        var moving: int = abs(int(board[mv.from.y][mv.from.x]))
        var score: int = capture * 1000 - moving
        if mv.from.y != mv.to.y and capture == 0:
            score += 30
        scored.append({"move": mv, "score": score})
    scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.score) > int(b.score))
    var out: Array = []
    for item: Dictionary in scored:
        out.append(item.move)
    return out

func _evaluate_for(board: Array, color: int, castling: Dictionary, en_passant: Vector2i) -> int:
    var score: int = _static_evaluate(board, color)
    var my_moves: Array = ChessRules.legal_moves(board, color, castling, en_passant)
    var opp_moves: Array = ChessRules.legal_moves(board, -color, castling, en_passant)
    score += (my_moves.size() - opp_moves.size()) * 3
    return score

func _static_evaluate(board: Array, color: int) -> int:
    var score: int = 0
    for y in range(8):
        for x in range(8):
            var piece: int = int(board[y][x])
            if piece == 0:
                continue
            var piece_type: int = abs(piece)
            var value: int = int(VALUES.get(piece_type, 0))
            var piece_color: int = ChessRules.color_of(piece)
            var advance: int = 0
            if piece_type == ChessRules.PAWN:
                advance = (6 - y) if piece_color == ChessRules.WHITE else (y - 1)
            var idx: int = y * 8 + x
            var table_bonus: int = _piece_square_bonus(piece_type, idx, piece_color)
            var local_score: int = value + advance * 7 + table_bonus
            if piece_color == color:
                score += local_score
            else:
                score -= local_score

    if ChessRules.in_check(board, color):
        score -= 55
    if ChessRules.in_check(board, -color):
        score += 55
    return score

func _piece_square_bonus(piece_type: int, idx: int, piece_color: int) -> int:
    var table: Array[int]
    match piece_type:
        ChessRules.PAWN:
            table = PAWN_TABLE
        ChessRules.KNIGHT:
            table = KNIGHT_TABLE
        ChessRules.BISHOP:
            table = BISHOP_TABLE
        ChessRules.ROOK:
            table = ROOK_TABLE
        ChessRules.QUEEN:
            table = QUEEN_TABLE
        _:
            table = KING_TABLE
    var x: int = idx % 8
    var y: int = idx >> 3
    var row: int = 7 - y if piece_color == ChessRules.WHITE else y
    return int(table[row * 8 + x])
