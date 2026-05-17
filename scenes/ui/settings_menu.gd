extends CanvasLayer

signal close_requested

@onready var music_on_button: Button = %MusicOnButton
@onready var music_off_button: Button = %MusicOffButton
@onready var sfx_on_button: Button = %SfxOnButton
@onready var sfx_off_button: Button = %SfxOffButton
@onready var music_volume_slider: HSlider = %MusicVolumeSlider
@onready var sfx_volume_slider: HSlider = %SfxVolumeSlider
@onready var master_volume_slider: HSlider = %MasterVolumeSlider
@onready var music_volume_value: Label = %MusicVolumeValue
@onready var sfx_volume_value: Label = %SfxVolumeValue
@onready var master_volume_value: Label = %MasterVolumeValue
@onready var keyboard_button: CheckButton = %KeyboardButton
@onready var joystick_button: CheckButton = %JoystickButton
@onready var vibration_button: CheckBox = %VibrationButton
@onready var apply_button: Button = %ApplyButton
@onready var restore_button: Button = %RestoreButton
@onready var back_button: Button = %BackButton

var _audio_manager: Node
var _settings := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_audio_manager = get_node_or_null("/root/AudioManager")
	_settings = _get_audio_settings()
	_apply_settings_to_controls()
	_connect_controls()
	_configure_focus()


func focus_first() -> void:
	apply_button.grab_focus()


func _connect_controls() -> void:
	music_on_button.pressed.connect(_set_music_enabled.bind(true))
	music_off_button.pressed.connect(_set_music_enabled.bind(false))
	sfx_on_button.pressed.connect(_set_sfx_enabled.bind(true))
	sfx_off_button.pressed.connect(_set_sfx_enabled.bind(false))
	music_volume_slider.value_changed.connect(_set_music_volume)
	sfx_volume_slider.value_changed.connect(_set_sfx_volume)
	master_volume_slider.value_changed.connect(_set_master_volume)
	keyboard_button.pressed.connect(_set_input_mode.bind("keyboard"))
	joystick_button.pressed.connect(_set_input_mode.bind("joystick"))
	apply_button.pressed.connect(_on_apply_pressed)
	restore_button.pressed.connect(_on_restore_pressed)
	back_button.pressed.connect(_on_back_pressed)


func _get_audio_settings() -> Dictionary:
	if _audio_manager != null and _audio_manager.has_method("get_settings"):
		return _audio_manager.call("get_settings").duplicate(true)

	return {
		"master_volume": 0.75,
		"music_volume": 0.7,
		"sfx_volume": 0.8,
		"music_enabled": true,
		"sfx_enabled": true,
	}


func _apply_settings_to_controls() -> void:
	var music_enabled := bool(_settings.get("music_enabled", true))
	var sfx_enabled := bool(_settings.get("sfx_enabled", true))
	var music_volume := float(_settings.get("music_volume", 0.7))
	var sfx_volume := float(_settings.get("sfx_volume", 0.8))
	var master_volume := float(_settings.get("master_volume", 0.75))

	music_on_button.button_pressed = music_enabled
	music_off_button.button_pressed = not music_enabled
	sfx_on_button.button_pressed = sfx_enabled
	sfx_off_button.button_pressed = not sfx_enabled
	music_volume_slider.value = music_volume * 100.0
	sfx_volume_slider.value = sfx_volume * 100.0
	master_volume_slider.value = master_volume * 100.0
	keyboard_button.button_pressed = true
	joystick_button.button_pressed = false
	vibration_button.disabled = true
	vibration_button.button_pressed = false
	_refresh_volume_labels()


func _set_music_enabled(enabled: bool) -> void:
	_settings["music_enabled"] = enabled
	music_on_button.button_pressed = enabled
	music_off_button.button_pressed = not enabled


func _set_sfx_enabled(enabled: bool) -> void:
	_settings["sfx_enabled"] = enabled
	sfx_on_button.button_pressed = enabled
	sfx_off_button.button_pressed = not enabled


func _set_music_volume(value: float) -> void:
	_settings["music_volume"] = clampf(value / 100.0, 0.0, 1.0)
	_refresh_volume_labels()


func _set_sfx_volume(value: float) -> void:
	_settings["sfx_volume"] = clampf(value / 100.0, 0.0, 1.0)
	_refresh_volume_labels()


func _set_master_volume(value: float) -> void:
	_settings["master_volume"] = clampf(value / 100.0, 0.0, 1.0)
	_refresh_volume_labels()


func _set_input_mode(mode: String) -> void:
	var joystick := mode == "joystick"
	keyboard_button.button_pressed = not joystick
	joystick_button.button_pressed = joystick
	vibration_button.disabled = not joystick
	if not joystick:
		vibration_button.button_pressed = false


func _refresh_volume_labels() -> void:
	music_volume_value.text = "%d%%" % roundi(music_volume_slider.value)
	sfx_volume_value.text = "%d%%" % roundi(sfx_volume_slider.value)
	master_volume_value.text = "%d%%" % roundi(master_volume_slider.value)


func _on_apply_pressed() -> void:
	if _audio_manager != null and _audio_manager.has_method("apply_settings"):
		_audio_manager.call("apply_settings", _settings, true)


func _on_restore_pressed() -> void:
	if _audio_manager != null and _audio_manager.has_method("restore_defaults"):
		_audio_manager.call("restore_defaults", false)
	_settings = _get_audio_settings()
	_apply_settings_to_controls()


func _on_back_pressed() -> void:
	close_requested.emit()
	hide()


func _configure_focus() -> void:
	for control in [
		music_on_button,
		music_off_button,
		sfx_on_button,
		sfx_off_button,
		music_volume_slider,
		sfx_volume_slider,
		master_volume_slider,
		keyboard_button,
		joystick_button,
		apply_button,
		restore_button,
		back_button,
	]:
		control.focus_mode = Control.FOCUS_ALL
