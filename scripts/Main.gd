extends Control

const ChessRules = preload("res://scripts/Chess.gd")
const Locale = preload("res://scripts/Locale.gd")

var language: String = "ru"
var effects_volume: float = 0.5
var music_volume: float = 0.55
var current_screen: String = "menu"
var current_bot_level: int = 3
var game_return_screen: String = "menu"
var settings_return_screen: String = "menu"
var bot: ChessBot
var bot_human_color: int = ChessRules.WHITE
var bot_color: int = ChessRules.BLACK
var bot_side_rng := RandomNumberGenerator.new()
var bot_thread: Thread = null
var bot_thinking: bool = false
var bot_job_id: int = 0

var screen_root: Control
var overlay_root: Control
var board_view: ChessBoard
var title_label: Label
var gear_button: Button
var status_label: Label
var address_label: Label
var players_label: Label
var player_info_labels: Array[Label] = []
var name_edit: LineEdit
var ip_edit: LineEdit
var start_button: Button
var network_mode: int = 4
var selected := Vector2i(-1, -1)
var legal_targets: Array = []
var local_board: Array = []
var local_turn: int = ChessRules.WHITE
var local_castling: Dictionary = {"K": true, "Q": true, "k": true, "q": true}
var local_en_passant := Vector2i(-1, -1)
var local_game_active: bool = false
var local_mode: String = ""
var toast: Label
var menu_buttons: Array[Button] = []
var slot_buttons: Array[Button] = []
var slot_button_slots: Array[int] = []
var selected_network_slot: int = 0
var lobby_music_player: AudioStreamPlayer = null
var menu_music_player: AudioStreamPlayer = null
var move_history: Array = []
var hint_step: int = 0
var last_hint_move: Dictionary = {}
var notation_log: Array = []
var notation_visible: bool = true
var notation_label: Label = null
var notation_toggle_btn: Button = null
var _float_nodes: Array = []
var _float_bases: Dictionary = {}
var _pointer_norm := Vector2(0.5, 0.5)
var _float_offset := Vector2.ZERO
var _float_panels: Array = []





const BG := Color("f3e6d4")
const CARD := Color("e8d5b8")
const CARD_2 := Color("dcc4a0")
const CYAN := Color("c4a574")
const CYAN_HOVER := Color("d4b88a")
const CYAN_PRESS := Color("a8895c")
const BLUE := Color("9a8060cc")
const BLUE_HOVER := Color("b09070dd")
const BLUE_PRESS := Color("7a6248ee")
const GREEN := Color("6fa050dd")
const GREEN_HOVER := Color("82b568ee")
const GREEN_PRESS := Color("58803cee")
const TEXT := Color("3d2b1f")
const MUTED := Color("c4b09a")
const FIELD := Color("fff8ee")
const FIELD_TEXT := Color("3d2b1f")
const DARK_TEXT := Color("2a1c12")
const BORDER := Color("c4a574")

func _ready() -> void:
	_load_settings()
	_build_base()
	GameNet.lobby_changed.connect(_on_lobby)
	GameNet.game_changed.connect(_on_game)
	GameNet.network_message.connect(_toast)
	GameNet.connection_state.connect(_on_connection)
	set_process(true)
	set_process_input(true)
	_show_main_menu()

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		language = str(cfg.get_value("settings", "language", "ru"))
		effects_volume = float(cfg.get_value("settings", "effects_volume", 0.5))
		music_volume = float(cfg.get_value("settings", "music_volume", 0.55))
		effects_volume = clampf(effects_volume, 0.0, 1.0)
		music_volume = clampf(music_volume, 0.0, 1.0)

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("settings", "language", language)
	cfg.set_value("settings", "effects_volume", effects_volume)
	cfg.set_value("settings", "music_volume", music_volume)
	cfg.save("user://settings.cfg")


func _refresh_float_bases() -> void:
	for node_v in _float_nodes:
		var node: Control = node_v as Control
		if is_instance_valid(node):
			_float_bases[node] = {
				"pos": node.position,
				"rot": 0.0,
				"in_container": node.get_parent() is Container
			}

func _register_float_node(node: Control) -> void:

	if node == null or not is_instance_valid(node):
		return
	if node in _float_nodes:
		return
	_float_nodes.append(node)
	_float_bases[node] = {
		"pos": node.position,
		"rot": node.rotation,
		"in_container": node.get_parent() is Container
	}

func _clear_float_nodes() -> void:
	for node_v in _float_nodes:
		var node: Control = node_v as Control
		if is_instance_valid(node) and _float_bases.has(node):
			var base: Dictionary = _float_bases[node]
			if not bool(base.get("in_container", false)):
				node.position = base.pos
			node.rotation = float(base.get("rot", 0.0))
			node.scale = Vector2.ONE
	_float_nodes.clear()
	_float_bases.clear()
	_float_panels.clear()
	_float_offset = Vector2.ZERO

func _gui_input(event: InputEvent) -> void:
	_handle_pointer_event(event)

func _unhandled_input(event: InputEvent) -> void:
	_handle_pointer_event(event)

func _handle_pointer_event(event: InputEvent) -> void:
	var pos := Vector2(-1, -1)
	if event is InputEventScreenTouch:
		pos = event.position
	elif event is InputEventScreenDrag:
		pos = event.position
	elif event is InputEventMouseMotion:
		pos = event.position
	if pos.x < 0.0:
		return
	var vp := get_viewport_rect().size
	if vp.x < 1.0 or vp.y < 1.0:
		return
	_pointer_norm = Vector2(pos.x / vp.x, pos.y / vp.y)
	# Кнопки чуть «плывут» навстречу/от пальца
	var target := Vector2((0.5 - _pointer_norm.x) * 16.0, (0.5 - _pointer_norm.y) * 20.0)
	_float_offset = _float_offset.lerp(target, 0.4)

func _process(delta: float) -> void:
	# Удаляем освобождённые ноды, чтобы не кастовать freed object
	if not _float_nodes.is_empty():
		var alive_nodes: Array = []
		for node_v in _float_nodes:
			if is_instance_valid(node_v):
				alive_nodes.append(node_v)
			elif _float_bases.has(node_v):
				_float_bases.erase(node_v)
		_float_nodes = alive_nodes
	if not _float_panels.is_empty():
		var alive_panels: Array = []
		for panel_v in _float_panels:
			var panel: Dictionary = panel_v
			var node_ref = panel.get("node")
			if is_instance_valid(node_ref):
				alive_panels.append(panel)
		_float_panels = alive_panels

	if _float_nodes.is_empty() and _float_panels.is_empty():
		return
	var blend: float = clampf(delta * 9.0, 0.0, 1.0)
	for i in range(_float_nodes.size()):
		var node_v = _float_nodes[i]
		if not is_instance_valid(node_v):
			continue
		var node: Control = node_v
		if not _float_bases.has(node):
			continue
		var base: Dictionary = _float_bases[node]
		var amp: float = 1.0 + 0.1 * float(i % 5)
		var off: Vector2 = _float_offset * amp
		var in_container: bool = bool(base.get("in_container", false))
		if in_container:
			var target_rot: float = clampf(off.x * 0.012, -0.08, 0.08)
			node.rotation = lerpf(node.rotation, target_rot, blend)
			var target_scale := Vector2.ONE * (1.0 + clampf(-off.y * 0.0015, -0.02, 0.02))
			node.scale = node.scale.lerp(target_scale, blend)
		else:
			var base_pos: Vector2 = base.pos
			var desired: Vector2 = base_pos + off
			node.position = node.position.lerp(desired, blend)
			node.rotation = lerpf(node.rotation, clampf(off.x * 0.01, -0.06, 0.06), blend)
	for panel_v in _float_panels:
		var panel: Dictionary = panel_v
		var node_ref = panel.get("node")
		if not is_instance_valid(node_ref):
			continue
		var n: Control = node_ref
		var ox: float = _float_offset.x
		var oy: float = _float_offset.y
		n.offset_left = float(panel.left) + ox
		n.offset_right = float(panel.right) + ox
		n.offset_top = float(panel.top) + oy
		n.offset_bottom = float(panel.bottom) + oy

func _linear_to_db(linear: float) -> float:
	if linear <= 0.001:
		return -80.0
	return 20.0 * log(linear) / log(10.0)

# Слайдер кажется громче реальных % — кривая x^2.4 и потолок ниже
func _music_slider_to_db(slider: float) -> float:
	if slider <= 0.001:
		return -80.0
	# Мягче кривая: на 40–60% уже хорошо слышно с динамиков, 100% не обязателен
	var shaped: float = pow(clampf(slider, 0.0, 1.0), 1.55)
	return _linear_to_db(shaped) - 2.0

func _effects_slider_to_db(slider: float) -> float:
	if slider <= 0.001:
		return -80.0
	var shaped: float = pow(clampf(slider, 0.0, 1.0), 2.4)
	return _linear_to_db(shaped) - 6.0

func _apply_music_volume() -> void:
	var db: float = _music_slider_to_db(music_volume)
	if menu_music_player != null and is_instance_valid(menu_music_player):
		menu_music_player.volume_db = db
	if lobby_music_player != null and is_instance_valid(lobby_music_player):
		lobby_music_player.volume_db = db
	# В партии музыка никогда не должна запускаться
	if current_screen == "game" or local_game_active:
		_stop_menu_music()
		_stop_lobby_music()
		return
	if music_volume <= 0.001:
		_stop_menu_music()
		_stop_lobby_music()
		return
	# Только обновляем громкость уже играющего трека на меню-экранах
	# Не стартуем заново из настроек, если открыты из партии (settings_return_screen == "game")
	if settings_return_screen == "game" and current_screen in ["settings", "language"]:
		_stop_menu_music()
		_stop_lobby_music()
		return

func _ui_click() -> void:
	if effects_volume > 0.001:
		SoundFX.play("ui_click", _effects_slider_to_db(effects_volume))

func t(key: String) -> String:
	return Locale.t(key, language)

func _build_base() -> void:
	var bg := Control.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.set_script(load("res://scripts/Background.gd"))
	add_child(bg)

	screen_root = Control.new()
	screen_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(screen_root)

	title_label = Label.new()
	title_label.text = t("title")
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_color_override("font_color", Color("f7f0e6"))
	title_label.add_theme_font_size_override("font_size", 28)
	title_label.add_theme_constant_override("outline_size", 10)
	title_label.add_theme_color_override("font_outline_color", Color("1a120cdd"))
	title_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title_label.offset_top = 18
	title_label.offset_bottom = 58
	add_child(title_label)

	gear_button = Button.new()
	var gear: Button = gear_button
	gear.text = "⚙"
	gear.tooltip_text = t("settings")
	gear.custom_minimum_size = Vector2(58, 58)
	gear.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	gear.offset_left = -70.0
	gear.offset_top = 10.0
	gear.offset_right = -12.0
	gear.offset_bottom = 68.0
	gear.add_theme_font_size_override("font_size", 28)
	gear.add_theme_color_override("font_color", Color("f7f0e6"))
	gear.add_theme_color_override("font_hover_color", Color("e8d5b0"))
	gear.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	gear.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	gear.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	add_child(gear)
	gear.pressed.connect(func() -> void:
		_ui_click()
		_open_settings())

	overlay_root = Control.new()
	overlay_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay_root)

	toast = Label.new()
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast.add_theme_color_override("font_color", TEXT)
	toast.add_theme_font_size_override("font_size", 16)
	toast.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	toast.offset_top = -88
	toast.offset_bottom = -34
	toast.visible = false
	add_child(toast)

func _clear_screen() -> void:
	_clear_float_nodes()
	selected = Vector2i(-1, -1)
	legal_targets.clear()
	for child in screen_root.get_children():
		child.queue_free()

func _content_container(min_width: float = 360.0) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_left = 16
	center.offset_right = -16
	center.offset_top = 76
	center.offset_bottom = -28
	screen_root.add_child(center)
	_float_panels.append({
		"node": center,
		"left": 16.0,
		"right": -16.0,
		"top": 76.0,
		"bottom": -28.0
	})
	var box := VBoxContainer.new()
	var available_width: float = maxf(280.0, get_viewport_rect().size.x - 32.0)
	box.custom_minimum_size = Vector2(minf(min_width, available_width), 0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	return box

func _section_label(text_value: String, font_size: int = 30) -> Label:
	var label := Label.new()
	label.text = text_value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color("f7f0e6"))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_outline_color", Color("1a120ccc"))
	return label

func _card_style(color: Color = CARD, radius: int = 24) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.corner_radius_top_left = radius
	box.corner_radius_top_right = radius
	box.corner_radius_bottom_left = radius
	box.corner_radius_bottom_right = radius
	box.border_color = BORDER
	box.border_width_left = 1
	box.border_width_top = 1
	box.border_width_right = 1
	box.border_width_bottom = 1
	return box

func _button_style(primary_color: Color, hover_color: Color, press_color: Color, text_color: Color = Color("f7f0e6")) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 82)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_stylebox_override("normal", _button_box(primary_color, 20, 10))
	b.add_theme_stylebox_override("hover", _button_box(hover_color, 20, 12))
	b.add_theme_stylebox_override("pressed", _button_box(press_color, 20, 5))
	b.add_theme_color_override("font_color", text_color)
	b.add_theme_color_override("font_hover_color", text_color)
	b.add_theme_color_override("font_pressed_color", text_color)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.clip_text = false
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(_ui_click)
	call_deferred("_register_float_node", b)
	return b

func _button_box(color: Color, radius: int, shadow: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.corner_radius_top_left = radius
	box.corner_radius_top_right = radius
	box.corner_radius_bottom_left = radius
	box.corner_radius_bottom_right = radius
	box.border_color = Color(0.45, 0.32, 0.18, 0.22)
	box.border_width_left = 1
	box.border_width_top = 1
	box.border_width_right = 1
	box.border_width_bottom = 1
	box.shadow_color = Color(0.35, 0.22, 0.10, 0.28)
	box.shadow_size = shadow
	box.shadow_offset = Vector2(0, 6)
	return box

func _field_style() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = FIELD
	box.corner_radius_top_left = 14
	box.corner_radius_top_right = 14
	box.corner_radius_bottom_left = 14
	box.corner_radius_bottom_right = 14
	box.border_color = Color("9cb8b8")
	box.border_width_left = 1
	box.border_width_top = 1
	box.border_width_right = 1
	box.border_width_bottom = 1
	return box

func _add_back_button(_text_value: String, callback: Callable) -> void:
	var back := Button.new()
	back.text = "←"
	# Ниже и крупнее, тёмный выразительный цвет
	back.position = Vector2(8, 22)
	back.custom_minimum_size = Vector2(64, 64)
	back.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	back.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	back.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	back.add_theme_color_override("font_color", Color("2a1c12"))
	back.add_theme_color_override("font_hover_color", Color("1a1008"))
	back.add_theme_color_override("font_pressed_color", Color("000000"))
	back.add_theme_constant_override("outline_size", 4)
	back.add_theme_color_override("font_outline_color", Color("f7f0e688"))
	back.add_theme_font_size_override("font_size", 42)
	back.z_index = 10
	screen_root.add_child(back)
	call_deferred("_register_float_node", back)
	back.pressed.connect(func() -> void:
		_ui_click()
		callback.call_deferred())


func _show_tutorial() -> void:
	title_label.visible = true
	gear_button.visible = true
	current_screen = "tutorial"
	_clear_screen()
	_add_back_button(t("back"), _show_main_menu)
	var box := _content_container(360.0)
	box.add_child(_section_label("ОБУЧЕНИЕ" if language == "ru" else "TUTORIAL", 26))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 560)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)

	var body := Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_color_override("font_color", Color("f7f0e6"))
	body.add_theme_font_size_override("font_size", 15)
	body.add_theme_constant_override("outline_size", 4)
	body.add_theme_color_override("font_outline_color", Color("1a120caa"))
	if language == "ru":
		body.text = """ПРАВИЛА ШАХМАТ

ЦЕЛЬ ИГРЫ
Поставить мат королю соперника — так атаковать его, чтобы у него не осталось ни одного способа уйти от шаха.

ХОДЫ ФИГУР
• Пешка — ходит только вперёд на 1 клетку. С начальной позиции может сразу на 2 клетки. Бьёт по диагонали вперёд на 1 клетку.
• Конь (N) — ходит буквой «Г»: на 2 клетки прямо и на 1 в сторону (или наоборот). Единственная фигура, которая перепрыгивает через другие.
• Слон (B) — на любое число свободных клеток по диагонали.
• Ладья (R) — на любое число свободных клеток по горизонтали или вертикали.
• Ферзь (Q) — сочетает ходы слона и ладьи: в любом направлении на любое число свободных клеток.
• Король (K) — на 1 клетку в любом направлении.

ВЗЯТИЕ
Ход на клетку, занятую фигурой соперника, снимает её с доски. Короля взять нельзя — ему ставят шах или мат.

ШАХ, МАТ И ПАТ
• Шах — король находится под ударом. Обязательно нужно уйти из-под шаха: отойти королём, закрыться своей фигурой или взять атакующую фигуру.
• Мат — шах, от которого нет защиты. Партия заканчивается победой атакующей стороны.
• Пат — у стороны, которой ходить, нет ни одного легального хода, но её король не под шахом. Партия заканчивается ничьей.

РОКИРОВКА
Особый ход короля и ладьи одновременно. Король перемещается на 2 клетки в сторону ладьи, а ладья встаёт с другой стороны короля.
• Короткая рокировка (O-O) — в сторону королевского фланга.
• Длинная рокировка (O-O-O) — в сторону ферзевого фланга.
Условия: король и эта ладья ещё ни разу не ходили; между ними нет фигур; король не под шахом; клетка, через которую проходит король, и клетка назначения не находятся под ударом.

ВЗЯТИЕ НА ПРОХОДЕ (en passant)
Если пешка соперника с начальной позиции сразу пошла на 2 клетки и встала рядом с вашей пешкой на той же горизонтали, своим ближайшим ходом вы можете взять её «на проходе»: ход по диагонали на клетку, которую пешка соперника «перепрыгнула». Право действует только на следующий ход.

ПРЕВРАЩЕНИЕ ПЕШКИ
Когда пешка достигает последней горизонтали, она обязательно превращается в ферзя, ладью, слона или коня (того же цвета). Чаще всего выбирают ферзя.

НИЧЬЯ
Возможна при: пате; соглашении игроков; троекратном повторении одной и той же позиции; недостатке материала для мата; правиле 50 ходов подряд без взятий и без хода пешкой.

ПОРЯДОК ХОДА
Белые делают первый ход, далее игроки ходят по очереди."""
	else:
		body.text = """CHESS RULES

GOAL
Checkmate the opponent's king — attack it so there is no legal way to escape check.

PIECE MOVES
• Pawn — moves forward 1 square (2 from its starting rank). Captures one square diagonally forward.
• Knight (N) — L-shape: 2 squares in one direction and 1 sideways. The only piece that jumps over others.
• Bishop (B) — any number of free squares diagonally.
• Rook (R) — any number of free squares horizontally or vertically.
• Queen (Q) — combines bishop and rook moves.
• King (K) — one square in any direction.

CAPTURE
Moving onto a square occupied by an enemy piece captures it. The king is never captured — it is checked or checkmated.

CHECK, MATE, STALEMATE
• Check — the king is under attack. You must get out of check: move the king, block, or capture the attacker.
• Checkmate — check with no legal escape. The game ends; the attacker wins.
• Stalemate — the side to move has no legal moves, but the king is not in check. The game is a draw.

CASTLING
A special move of the king and a rook. The king moves 2 squares toward the rook; the rook moves to the square on the other side of the king.
• Short castling (O-O) — kingside.
• Long castling (O-O-O) — queenside.
Requirements: the king and that rook have not moved yet; the path between them is empty; the king is not in check; the square the king crosses and the destination are not attacked.

EN PASSANT
If an enemy pawn advances 2 squares from its starting rank and lands beside your pawn on the same rank, on your very next move you may capture it "en passant": diagonally onto the square it passed through. The right expires after that one move.

PROMOTION
When a pawn reaches the last rank, it must become a queen, rook, bishop, or knight of the same color (usually a queen).

DRAWS
Possible by: stalemate; agreement; threefold repetition of the same position; insufficient material to mate; the 50-move rule (50 moves each without a capture or pawn move).

TURN ORDER
White moves first; then players alternate."""
	scroll.add_child(body)


func _show_main_menu() -> void:
	_stop_bot_worker()
	_stop_lobby_music()
	_start_menu_music()
	title_label.visible = true
	gear_button.visible = true
	current_screen = "menu"
	_clear_screen()

	# Full-screen menu background art (pawn / mirror)
	var bg_art := TextureRect.new()
	bg_art.texture = load("res://assets/icons/menu_art.png") as Texture2D
	bg_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_art.modulate = Color(1, 1, 1, 1)
	screen_root.add_child(bg_art)

	# Soft dark overlay so buttons stay readable
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.10, 0.07, 0.04, 0.28)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen_root.add_child(dim)

	var box := _content_container(360.0)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 36
	box.add_child(spacer)

	var bot_button := _button_style(GREEN, GREEN_HOVER, GREEN_PRESS, Color("ffffff"))
	bot_button.text = "  " + t("bot")
	bot_button.icon = _ui_icon("res://assets/icons/computer.png", 36)
	bot_button.expand_icon = false
	bot_button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	bot_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(bot_button)
	bot_button.pressed.connect(func() -> void: _show_bot_difficulty())

	var two_button := _button_style(BLUE, BLUE_HOVER, BLUE_PRESS)
	two_button.text = "  " + t("two")
	two_button.icon = _ui_icon("res://assets/icons/wifi.png", 36)
	two_button.expand_icon = false
	two_button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	two_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(two_button)
	two_button.pressed.connect(func() -> void: _show_two_player_type())

	var team_button := _button_style(BLUE, BLUE_HOVER, BLUE_PRESS)
	team_button.text = "  " + t("team")
	team_button.icon = _ui_icon("res://assets/icons/people.png", 36)
	team_button.expand_icon = false
	team_button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	team_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(team_button)
	team_button.pressed.connect(func() -> void: _show_network_lobby(4))

	var learn_button := _button_style(CYAN, CYAN_HOVER, CYAN_PRESS)
	learn_button.text = "  " + ("ОБУЧЕНИЕ" if language == "ru" else "TUTORIAL")
	learn_button.icon = _ui_icon("res://assets/icons/book.png", 36)
	learn_button.expand_icon = false
	learn_button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	learn_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(learn_button)
	learn_button.pressed.connect(func() -> void: _show_tutorial())
	call_deferred("_refresh_float_bases")

	var bottom_space := Control.new()
	bottom_space.custom_minimum_size.y = 20
	box.add_child(bottom_space)


func _show_bot_difficulty() -> void:
	_stop_bot_worker()
	title_label.visible = true
	gear_button.visible = true
	current_screen = "bot_difficulty"
	_clear_screen()
	_add_back_button(t("back"), _show_main_menu)
	var box := _content_container(360.0)
	box.add_child(_section_label(t("difficulty"), 22))
	var levels: Array[Dictionary] = [
		{"id": 1, "key": "beginner"},
		{"id": 2, "key": "easy"},
		{"id": 3, "key": "medium"},
		{"id": 4, "key": "pro"},
		{"id": 5, "key": "expert"}
	]
	for item: Dictionary in levels:
		var b := _button_style(BLUE, BLUE_HOVER, BLUE_PRESS)
		b.text = t(str(item.key))
		b.custom_minimum_size.y = 58
		b.pressed.connect(func(level: int = int(item.id)) -> void: _show_bot_side_selection(level))
		box.add_child(b)

func _show_bot_side_selection(level: int) -> void:
	_stop_bot_worker()
	title_label.visible = true
	gear_button.visible = true
	current_screen = "bot_side"
	current_bot_level = level
	_clear_screen()
	_add_back_button(t("back"), _show_bot_difficulty)
	var box := _content_container(360.0)
	box.add_child(_section_label(t("choose_side"), 28))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(row)
	row.add_child(_make_bot_side_button(ChessRules.WHITE, t("white_side"), "res://assets/pieces/white_king.png"))
	row.add_child(_make_bot_side_button(ChessRules.BLACK, t("black_side"), "res://assets/pieces/black_king.png"))
	row.add_child(_make_bot_side_button(0, t("random_side"), "res://assets/pieces/random_king.png"))

func _make_bot_side_button(side: int, label_text: String, texture_path: String) -> Button:
	var b := _button_style(BLUE, BLUE_HOVER, BLUE_PRESS)
	b.custom_minimum_size = Vector2(0, 150)
	b.text = label_text
	b.icon = _scaled_piece_texture(texture_path, 64)
	b.expand_icon = false
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(func(chosen_side: int = side) -> void: _start_bot_game(current_bot_level, chosen_side))
	return b

func _ui_icon(texture_path: String, max_size: int) -> Texture2D:
	var source: Texture2D = load(texture_path) as Texture2D
	if source == null:
		return null
	var image: Image = source.get_image()
	if image == null or image.is_empty():
		return source
	var original: Vector2 = Vector2(image.get_width(), image.get_height())
	var scale_factor: float = minf(float(max_size) / original.x, float(max_size) / original.y)
	if scale_factor >= 0.999:
		return source
	var target_w: int = maxi(1, roundi(original.x * scale_factor))
	var target_h: int = maxi(1, roundi(original.y * scale_factor))
	image.resize(target_w, target_h, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(image)


func _scaled_piece_texture(texture_path: String, max_size: int) -> Texture2D:
	var source: Texture2D = load(texture_path) as Texture2D
	if source == null:
		return null
	var image: Image = source.get_image()
	if image.is_empty():
		return source
	var original: Vector2 = Vector2(image.get_width(), image.get_height())
	var scale_factor: float = minf(float(max_size) / original.x, float(max_size) / original.y)
	if scale_factor >= 0.999:
		return source
	var target_w: int = maxi(1, roundi(original.x * scale_factor))
	var target_h: int = maxi(1, roundi(original.y * scale_factor))
	image.resize(target_w, target_h, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(image)

func _show_two_player_type() -> void:
	title_label.visible = true
	gear_button.visible = true
	current_screen = "two_type"
	_clear_screen()
	_add_back_button(t("back"), _show_main_menu)
	var box := _content_container(360.0)
	box.add_child(_section_label(t("game_type"), 23))
	var local := _button_style(BLUE, BLUE_HOVER, BLUE_PRESS)
	local.text = "  " + t("local")
	local.icon = _ui_icon("res://assets/icons/phone.png", 32)
	local.expand_icon = false
	local.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	local.alignment = HORIZONTAL_ALIGNMENT_LEFT
	local.custom_minimum_size.y = 78
	box.add_child(local)
	local.pressed.connect(func() -> void: _start_local_game())
	var lan := _button_style(BLUE, BLUE_HOVER, BLUE_PRESS)
	lan.text = "  " + t("lan")
	lan.icon = _ui_icon("res://assets/icons/wifi.png", 32)
	lan.expand_icon = false
	lan.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lan.alignment = HORIZONTAL_ALIGNMENT_LEFT
	lan.custom_minimum_size.y = 78
	box.add_child(lan)
	lan.pressed.connect(func() -> void: _show_network_lobby(2))


func _make_name_edit() -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = t("your_name")
	edit.text = "desu"
	edit.custom_minimum_size.y = 48
	edit.add_theme_font_size_override("font_size", 18)
	edit.add_theme_color_override("font_color", FIELD_TEXT)
	edit.add_theme_stylebox_override("normal", _field_style())
	edit.add_theme_stylebox_override("focus", _field_style())
	return edit

func _make_ip_edit() -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = "192.168.43.1"
	edit.custom_minimum_size.y = 48
	edit.add_theme_font_size_override("font_size", 18)
	edit.add_theme_color_override("font_color", FIELD_TEXT)
	edit.add_theme_stylebox_override("normal", _field_style())
	edit.add_theme_stylebox_override("focus", _field_style())
	return edit

func _team_name_for_slot(slot: int) -> String:
	return t("white_team") if slot < 2 else t("black_team")

func _slot_title(slot: int) -> String:
	return ("ИГРОК %d" % (slot + 1)) if language == "ru" else ("PLAYER %d" % (slot + 1))

func _slot_button_style(button_index: int, _slot: int, occupied: bool, mine: bool) -> void:
	if button_index < 0 or button_index >= slot_buttons.size() or not is_instance_valid(slot_buttons[button_index]):
		return
	var b: Button = slot_buttons[button_index]
	var active_color: Color = GREEN if mine else (Color("a89070") if occupied else BLUE)
	var hover_color: Color = GREEN_HOVER if mine else (Color("b9a282") if occupied else BLUE_HOVER)
	var press_color: Color = GREEN_PRESS if mine else (Color("8f7858") if occupied else BLUE_PRESS)
	b.add_theme_stylebox_override("normal", _button_box(active_color, 16, 7))
	b.add_theme_stylebox_override("hover", _button_box(hover_color, 16, 9))
	b.add_theme_stylebox_override("pressed", _button_box(press_color, 16, 3))

func _refresh_slot_buttons() -> void:
	if slot_buttons.is_empty():
		return
	var my_id: int = multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else -999
	var current_slot: int = GameNet.my_slot if GameNet.my_slot >= 0 else selected_network_slot
	var active_slots: Array[int] = []
	if network_mode == 4:
		active_slots.append(0)
		active_slots.append(1)
		active_slots.append(2)
		active_slots.append(3)
	else:
		active_slots.append(0)
		active_slots.append(2)
	for button_index: int in range(slot_buttons.size()):
		if not is_instance_valid(slot_buttons[button_index]):
			continue
		var b: Button = slot_buttons[button_index]
		var slot: int = slot_button_slots[button_index] if button_index < slot_button_slots.size() else active_slots[button_index]
		var entry: Variant = GameNet.players[slot] if GameNet.players.size() > slot else null
		var occupied: bool = entry != null
		var mine: bool = occupied and int(entry.peer_id) == my_id
		var can_choose: bool = not occupied or mine
		if not GameNet.is_host and GameNet.my_slot < 0 and not occupied:
			can_choose = true
		b.disabled = not can_choose
		var occupant_text: String = t("free")
		if occupied:
			occupant_text = str(entry.name)
			if mine:
				occupant_text += " • " + t("me")
		if network_mode == 2:
			b.text = t("white_side") if slot == 0 else t("black_side")
			if occupied:
				b.text += "\n" + occupant_text
		else:
			var team_text: String = _team_name_for_slot(slot)
			b.text = "%s\n%s\n%s" % [_slot_title(slot), team_text, occupant_text]
		var selected_now: bool = (slot == current_slot) and (mine or (GameNet.my_slot < 0 and slot == selected_network_slot))
		_slot_button_style(button_index, slot, occupied, selected_now)

func _choose_network_slot(slot: int) -> void:
	selected_network_slot = slot
	GameNet.set_pending_slot(slot)
	var err: Error = GameNet.change_slot(slot)
	if err != OK and err != ERR_BUSY:
		_toast(error_string(err))
	_refresh_slot_buttons()



func _ensure_menu_music_player() -> void:
	if menu_music_player != null and is_instance_valid(menu_music_player):
		return
	menu_music_player = AudioStreamPlayer.new()
	menu_music_player.bus = "Master"
	menu_music_player.volume_db = _music_slider_to_db(music_volume)
	add_child(menu_music_player)
	var stream: AudioStream = load("res://assets/sounds/lobby_theme.wav") as AudioStream
	if stream != null:
		if stream is AudioStreamWAV:
			var wav := stream as AudioStreamWAV
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			var channels: int = 2 if wav.stereo else 1
			var bytes_per_sample: int = 2 if wav.format == AudioStreamWAV.FORMAT_16_BITS else 1
			wav.loop_end = int(wav.data.size() / float(bytes_per_sample * channels))
		menu_music_player.stream = stream

func _start_menu_music() -> void:
	if music_volume <= 0.001:
		return
	_ensure_menu_music_player()
	if menu_music_player == null:
		return
	if menu_music_player.stream == null:
		var stream2: AudioStream = load("res://assets/sounds/lobby_theme.wav") as AudioStream
		if stream2 != null:
			if stream2 is AudioStreamWAV:
				var wav := stream2 as AudioStreamWAV
				wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
				wav.loop_begin = 0
				var channels: int = 2 if wav.stereo else 1
				var bytes_per_sample: int = 2 if wav.format == AudioStreamWAV.FORMAT_16_BITS else 1
				wav.loop_end = int(wav.data.size() / float(bytes_per_sample * channels))
			menu_music_player.stream = stream2
	if menu_music_player.stream == null:
		return
	# Не перезапускать при переходах по вкладкам — только если уже не играет
	menu_music_player.volume_db = _music_slider_to_db(music_volume)
	if not menu_music_player.playing:
		menu_music_player.play()

func _stop_menu_music() -> void:
	if menu_music_player != null and is_instance_valid(menu_music_player):
		menu_music_player.stop()

func _ensure_lobby_music_player() -> void:
	if lobby_music_player != null and is_instance_valid(lobby_music_player):
		return
	lobby_music_player = AudioStreamPlayer.new()
	lobby_music_player.bus = "Master"
	lobby_music_player.volume_db = _music_slider_to_db(music_volume)
	add_child(lobby_music_player)
	var stream: AudioStream = load("res://assets/sounds/lobby_theme.wav") as AudioStream
	if stream != null:
		if stream is AudioStreamWAV:
			var wav := stream as AudioStreamWAV
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			var channels: int = 2 if wav.stereo else 1
			var bytes_per_sample: int = 2 if wav.format == AudioStreamWAV.FORMAT_16_BITS else 1
			wav.loop_end = int(wav.data.size() / float(bytes_per_sample * channels))
		lobby_music_player.stream = stream

func _start_lobby_music() -> void:
	if music_volume <= 0.001:
		return
	_ensure_lobby_music_player()
	if lobby_music_player == null:
		return
	if lobby_music_player.stream == null:
		var stream2: AudioStream = load("res://assets/sounds/lobby_theme.wav") as AudioStream
		if stream2 != null:
			if stream2 is AudioStreamWAV:
				var wav := stream2 as AudioStreamWAV
				wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
				wav.loop_begin = 0
				var channels: int = 2 if wav.stereo else 1
				var bytes_per_sample: int = 2 if wav.format == AudioStreamWAV.FORMAT_16_BITS else 1
				wav.loop_end = int(wav.data.size() / float(bytes_per_sample * channels))
			lobby_music_player.stream = stream2
	if lobby_music_player.stream == null:
		return
	lobby_music_player.volume_db = _music_slider_to_db(music_volume)
	if not lobby_music_player.playing:
		lobby_music_player.play()

func _stop_lobby_music() -> void:
	if lobby_music_player != null and is_instance_valid(lobby_music_player):
		lobby_music_player.stop()


func _show_network_lobby(mode: int) -> void:
	# Never enter a network lobby while an old bot worker is still alive.
	_stop_bot_worker()
	title_label.visible = true
	gear_button.visible = true
	current_screen = "lobby"
	# Одна непрерывная тема: не сбрасываем при входе в лобби, только продолжаем
	_start_menu_music()
	network_mode = mode
	selected_network_slot = 0 if mode == 4 else 0
	GameNet.set_network_mode(mode)
	GameNet.set_pending_slot(selected_network_slot)
	slot_buttons.clear()
	slot_button_slots.clear()
	player_info_labels.clear()
	_clear_screen()
	_add_back_button(t("back"), _leave_network_to_menu)

	# Тёплый полупрозрачный слой — кнопки лобби лучше стыкуются с фоном
	var lobby_dim := ColorRect.new()
	lobby_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lobby_dim.color = Color(0.20, 0.14, 0.09, 0.40)
	lobby_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen_root.add_child(lobby_dim)

	# Для LAN-лобби контент начинается сразу под верхним заголовком,
	# чтобы адрес хоста был почти вверху, а остальные элементы шли ниже.
	var lobby_root := Control.new()
	lobby_root.set_anchors_preset(Control.PRESET_TOP_WIDE)
	lobby_root.offset_left = 18.0
	lobby_root.offset_right = -18.0
	lobby_root.offset_top = 70.0
	lobby_root.offset_bottom = -12.0
	screen_root.add_child(lobby_root)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 12)
	lobby_root.add_child(box)

	# Единственный блок с адресом хоста — сразу под заголовком.
	address_label = Label.new()
	address_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	address_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	address_label.add_theme_color_override("font_color", Color("e8d4a8"))
	address_label.add_theme_font_size_override("font_size", 17)
	address_label.custom_minimum_size = Vector2(0, 52)
	box.add_child(address_label)

	name_edit = _make_name_edit()
	box.add_child(name_edit)
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 10)
	action_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(action_row)
	var host := _button_style(GREEN, GREEN_HOVER, GREEN_PRESS)
	host.text = t("create")
	host.custom_minimum_size = Vector2(0, 66)
	host.add_theme_font_size_override("font_size", 18)
	host.autowrap_mode = TextServer.AUTOWRAP_OFF
	action_row.add_child(host)
	host.pressed.connect(_host)
	var join := _button_style(BLUE, BLUE_HOVER, BLUE_PRESS)
	join.text = t("join")
	join.custom_minimum_size = Vector2(0, 66)
	join.add_theme_font_size_override("font_size", 18)
	join.autowrap_mode = TextServer.AUTOWRAP_OFF
	action_row.add_child(join)
	join.pressed.connect(_join)
	ip_edit = _make_ip_edit()
	box.add_child(ip_edit)
	var slot_title_label := _section_label(t("choose_side") if mode == 2 else ("ВЫБЕРИТЕ МЕСТО" if language == "ru" else "CHOOSE A SLOT"), 22)
	box.add_child(slot_title_label)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(grid)
	var slot_options: Array[int] = []
	if mode == 2:
		slot_options.append(0)
		slot_options.append(2)
	else:
		slot_options.append(0)
		slot_options.append(1)
		slot_options.append(2)
		slot_options.append(3)
	for slot: int in slot_options:
		var slot_btn := Button.new()
		slot_btn.custom_minimum_size = Vector2(0, 78)
		slot_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot_btn.add_theme_font_size_override("font_size", 16)
		slot_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		slot_btn.add_theme_stylebox_override("normal", _button_box(BLUE, 16, 7))
		slot_btn.add_theme_stylebox_override("hover", _button_box(BLUE_HOVER, 16, 9))
		slot_btn.add_theme_stylebox_override("pressed", _button_box(BLUE_PRESS, 16, 3))
		grid.add_child(slot_btn)
		slot_buttons.append(slot_btn)
		slot_button_slots.append(slot)
		slot_btn.pressed.connect(func(chosen_slot: int = slot) -> void:
			_ui_click()
			_choose_network_slot(chosen_slot))
	var player_info_grid := GridContainer.new()
	player_info_grid.columns = 2
	player_info_grid.add_theme_constant_override("h_separation", 22)
	player_info_grid.add_theme_constant_override("v_separation", 8)
	player_info_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(player_info_grid)
	for slot: int in range(4):
		var info := Label.new()
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		info.add_theme_color_override("font_color", Color("f0e6d8"))
		info.add_theme_font_size_override("font_size", 14)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.custom_minimum_size = Vector2(0, 38)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		player_info_grid.add_child(info)
		player_info_labels.append(info)
	players_label = null
	start_button = _button_style(GREEN, GREEN_HOVER, GREEN_PRESS)
	start_button.text = t("start")
	start_button.visible = false
	start_button.custom_minimum_size.y = 60
	box.add_child(start_button)
	start_button.pressed.connect(_start)
	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_color_override("font_color", Color("d4c4b0"))
	status_label.add_theme_font_size_override("font_size", 14)
	box.add_child(status_label)
	_on_lobby(GameNet.players, GameNet.game_status)

func _leave_network_to_menu() -> void:
	GameNet.stop_host()
	set_process(true)
	set_process_input(true)
	_show_main_menu()

func _host() -> void:
	var player_name: String = name_edit.text.strip_edges() if is_instance_valid(name_edit) else "desu"
	var err: Error = GameNet.host_game(player_name, network_mode, selected_network_slot)
	if err != OK:
		_toast("%s: %s" % [t("create"), error_string(err)])
		return
	if is_instance_valid(address_label):
		address_label.text = GameNet._host_addresses_text()

func _join() -> void:
	var ip: String = ip_edit.text.strip_edges() if is_instance_valid(ip_edit) else ""
	if ip.is_empty():
		_toast(t("need_ip"))
		return
	var player_name: String = name_edit.text.strip_edges() if is_instance_valid(name_edit) else "desu"
	var err: Error = GameNet.join_game(ip, player_name, network_mode, selected_network_slot)
	if err != OK:
		_toast(error_string(err))

func _start() -> void:
	GameNet.start_game()

func _start_local_game() -> void:
	_stop_menu_music()
	_stop_lobby_music()
	_stop_lobby_music()
	bot_job_id += 1
	bot_thinking = false
	game_return_screen = "two_type"
	current_screen = "game"
	local_mode = "local"
	local_game_active = true
	local_board = ChessRules.initial_board()
	local_turn = ChessRules.WHITE
	local_castling = {"K": true, "Q": true, "k": true, "q": true}
	local_en_passant = Vector2i(-1, -1)
	_show_game_screen()

func _start_bot_game(level: int, chosen_side: int) -> void:
	_stop_menu_music()
	_stop_lobby_music()
	bot_job_id += 1
	bot_thinking = false
	game_return_screen = "bot_difficulty"
	current_screen = "game"
	local_mode = "bot"
	local_game_active = true
	current_bot_level = level
	bot_side_rng.randomize()
	if chosen_side == 0:
		bot_human_color = ChessRules.WHITE if bot_side_rng.randi_range(0, 1) == 0 else ChessRules.BLACK
	else:
		bot_human_color = chosen_side
	bot_color = -bot_human_color
	bot = ChessBot.new(level)
	bot_job_id += 1
	bot_thinking = false
	local_board = ChessRules.initial_board()
	local_turn = ChessRules.WHITE
	local_castling = {"K": true, "Q": true, "k": true, "q": true}
	local_en_passant = Vector2i(-1, -1)
	_show_game_screen()
	if local_game_active and local_turn == bot_color:
		call_deferred("_bot_move")


func _sq_name(sq: Vector2i) -> String:
	return "abcdefgh"[sq.x] + str(8 - sq.y)

func _piece_letter(piece_type: int) -> String:
	match piece_type:
		ChessRules.KNIGHT:
			return "N"
		ChessRules.BISHOP:
			return "B"
		ChessRules.ROOK:
			return "R"
		ChessRules.QUEEN:
			return "Q"
		ChessRules.KING:
			return "K"
		_:
			return ""

func _format_algebraic(before_board: Array, mv: Dictionary, is_check: bool, is_mate: bool) -> String:
	var from: Vector2i = mv.from
	var to: Vector2i = mv.to
	var piece: int = int(before_board[from.y][from.x])
	var ptype: int = ChessRules.type_of(piece)
	# Castling
	if ptype == ChessRules.KING and abs(to.x - from.x) == 2:
		var castle_text: String = "O-O" if to.x == 6 else "O-O-O"
		if is_mate:
			castle_text += "#"
		elif is_check:
			castle_text += "+"
		return castle_text
	var captured: int = int(before_board[to.y][to.x])
	var ep: bool = ptype == ChessRules.PAWN and captured == ChessRules.EMPTY and from.x != to.x
	var is_capture: bool = captured != ChessRules.EMPTY or ep
	var text_move: String = ""
	if ptype == ChessRules.PAWN:
		if is_capture:
			text_move = "abcdefgh"[from.x] + "x" + _sq_name(to)
		else:
			text_move = _sq_name(to)
	else:
		text_move = _piece_letter(ptype)
		if is_capture:
			text_move += "x"
		text_move += _sq_name(to)
	var promo: int = int(mv.get("promotion", 0))
	if ptype == ChessRules.PAWN and (to.y == 0 or to.y == 7) and promo in [ChessRules.KNIGHT, ChessRules.BISHOP, ChessRules.ROOK, ChessRules.QUEEN]:
		text_move += "=" + _piece_letter(promo)
	if is_mate:
		text_move += "#"
	elif is_check:
		text_move += "+"
	return text_move

func _notation_display_text() -> String:
	var parts: PackedStringArray = []
	var i: int = 0
	var move_no: int = 1
	while i < notation_log.size():
		var white_move: String = str(notation_log[i])
		var chunk: String = "%d. %s" % [move_no, white_move]
		i += 1
		if i < notation_log.size():
			chunk += " " + str(notation_log[i])
			i += 1
		parts.append(chunk)
		move_no += 1
	return "  ".join(parts)

func _refresh_notation_label() -> void:
	if not is_instance_valid(notation_label):
		return
	notation_label.text = _notation_display_text()
	notation_label.visible = notation_visible
	var parent_scroll := notation_label.get_parent()
	if parent_scroll is ScrollContainer:
		call_deferred("_scroll_notation_to_end", parent_scroll)

func _scroll_notation_to_end(scroll: ScrollContainer) -> void:
	if is_instance_valid(scroll):
		scroll.scroll_horizontal = 999999

func _toggle_notation() -> void:
	_ui_click()
	notation_visible = not notation_visible
	if is_instance_valid(notation_label):
		notation_label.visible = notation_visible
	var panels: Array[Node] = screen_root.find_children("NotationPanel", "Panel", true, false)
	for p in panels:
		(p as CanvasItem).visible = notation_visible
	if is_instance_valid(notation_toggle_btn):
		if language == "ru":
			notation_toggle_btn.text = "ПОКАЗАТЬ" if not notation_visible else "СКРЫТЬ"
		else:
			notation_toggle_btn.text = "SHOW" if not notation_visible else "HIDE"

func _append_notation_from_boards(before_board: Array, mv: Dictionary, after_board: Array, turn_after: int, castling_after: Dictionary, ep_after: Vector2i) -> void:
	var st: Dictionary = ChessRules.status(after_board, turn_after, castling_after, ep_after)
	var is_mate: bool = bool(st.get("mate", false))
	var is_check: bool = bool(st.get("check", false))
	var alg: String = _format_algebraic(before_board, mv, is_check, is_mate)
	notation_log.append(alg)
	_refresh_notation_label()

func _setup_notation_ui(top_y: float, height: float) -> void:
	var panel := Panel.new()
	panel.name = "NotationPanel"
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_left = 8.0
	panel.offset_right = -8.0
	panel.offset_top = top_y
	panel.offset_bottom = top_y + height
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.92, 0.86, 0.76, 0.95)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	panel.add_theme_stylebox_override("panel", style)
	screen_root.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.name = "NotationScroll"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 8.0
	scroll.offset_right = -8.0
	scroll.offset_top = 4.0
	scroll.offset_bottom = -4.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var line := Label.new()
	line.name = "NotationLog"
	line.text = ""
	line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.autowrap_mode = TextServer.AUTOWRAP_OFF
	line.add_theme_color_override("font_color", Color("3d2b1f"))
	line.add_theme_font_size_override("font_size", 14)
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	scroll.add_child(line)
	notation_label = line
	panel.visible = notation_visible

	notation_toggle_btn = Button.new()
	notation_toggle_btn.name = "NotationToggle"
	notation_toggle_btn.text = "СКРЫТЬ" if language == "ru" else "HIDE"
	notation_toggle_btn.custom_minimum_size = Vector2(0, 40)
	notation_toggle_btn.add_theme_font_size_override("font_size", 15)
	notation_toggle_btn.add_theme_color_override("font_color", Color("f7f0e6"))
	notation_toggle_btn.add_theme_stylebox_override("normal", _button_box(Color("8a7358"), 12, 3))
	notation_toggle_btn.add_theme_stylebox_override("hover", _button_box(Color("a08a6a"), 12, 4))
	notation_toggle_btn.add_theme_stylebox_override("pressed", _button_box(Color("6e5a42"), 12, 2))
	notation_toggle_btn.pressed.connect(_toggle_notation)
	# Position assigned later in _layout_game_chrome
	screen_root.add_child(notation_toggle_btn)
	_refresh_notation_label()


func _show_game_screen() -> void:
	title_label.visible = true
	gear_button.visible = true
	_clear_screen()
	_add_back_button("←", _exit_current_game)

	var viewport_w: float = get_viewport_rect().size.x
	var viewport_h: float = get_viewport_rect().size.y
	if viewport_w < 1.0:
		viewport_w = 400.0
	if viewport_h < 1.0:
		viewport_h = 800.0

	# Layout zones (no overlap):
	# top: title ~0-56, status 56-92, notation 96-168
	# bottom: toggle + optional bot bar
	var status_top: float = 56.0
	var status_h: float = 36.0
	var notation_top: float = 96.0
	var notation_h: float = 72.0
	var bottom_bar_h: float = 52.0
	var bot_bar_h: float = 86.0 if local_mode == "bot" else 0.0
	var bottom_reserved: float = bottom_bar_h + bot_bar_h + 16.0
	var top_reserved: float = notation_top + notation_h + 8.0

	var status := Label.new()
	status.name = "GameStatus"
	status.set_anchors_preset(Control.PRESET_TOP_WIDE)
	status.offset_top = status_top
	status.offset_left = 14.0
	status.offset_right = -14.0
	status.offset_bottom = status_top + status_h
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_color_override("font_color", TEXT)
	status.add_theme_font_size_override("font_size", 17)
	screen_root.add_child(status)

	notation_log.clear()
	notation_visible = true
	_setup_notation_ui(notation_top, notation_h)

	board_view = ChessBoard.new()
	var available_h: float = viewport_h - top_reserved - bottom_reserved
	var board_size: float = minf(viewport_w, maxf(280.0, available_h))
	board_view.custom_minimum_size = Vector2(board_size, board_size)
	board_view.size = Vector2(board_size, board_size)
	var board_x: float = (viewport_w - board_size) * 0.5
	var board_y: float = top_reserved + (available_h - board_size) * 0.5
	board_view.position = Vector2(board_x, board_y)
	board_view.board = GameNet.board if local_mode == "lan" else local_board
	board_view.turn_team = GameNet.turn_team if local_mode == "lan" else local_turn
	if local_mode == "lan":
		board_view.perspective_color = int(GameNet.players[GameNet.my_slot].team) if GameNet.my_slot >= 0 and GameNet.my_slot < GameNet.players.size() and GameNet.players[GameNet.my_slot] != null else ChessRules.WHITE
	elif local_mode == "bot":
		board_view.perspective_color = bot_human_color
	elif local_mode == "local":
		board_view.perspective_color = local_turn
	else:
		board_view.perspective_color = ChessRules.WHITE
	screen_root.add_child(board_view)
	board_view.square_tapped.connect(_square_tapped)

	# Hide/Show under the board (never on the board)
	if is_instance_valid(notation_toggle_btn):
		var toggle_y: float = board_y + board_size + 8.0
		notation_toggle_btn.set_anchors_preset(Control.PRESET_TOP_WIDE)
		notation_toggle_btn.anchor_bottom = 0.0
		notation_toggle_btn.offset_left = 70.0
		notation_toggle_btn.offset_right = -70.0
		notation_toggle_btn.offset_top = toggle_y
		notation_toggle_btn.offset_bottom = toggle_y + 40.0

	if local_mode == "bot":
		hint_step = 0
		last_hint_move = {}
		if is_instance_valid(board_view):
			board_view.clear_hint()
		_add_bot_toolbar(board_y + board_size + 56.0)
	if local_mode == "local" or local_mode == "bot":
		move_history.clear()
	_update_game_screen_status(status)


func _update_game_screen_status(label: Label) -> void:
	if local_mode == "bot":
		if local_turn == bot_human_color and local_game_active:
			label.text = t("your_turn")
		else:
			label.text = t("bot_thinking") if local_game_active else t("game_finished")
	elif local_mode == "local":
		label.text = t("your_turn_white") if local_turn == ChessRules.WHITE else t("your_turn_black")
	else:
		label.text = _network_status_text(GameNet.game_status)

func _exit_current_game() -> void:
	if local_mode == "bot":
		_stop_bot_worker()
	else:
		bot_job_id += 1
		bot_thinking = false
	var destination: String = game_return_screen
	if local_mode == "lan":
		GameNet.stop_host()
	local_game_active = false
	match destination:
		"bot_difficulty":
			_show_bot_difficulty()
		"two_type":
			_show_two_player_type()
		"lobby":
			_show_network_lobby(network_mode)
		_:
			set_process(true)
	set_process_input(true)
	_show_main_menu()


func _add_bot_toolbar(top_y: float = -1.0) -> void:
	var bar := HBoxContainer.new()
	bar.name = "BotToolbar"
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 10.0
	bar.offset_right = -10.0
	if top_y < 0.0:
		top_y = get_viewport_rect().size.y - 100.0
	bar.offset_top = top_y
	bar.offset_bottom = top_y + 78.0
	bar.add_theme_constant_override("separation", 12)
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	screen_root.add_child(bar)

	bar.add_child(_bot_tool_button("💡", "Подсказка" if language == "ru" else "Hint", _on_hint_pressed))
	bar.add_child(_bot_tool_button("↩", "Назад" if language == "ru" else "Undo", _on_undo_pressed))
	bar.add_child(_bot_tool_button("↻", "Заново" if language == "ru" else "Restart", _on_restart_bot_pressed))

func _bot_tool_button(icon_text: String, label_text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = icon_text + "\n" + label_text
	b.custom_minimum_size = Vector2(112, 68)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", Color("f7f0e6"))
	b.add_theme_stylebox_override("normal", _button_box(Color("8a7358"), 14, 4))
	b.add_theme_stylebox_override("hover", _button_box(Color("a08a6a"), 14, 5))
	b.add_theme_stylebox_override("pressed", _button_box(Color("6e5a42"), 14, 2))
	b.pressed.connect(func() -> void:
		_ui_click()
		callback.call())
	call_deferred("_register_float_node", b)
	return b

func _on_hint_pressed() -> void:
	if local_mode != "bot" or not local_game_active or bot_thinking:
		return
	if local_turn != bot_human_color:
		_toast("Сейчас ход бота" if language == "ru" else "Bot is to move")
		return
	if not is_instance_valid(board_view):
		return
	if hint_step == 0 or last_hint_move.is_empty():
		var helper := ChessBot.new(1)
		var mv: Dictionary = helper.choose_move(local_board, bot_human_color, local_castling, local_en_passant)
		if mv.is_empty():
			_toast("Нет ходов" if language == "ru" else "No moves")
			return
		last_hint_move = mv
		board_view.hint_from = mv.from
		board_view.hint_to = mv.to
		board_view.show_hint_to = false
		hint_step = 1
		board_view.queue_redraw()
		_toast("Лучшая фигура" if language == "ru" else "Best piece")
	else:
		board_view.hint_from = last_hint_move.from
		board_view.hint_to = last_hint_move.to
		board_view.show_hint_to = true
		hint_step = 0
		board_view.queue_redraw()
		_toast("Куда ходить" if language == "ru" else "Best square")

func _on_undo_pressed() -> void:
	if local_mode != "bot" or bot_thinking:
		return
	if move_history.size() < 1:
		_toast("Нечего отменять" if language == "ru" else "Nothing to undo")
		return
	# Отменить ход бота и ход игрока (если есть)
	var steps: int = 0
	while steps < 2 and move_history.size() > 0:
		var snap: Dictionary = move_history.pop_back()
		local_board = snap.board
		local_castling = snap.castling
		local_en_passant = snap.en_passant
		local_turn = snap.turn
		local_game_active = snap.active
		if notation_log.size() > 0:
			notation_log.pop_back()
		steps += 1
	_refresh_notation_label()
	hint_step = 0
	last_hint_move = {}
	if is_instance_valid(board_view):
		board_view.clear_hint()
		board_view.board = local_board
		board_view.turn_team = local_turn
		board_view.perspective_color = bot_human_color
		board_view.selected = Vector2i(-1, -1)
		board_view.legal_targets = []
		board_view.queue_redraw()
	selected = Vector2i(-1, -1)
	legal_targets.clear()
	if effects_volume > 0.001:
		SoundFX.play("undo", _effects_slider_to_db(effects_volume))
	var labels: Array[Node] = screen_root.find_children("GameStatus", "Label", true, false)
	if not labels.is_empty():
		_update_game_screen_status(labels[0] as Label)

func _on_restart_bot_pressed() -> void:
	if local_mode != "bot":
		return
	_stop_bot_worker()
	bot_job_id += 1
	bot_thinking = false
	move_history.clear()
	notation_log.clear()
	_refresh_notation_label()
	hint_step = 0
	last_hint_move = {}
	local_board = ChessRules.initial_board()
	local_turn = ChessRules.WHITE
	local_castling = {"K": true, "Q": true, "k": true, "q": true}
	local_en_passant = Vector2i(-1, -1)
	local_game_active = true
	selected = Vector2i(-1, -1)
	legal_targets.clear()
	if is_instance_valid(board_view):
		board_view.clear_hint()
		board_view.board = local_board
		board_view.turn_team = local_turn
		board_view.perspective_color = bot_human_color
		board_view.selected = selected
		board_view.legal_targets = []
		board_view.queue_redraw()
	var labels: Array[Node] = screen_root.find_children("GameStatus", "Label", true, false)
	if not labels.is_empty():
		_update_game_screen_status(labels[0] as Label)
	if local_turn == bot_color:
		call_deferred("_bot_move")

func _square_tapped(square: Vector2i) -> void:
	if local_mode == "lan":
		_square_tapped_lan(square)
	else:
		_square_tapped_local(square)

func _square_tapped_lan(square: Vector2i) -> void:
	if not GameNet.started or GameNet.my_slot < 0:
		return
	if GameNet.my_slot != GameNet.turn_slot:
		_toast(t("other_player"))
		return
	var my_team: int = int(GameNet.players[GameNet.my_slot].team)
	if my_team != GameNet.turn_team:
		_toast(t("other_team"))
		return
	_select_or_move(square, GameNet.board, GameNet.turn_team, GameNet.castling, GameNet.en_passant, true)

func _square_tapped_local(square: Vector2i) -> void:
	if not local_game_active: return
	if local_mode == "bot" and local_turn != bot_human_color: return
	_select_or_move(square, local_board, local_turn, local_castling, local_en_passant, false)

func _select_or_move(square: Vector2i, board: Array, turn_color: int, castling: Dictionary, en_passant: Vector2i, remote: bool) -> void:
	if selected.x < 0:
		var piece: int = int(board[square.y][square.x])
		if ChessRules.color_of(piece) == turn_color:
			selected = square
			legal_targets.clear()
			var castle_list: Array = []
			var piece_sel: int = int(board[square.y][square.x])
			for mv: Dictionary in ChessRules.legal_moves(board, turn_color, castling, en_passant):
				if mv.from == square:
					legal_targets.append(mv.to)
					if ChessRules.type_of(piece_sel) == ChessRules.KING and abs(int(mv.to.x) - square.x) == 2:
						castle_list.append(mv.to)
			board_view.selected = selected
			board_view.legal_targets = legal_targets
			board_view.castle_targets = castle_list
			board_view.queue_redraw()
		return
	if square == selected:
		selected = Vector2i(-1, -1)
		legal_targets.clear()
		board_view.selected = selected
		board_view.legal_targets = legal_targets
		board_view.castle_targets = []
		board_view.queue_redraw()
		return
	if square in legal_targets:
		var piece_moving: int = int(board[selected.y][selected.x])
		if ChessRules.type_of(piece_moving) == ChessRules.PAWN and square.y in [0, 7]:
			_ask_promotion(selected, square, remote)
			return
		_perform_move(selected, square, ChessRules.QUEEN, remote)
		return
	var other_piece: int = int(board[square.y][square.x])
	if ChessRules.color_of(other_piece) == turn_color:
		selected = square
		legal_targets.clear()
		var castle_list2: Array = []
		var piece_sel2: int = int(board[square.y][square.x])
		for mv: Dictionary in ChessRules.legal_moves(board, turn_color, castling, en_passant):
			if mv.from == square:
				legal_targets.append(mv.to)
				if ChessRules.type_of(piece_sel2) == ChessRules.KING and abs(int(mv.to.x) - square.x) == 2:
					castle_list2.append(mv.to)
		board_view.selected = selected
		board_view.legal_targets = legal_targets
		board_view.castle_targets = castle_list2
		board_view.queue_redraw()

func _ask_promotion(from: Vector2i, to: Vector2i, remote: bool) -> void:
	_close_overlay()
	var panel := Panel.new()
	var board_size: float = 376.0
	var cell: float = board_size / 8.0
	panel.custom_minimum_size = Vector2(cell, cell * 4.0)
	panel.size = Vector2(cell, cell * 4.0)
	var is_white: bool = int((GameNet.board if remote else local_board)[from.y][from.x]) > 0
	var panel_color: Color = Color("b58863") if is_white else Color("ebecd0")
	var border_color: Color = Color("7c5a41") if is_white else Color("b6a87e")
	var style := StyleBoxFlat.new()
	style.bg_color = panel_color
	style.border_color = border_color
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	panel.add_theme_stylebox_override("panel", style)
	var choices: Array[int] = []
	choices.append(ChessRules.QUEEN)
	choices.append(ChessRules.ROOK)
	choices.append(ChessRules.BISHOP)
	choices.append(ChessRules.KNIGHT)
	var pieces: Dictionary = {
		ChessRules.QUEEN: preload("res://assets/pieces/white_queen.png") if is_white else preload("res://assets/pieces/black_queen.png"),
		ChessRules.ROOK: preload("res://assets/pieces/white_rook.png") if is_white else preload("res://assets/pieces/black_rook.png"),
		ChessRules.BISHOP: preload("res://assets/pieces/white_bishop.png") if is_white else preload("res://assets/pieces/black_bishop.png"),
		ChessRules.KNIGHT: preload("res://assets/pieces/white_knight.png") if is_white else preload("res://assets/pieces/black_knight.png")
	}
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 0)
	panel.add_child(column)
	for piece_type: int in choices:
		var choice := Button.new()
		choice.custom_minimum_size = Vector2(cell, cell)
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choice.size_flags_vertical = Control.SIZE_EXPAND_FILL
		choice.text = ""
		choice.add_theme_stylebox_override("normal", _button_box(panel_color, 0, 0))
		choice.add_theme_stylebox_override("hover", _button_box(panel_color.lightened(0.08), 0, 0))
		choice.add_theme_stylebox_override("pressed", _button_box(panel_color.darkened(0.08), 0, 0))
		column.add_child(choice)
		var piece_rect := TextureRect.new()
		piece_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		piece_rect.offset_left = 7.0
		piece_rect.offset_top = 7.0
		piece_rect.offset_right = -7.0
		piece_rect.offset_bottom = -7.0
		piece_rect.texture = pieces[piece_type] as Texture2D
		piece_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		piece_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		piece_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		choice.add_child(piece_rect)
		choice.pressed.connect(func(chosen_piece: int = piece_type) -> void:
			_close_overlay()
			_perform_move(from, to, chosen_piece, remote)
		)

	overlay_root.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay_root.add_child(panel)
	var view_square: Vector2i = board_view.board_to_view(to) if is_instance_valid(board_view) else to
	var top_row: int = 0 if view_square.y <= 3 else 4
	var board_x: float = board_view.position.x if is_instance_valid(board_view) else (400.0 - board_size) * 0.5
	var board_y: float = board_view.position.y if is_instance_valid(board_view) else 120.0
	var panel_x: float = board_x + float(view_square.x) * cell
	var panel_y: float = board_y + float(top_row) * cell
	panel.position = Vector2(panel_x, panel_y)
func _play_move_effect(before_board: Array, after_board: Array, status_text: String = "") -> void:
	if effects_volume <= 0.001 or before_board.size() != 8 or after_board.size() != 8:
		return
	var event: String = "move"
	var occupied_before: int = 0
	var occupied_after: int = 0
	var castle: bool = false
	var promotion: bool = false
	for y in range(8):
		for x in range(8):
			var before_piece: int = int(before_board[y][x])
			var after_piece: int = int(after_board[y][x])
			if before_piece != ChessRules.EMPTY:
				occupied_before += 1
			if after_piece != ChessRules.EMPTY:
				occupied_after += 1
	for y in range(8):
		for x in range(8):
			var before_piece: int = int(before_board[y][x])
			var after_piece: int = int(after_board[y][x])
			if abs(before_piece) == ChessRules.KING and abs(after_piece) == ChessRules.KING and before_piece == after_piece:
				# A king moving two files identifies castling visually in the resulting position.
				for tx in range(8):
					if tx != x and int(after_board[y][tx]) == after_piece and abs(tx - x) == 2:
						castle = true
			if abs(before_piece) == ChessRules.PAWN and after_piece != 0 and ChessRules.color_of(before_piece) == ChessRules.color_of(after_piece) and abs(after_piece) != ChessRules.PAWN:
				promotion = true
	var lower_status: String = status_text.to_lower()
	if lower_status.contains("мат") or lower_status.contains("mate"):
		event = "mate"
	elif lower_status.contains("пат") or lower_status.contains("stalemate") or lower_status.contains("ничья") or lower_status.contains("draw"):
		event = "draw"
	elif castle:
		event = "castle"
	elif promotion:
		event = "promotion"
	elif occupied_after < occupied_before:
		event = "capture"
	elif lower_status.contains("шах") or lower_status.contains("check"):
		event = "check"
	SoundFX.play(event, _effects_slider_to_db(effects_volume))


func _push_move_snapshot() -> void:
	var board_copy: Array = local_board.duplicate(true)
	move_history.append({
		"board": board_copy,
		"castling": local_castling.duplicate(true),
		"en_passant": local_en_passant,
		"turn": local_turn,
		"active": local_game_active
	})

func _perform_move(from: Vector2i, to: Vector2i, promotion: int, remote: bool) -> void:
	if remote:
		GameNet.request_move(from, to, promotion)
	else:
		var mv: Dictionary = ChessRules.find_move(local_board, local_turn, from, to, promotion, local_castling, local_en_passant)
		if mv.is_empty():
			_toast(t("invalid"))
			return
		_push_move_snapshot()
		var before_board: Array = local_board.duplicate(true)
		var result: Dictionary = ChessRules.make_move(local_board, mv, local_castling, local_en_passant)
		local_board = result.board
		local_castling = result.castling
		local_en_passant = result.en_passant
		local_turn = -local_turn
		_append_notation_from_boards(before_board, mv, local_board, local_turn, local_castling, local_en_passant)
		hint_step = 0
		last_hint_move = {}
		if is_instance_valid(board_view):
			board_view.clear_hint()
		var local_status: Dictionary = ChessRules.status(local_board, local_turn, local_castling, local_en_passant)
		var effect_status: String = ""
		if bool(local_status.get("mate", false)):
			effect_status = "mate"
		elif bool(local_status.get("stalemate", false)):
			effect_status = "draw"
		elif bool(local_status.get("check", false)):
			effect_status = "check"
		_play_move_effect(before_board, local_board, effect_status)
		_reset_selection()
		_refresh_local_game()
		if local_game_active and local_mode == "bot" and local_turn == bot_color:
			call_deferred("_bot_move")
	if remote:
		_reset_selection()

func _reset_selection() -> void:
	selected = Vector2i(-1, -1)
	legal_targets.clear()
	if is_instance_valid(board_view):
		board_view.selected = selected
		board_view.legal_targets = legal_targets
		board_view.castle_targets = []
		board_view.queue_redraw()

func _stop_bot_worker() -> void:
	# Invalidate any queued result from the current bot calculation first.
	bot_job_id += 1
	bot_thinking = false
	if bot_thread != null:
		# The worker only uses its private snapshots, so it is safe to wait
		# for it here before switching to another game/network screen.
		bot_thread.wait_to_finish()
		bot_thread = null

func _bot_move() -> void:
	if not local_game_active or local_mode != "bot" or local_turn != bot_color or bot_thinking:
		return
	if bot_thread != null:
		return

	bot_thinking = true
	var job_id: int = bot_job_id + 1
	bot_job_id = job_id
	var board_snapshot: Array = ChessRules.clone_board(local_board)
	var castling_snapshot: Dictionary = local_castling.duplicate(true)
	var en_passant_snapshot: Vector2i = local_en_passant
	var bot_color_snapshot: int = bot_color
	var level_snapshot: int = current_bot_level

	var status_labels: Array[Node] = screen_root.find_children("GameStatus", "Label", true, false)
	if not status_labels.is_empty():
		_update_game_screen_status(status_labels[0] as Label)

	bot_thread = Thread.new()
	var err: Error = bot_thread.start(Callable(self, "_bot_search_thread").bind(job_id, board_snapshot, bot_color_snapshot, castling_snapshot, en_passant_snapshot, level_snapshot))
	if err != OK:
		bot_thread = null
		bot_thinking = false
		_toast("Не удалось запустить расчёт бота." if language == "ru" else "Could not start the bot calculation.")

func _bot_search_thread(job_id: int, board_snapshot: Array, bot_color_snapshot: int, castling_snapshot: Dictionary, en_passant_snapshot: Vector2i, level_snapshot: int) -> void:
	var worker_bot := ChessBot.new(level_snapshot)
	var move: Dictionary = worker_bot.choose_move(board_snapshot, bot_color_snapshot, castling_snapshot, en_passant_snapshot)
	call_deferred("_on_bot_search_finished", job_id, move)

func _on_bot_search_finished(job_id: int, move: Dictionary) -> void:
	if bot_thread != null:
		bot_thread.wait_to_finish()
		bot_thread = null
	bot_thinking = false

	if job_id != bot_job_id:
		return
	if not local_game_active or local_mode != "bot" or local_turn != bot_color:
		return
	if move.is_empty():
		local_game_active = false
		_refresh_local_game()
		return

	await get_tree().create_timer(0.35).timeout
	if not local_game_active or local_mode != "bot" or local_turn != bot_color or job_id != bot_job_id:
		return
	_push_move_snapshot()
	var before_board: Array = local_board.duplicate(true)
	var result: Dictionary = ChessRules.make_move(local_board, move, local_castling, local_en_passant)
	local_board = result.board
	local_castling = result.castling
	local_en_passant = result.en_passant
	local_turn = -local_turn
	_append_notation_from_boards(before_board, move, local_board, local_turn, local_castling, local_en_passant)
	var bot_status: Dictionary = ChessRules.status(local_board, local_turn, local_castling, local_en_passant)
	var bot_effect_status: String = ""
	if bool(bot_status.get("mate", false)):
		bot_effect_status = "mate"
	elif bool(bot_status.get("stalemate", false)):
		bot_effect_status = "draw"
	elif bool(bot_status.get("check", false)):
		bot_effect_status = "check"
	_play_move_effect(before_board, local_board, bot_effect_status)
	_refresh_local_game()
	if local_game_active and local_mode == "bot" and local_turn == bot_color:
		call_deferred("_bot_move")

func _refresh_local_game() -> void:
	if not is_instance_valid(board_view): return
	board_view.board = local_board
	board_view.turn_team = local_turn
	if local_mode == "bot":
		board_view.perspective_color = bot_human_color
	elif local_mode == "local":
		board_view.perspective_color = local_turn
	else:
		board_view.perspective_color = ChessRules.WHITE
	board_view.selected = selected
	board_view.legal_targets = legal_targets
	board_view.queue_redraw()
	var labels: Array[Node] = screen_root.find_children("GameStatus", "Label", true, false)
	if not labels.is_empty():
		_update_game_screen_status(labels[0] as Label)
	var state: Dictionary = ChessRules.status(local_board, local_turn, local_castling, local_en_passant)
	if state.mate:
		local_game_active = false
		(labels[0] as Label).text = t("mate_white") if local_turn == ChessRules.BLACK else t("mate_black")
	elif state.stalemate:
		local_game_active = false
		(labels[0] as Label).text = t("stalemate")
	elif state.check:
		(labels[0] as Label).text = t("check_white") if local_turn == ChessRules.WHITE else t("check_black")

func _on_lobby(players: Array, status: String) -> void:
	if current_screen != "lobby": return
	if is_instance_valid(address_label):
		address_label.text = GameNet._host_addresses_text() if GameNet.is_host else ""
	if not player_info_labels.is_empty():
		var active_slots_for_info: Array[int] = []
		if network_mode == 4:
			active_slots_for_info.assign([0, 1, 2, 3])
		else:
			active_slots_for_info.assign([0, 2])
		for i: int in range(player_info_labels.size()):
			var info_label: Label = player_info_labels[i]
			if not is_instance_valid(info_label):
				continue
			if network_mode != 4 and i >= active_slots_for_info.size():
				info_label.visible = false
				continue
			info_label.visible = true
			var slot: int = active_slots_for_info[i] if network_mode != 4 else i
			var entry: String = t("free")
			if players.size() > slot and players[slot] != null:
				entry = str(players[slot].name)
				if int(players[slot].peer_id) == multiplayer.get_unique_id():
					entry += " • " + t("me")
			var team_name: String = t("white_team") if slot < 2 else t("black_team")
			var display_number: int = (i + 1) if network_mode == 2 else (slot + 1)
			info_label.text = "%d. %s — %s" % [display_number, team_name, entry]
	if is_instance_valid(status_label):
		status_label.text = _network_status_text(status)
	if GameNet.my_slot >= 0:
		selected_network_slot = GameNet.my_slot
	_refresh_slot_buttons()
	var count: int = 0
	var active_slots: Array[int] = []
	if network_mode == 4:
		active_slots.assign([0, 1, 2, 3])
	else:
		active_slots.assign([0, 2])
	for slot: int in active_slots:
		if players.size() > slot and players[slot] != null:
			count += 1
	if is_instance_valid(start_button):
		start_button.visible = GameNet.is_host and count == (4 if network_mode == 4 else 2)

func _network_status_text(text_value: String) -> String:
	if text_value == "": return ""
	if text_value.contains("4/4") or text_value.contains("2/2") or text_value == Locale.t("lobby_full", "ru"):
		return t("lobby_full")
	if text_value.contains("Лобби"):
		var numbers: Array = text_value.split("/")
		if not numbers.is_empty():
			var count_text: String = str(numbers[0]).split(": ")[-1]
			var n: int = int(count_text)
			return Locale.format("lobby_wait_4" if network_mode == 4 else "lobby_wait_2", n, language)
	if text_value == "Ход белых": return t("your_turn_white")
	if text_value == "Ход чёрных": return t("your_turn_black")
	if text_value == "Игра началась": return t("game_started")
	if text_value.begins_with("Мат. Победили"):
		return t("mate_white") if text_value.contains("белые") else t("mate_black")
	if text_value == "Пат. Ничья.": return t("stalemate")
	if text_value.begins_with("Шах!"):
		return t("check_white") if text_value.contains("белых") else t("check_black")
	return text_value

func _last_move_is_initial(move_text: String) -> bool:
	var value: String = move_text.strip_edges().to_lower()
	return value.is_empty() or value == "игра началась" or value == "game started"


func _detect_move(before_board: Array, after_board: Array) -> Dictionary:
	if before_board.size() != 8 or after_board.size() != 8:
		return {}
	var froms: Array[Vector2i] = []
	var tos: Array[Vector2i] = []
	for y in range(8):
		for x in range(8):
			var a: int = int(before_board[y][x])
			var b: int = int(after_board[y][x])
			if a != b:
				if a != ChessRules.EMPTY and b == ChessRules.EMPTY:
					froms.append(Vector2i(x, y))
				elif b != ChessRules.EMPTY and (a == ChessRules.EMPTY or ChessRules.color_of(a) != ChessRules.color_of(b)):
					tos.append(Vector2i(x, y))
	# Castling: king moves 2, rook also moves
	var from_sq := Vector2i(-1, -1)
	var to_sq := Vector2i(-1, -1)
	for f in froms:
		var piece: int = int(before_board[f.y][f.x])
		if ChessRules.type_of(piece) == ChessRules.KING:
			from_sq = f
			break
	if from_sq.x < 0 and froms.size() > 0:
		from_sq = froms[0]
	for cand in tos:
		var piece_after: int = int(after_board[cand.y][cand.x])
		if from_sq.x >= 0:
			var piece_before: int = int(before_board[from_sq.y][from_sq.x])
			if ChessRules.color_of(piece_after) == ChessRules.color_of(piece_before) or (ChessRules.type_of(piece_before) == ChessRules.KING and abs(cand.x - from_sq.x) <= 2):
				if ChessRules.type_of(piece_after) == ChessRules.type_of(piece_before) or ChessRules.type_of(piece_before) == ChessRules.PAWN:
					to_sq = cand
					break
	if to_sq.x < 0 and tos.size() > 0:
		to_sq = tos[0]
	if from_sq.x < 0 or to_sq.x < 0:
		return {}
	var promo: int = 0
	var before_piece: int = int(before_board[from_sq.y][from_sq.x])
	var after_piece: int = int(after_board[to_sq.y][to_sq.x])
	if ChessRules.type_of(before_piece) == ChessRules.PAWN and ChessRules.type_of(after_piece) != ChessRules.PAWN:
		promo = ChessRules.type_of(after_piece)
	return {"from": from_sq, "to": to_sq, "promotion": promo}

func _on_game(_board: Array, _turn: int, status: String, _last_move: String) -> void:
	if current_screen == "lobby" or current_screen == "game":
		if current_screen == "lobby":
			_stop_menu_music()
			_stop_lobby_music()
			game_return_screen = "lobby"
			current_screen = "game"
			notation_log.clear()
			_show_game_screen()
		var before_board: Array = board_view.board.duplicate(true) if is_instance_valid(board_view) and board_view.board.size() == 8 else []
		if is_instance_valid(board_view):
			board_view.board = GameNet.board
			board_view.turn_team = GameNet.turn_team
			_reset_selection()
			board_view.queue_redraw()
			if not _last_move_is_initial(_last_move):
				_play_move_effect(before_board, GameNet.board, status)
				var net_mv: Dictionary = _detect_move(before_board, GameNet.board)
				if not net_mv.is_empty():
					_append_notation_from_boards(before_board, net_mv, GameNet.board, GameNet.turn_team, GameNet.castling, GameNet.en_passant)
		var labels: Array[Node] = screen_root.find_children("GameStatus", "Label", true, false)
		if not labels.is_empty():
			(labels[0] as Label).text = _network_status_text(status)

func _on_connection(text_value: String) -> void:
	if current_screen != "lobby":
		return

	# Адрес хоста показываем только в одном месте — в address_label.
	if GameNet.is_host:
		if is_instance_valid(address_label):
			address_label.text = GameNet._host_addresses_text()
		if is_instance_valid(status_label):
			status_label.text = ""
	elif is_instance_valid(status_label):
		status_label.text = _network_status_text(text_value)

func _simple_dialog() -> Panel:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(340, 0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.add_theme_stylebox_override("panel", _card_style(Color("06232b"), 22))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	return panel

func _open_overlay(panel: Control) -> void:
	_close_overlay()
	var dim := ColorRect.new()
	dim.color = Color("031116")
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay_root.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_top = 76
	center.offset_bottom = -24
	center.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay_root.add_child(center)
	center.add_child(panel)

func _add_overlay_back(callback: Callable) -> void:
	var back := Button.new()
	back.text = "←"
	back.position = Vector2(10, 8)
	back.custom_minimum_size = Vector2(54, 54)
	back.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	back.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	back.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	back.add_theme_color_override("font_color", MUTED)
	back.add_theme_color_override("font_hover_color", TEXT)
	back.add_theme_color_override("font_pressed_color", TEXT)
	back.add_theme_font_size_override("font_size", 34)
	overlay_root.add_child(back)
	back.pressed.connect(func() -> void:
		_ui_click()
		callback.call())

func _close_overlay() -> void:
	for child in overlay_root.get_children():
		child.queue_free()
	overlay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _settings_back_to_previous() -> void:
	var destination: String = settings_return_screen
	title_label.visible = true
	gear_button.visible = true
	match destination:
		"game":
			_show_game_screen()
		"bot_difficulty":
			_show_bot_difficulty()
		"bot_side":
			_show_bot_side_selection(current_bot_level)
		"two_type":
			_show_two_player_type()
		"lobby":
			_show_network_lobby(network_mode)
		_:
			set_process(true)
	set_process_input(true)
	_show_main_menu()

func _settings_background() -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen_root.add_child(bg)
	screen_root.move_child(bg, 0)

func _settings_card_box(title_text: String) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_left = 24
	center.offset_right = -24
	center.offset_top = 72
	center.offset_bottom = -90
	screen_root.add_child(center)

	var box := VBoxContainer.new()
	var available_width: float = maxf(260.0, get_viewport_rect().size.x - 48.0)
	box.custom_minimum_size = Vector2(minf(320.0, available_width), 0)
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)

	var title := Label.new()
	title.text = title_text
	title.custom_minimum_size = Vector2(0, 54)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.clip_text = true
	title.add_theme_color_override("font_color", TEXT)
	title.add_theme_color_override("font_outline_color", Color("ffffff66"))
	title.add_theme_constant_override("outline_size", 5)
	title.add_theme_font_size_override("font_size", 27)
	box.add_child(title)
	return box

func _show_settings_screen() -> void:
	current_screen = "settings"
	_clear_screen()
	title_label.visible = false
	gear_button.visible = false
	_settings_background()
	_add_back_button(t("back"), _settings_back_to_previous)
	var box := _settings_card_box(t("settings_title"))

	var lang := _button_style(BLUE, BLUE_HOVER, BLUE_PRESS)
	lang.text = t("language")
	lang.custom_minimum_size = Vector2(0, 58)
	box.add_child(lang)
	lang.pressed.connect(func() -> void: _open_language.call_deferred())

	var gap1 := Control.new()
	gap1.custom_minimum_size.y = 18
	box.add_child(gap1)

	var fx_label := Label.new()
	fx_label.text = "ЗВУК ЭФФЕКТОВ" if language == "ru" else "EFFECTS VOLUME"
	fx_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fx_label.add_theme_color_override("font_color", Color("3d2b1f"))
	fx_label.add_theme_font_size_override("font_size", 27)
	box.add_child(fx_label)

	var gap_fx := Control.new()
	gap_fx.custom_minimum_size.y = 14
	box.add_child(gap_fx)

	var fx_row := HBoxContainer.new()
	fx_row.add_theme_constant_override("separation", 12)
	fx_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fx_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(fx_row)

	var fx_slider := HSlider.new()
	fx_slider.min_value = 0.0
	fx_slider.max_value = 1.0
	fx_slider.step = 0.01
	fx_slider.value = effects_volume
	fx_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fx_slider.custom_minimum_size = Vector2(220, 34)
	fx_row.add_child(fx_slider)

	var fx_value := Label.new()
	fx_value.custom_minimum_size = Vector2(52, 0)
	fx_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fx_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fx_value.add_theme_color_override("font_color", Color("3d2b1f"))
	fx_value.add_theme_font_size_override("font_size", 17)
	fx_value.text = "%d%%" % int(round(effects_volume * 100.0))
	fx_row.add_child(fx_value)

	fx_slider.value_changed.connect(func(v: float) -> void:
		effects_volume = clampf(v, 0.0, 1.0)
		fx_value.text = "%d%%" % int(round(effects_volume * 100.0))
		_save_settings()
	)

	var gap2 := Control.new()
	gap2.custom_minimum_size.y = 28
	box.add_child(gap2)

	var music_label := Label.new()
	music_label.text = "МУЗЫКА" if language == "ru" else "MUSIC VOLUME"
	music_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	music_label.add_theme_color_override("font_color", Color("3d2b1f"))
	music_label.add_theme_font_size_override("font_size", 27)
	box.add_child(music_label)

	var gap_music := Control.new()
	gap_music.custom_minimum_size.y = 14
	box.add_child(gap_music)

	var music_row := HBoxContainer.new()
	music_row.add_theme_constant_override("separation", 12)
	music_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	music_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(music_row)

	var music_slider := HSlider.new()
	music_slider.min_value = 0.0
	music_slider.max_value = 1.0
	music_slider.step = 0.01
	music_slider.value = music_volume
	music_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	music_slider.custom_minimum_size = Vector2(220, 34)
	music_row.add_child(music_slider)

	var music_value := Label.new()
	music_value.custom_minimum_size = Vector2(52, 0)
	music_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	music_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	music_value.add_theme_color_override("font_color", Color("3d2b1f"))
	music_value.add_theme_font_size_override("font_size", 17)
	music_value.text = "%d%%" % int(round(music_volume * 100.0))
	music_row.add_child(music_value)

	music_slider.value_changed.connect(func(v: float) -> void:
		music_volume = clampf(v, 0.0, 1.0)
		music_value.text = "%d%%" % int(round(music_volume * 100.0))
		_apply_music_volume()
		_save_settings()
	)

	var footer := Label.new()
	footer.text = "ChessTeam 2026"
	footer.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_top = -48
	footer.offset_bottom = -16
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_color_override("font_color", MUTED)
	footer.add_theme_font_size_override("font_size", 15)
	screen_root.add_child(footer)

func _open_settings() -> void:
	settings_return_screen = current_screen
	_close_overlay()
	_show_settings_screen()

func _open_language() -> void:
	current_screen = "language"
	_clear_screen()
	title_label.visible = false
	gear_button.visible = false
	_settings_background()
	_add_back_button(t("back"), _show_settings_screen)
	var box := _settings_card_box(t("choose_language"))

	var ru := _button_style(BLUE, BLUE_HOVER, BLUE_PRESS)
	ru.text = t("russian")
	ru.custom_minimum_size = Vector2(0, 58)
	box.add_child(ru)
	ru.pressed.connect(func() -> void: _set_language.call_deferred("ru"))

	var en := _button_style(BLUE, BLUE_HOVER, BLUE_PRESS)
	en.text = t("english")
	en.custom_minimum_size = Vector2(0, 58)
	box.add_child(en)
	en.pressed.connect(func() -> void: _set_language.call_deferred("en"))

	var footer := Label.new()
	footer.text = "ChessTeam 2026"
	footer.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_top = -48
	footer.offset_bottom = -16
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_color_override("font_color", MUTED)
	footer.add_theme_font_size_override("font_size", 15)
	screen_root.add_child(footer)

func _set_language(new_language: String) -> void:
	language = "en" if new_language == "en" else "ru"
	GameNet.set_language(language)
	_save_settings()
	if current_screen == "language":
		_show_settings_screen.call_deferred()
		return
	title_label.visible = true
	gear_button.visible = true
	match current_screen:
		"menu": _show_main_menu()
		"bot_difficulty": _show_bot_difficulty()
		"bot_side": _show_bot_side_selection(current_bot_level)
		"two_type": _show_two_player_type()
		"lobby": _show_network_lobby(network_mode)
		"game": _show_game_screen()
		_: _show_main_menu()

func _toast(text_value: String) -> void:
	toast.text = text_value
	toast.visible = true
	var timer := get_tree().create_timer(2.2)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(toast):
			toast.visible = false
	)

func _exit_tree() -> void:
	_stop_bot_worker()
