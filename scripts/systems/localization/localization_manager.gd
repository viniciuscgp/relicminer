extends Node

signal language_changed(language: String)

const DEFAULT_LANGUAGE := "en"
const SUPPORTED_LANGUAGES := ["en", "pt"]
const TRANSLATIONS_PATH := "res://resources/localization/translations.json"

var current_language := DEFAULT_LANGUAGE
var _translations: Dictionary = {}


func _ready() -> void:
	_load_translations()
	var settings := _get_saved_settings()
	set_language(str(settings.get("language", DEFAULT_LANGUAGE)), false)


func set_language(language: String, save := true) -> void:
	if not SUPPORTED_LANGUAGES.has(language):
		language = DEFAULT_LANGUAGE

	if current_language == language:
		return

	current_language = language
	TranslationServer.set_locale(language)
	if save:
		_save_language(language)
	language_changed.emit(language)


func get_language() -> String:
	return current_language


func get_language_options() -> Array[Dictionary]:
	return [
		{"code": "en", "label_key": "ui.settings.language.english"},
		{"code": "pt", "label_key": "ui.settings.language.portuguese"},
	]


func text(key: String, args: Array = []) -> String:
	var localized := key
	if _translations.has(key):
		var entry: Dictionary = _translations[key]
		localized = str(entry.get(current_language, entry.get(DEFAULT_LANGUAGE, key)))

	if args.is_empty():
		return localized
	return localized % args


func item_name(item: Resource, fallback := "Item") -> String:
	var item_id := _get_item_id(item)
	if item_id.is_empty():
		return fallback
	return text("item.%s.name" % item_id)


func item_description(item: Resource, fallback := "") -> String:
	var item_id := _get_item_id(item)
	if item_id.is_empty():
		return fallback
	return text("item.%s.description" % item_id)


func has_key(key: String) -> bool:
	return _translations.has(key)


func _load_translations() -> void:
	var file := FileAccess.open(TRANSLATIONS_PATH, FileAccess.READ)
	if file == null:
		push_warning("LocalizationManager: translations file not found: %s" % TRANSLATIONS_PATH)
		return

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_translations = parsed
	else:
		push_warning("LocalizationManager: translations file is invalid.")


func _get_saved_settings() -> Dictionary:
	var audio_manager := get_node_or_null("/root/AudioManager")
	if audio_manager != null and audio_manager.has_method("get_settings"):
		return audio_manager.call("get_settings")
	return {}


func _save_language(language: String) -> void:
	var audio_manager := get_node_or_null("/root/AudioManager")
	if audio_manager == null or not audio_manager.has_method("get_settings") or not audio_manager.has_method("apply_settings"):
		return

	var settings: Dictionary = audio_manager.call("get_settings")
	settings["language"] = language
	audio_manager.call("apply_settings", settings, true)


func _get_item_id(item: Resource) -> String:
	if item == null:
		return ""
	return str(item.get("id"))
