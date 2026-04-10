extends Node

# ── Signals ──────────────────────────────────────────────────────────────────
signal login_success
signal login_failed(message: String)
signal thermostat_status_received(data: Dictionary)
signal thermostat_set_done(success: bool)
signal hvac_data_received(data: Dictionary)
signal hvac_set_done(success: bool)
signal weather_home_received(warnings: Array)
signal calendar_events_received(events: Array)
signal plugs_status_received(plugs: Array)
signal plug_set_done(success: bool)

# ── Config ────────────────────────────────────────────────────────────────────
var base_url: String           = "http://192.168.0.1:5000"
var username: String           = ""
var password: String           = ""
var vent_control_style: String = "dropdown"   # "dropdown" or "stepper"

const CONFIG_PATH := "user://config.cfg"

# ── Session state ─────────────────────────────────────────────────────────────
var session_cookie: String = ""
var _csrf_token:    String = ""
var _login_creds:   Dictionary = {}
var _login_phase:   int = 0   # 0=idle  1=waiting GET  2=waiting POST

# ── Busy flags (prevent double-fire) ─────────────────────────────────────────
var _thermo_poll_busy: bool = false
var _thermo_set_busy:  bool = false
var _hvac_poll_busy:    bool = false
var _hvac_set_busy:     bool = false
var _weather_busy:      bool = false
var _calendar_busy:     bool = false
var _plugs_busy:        bool = false
var _plug_set_busy:     bool = false

# ── HTTP nodes ────────────────────────────────────────────────────────────────
var _http_login:        HTTPRequest
var _http_thermo_poll:  HTTPRequest
var _http_thermo_set:   HTTPRequest
var _http_hvac_poll:    HTTPRequest
var _http_hvac_set:     HTTPRequest
var _http_weather:      HTTPRequest
var _http_calendar:     HTTPRequest
var _http_plugs:        HTTPRequest
var _http_plug_set:     HTTPRequest


func _ready() -> void:
	_http_login = _make_http()
	_http_login.max_redirects = 0
	_http_login.request_completed.connect(_on_login_completed)

	_http_thermo_poll = _make_http()
	_http_thermo_poll.request_completed.connect(_on_thermo_poll_done)

	_http_thermo_set = _make_http()
	_http_thermo_set.request_completed.connect(_on_thermo_set_done)

	_http_hvac_poll = _make_http()
	_http_hvac_poll.request_completed.connect(_on_hvac_poll_done)

	_http_hvac_set = _make_http()
	_http_hvac_set.request_completed.connect(_on_hvac_set_done)

	_http_weather = _make_http()
	_http_weather.request_completed.connect(_on_weather_done)

	_http_calendar = _make_http()
	_http_calendar.request_completed.connect(_on_calendar_done)

	_http_plugs = _make_http()
	_http_plugs.request_completed.connect(_on_plugs_done)

	_http_plug_set = _make_http()
	_http_plug_set.request_completed.connect(_on_plug_set_done)

	load_config()


func _make_http() -> HTTPRequest:
	var h = HTTPRequest.new()
	h.timeout = 8.0
	add_child(h)
	return h


# ── Config I/O ────────────────────────────────────────────────────────────────

func load_config() -> void:
	var cfg = ConfigFile.new()
	if cfg.load(CONFIG_PATH) == OK:
		base_url           = cfg.get_value("server", "base_url",           "http://192.168.0.1:5000")
		username           = cfg.get_value("auth",   "username",           "")
		password           = cfg.get_value("auth",   "password",           "")
		vent_control_style = cfg.get_value("ui",     "vent_control_style", "dropdown")
	else:
		save_config()


func save_config() -> void:
	var cfg = ConfigFile.new()
	cfg.set_value("server", "base_url",           base_url)
	cfg.set_value("auth",   "username",           username)
	cfg.set_value("auth",   "password",           password)
	cfg.set_value("ui",     "vent_control_style", vent_control_style)
	cfg.save(CONFIG_PATH)


# ── Login ─────────────────────────────────────────────────────────────────────

func do_login(u: String = "", p: String = "") -> void:
	if u.is_empty(): u = username
	if p.is_empty(): p = password
	_login_creds  = {"u": u, "p": p}
	session_cookie = ""
	_csrf_token    = ""
	_login_phase   = 1
	var err := _http_login.request(base_url + "/login/")
	if err != OK:
		_login_phase = 0
		login_failed.emit("Cannot reach server (err %d)" % err)


func _on_login_completed(result: int, code: int,
		headers: PackedStringArray, body: PackedByteArray) -> void:

	if _login_phase == 1:
		# ── Phase 1: received the login page ─────────────────────────────────
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			_login_phase = 0
			login_failed.emit("Server unreachable (HTTP %d)" % code)
			return

		_extract_cookie(headers)

		# Pull csrf_token from the HTML
		var html := body.get_string_from_utf8()
		var found := _extract_csrf(html)
		if not found:
			_login_phase = 0
			login_failed.emit("CSRF token not found — is the backend URL correct?")
			return

		# ── Phase 2: POST the credentials ────────────────────────────────────
		_login_phase = 2
		var post_body := (
			"username_or_email=%s&password=%s&csrf_token=%s" % [
				_login_creds["u"].uri_encode(),
				_login_creds["p"].uri_encode(),
				_csrf_token.uri_encode()
			]
		)
		var hdrs := PackedStringArray([
			"Content-Type: application/x-www-form-urlencoded",
			"Cookie: " + session_cookie
		])
		var err := _http_login.request(
			base_url + "/login/", hdrs, HTTPClient.METHOD_POST, post_body
		)
		if err != OK:
			_login_phase = 0
			login_failed.emit("POST failed (err %d)" % err)

	elif _login_phase == 2:
		# ── Phase 2: received login POST response ─────────────────────────────
		_login_phase = 0
		_extract_cookie(headers)

		# Flask redirects (302/303) on success; stays on 200 on failure.
		# With max_redirects=0 we see the redirect directly.
		# Godot may also return RESULT_REDIRECT_LIMIT_REACHED (8) for 302.
		var redirected := code in [301, 302, 303] \
			or result == HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED
		if redirected:
			login_success.emit()
		elif code == 200:
			var html := body.get_string_from_utf8()
			if "napačen" in html or "Invalid" in html or "error" in html.to_lower():
				login_failed.emit("Invalid username or password")
			else:
				login_failed.emit("Login failed — check credentials")
		else:
			login_failed.emit("Unexpected response (HTTP %d)" % code)


func _extract_csrf(html: String) -> bool:
	# Flask-WTF renders: <input id="csrf_token" name="csrf_token" type="hidden" value="TOKEN">
	# Attributes may appear in any order, so search line-by-line.
	var re := RegEx.new()
	re.compile('value="([^"]+)"')
	for line in html.split("\n"):
		if "csrf_token" in line:
			var m := re.search(line)
			if m:
				_csrf_token = m.get_string(1)
				return true
	return false


func _extract_cookie(headers: PackedStringArray) -> void:
	for h in headers:
		if h.to_lower().begins_with("set-cookie:"):
			var parts := h.split(":", false, 1)
			if parts.size() >= 2:
				session_cookie = parts[1].strip_edges().split(";")[0]
			return


# ── Shared header builders ────────────────────────────────────────────────────

func _hdrs_get() -> PackedStringArray:
	return PackedStringArray(["Cookie: " + session_cookie])


func _hdrs_post() -> PackedStringArray:
	return PackedStringArray([
		"Content-Type: application/x-www-form-urlencoded",
		"Cookie: " + session_cookie
	])


# ── Thermostat ────────────────────────────────────────────────────────────────

func get_thermostat_status() -> void:
	if _thermo_poll_busy:
		return
	_thermo_poll_busy = true
	if _http_thermo_poll.request(
			base_url + "/api/shelly_thermostat_status", _hdrs_get()
	) != OK:
		_thermo_poll_busy = false


func set_thermostat_temp(temp: float) -> void:
	if _thermo_set_busy:
		return
	_thermo_set_busy = true
	var snap := snappedf(temp, 0.5)
	var body := "temperature=" + str(snap)
	if _http_thermo_set.request(
			base_url + "/api/shelly_thermostat_set_temp",
			_hdrs_post(), HTTPClient.METHOD_POST, body
	) != OK:
		_thermo_set_busy = false


func set_thermostat_enabled(enabled: bool) -> void:
	if _thermo_set_busy:
		return
	_thermo_set_busy = true
	var body := "enabled=" + ("true" if enabled else "false")
	if _http_thermo_set.request(
			base_url + "/api/shelly_thermostat_enable",
			_hdrs_post(), HTTPClient.METHOD_POST, body
	) != OK:
		_thermo_set_busy = false


func _on_thermo_poll_done(result: int, code: int,
		_headers: PackedStringArray, body: PackedByteArray) -> void:
	_thermo_poll_busy = false
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		var json = JSON.parse_string(body.get_string_from_utf8())
		if json is Dictionary:
			thermostat_status_received.emit(json)


func _on_thermo_set_done(result: int, code: int,
		_headers: PackedStringArray, _body: PackedByteArray) -> void:
	_thermo_set_busy = false
	thermostat_set_done.emit(result == HTTPRequest.RESULT_SUCCESS and code == 200)


# ── HVAC unit ─────────────────────────────────────────────────────────────────

func get_hvac_data() -> void:
	if _hvac_poll_busy:
		return
	_hvac_poll_busy = true
	if _http_hvac_poll.request(
			base_url + "/api/hvac_data_get", _hdrs_get()
	) != OK:
		_hvac_poll_busy = false


func _on_hvac_poll_done(result: int, code: int,
		_headers: PackedStringArray, body: PackedByteArray) -> void:
	_hvac_poll_busy = false
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		var json = JSON.parse_string(body.get_string_from_utf8())
		if json is Dictionary:
			hvac_data_received.emit(json)


func set_hvac_ventilation(vent_level: int) -> void:
	if _hvac_set_busy:
		return
	_hvac_set_busy = true
	var body := "user_set_temp=0&user_set_ventilation=%d" % vent_level
	if _http_hvac_set.request(
			base_url + "/api/hvac_data_get",
			_hdrs_post(), HTTPClient.METHOD_POST, body
	) != OK:
		_hvac_set_busy = false


func _on_hvac_set_done(result: int, code: int,
		_headers: PackedStringArray, _body: PackedByteArray) -> void:
	_hvac_set_busy = false
	hvac_set_done.emit(result == HTTPRequest.RESULT_SUCCESS and code == 200)


# ── Weather / notifications ───────────────────────────────────────────────────

func get_weather_home() -> void:
	if _weather_busy:
		return
	_weather_busy = true
	if _http_weather.request(base_url + "/api/weather_home", _hdrs_get()) != OK:
		_weather_busy = false


func get_calendar_events() -> void:
	if _calendar_busy:
		return
	_calendar_busy = true
	if _http_calendar.request(base_url + "/api/calendar_events", _hdrs_get()) != OK:
		_calendar_busy = false


func _on_weather_done(result: int, code: int,
		_headers: PackedStringArray, body: PackedByteArray) -> void:
	_weather_busy = false
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		var json = JSON.parse_string(body.get_string_from_utf8())
		if json is Dictionary:
			var warnings = json.get("warnings", [])
			if warnings is Array:
				weather_home_received.emit(warnings)


func _on_calendar_done(result: int, code: int,
		_headers: PackedStringArray, body: PackedByteArray) -> void:
	_calendar_busy = false
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		var json = JSON.parse_string(body.get_string_from_utf8())
		if json is Dictionary:
			var events = json.get("events", [])
			if events is Array:
				calendar_events_received.emit(events)


# ── Stikala (Shelly plugs) ────────────────────────────────────────────────────

func get_shelly_plugs() -> void:
	if _plugs_busy:
		return
	_plugs_busy = true
	if _http_plugs.request(base_url + "/api/shelly_plugs_status", _hdrs_get()) != OK:
		_plugs_busy = false


func set_shelly_plug(index: int, on: bool) -> void:
	if _plug_set_busy:
		return
	_plug_set_busy = true
	var body := "index=%d&on=%s" % [index, "true" if on else "false"]
	if _http_plug_set.request(
			base_url + "/api/shelly_plug_set",
			_hdrs_post(), HTTPClient.METHOD_POST, body
	) != OK:
		_plug_set_busy = false


func _on_plugs_done(result: int, code: int,
		_headers: PackedStringArray, body: PackedByteArray) -> void:
	_plugs_busy = false
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		var json = JSON.parse_string(body.get_string_from_utf8())
		if json is Dictionary:
			var plugs = json.get("plugs", [])
			if plugs is Array:
				plugs_status_received.emit(plugs)


func _on_plug_set_done(result: int, code: int,
		_headers: PackedStringArray, _body: PackedByteArray) -> void:
	_plug_set_busy = false
	plug_set_done.emit(result == HTTPRequest.RESULT_SUCCESS and code == 200)
