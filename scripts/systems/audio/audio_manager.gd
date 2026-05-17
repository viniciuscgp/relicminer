extends Node

signal settings_changed

const SETTINGS_PATH := "user://audio_settings.cfg"
const MASTER_BUS := "Master"
const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"

const DEFAULT_MASTER_VOLUME := 0.75
const DEFAULT_MUSIC_VOLUME := 0.7
const DEFAULT_SFX_VOLUME := 0.8
const DEFAULT_MUSIC_ENABLED := true
const DEFAULT_SFX_ENABLED := true
const DEFAULT_MAX_SFX_PLAYERS := 16

var master_volume := DEFAULT_MASTER_VOLUME
var music_volume := DEFAULT_MUSIC_VOLUME
var sfx_volume := DEFAULT_SFX_VOLUME
var music_enabled := DEFAULT_MUSIC_ENABLED
var sfx_enabled := DEFAULT_SFX_ENABLED
var max_sfx_players := DEFAULT_MAX_SFX_PLAYERS

var _music_player: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []


func _ready() -> void:
	_ensure_bus(MUSIC_BUS)
	_ensure_bus(SFX_BUS)
	_create_music_player()
	load_settings()
	_apply_to_audio_server()


func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	_apply_to_audio_server()


func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	_apply_to_audio_server()


func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	_apply_to_audio_server()


func set_music_enabled(value: bool) -> void:
	music_enabled = value
	_apply_to_audio_server()


func set_sfx_enabled(value: bool) -> void:
	sfx_enabled = value
	_apply_to_audio_server()


func play_music(stream: AudioStream, restart := true) -> void:
	if stream == null:
		return
	if _music_player == null:
		_create_music_player()
	if _music_player.stream == stream and _music_player.playing and not restart:
		return

	_music_player.stop()
	_music_player.stream = stream
	_music_player.play()


func stop_music() -> void:
	if _music_player != null:
		_music_player.stop()


func play_sfx(stream: AudioStream, volume_scale := 1.0, pitch_scale := 1.0) -> AudioStreamPlayer:
	if stream == null or not sfx_enabled:
		return null

	var player := _get_available_sfx_player()
	player.stream = stream
	player.volume_db = _linear_to_db(maxf(volume_scale, 0.0))
	player.pitch_scale = maxf(pitch_scale, 0.01)
	player.play()
	return player


func apply_settings(settings: Dictionary, save := true) -> void:
	master_volume = clampf(float(settings.get("master_volume", master_volume)), 0.0, 1.0)
	music_volume = clampf(float(settings.get("music_volume", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(settings.get("sfx_volume", sfx_volume)), 0.0, 1.0)
	music_enabled = bool(settings.get("music_enabled", music_enabled))
	sfx_enabled = bool(settings.get("sfx_enabled", sfx_enabled))
	_apply_to_audio_server()

	if save:
		save_settings()


func get_settings() -> Dictionary:
	return {
		"master_volume": master_volume,
		"music_volume": music_volume,
		"sfx_volume": sfx_volume,
		"music_enabled": music_enabled,
		"sfx_enabled": sfx_enabled,
	}


func restore_defaults(save := true) -> void:
	apply_settings({
		"master_volume": DEFAULT_MASTER_VOLUME,
		"music_volume": DEFAULT_MUSIC_VOLUME,
		"sfx_volume": DEFAULT_SFX_VOLUME,
		"music_enabled": DEFAULT_MUSIC_ENABLED,
		"sfx_enabled": DEFAULT_SFX_ENABLED,
	}, save)


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.set_value("audio", "music_enabled", music_enabled)
	config.set_value("audio", "sfx_enabled", sfx_enabled)
	config.save(SETTINGS_PATH)


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return

	master_volume = clampf(float(config.get_value("audio", "master_volume", DEFAULT_MASTER_VOLUME)), 0.0, 1.0)
	music_volume = clampf(float(config.get_value("audio", "music_volume", DEFAULT_MUSIC_VOLUME)), 0.0, 1.0)
	sfx_volume = clampf(float(config.get_value("audio", "sfx_volume", DEFAULT_SFX_VOLUME)), 0.0, 1.0)
	music_enabled = bool(config.get_value("audio", "music_enabled", DEFAULT_MUSIC_ENABLED))
	sfx_enabled = bool(config.get_value("audio", "sfx_enabled", DEFAULT_SFX_ENABLED))


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return

	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, MASTER_BUS)


func _create_music_player() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	_music_player.bus = MUSIC_BUS
	add_child(_music_player)


func _get_available_sfx_player() -> AudioStreamPlayer:
	for player in _sfx_players:
		if not player.playing:
			return player

	if _sfx_players.size() < max_sfx_players:
		return _create_sfx_player()

	var player: AudioStreamPlayer = _sfx_players.pop_front()
	player.stop()
	_sfx_players.append(player)
	return player


func _create_sfx_player() -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = "SfxPlayer"
	player.bus = SFX_BUS
	add_child(player)
	_sfx_players.append(player)
	return player


func _apply_to_audio_server() -> void:
	_set_bus_volume(MASTER_BUS, master_volume, true)
	_set_bus_volume(MUSIC_BUS, music_volume, music_enabled)
	_set_bus_volume(SFX_BUS, sfx_volume, sfx_enabled)
	settings_changed.emit()


func _set_bus_volume(bus_name: String, volume: float, enabled: bool) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index == -1:
		return

	AudioServer.set_bus_volume_db(bus_index, _linear_to_db(clampf(volume, 0.0, 1.0)))
	AudioServer.set_bus_mute(bus_index, not enabled)


func _linear_to_db(value: float) -> float:
	if value <= 0.001:
		return -80.0
	return linear_to_db(value)
