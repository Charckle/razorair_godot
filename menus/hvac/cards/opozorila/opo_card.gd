extends PanelContainer

const C_TEXT    := Color(0.902, 0.929, 0.953)
const C_MUTED   := Color(0.545, 0.580, 0.620)
const C_WARN_HI := Color(1.0,   0.75,  0.2)
const C_WARN_LO := Color(0.5,   0.8,   1.0)
const C_SEP     := Color(0.196, 0.220, 0.259)

const BOOTSTRAP_COLORS := {
	"primary":   Color(0.208, 0.510, 0.965),
	"secondary": Color(0.416, 0.447, 0.482),
	"success":   Color(0.102, 0.557, 0.314),
	"danger":    Color(0.843, 0.176, 0.220),
	"warning":   Color(1.000, 0.757, 0.027),
	"info":      Color(0.055, 0.749, 0.882),
	"light":     Color(0.871, 0.882, 0.894),
	"dark":      Color(0.129, 0.157, 0.188),
	"brown":     Color(0.545, 0.271, 0.075),
	"lime":      Color(0.518, 0.800, 0.086),
	"amber":     Color(0.961, 0.620, 0.043),
	"rose":      Color(0.882, 0.114, 0.282),
	"violet":    Color(0.486, 0.227, 0.929),
	"emerald":   Color(0.063, 0.725, 0.506),
	"pink":      Color(0.925, 0.282, 0.600),
}

@onready var _timer:    Timer         = %OpoTimer
@onready var _opo_list: VBoxContainer = %OpoList

var _warnings:        Array = []
var _calendar_events: Array = []


func _ready() -> void:
	_timer.timeout.connect(_do_poll)
	visibility_changed.connect(_on_visibility_changed)
	ApiClient.weather_home_received.connect(_on_weather_data)
	ApiClient.calendar_events_received.connect(_on_calendar_data)
	ApiClient.login_success.connect(_do_poll)


func _on_visibility_changed() -> void:
	if visible:
		_do_poll()
		_timer.start()
	else:
		_timer.stop()


func _do_poll() -> void:
	ApiClient.get_weather_home()
	ApiClient.get_calendar_events()


func _on_weather_data(warnings: Array) -> void:
	_warnings = warnings
	_rebuild()


func _on_calendar_data(events: Array) -> void:
	_calendar_events = events
	_rebuild()


func _rebuild() -> void:
	for child in _opo_list.get_children():
		child.queue_free()

	if _warnings.is_empty() and _calendar_events.is_empty():
		_opo_list.add_child(_make_label("Ni opozoril", C_MUTED))
		return

	for w in _warnings:
		var msg: String = w.get("message", "")
		var color := C_WARN_HI if w.get("type", "") == "high" else C_WARN_LO
		_opo_list.add_child(_make_label("⚠  " + msg, color))

	if not _warnings.is_empty() and not _calendar_events.is_empty():
		var sep := ColorRect.new()
		sep.custom_minimum_size = Vector2(0, 1)
		sep.color = C_SEP
		_opo_list.add_child(sep)

	var expanded: Array = []
	for ev in _calendar_events:
		expanded += _expand(ev)
	expanded.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.display_date < b.display_date)

	for row in expanded:
		var prefix := _fmt_date(row.display_date)
		var ts = row.time_start
		if row.is_first and ts != null and ts != "":
			prefix += "  " + str(ts)
		var badge := ""
		if row.is_multiday:
			var sym := "→" if row.is_first else ("←" if row.is_last else "↔")
			badge = " " + sym + "(" + str(row.day_num) + "/" + str(row.total_days) + ")"
		var text = prefix + badge + "   " + row.title
		var col: Color = BOOTSTRAP_COLORS.get(row.color, C_MUTED)
		_opo_list.add_child(_make_event_row(text, col))


func _fmt_date(iso: String) -> String:
	var p := iso.split("-")
	if p.size() != 3:
		return iso
	return p[2] + "." + p[1] + "." + p[0]


func _date_to_unix(iso: String) -> int:
	var p := iso.split("-")
	return Time.get_unix_time_from_datetime_dict({
		"year": int(p[0]), "month": int(p[1]), "day": int(p[2]),
		"hour": 0, "minute": 0, "second": 0
	})


func _expand(ev: Dictionary) -> Array:
	var date_start: String = ev.get("date_start", "")
	var date_end: String   = ev.get("date_end", date_start)
	var start_u := _date_to_unix(date_start)
	var end_u   := _date_to_unix(date_end)
	var total   := int((end_u - start_u) / 86400) + 1
	var rows:   Array = []
	var day     := 1
	var cur_u   := start_u
	while cur_u <= end_u:
		var d := Time.get_datetime_dict_from_unix_time(cur_u)
		rows.append({
			"display_date": "%04d-%02d-%02d" % [d.year, d.month, d.day],
			"title":        ev.get("title", ""),
			"time_start":   ev.get("time_start"),
			"color":        ev.get("color", ""),
			"is_multiday":  total > 1,
			"is_first":     day == 1,
			"is_last":      day == total,
			"day_num":      day,
			"total_days":   total,
		})
		cur_u += 86400
		day   += 1
	return rows


func _make_label(text: String, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", 14)
	return lbl


func _make_event_row(text: String, tab_color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)

	var tab := ColorRect.new()
	tab.custom_minimum_size = Vector2(4, 0)
	tab.size_flags_vertical = Control.SIZE_FILL
	tab.color = tab_color
	row.add_child(tab)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(5, 0)
	row.add_child(gap)

	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	lbl.add_theme_color_override("font_color", C_TEXT)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	return row
