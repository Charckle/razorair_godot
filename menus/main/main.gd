extends Control

# ── Colours needed at runtime for dynamic state changes ───────────────────────
const C_SIDEBAR := Color(0.082, 0.086, 0.110)
const C_CARD    := Color(0.137, 0.157, 0.196)
const C_ACCENT  := Color(0.122, 0.435, 0.933)
const C_TEXT2   := Color(0.545, 0.580, 0.620)
const C_OK      := Color(0.337, 0.784, 0.337)
const C_ERR     := Color(0.902, 0.298, 0.298)

# ── Scene node references (defined in Main.tscn) ──────────────────────────────
@onready var _content_holder: Control      = %ContentHolder
@onready var _status_lbl:     Label        = %StatusLabel
@onready var _login_dialog:   AcceptDialog = %LoginDialog
@onready var _btn_hvac:       Button       = %BtnHVAC
@onready var _btn_admin:      Button       = %BtnAdmin

# ── Runtime state ─────────────────────────────────────────────────────────────
var _nav_btns:   Dictionary = {}   # key → Button
var _scenes:     Dictionary = {}   # key → Control instance
var _active_key: String     = ""


func _ready() -> void:
	if ApiClient.display_mode == "portrait":
		get_tree().change_scene_to_file("res://menus/mobile/MobileMain.tscn")
		return

	_nav_btns = {"hvac": _btn_hvac, "admin": _btn_admin}

	# Nav button signals
	_btn_hvac.pressed.connect(func():  _switch_to("hvac"))
	_btn_admin.pressed.connect(func(): _switch_to("admin"))

	_login_dialog.ok_button_text = "Open Settings"
	_login_dialog.confirmed.connect(func(): _switch_to("admin"))
	ApiClient.login_success.connect(_on_login_success)
	ApiClient.login_failed.connect(_on_login_failed)
	ApiClient.hvac_data_received.connect(func(_d: Dictionary):
		_set_status("Updated  " + Time.get_time_string_from_system(), C_OK))
	_load_scenes()
	_do_startup_login()


# ── Scene management ──────────────────────────────────────────────────────────

func _load_scenes() -> void:
	_add_scene("hvac",  "res://menus/hvac/HVAC.tscn")
	_add_scene("admin", "res://menus/admin/Admin.tscn")
	_switch_to("hvac")


func _add_scene(key: String, path: String) -> void:
	var inst: Control = (load(path) as PackedScene).instantiate()
	inst.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inst.hide()
	_content_holder.add_child(inst)
	_scenes[key] = inst


func _switch_to(key: String) -> void:
	if _active_key == key:
		return
	if _active_key != "" and _scenes.has(_active_key):
		_scenes[_active_key].hide()
	_active_key = key
	if _scenes.has(key):
		_scenes[key].show()
	_refresh_nav_styles()


func _refresh_nav_styles() -> void:
	for key in _nav_btns:
		_nav_btns[key].add_theme_stylebox_override("normal",
			_nav_btn_style(key == _active_key))


func _nav_btn_style(selected: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = C_CARD if selected else C_SIDEBAR
	s.set_border_width_all(0)
	if selected:
		s.set_border_width(SIDE_LEFT, 4)
		s.border_color = C_ACCENT
	return s




# ── Login flow ────────────────────────────────────────────────────────────────

func _do_startup_login() -> void:
	_set_status("Connecting…", C_TEXT2)
	ApiClient.do_login()


func _on_login_success() -> void:
	_set_status("Connected", C_OK)


func _on_login_failed(message: String) -> void:
	_set_status("Not connected", C_ERR)
	_login_dialog.dialog_text = (
		message + "\n\nPlease open Settings and enter the\nbackend URL and login credentials."
	)
	_login_dialog.popup_centered(Vector2(480, 220))


func _set_status(text: String, color: Color) -> void:
	_status_lbl.text = text
	_status_lbl.add_theme_color_override("font_color", color)
