extends Control

const C_TEXT2 := Color(0.545, 0.580, 0.620)
const C_OK    := Color(0.337, 0.784, 0.337)
const C_ERR   := Color(0.902, 0.298, 0.298)

@onready var _status_lbl:       Label          = %StatusLabel
@onready var _settings_btn:     Button         = %SettingsBtn
@onready var _settings_overlay: PanelContainer = %SettingsOverlay
@onready var _done_btn:         Button         = %DoneBtn


func _ready() -> void:
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_PORTRAIT)
	get_tree().root.content_scale_size = Vector2i(480, 854)

	_settings_btn.pressed.connect(_open_settings)
	_done_btn.pressed.connect(_close_settings)

	ApiClient.login_success.connect(_on_login_success)
	ApiClient.login_failed.connect(_on_login_failed)

	_set_status("Connecting…", C_TEXT2)
	ApiClient.do_login()


func _open_settings() -> void:
	_settings_overlay.show()


func _close_settings() -> void:
	_settings_overlay.hide()


func _on_login_success() -> void:
	_set_status("Connected", C_OK)
	_close_settings()


func _on_login_failed(_message: String) -> void:
	_set_status("Not connected — tap ⚙ to configure", C_ERR)
	_open_settings()


func _set_status(text: String, color: Color) -> void:
	_status_lbl.text = text
	_status_lbl.add_theme_color_override("font_color", color)
