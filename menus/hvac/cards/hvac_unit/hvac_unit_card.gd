extends PanelContainer

@onready var _timer:       Timer        = %HVACUnitTimer
@onready var _outdoor_lbl: Label        = %OutdoorVal
@onready var _intake_lbl:  Label        = %IntakeVal
@onready var _outtake_lbl: Label        = %OuttakeVal
@onready var _heat_ex_lbl: Label        = %HeatExVal
@onready var _heater_lbl:  Label        = %HeaterVal
@onready var _vent_option: OptionButton = %VentOption
@onready var _status_lbl:  Label        = %HVACStatusLabel

var _vent_updating: bool = false


func _ready() -> void:
	_timer.timeout.connect(_do_poll)
	visibility_changed.connect(_on_visibility_changed)

	_vent_option.add_item("Stopped", 0)
	_vent_option.add_item("Slow",    2)
	_vent_option.add_item("Medium",  3)
	_vent_option.add_item("Max",     4)
	_vent_option.item_selected.connect(_on_vent_selected)

	ApiClient.hvac_data_received.connect(_on_data)
	ApiClient.hvac_set_done.connect(_on_set_done)
	ApiClient.login_success.connect(_do_poll)


func _on_visibility_changed() -> void:
	if visible:
		_do_poll()
		_timer.start()
	else:
		_timer.stop()


func _do_poll() -> void:
	ApiClient.get_hvac_data()


func _on_data(data: Dictionary) -> void:
	var outdoor  = data.get("outside_temp")
	var intake   = data.get("intake_temp")
	var outtake  = data.get("outtake_temp")
	# Note: "echanger" preserves the typo that exists in the Systemair/proxy source
	var heat_ex  = data.get("heat_echanger_percentage")
	var heater   = data.get("heater_percentage")
	var vent_val = data.get("user_set_ventilation")

	_outdoor_lbl.text = ("%.1f°C" % float(outdoor)) if outdoor != null else "–"
	_intake_lbl.text  = ("%.1f°C" % float(intake))  if intake  != null else "–"
	_outtake_lbl.text = ("%.1f°C" % float(outtake)) if outtake != null else "–"
	_heat_ex_lbl.text = ("%.0f%%" % float(heat_ex)) if heat_ex != null else "–"
	_heater_lbl.text  = ("%.0f%%" % float(heater))  if heater  != null else "–"

	if vent_val != null:
		var v := int(vent_val)
		_vent_updating = true
		for i in range(_vent_option.item_count):
			if _vent_option.get_item_id(i) == v:
				_vent_option.select(i)
				break
		_vent_updating = false

	_status_lbl.text = "OK"
	_status_lbl.add_theme_color_override("font_color", Color(0.4, 0.8, 0.4))


func _on_vent_selected(index: int) -> void:
	if _vent_updating:
		return
	ApiClient.set_hvac_ventilation(_vent_option.get_item_id(index))


func _on_set_done(success: bool) -> void:
	if not success:
		_status_lbl.text = "Set failed"
		_status_lbl.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
