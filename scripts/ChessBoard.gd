class_name ChessBoard
extends Control

const ChessRules = preload("res://scripts/Chess.gd")

signal square_tapped(square: Vector2i)

var board: Array = []
var selected := Vector2i(-1, -1)
var legal_targets: Array = []
var castle_targets: Array = []
var turn_team := 1
var perspective_color: int = ChessRules.WHITE
var hint_from := Vector2i(-1, -1)
var hint_to := Vector2i(-1, -1)
var show_hint_to: bool = false

const LIGHT := Color("ebecd0")
const DARK := Color("b58863")
const SELECTED := Color("f1bf52")
const TARGET_DOT := Color("7ea76d")
const CASTLE_DOT := Color("3db8e8")
const CASTLE_RING := Color("1a8fc4")
const CAPTURE_FILL := Color(0.93, 0.89, 0.74, 0.72)
const CAPTURE_RING := Color("86a56f")
const CHECK := Color("c95f5f")
const HINT_FROM := Color("6cb4e8")
const HINT_TO := Color("f0d060")

const PIECES: Dictionary = {
	1: preload("res://assets/pieces/white_pawn.png"),
	2: preload("res://assets/pieces/white_knight.png"),
	3: preload("res://assets/pieces/white_bishop.png"),
	4: preload("res://assets/pieces/white_rook.png"),
	5: preload("res://assets/pieces/white_queen.png"),
	6: preload("res://assets/pieces/white_king.png"),
	-1: preload("res://assets/pieces/black_pawn.png"),
	-2: preload("res://assets/pieces/black_knight.png"),
	-3: preload("res://assets/pieces/black_bishop.png"),
	-4: preload("res://assets/pieces/black_rook.png"),
	-5: preload("res://assets/pieces/black_queen.png"),
	-6: preload("res://assets/pieces/black_king.png")
}

const FILE_LETTERS := ["a", "b", "c", "d", "e", "f", "g", "h"]

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(320, 320)
	queue_redraw()

func clear_hint() -> void:
	hint_from = Vector2i(-1, -1)
	hint_to = Vector2i(-1, -1)
	show_hint_to = false
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_tap(event.position)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_tap(event.position)
		accept_event()

func _tap(pos: Vector2) -> void:
	var s: float = minf(size.x, size.y)
	var ox: float = (size.x - s) / 2.0
	var oy: float = (size.y - s) / 2.0
	var cell: float = s / 8.0
	var view_x: int = int(floor((pos.x - ox) / cell))
	var view_y: int = int(floor((pos.y - oy) / cell))
	if view_x < 0 or view_x >= 8 or view_y < 0 or view_y >= 8:
		return
	var board_x: int = view_x if perspective_color == ChessRules.WHITE else 7 - view_x
	var board_y: int = view_y if perspective_color == ChessRules.WHITE else 7 - view_y
	square_tapped.emit(Vector2i(board_x, board_y))

func board_to_view(square: Vector2i) -> Vector2i:
	if perspective_color == ChessRules.WHITE:
		return square
	return Vector2i(7 - square.x, 7 - square.y)

func _draw() -> void:
	var s: float = minf(size.x, size.y)
	var ox: float = (size.x - s) / 2.0
	var oy: float = (size.y - s) / 2.0
	var cell: float = s / 8.0
	var font: Font = ThemeDB.fallback_font
	var font_size: int = maxi(10, int(cell * 0.20))

	for view_y in range(8):
		for view_x in range(8):
			var board_x: int = view_x if perspective_color == ChessRules.WHITE else 7 - view_x
			var board_y: int = view_y if perspective_color == ChessRules.WHITE else 7 - view_y
			var board_square := Vector2i(board_x, board_y)
			var rect := Rect2(ox + view_x * cell, oy + view_y * cell, cell + 0.25, cell + 0.25)
			# Color by board square (file+rank), not view — so letters match square color
			var is_light: bool = ((board_x + board_y) % 2) == 0
			var square_color: Color = LIGHT if is_light else DARK
			if selected == board_square:
				square_color = SELECTED
			if hint_from == board_square:
				square_color = HINT_FROM
			if show_hint_to and hint_to == board_square:
				square_color = HINT_TO

			var piece: int = int(board[board_y][board_x]) if board.size() == 8 else 0
			if piece != 0 and abs(piece) == ChessRules.KING and board.size() == 8:
				var king_color: int = 1 if piece > 0 else -1
				if ChessRules.in_check(board, king_color):
					square_color = CHECK

			draw_rect(rect, square_color)

			if board_square in legal_targets:
				var center := Vector2(ox + (view_x + 0.5) * cell, oy + (view_y + 0.5) * cell)
				var is_castle: bool = board_square in castle_targets
				if piece != 0:
					draw_circle(center, cell * 0.37, CAPTURE_FILL)
					draw_arc(center, cell * 0.37, 0.0, TAU, 32, CAPTURE_RING, 3.0, true)
				elif is_castle:
					draw_circle(center, cell * 0.12, CASTLE_DOT)
					draw_arc(center, cell * 0.18, 0.0, TAU, 28, CASTLE_RING, 2.5, true)
				else:
					draw_circle(center, cell * 0.105, TARGET_DOT)

			# Coordinates: clean small labels, opposite shade of square
			var coord_color: Color = DARK if is_light else LIGHT
			if view_x == 0:
				var rank_str: String = str(8 - board_y)
				draw_string(font, Vector2(ox + view_x * cell + 3.0, oy + view_y * cell + float(font_size) + 2.0), rank_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, coord_color)
			if view_y == 7:
				var file_str: String = FILE_LETTERS[board_x]
				var tw: float = font.get_string_size(file_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
				draw_string(font, Vector2(ox + (view_x + 1) * cell - tw - 4.0, oy + (view_y + 1) * cell - 4.0), file_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, coord_color)

			if piece != 0:
				_draw_piece(piece, Vector2(ox + (view_x + 0.5) * cell, oy + (view_y + 0.5) * cell), cell)

func _draw_piece(piece: int, center: Vector2, cell: float) -> void:
	var texture: Texture2D = PIECES.get(piece)
	if texture == null:
		return
	# Пешки чуть меньше остальных фигур
	var max_size: float = cell * 0.72 if abs(piece) == ChessRules.PAWN else cell * 0.77
	var tex_size: Vector2 = texture.get_size()
	var scale_factor: float = minf(max_size / tex_size.x, max_size / tex_size.y)
	var draw_size := tex_size * scale_factor
	# На 1 пиксель ниже центра клетки
	var rect := Rect2(center - draw_size * 0.5 + Vector2(0.0, 1.0), draw_size)
	draw_texture_rect(texture, rect, false)
