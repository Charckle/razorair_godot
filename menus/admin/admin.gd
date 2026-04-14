extends Control

# ── Colours needed at runtime ─────────────────────────────────────────────────
const C_TEXT2 := Color(0.545, 0.580, 0.620)
const C_OK    := Color(0.337, 0.784, 0.337)
const C_ERR   := Color(0.902, 0.298, 0.298)

# ── Node references (defined in Admin.tscn) ───────────────────────────────────
@onready var _url_edit:          LineEdit    = %UrlEdit
@onready var _user_edit:         LineEdit    = %UserEdit
@onready var _pass_edit:         LineEdit    = %PassEdit
@onready var _save_btn:          Button      = %SaveBtn
@onready var _reconnect_btn:     Button      = %ReconnectBtn
@onready var _status_lbl:        Label       = %StatusLabel
@onready var _show_pass_btn:     Button      = %ShowPassBtn
@onready var _vent_style_check:  CheckButton = %VentStyleCheck
@onready var _portrait_check:    CheckButton = %PortraitModeCheck


func _ready() -> void:
	_save_btn.pressed.connect(_on_save_pressed)
	_reconnect_btn.pressed.connect(_on_reconnect_pressed)
	_show_pass_btn.pressed.connect(_on_show_pass_toggled)

	# Use separate functions so signal parameter types match exactly —
	# login_success emits nothing; login_failed emits (message: String).
	ApiClient.login_success.connect(_on_login_success)
	ApiClient.login_failed.connect(_on_login_failed)

	_populate_fields()


# ── Populate / persist ────────────────────────────────────────────────────────

func _populate_fields() -> void:
	_url_edit.text  = ApiClient.base_url
	_user_edit.text = ApiClient.username
	_pass_edit.text = ApiClient.password
	_vent_style_check.button_pressed = ApiClient.vent_control_style == "stepper"
	_portrait_check.button_pressed   = ApiClient.display_mode == "portrait"


func _write_fields_to_api_client() -> void:
	ApiClient.base_url           = _url_edit.text.strip_edges()
	ApiClient.username           = _user_edit.text.strip_edges()
	ApiClient.password           = _pass_edit.text
	ApiClient.vent_control_style = "stepper" if _vent_style_check.button_pressed else "dropdown"
	ApiClient.display_mode       = "portrait" if _portrait_check.button_pressed else "landscape"
	ApiClient.save_config()


# ── Signal handlers ───────────────────────────────────────────────────────────

func _on_save_pressed() -> void:
	_write_fields_to_api_client()
	_set_status("Settings saved.", C_OK)


func _on_reconnect_pressed() -> void:
	_write_fields_to_api_client()
	_set_status("Connecting…", C_TEXT2)
	_save_btn.disabled      = true
	_reconnect_btn.disabled = true
	ApiClient.do_login()


func _on_login_success() -> void:
	_save_btn.disabled      = false
	_reconnect_btn.disabled = false
	_set_status("Connected successfully  ✓", C_OK)


func _on_login_failed(message: String) -> void:
	_save_btn.disabled      = false
	_reconnect_btn.disabled = false
	_set_status("Login failed: " + message, C_ERR)


func _on_show_pass_toggled() -> void:
	_pass_edit.secret = not _pass_edit.secret
	_show_pass_btn.text = "🙈" if not _pass_edit.secret else "👁"


func _set_status(text: String, color: Color) -> void:
	_status_lbl.text = text
	_status_lbl.add_theme_color_override("font_color", color)
