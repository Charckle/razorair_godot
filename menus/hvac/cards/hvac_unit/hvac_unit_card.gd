extends PanelContainer

@onready var _timer:          Timer         = %HVACUnitTimer
@onready var _outdoor_lbl:    Label         = %OutdoorVal
@onready var _intake_lbl:     Label         = %IntakeVal
@onready var _outtake_lbl:    Label         = %OuttakeVal
@onready var _heat_ex_lbl:    Label         = %HeatExVal
@onready var _heater_lbl:     Label         = %HeaterVal
@onready var _vent_option:    OptionButton  = %VentOption
@onready var _vent_stepper:   HBoxContainer = %VentStepper
@onready var _vent_step_lbl:  Label         = %VentStepLabel
@onready var _vent_down:      Button        = %VentDown
@onready var _vent_up:        Button        = %VentUp
@onready var _status_lbl:     Label         = %HVACStatusLabel

# API values in order from lowest to highest
const VENT_LEVELS := [0, 2, 3, 4]
const VENT_NAMES  := ["Stopped", "Slow", "Medium", "Max"]

const DEBOUNCE_SECS    := 2.0
const PROPAGATION_SECS := 4.0

var _vent_updating:     bool  = false
var _current_vent_level: int  = 0
# Two-phase lock: true while debouncing or waiting for HVAC to apply the change
var _vent_locked:       bool  = false
var _vent_propagating:  bool  = false   # true = debounce fired, waiting for HVAC
var _vent_debounce:     Timer


func _ready() -> void:
	_timer.timeout.connect(_do_poll)
	visibility_changed.connect(_on_visibility_changed)

	_vent_option.add_item("Stopped", 0)
	_vent_option.add_item("Slow",    2)
	_vent_option.add_item("Medium",  3)
	_vent_option.add_item("Max",     4)
	_vent_option.item_selected.connect(_on_vent_selected)

	_vent_down.pressed.connect(_on_vent_down)
	_vent_up.pressed.connect(_on_vent_up)

	_vent_debounce = Timer.new()
	_vent_debounce.one_shot = true
	add_child(_vent_debounce)
	_vent_debounce.timeout.connect(_on_vent_debounce_timeout)

	ApiClient.hvac_data_received.connect(_on_data)
	ApiClient.hvac_set_done.connect(_on_set_done)
	ApiClient.login_success.connect(_do_poll)

	_apply_vent_style()


func _on_visibility_changed() -> void:
	if visible:
		_apply_vent_style()
		_do_poll()
		_timer.start()
	else:
		_timer.stop()


func _apply_vent_style() -> void:
	var use_stepper := ApiClient.vent_control_style == "stepper"
	_vent_option.visible  = not use_stepper
	_vent_stepper.visible = use_stepper


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

		# Always keep the dropdown in sync (it is not shown during stepper mode anyway)
		_vent_updating = true
		for i in range(_vent_option.item_count):
			if _vent_option.get_item_id(i) == v:
				_vent_option.select(i)
				break
		_vent_updating = false

		# Stepper display is locked while debouncing or waiting for HVAC to apply the change
		if not _vent_locked:
			_set_vent_display(VENT_LEVELS.find(v), v)

	_status_lbl.text = "OK"
	_status_lbl.add_theme_color_override("font_color", Color(0.4, 0.8, 0.4))


func _set_vent_display(idx: int, raw_value: int) -> void:
	_current_vent_level = raw_value
	_vent_step_lbl.text = VENT_NAMES[idx] if idx >= 0 else str(raw_value)
	_vent_down.disabled = idx <= 0
	_vent_up.disabled   = idx >= VENT_LEVELS.size() - 1


# ── Dropdown handler ──────────────────────────────────────────────────────────

func _on_vent_selected(index: int) -> void:
	if _vent_updating:
		return
	ApiClient.set_hvac_ventilation(_vent_option.get_item_id(index))


# ── Stepper handlers ──────────────────────────────────────────────────────────

func _on_vent_down() -> void:
	var idx := VENT_LEVELS.find(_current_vent_level)
	if idx > 0:
		_set_vent_display(idx - 1, VENT_LEVELS[idx - 1])
		_restart_debounce()


func _on_vent_up() -> void:
	var idx := VENT_LEVELS.find(_current_vent_level)
	if idx >= 0 and idx < VENT_LEVELS.size() - 1:
		_set_vent_display(idx + 1, VENT_LEVELS[idx + 1])
		_restart_debounce()


func _restart_debounce() -> void:
	_vent_locked      = true
	_vent_propagating = false
	_vent_debounce.stop()
	_vent_debounce.start(DEBOUNCE_SECS)


func _on_vent_debounce_timeout() -> void:
	if not _vent_propagating:
		# Debounce phase over — send the command, enter propagation phase
		_vent_propagating = true
		ApiClient.set_hvac_ventilation(_current_vent_level)
		_vent_debounce.start(PROPAGATION_SECS)
	else:
		# Propagation phase over — HVAC should have applied the change, unlock
		_vent_locked      = false
		_vent_propagating = false


# ── Set confirmation ──────────────────────────────────────────────────────────

func _on_set_done(success: bool) -> void:
	if not success:
		_status_lbl.text = "Set failed"
		_status_lbl.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
