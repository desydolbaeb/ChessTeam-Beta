extends Control

const LIGHT := Color("eadfcf")
const DARK := Color("956d4d")
const FRAME := Color("4c382c")

const PIECES: Dictionary = {
    -1: preload("res://assets/pieces/black_pawn.png"),
    -4: preload("res://assets/pieces/black_rook.png"),
    -2: preload("res://assets/pieces/black_knight.png"),
    -3: preload("res://assets/pieces/black_bishop.png"),
    -5: preload("res://assets/pieces/black_queen.png"),
    -6: preload("res://assets/pieces/black_king.png"),
    1: preload("res://assets/pieces/white_pawn.png"),
    4: preload("res://assets/pieces/white_rook.png"),
    2: preload("res://assets/pieces/white_knight.png"),
    3: preload("res://assets/pieces/white_bishop.png"),
    5: preload("res://assets/pieces/white_queen.png"),
    6: preload("res://assets/pieces/white_king.png")
}

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    custom_minimum_size = Vector2(150, 150)
    queue_redraw()

func _draw() -> void:
    var s: float = minf(size.x, size.y)
    var ox: float = (size.x - s) / 2.0
    var oy: float = (size.y - s) / 2.0
    var cell: float = s / 4.0

    draw_style_box(_box(FRAME, 12), Rect2(ox - 4, oy - 4, s + 8, s + 8))
    for y in range(4):
        for x in range(4):
            var square_color: Color = LIGHT if (x + y) % 2 == 0 else DARK
            draw_rect(Rect2(ox + x * cell, oy + y * cell, cell + 0.2, cell + 0.2), square_color)

    var layout: Array[Dictionary] = [
        {"piece": -4, "x": 0, "y": 0}, {"piece": -2, "x": 1, "y": 0},
        {"piece": -1, "x": 2, "y": 1}, {"piece": -1, "x": 0, "y": 1},
        {"piece": 1, "x": 1, "y": 2}, {"piece": 1, "x": 3, "y": 2},
        {"piece": 6, "x": 2, "y": 3}, {"piece": 4, "x": 3, "y": 3}
    ]
    for item: Dictionary in layout:
        var center := Vector2(ox + (int(item.x) + 0.5) * cell, oy + (int(item.y) + 0.5) * cell)
        _draw_piece(int(item.piece), center, cell)

func _draw_piece(piece: int, center: Vector2, cell: float) -> void:
    var texture: Texture2D = PIECES.get(piece)
    if texture == null:
        return
    var max_size: float = cell * 0.90
    var tex_size: Vector2 = texture.get_size()
    var scale_factor: float = minf(max_size / tex_size.x, max_size / tex_size.y)
    var draw_size := tex_size * scale_factor
    draw_texture_rect(texture, Rect2(center - draw_size * 0.5, draw_size), false)

func _box(color: Color, radius: int) -> StyleBoxFlat:
    var box := StyleBoxFlat.new()
    box.bg_color = color
    box.corner_radius_top_left = radius
    box.corner_radius_top_right = radius
    box.corner_radius_bottom_left = radius
    box.corner_radius_bottom_right = radius
    return box
