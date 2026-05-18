extends CanvasLayer

signal close_requested

@onready var title_label: Label = %Title
@onready var audio_title: Label = %AudioTitle
@onready var music_label: Label = %MusicLabel
@onready var music_on_button: Button = %MusicOnButton
@onready var music_off_button: Button = %MusicOffButton
@onready var sfx_label: Label = %SfxLabel
@onready var sfx_on_button: Button = %SfxOnButton
@onready var sfx_off_button: Button = %SfxOffButton
@onready var music_volume_label: Label = %MusicVolumeLabel
@onready var music_volume_slider: HSlider = %MusicVolumeSlider
@onready var sfx_volume_label: Label = %SfxVolumeLabel
@onready var sfx_volume_slider: HSlider = %SfxVolumeSlider
@onready var master_volume_label: Label = %MasterVolumeLabel
@onready var master_volume_slider: HSlider = %MasterVolumeSlider
@onready var music_volume_value: Label = %MusicVolumeValue
@onready var sfx_volume_value: Label = %SfxVolumeValue
@onready var master_volume_value: Label = %MasterVolumeValue
@onready var input_title: Label = %InputTitle
@onready var language_label: Label = %LanguageLabel
@onready var language_option: OptionButton = %LanguageOption
@onready var keyboard_button: CheckButton = %KeyboardButton
@onready var joystick_button: CheckButton = %JoystickButton
@onready var vibration_button: CheckBox = %VibrationButton
@onready var apply_button: Button = %ApplyButton
@onready var restore_button: Button = %RestoreButton
@onready var back_button: Button = %BackButton

var _audio_manager: Node
var _localization_manager: Node
var _settings := {}
var _language_codes: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_audio_manager = get_node_or_null("/root/AudioManager")
	_localization_manager = get_node_or_null("/root/LocalizationManager")
	if _localization_manager != null and _localization_manager.has_signal("language_changed"):
		_localization_manager.connect("language_changed", _on_language_changed)
	_settings = _get_audio_settings()
	_populate_language_options()
	_apply_settings_to_controls()
	_connect_controls()
	_configure_focus()
	_apply_localization()


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
	vibration_button.toggled.connect(_set_vibration_enabled)
	language_option.item_selected.connect(_set_language_by_index)
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
		"input_mode": "keyboard",
		"vibration_enabled": false,
		"language": "en",
	}


func _apply_settings_to_controls() -> void:
	var music_enabled := bool(_settings.get("music_enabled", true))
	var sfx_enabled := bool(_settings.get("sfx_enabled", true))
	var music_volume := float(_settings.get("music_volume", 0.7))
	var sfx_volume := float(_settings.get("sfx_volume", 0.8))
	var master_volume := float(_settings.get("master_volume", 0.75))
	var input_mode := str(_settings.get("input_mode", "keyboard"))
	var joystick := input_mode == "joystick"
	var vibration_enabled := bool(_settings.get("vibration_enabled", false))
	var language := str(_settings.get("language", _get_current_language()))

	music_on_button.button_pressed = music_enabled
	music_off_button.button_pressed = not music_enabled
	sfx_on_button.button_pressed = sfx_enabled
	sfx_off_button.button_pressed = not sfx_enabled
	music_volume_slider.value = music_volume * 100.0
	sfx_volume_slider.value = sfx_volume * 100.0
	master_volume_slider.value = master_volume * 100.0
	keyboard_button.button_pressed = not joystick
	joystick_button.button_pressed = joystick
	vibration_button.disabled = not joystick
	vibration_button.button_pressed = joystick and vibration_enabled
	_select_language(language)
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
	_settings["input_mode"] = mode
	keyboard_button.button_pressed = not joystick
	joystick_button.button_pressed = joystick
	vibration_button.disabled = not joystick
	if not joystick:
		vibration_button.button_pressed = false
		_settings["vibration_enabled"] = false


func _set_vibration_enabled(enabled: bool) -> void:
	_settings["vibration_enabled"] = enabled and not vibration_button.disabled


func _set_language_by_index(index: int) -> void:
	if index < 0 or index >= _language_codes.size():
		return

	var language := _language_codes[index]
	_settings["language"] = language
	if _localization_manager != null and _localization_manager.has_method("set_language"):
		_localization_manager.call("set_language", language, false)


func _refresh_volume_labels() -> void:
	music_volume_value.text = "%d%%" % roundi(music_volume_slider.value)
	sfx_volume_value.text = "%d%%" % roundi(sfx_volume_slider.value)
	master_volume_value.text = "%d%%" % roundi(master_volume_slider.value)


func _on_apply_pressed() -> void:
	if _audio_manager != null and _audio_manager.has_method("apply_settings"):
		_audio_manager.call("apply_settings", _settings, true)
	if _localization_manager != null and _localization_manager.has_method("set_language"):
		_localization_manager.call("set_language", str(_settings.get("language", "en")), false)


func _on_restore_pressed() -> void:
	if _audio_manager != null and _audio_manager.has_method("restore_defaults"):
		_audio_manager.call("restore_defaults", false)
	_settings = _get_audio_settings()
	_apply_settings_to_controls()
	if _localization_manager != null and _localization_manager.has_method("set_language"):
		_localization_manager.call("set_language", str(_settings.get("language", "en")), false)


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
		language_option,
		keyboard_button,
		joystick_button,
		vibration_button,
		apply_button,
		restore_button,
		back_button,
	]:
		control.focus_mode = Control.FOCUS_ALL


func _apply_localization() -> void:
	title_label.text = _text("ui.settings.title")
	audio_title.text = _text("ui.settings.audio")
	music_label.text = _text("ui.settings.music")
	music_on_button.text = _text("ui.settings.on")
	music_off_button.text = _text("ui.settings.off")
	sfx_label.text = _text("ui.settings.sfx")
	sfx_on_button.text = _text("ui.settings.on")
	sfx_off_button.text = _text("ui.settings.off")
	music_volume_label.text = _text("ui.settings.music_volume")
	sfx_volume_label.text = _text("ui.settings.sfx_volume")
	master_volume_label.text = _text("ui.settings.master_volume")
	input_title.text = _text("ui.settings.input")
	language_label.text = _text("ui.settings.language")
	keyboard_button.text = _text("ui.settings.keyboard_mouse")
	joystick_button.text = _text("ui.settings.joystick")
	vibration_button.text = _text("ui.settings.vibration")
	apply_button.text = _text("ui.settings.apply")
	restore_button.text = _text("ui.settings.restore")
	back_button.text = _text("ui.settings.back")
	var selected_language := str(_settings.get("language", _get_current_language()))
	_populate_language_options()
	_select_language(selected_language)


func _populate_language_options() -> void:
	if language_option == null:
		return

	_language_codes.clear()
	language_option.clear()
	var options: Array = []
	if _localization_manager != null and _localization_manager.has_method("get_language_options"):
		options = _localization_manager.call("get_language_options")
	else:
		options = [
			{"code": "en", "label_key": "ui.settings.language.english"},
			{"code": "pt", "label_key": "ui.settings.language.portuguese"},
		]

	for option in options:
		var code := str(option.get("code", "en"))
		var label_key := str(option.get("label_key", "ui.settings.language.english"))
		_language_codes.append(code)
		language_option.add_item(_text(label_key))


func _select_language(language: String) -> void:
	var index := _language_codes.find(language)
	if index == -1:
		index = _language_codes.find("en")
	if index != -1:
		language_option.select(index)


func _on_language_changed(_language: String) -> void:
	_settings["language"] = _get_current_language()
	_apply_localization()


func _get_current_language() -> String:
	if _localization_manager != null and _localization_manager.has_method("get_language"):
		return str(_localization_manager.call("get_language"))
	return "en"


func _text(key: String, args: Array = []) -> String:
	if _localization_manager != null and _localization_manager.has_method("text"):
		return str(_localization_manager.call("text", key, args))
	return key
