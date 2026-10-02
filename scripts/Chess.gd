class_name Chess
extends RefCounted

const EMPTY := 0
const PAWN := 1
const KNIGHT := 2
const BISHOP := 3
const ROOK := 4
const QUEEN := 5
const KING := 6

const WHITE := 1
const BLACK := -1

static func initial_board() -> Array:
    var b: Array = []
    for y in range(8):
        var row: Array = []
        for x in range(8):
            row.append(EMPTY)
        b.append(row)
    var back := [ROOK, KNIGHT, BISHOP, QUEEN, KING, BISHOP, KNIGHT, ROOK]
    for x in range(8):
        b[7][x] = back[x]
        b[6][x] = PAWN
        b[0][x] = -back[x]
        b[1][x] = -PAWN
    return b

static func clone_board(board: Array) -> Array:
    return board.duplicate(true)

static func in_bounds(p: Vector2i) -> bool:
    return p.x >= 0 and p.x < 8 and p.y >= 0 and p.y < 8

static func color_of(piece: int) -> int:
    if piece > 0: return WHITE
    if piece < 0: return BLACK
    return 0

static func type_of(piece: int) -> int:
    return abs(piece)

static func piece_char(piece: int) -> String:
    var chars := {PAWN:"P", KNIGHT:"N", BISHOP:"B", ROOK:"R", QUEEN:"Q", KING:"K"}
    var c: String = chars.get(abs(piece), "")
    return c if piece > 0 else c.to_lower()

static func find_king(board: Array, color: int) -> Vector2i:
    var target := KING * color
    for y in range(8):
        for x in range(8):
            if int(board[y][x]) == target:
                return Vector2i(x, y)
    return Vector2i(-1, -1)

static func is_square_attacked(board: Array, sq: Vector2i, by_color: int) -> bool:
    # Pawns: reverse lookup from target square.
    var pawn_y := sq.y + (1 if by_color == WHITE else -1)
    for dx: int in [-1, 1]:
        var p := Vector2i(sq.x + dx, pawn_y)
        if in_bounds(p) and int(board[p.y][p.x]) == PAWN * by_color:
            return true
    # Knights.
    for d: Vector2i in [Vector2i(1,2), Vector2i(2,1), Vector2i(-1,2), Vector2i(-2,1), Vector2i(1,-2), Vector2i(2,-1), Vector2i(-1,-2), Vector2i(-2,-1)]:
        var p := sq + d
        if in_bounds(p) and int(board[p.y][p.x]) == KNIGHT * by_color:
            return true
    # Sliding lines.
    for d: Vector2i in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
        var p := sq + d
        while in_bounds(p):
            var piece: int = int(board[p.y][p.x])
            if piece != EMPTY:
                if piece == ROOK * by_color or piece == QUEEN * by_color:
                    return true
                break
            p += d
    for d: Vector2i in [Vector2i(1,1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(-1,-1)]:
        var p := sq + d
        while in_bounds(p):
            var piece: int = int(board[p.y][p.x])
            if piece != EMPTY:
                if piece == BISHOP * by_color or piece == QUEEN * by_color:
                    return true
                break
            p += d
    # King.
    for dx: int in [-1,0,1]:
        for dy: int in [-1,0,1]:
            if dx == 0 and dy == 0: continue
            var p := sq + Vector2i(dx,dy)
            if in_bounds(p) and int(board[p.y][p.x]) == KING * by_color:
                return true
    return false

static func in_check(board: Array, color: int) -> bool:
    var king := find_king(board, color)
    if not in_bounds(king): return true
    return is_square_attacked(board, king, -color)

static func make_move(board: Array, mv: Dictionary, castling: Dictionary, en_passant: Vector2i) -> Dictionary:
    var b := clone_board(board)
    var from: Vector2i = mv.from
    var to: Vector2i = mv.to
    var piece: int = int(b[from.y][from.x])
    var captured: int = int(b[to.y][to.x])
    b[from.y][from.x] = EMPTY

    # En-passant capture.
    if type_of(piece) == PAWN and to == en_passant and captured == EMPTY and from.x != to.x:
        var cap_y := to.y + (1 if color_of(piece) == WHITE else -1)
        captured = int(b[cap_y][to.x])
        b[cap_y][to.x] = EMPTY

    # Castling rook move.
    if type_of(piece) == KING and abs(to.x - from.x) == 2:
        if to.x == 6:
            b[to.y][5] = b[to.y][7]
            b[to.y][7] = EMPTY
        else:
            b[to.y][3] = b[to.y][0]
            b[to.y][0] = EMPTY

    var promotion: int = int(mv.get("promotion", 0))
    if type_of(piece) == PAWN and (to.y == 0 or to.y == 7):
        if promotion not in [KNIGHT, BISHOP, ROOK, QUEEN]:
            promotion = QUEEN
        piece = promotion * color_of(piece)
    b[to.y][to.x] = piece

    var rights := castling.duplicate()
    var color := color_of(piece)
    if type_of(int(board[from.y][from.x])) == KING:
        if color == WHITE:
            rights.K = false; rights.Q = false
        else:
            rights.k = false; rights.q = false
    if from == Vector2i(0,7): rights.Q = false
    if from == Vector2i(7,7): rights.K = false
    if from == Vector2i(0,0): rights.q = false
    if from == Vector2i(7,0): rights.k = false
    if captured == ROOK:
        if to == Vector2i(0,7): rights.Q = false
        if to == Vector2i(7,7): rights.K = false
    if captured == -ROOK:
        if to == Vector2i(0,0): rights.q = false
        if to == Vector2i(7,0): rights.k = false

    var new_ep := Vector2i(-1,-1)
    if type_of(piece) == PAWN and abs(to.y-from.y) == 2:
        new_ep = Vector2i(from.x, int(float(from.y + to.y) / 2.0))
    return {"board": b, "castling": rights, "en_passant": new_ep}

static func _pseudo_moves(board: Array, from: Vector2i, castling: Dictionary, en_passant: Vector2i) -> Array:
    var out: Array = []
    var piece: int = int(board[from.y][from.x])
    var color := color_of(piece)
    var t := type_of(piece)
    if t == PAWN:
        var dir := -1 if color == WHITE else 1
        var start_y := 6 if color == WHITE else 1
        var one := from + Vector2i(0,dir)
        if in_bounds(one) and int(board[one.y][one.x]) == EMPTY:
            out.append({"from":from,"to":one,"promotion":QUEEN if one.y in [0,7] else 0})
            var two := from + Vector2i(0,2*dir)
            if from.y == start_y and int(board[two.y][two.x]) == EMPTY:
                out.append({"from":from,"to":two,"promotion":0})
        for dx: int in [-1,1]:
            var cap := from + Vector2i(dx,dir)
            if not in_bounds(cap): continue
            var target := int(board[cap.y][cap.x])
            if target != EMPTY and color_of(target) == -color:
                out.append({"from":from,"to":cap,"promotion":QUEEN if cap.y in [0,7] else 0})
            elif cap == en_passant:
                out.append({"from":from,"to":cap,"promotion":0})
    elif t == KNIGHT:
        for d: Vector2i in [Vector2i(1,2),Vector2i(2,1),Vector2i(-1,2),Vector2i(-2,1),Vector2i(1,-2),Vector2i(2,-1),Vector2i(-1,-2),Vector2i(-2,-1)]:
            var p := from+d
            if in_bounds(p) and color_of(int(board[p.y][p.x])) != color:
                out.append({"from":from,"to":p,"promotion":0})
    elif t in [BISHOP, ROOK, QUEEN]:
        var dirs: Array = []
        if t in [BISHOP,QUEEN]: dirs += [Vector2i(1,1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(-1,-1)]
        if t in [ROOK,QUEEN]: dirs += [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]
        for d: Vector2i in dirs:
            var p := from+d
            while in_bounds(p):
                var target := int(board[p.y][p.x])
                if target == EMPTY:
                    out.append({"from":from,"to":p,"promotion":0})
                else:
                    if color_of(target) == -color:
                        out.append({"from":from,"to":p,"promotion":0})
                    break
                p += d
    elif t == KING:
        for dx: int in [-1,0,1]:
            for dy: int in [-1,0,1]:
                if dx == 0 and dy == 0: continue
                var p := from + Vector2i(dx,dy)
                if in_bounds(p) and color_of(int(board[p.y][p.x])) != color:
                    out.append({"from":from,"to":p,"promotion":0})
        if not in_check(board,color):
            if color == WHITE and from == Vector2i(4,7):
                if bool(castling.get("K",false)) and board[7][5] == EMPTY and board[7][6] == EMPTY and board[7][7] == ROOK and not is_square_attacked(board,Vector2i(5,7),BLACK) and not is_square_attacked(board,Vector2i(6,7),BLACK):
                    out.append({"from":from,"to":Vector2i(6,7),"promotion":0})
                if bool(castling.get("Q",false)) and board[7][1] == EMPTY and board[7][2] == EMPTY and board[7][3] == EMPTY and board[7][0] == ROOK and not is_square_attacked(board,Vector2i(3,7),BLACK) and not is_square_attacked(board,Vector2i(2,7),BLACK):
                    out.append({"from":from,"to":Vector2i(2,7),"promotion":0})
            elif color == BLACK and from == Vector2i(4,0):
                if bool(castling.get("k",false)) and board[0][5] == EMPTY and board[0][6] == EMPTY and board[0][7] == -ROOK and not is_square_attacked(board,Vector2i(5,0),WHITE) and not is_square_attacked(board,Vector2i(6,0),WHITE):
                    out.append({"from":from,"to":Vector2i(6,0),"promotion":0})
                if bool(castling.get("q",false)) and board[0][1] == EMPTY and board[0][2] == EMPTY and board[0][3] == EMPTY and board[0][0] == -ROOK and not is_square_attacked(board,Vector2i(3,0),WHITE) and not is_square_attacked(board,Vector2i(2,0),WHITE):
                    out.append({"from":from,"to":Vector2i(2,0),"promotion":0})
    return out

static func legal_moves(board: Array, color: int, castling: Dictionary, en_passant: Vector2i) -> Array:
    var out: Array = []
    for y in range(8):
        for x in range(8):
            var p := Vector2i(x,y)
            if color_of(int(board[y][x])) != color: continue
            for mv: Dictionary in _pseudo_moves(board,p,castling,en_passant):
                if abs(int(board[mv.to.y][mv.to.x])) == KING:
                    continue
                var result := make_move(board,mv,castling,en_passant)
                if not in_check(result.board,color):
                    out.append(mv)
    return out

static func find_move(board: Array, color: int, from: Vector2i, to: Vector2i, promotion: int, castling: Dictionary, en_passant: Vector2i) -> Dictionary:
    for mv: Dictionary in legal_moves(board,color,castling,en_passant):
        if mv.from == from and mv.to == to:
            if to.y in [0,7] and type_of(int(board[from.y][from.x])) == PAWN:
                var p := promotion if promotion in [KNIGHT,BISHOP,ROOK,QUEEN] else QUEEN
                mv["promotion"] = p
            return mv
    return {}

static func algebraic(p: Vector2i) -> String:
    return String.chr(97+p.x) + str(8-p.y)

static func status(board: Array, turn_color: int, castling: Dictionary, en_passant: Vector2i) -> Dictionary:
    var check := in_check(board,turn_color)
    var moves := legal_moves(board,turn_color,castling,en_passant)
    if moves.is_empty():
        return {"check":check,"mate":check,"stalemate":not check,"text":"Мат!" if check else "Пат!"}
    return {"check":check,"mate":false,"stalemate":false,"text":"Шах!" if check else ""}
