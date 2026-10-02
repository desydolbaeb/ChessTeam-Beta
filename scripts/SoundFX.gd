extends Node

const SOUND_PATHS: Dictionary = {
	"move": "res://assets/sounds/move.wav",
	"capture": "res://assets/sounds/capture.wav",
	"castle": "res://assets/sounds/castle.wav",
	"check": "res://assets/sounds/check.wav",
	"mate": "res://assets/sounds/mate.wav",
	"draw": "res://assets/sounds/draw.wav",
	"promotion": "res://assets/sounds/promotion.wav",
	"ui_click": "res://assets/sounds/ui_click.wav",
	"undo": "res://assets/sounds/undo.wav"
}

var players: Array[AudioStreamPlayer] = []
var streams: Dictionary = {}

func _ready() -> void:
	for effect_name_variant: Variant in SOUND_PATHS.keys():
		var effect_name: String = str(effect_name_variant)
		var path: String = str(SOUND_PATHS[effect_name])
		var stream: AudioStream = load(path) as AudioStream
		if stream != null:
			streams[effect_name] = stream

	for _i: int in range(8):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.bus = "Master"
		player.volume_db = -0.5
		add_child(player)
		players.append(player)

func play(effect_name: String, volume_db: float = -0.5) -> void:
	if not streams.has(effect_name) or players.is_empty():
		return
	var selected: AudioStreamPlayer = players[0]
	for player: AudioStreamPlayer in players:
		if not player.playing:
			selected = player
			break
	selected.stream = streams[effect_name] as AudioStream
	selected.volume_db = volume_db
	selected.play()

func stop_all() -> void:
	for player: AudioStreamPlayer in players:
		player.stop()
