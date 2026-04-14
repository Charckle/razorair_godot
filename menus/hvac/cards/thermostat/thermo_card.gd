extends PanelContainer

const C_ACCENT := Color(0.122, 0.435, 0.933)
const C_OFF    := Color(0.545, 0.580, 0.620)

const DEBOUNCE_SECS    := 1.5
const PROPAGATION_SECS := 3.0

@onready var _timer:         Timer       = %ThermoTimer
@onready var _curr_temp_lbl: Label       = %CurrTempLabel
@onready var _humidity_lbl:  Label       = %HumidityLabel
@onready var _status_lbl:    Label       = %ThermoStatusLabel
@onready var _set_temp_lbl:  Label       = %SetTempLabel
@onready var _minus_btn:     Button      = %MinusBtn
@onready var _plus_btn:      Button      = %PlusBtn
@onready var _enable_chk:    CheckButton = %EnableCheck

var _local_set_temp:   float = 20.0
var _enabled:          bool  = false
# Two-phase lock: true while debouncing or waiting for thermostat to apply the change
var _temp_locked:      bool  = false
var _temp_propagating: bool  = false
var _temp_debounce:    Timer


func _ready() -> void:
	_minus_btn.pressed.connect(_on_minus_pressed)
	_plus_btn.pressed.connect(_on_plus_pressed)
	_enable_chk.toggled.connect(_on_enable_toggled)
	_timer.timeout.connect(_do_poll)
	visibility_changed.connect(_on_visibility_changed)

	_temp_debounce = Timer.new()
	_temp_debounce.one_shot = true
	add_child(_temp_debounce)
	_temp_debounce.timeout.connect(_on_temp_debounce_timeout)

	ApiClient.thermostat_status_received.connect(_on_data)
	ApiClient.thermostat_set_done.connect(_on_set_done)
	ApiClient.login_success.connect(_do_poll)


func _on_visibility_changed() -> void:
	if visible:
		_do_poll()
		_timer.start()
	else:
		_timer.stop()


func _do_poll() -> void:
	ApiClient.get_thermostat_status()


func _on_data(data: Dictionary) -> void:
	var cur  = data.get("current_temp")
	var setp = data.get("set_temp")
	var hum  = data.get("current_humidity")
	var enab = data.get("enabled")

	if cur != null:
		_curr_temp_lbl.text = "%.1f°C" % float(cur)
	if setp != null and not _temp_locked:
		_local_set_temp = float(setp)
		_set_temp_lbl.text = "%.1f°C" % _local_set_temp
	if hum != null:
		_humidity_lbl.text = "Humidity: %.0f%%" % float(hum)
	if enab != null:
		_enabled = bool(enab)
		_enable_chk.set_pressed_no_signal(_enabled)
		_update_status_label()


func _update_status_label() -> void:
	if _enabled:
		_status_lbl.text = "ON"
		_status_lbl.add_theme_color_override("font_color", Color(0.4, 0.8, 0.4))
	else:
		_status_lbl.text = "OFF"
		_status_lbl.add_theme_color_override("font_color", C_OFF)


func _on_minus_pressed() -> void:
	_local_set_temp = maxf(_local_set_temp - 0.5, 5.0)
	_set_temp_lbl.text = "%.1f°C" % _local_set_temp
	_restart_debounce()


func _on_plus_pressed() -> void:
	_local_set_temp = minf(_local_set_temp + 0.5, 35.0)
	_set_temp_lbl.text = "%.1f°C" % _local_set_temp
	_restart_debounce()


func _restart_debounce() -> void:
	_temp_locked      = true
	_temp_propagating = false
	_temp_debounce.stop()
	_temp_debounce.start(DEBOUNCE_SECS)


func _on_temp_debounce_timeout() -> void:
	if not _temp_propagating:
		# Debounce phase over — send the command, enter propagation phase
		_temp_propagating = true
		ApiClient.set_thermostat_temp(_local_set_temp)
		_temp_debounce.start(PROPAGATION_SECS)
	else:
		# Propagation phase over — thermostat should have applied the change, unlock
		_temp_locked      = false
		_temp_propagating = false


func _on_set_done(success: bool) -> void:
	if not success:
		_set_temp_lbl.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
		await get_tree().create_timer(1.5).timeout
		_set_temp_lbl.add_theme_color_override("font_color", C_ACCENT)


func _on_enable_toggled(pressed: bool) -> void:
	_enabled = pressed
	_update_status_label()
	ApiClient.set_thermostat_enabled(pressed)
