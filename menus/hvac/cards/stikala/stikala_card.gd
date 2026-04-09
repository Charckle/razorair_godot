extends PanelContainer

const C_ON       := Color(0.157, 0.459, 0.196)
const C_ON_BRD   := Color(0.204, 0.596, 0.255)
const C_OFF      := Color(0.118, 0.137, 0.173)
const C_OFF_BRD  := Color(0.196, 0.220, 0.259)
const C_UNREACH  := Color(0.102, 0.114, 0.141)
const C_MUTED    := Color(0.545, 0.580, 0.620)
const C_TEXT     := Color(0.902, 0.929, 0.953)

@onready var _timer:      Timer         = %PlugsTimer
@onready var _plugs_list: VBoxContainer = %PlugsList
@onready var _status_lbl: Label         = %StatusLabel

var _plugs: Array = []


func _ready() -> void:
	_timer.timeout.connect(_do_poll)
	visibility_changed.connect(_on_visibility_changed)
	ApiClient.plugs_status_received.connect(_on_plugs_data)
	ApiClient.plug_set_done.connect(_on_set_done)
	ApiClient.login_success.connect(_do_poll)


func _on_visibility_changed() -> void:
	if visible:
		_do_poll()
		_timer.start()
	else:
		_timer.stop()


func _do_poll() -> void:
	ApiClient.get_shelly_plugs()


func _on_plugs_data(plugs: Array) -> void:
	_plugs = plugs
	_rebuild()
	_status_lbl.text = ""


func _rebuild() -> void:
	for child in _plugs_list.get_children():
		child.queue_free()

	if _plugs.is_empty():
		_plugs_list.add_child(_make_empty_label("Ni vtičnic"))
		return

	for plug in _plugs:
		_plugs_list.add_child(_make_plug_btn(plug))


func _make_plug_btn(plug: Dictionary) -> Button:
	var index:  int    = plug.get("index", -1)
	var name_s: String = plug.get("name", "Plug %d" % index)
	var output          = plug.get("output")      # true / false / null

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 64)
	btn.size_flags_horizontal = Control.SIZE_FILL | Control.SIZE_EXPAND
	btn.clip_text = true

	var sb := StyleBoxFlat.new()
	sb.corner_radius_top_left    = 8
	sb.corner_radius_top_right   = 8
	sb.corner_radius_bottom_right = 8
	sb.corner_radius_bottom_left  = 8
	sb.corner_detail = 5
	sb.set_border_width_all(1)

	if output == true:
		btn.text = "● " + name_s
		sb.bg_color     = C_ON
		sb.border_color = C_ON_BRD
		btn.add_theme_color_override("font_color", C_TEXT)
	elif output == false:
		btn.text = "○ " + name_s
		sb.bg_color     = C_OFF
		sb.border_color = C_OFF_BRD
		btn.add_theme_color_override("font_color", C_MUTED)
	else:
		btn.text = "? " + name_s
		sb.bg_color     = C_UNREACH
		sb.border_color = C_OFF_BRD
		btn.add_theme_color_override("font_color", C_MUTED)
		btn.disabled = true

	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_stylebox_override("normal",  sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_stylebox_override("focus",   StyleBoxEmpty.new())

	var hover_sb := sb.duplicate() as StyleBoxFlat
	hover_sb.bg_color = hover_sb.bg_color.lightened(0.12)
	btn.add_theme_stylebox_override("hover", hover_sb)

	if output != null:
		btn.pressed.connect(_on_plug_pressed.bind(index, output))

	return btn


func _make_empty_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", C_MUTED)
	lbl.add_theme_font_size_override("font_size", 14)
	return lbl


func _on_plug_pressed(index: int, current_output) -> void:
	var turn_on: bool = not bool(current_output)
	_status_lbl.text = "…"
	ApiClient.set_shelly_plug(index, turn_on)


func _on_set_done(success: bool) -> void:
	if success:
		_do_poll()
	else:
		_status_lbl.text = "Napaka"
		_status_lbl.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
