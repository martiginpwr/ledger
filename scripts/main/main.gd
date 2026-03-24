extends Control

const RULES_PATH := "res://data/balance/game_rules.json"
const ORIGINS_PATH := "res://data/content/origins.json"
const SKILLS_PATH := "res://data/content/skills.json"
const MOBS_PATH := "res://data/content/mobs.json"
const BOSSES_PATH := "res://data/content/bosses.json"
const AUTOSAVE_PATH := "user://autosave_match.json"
const AUTOSAVE_VERSION := 1
const ContentLoaderScript = preload("res://scripts/core/content_loader.gd")
const BoardGeneratorScript = preload("res://scripts/core/board_generator.gd")

const DEFAULT_PLAYER_COUNT := 4
const LOG_PANEL_WIDTH := 300.0
const INFO_PANEL_WIDTH := 340.0
const PANEL_MARGIN := 16.0
const PANEL_GAP := 18.0
const ACTION_PANEL_HEIGHT := 142.0
const ACTION_BUTTON_COUNT := 8
const CELL_RADIUS := 18.0
const TOKEN_RADIUS := 7.0
const TURN_PHASE_AWAIT_ROLL := "await_roll"
const TURN_PHASE_AWAIT_MOVE := "await_move"
const TURN_PHASE_MOVING := "moving"
const TURN_PHASE_READY_TO_END := "ready_to_end"

const PLAYER_COLORS := [
	Color("ef4444"),
	Color("3b82f6"),
	Color("f59e0b"),
	Color("10b981"),
	Color("8b5cf6"),
	Color("ec4899"),
	Color("14b8a6"),
	Color("f97316")
]

const CELL_COLORS := {
	"neutral": Color("475569"),
	"shrine": Color("06b6d4"),
	"shop": Color("f59e0b"),
	"event": Color("8b5cf6"),
	"casino": Color("e11d48"),
	"property": Color("22c55e"),
	"mob_den": Color("ef4444"),
	"boss_entrance": Color("f97316"),
	"portal": Color("38bdf8")
}

var _rng := RandomNumberGenerator.new()
var _rules: Dictionary = {}
var _origins: Array = []
var _skills: Array = []
var _mobs_data: Array = []
var _bosses_data: Array = []
var _board: Dictionary = {}
var _players: Array = []
var _property_states: Dictionary = {}
var _mob_states: Dictionary = {}
var _boss_states: Dictionary = {}
var _current_player_index := 0
var _round_number := 1
var _turn_phase := ""
var _turn_time_left := 0.0
var _last_roll := -1
var _current_move_steps := 0
var _major_action_used := false
var _quick_action_used := false
var _force_end_turn_after_resolution := false
var _reachable_cells: Dictionary = {}
var _available_actions: Array = []
var _hovered_cell_id := ""
var _log_lines: Array = []
var _raider_bonus_claimed: Dictionary = {}
var _trickster_reroll_claimed: Dictionary = {}
var _board_bounds := Rect2(-1.0, -1.0, 2.0, 2.0)
var _board_scale := 1.0
var _board_offset := Vector2.ZERO
var _animating_player_index := -1
var _next_mob_instance_id := 1
var _is_game_over := false
var _winner_summary := ""
var _final_round_triggered := false
var _final_round_target_round := -1

var _title_label: Label
var _status_label: Label
var _turn_label: Label
var _timer_label: Label
var _roll_label: Label
var _roster_label: Label
var _hover_label: Label
var _detail_label: Label
var _log_label: Label
var _roll_button: Button
var _end_turn_button: Button
var _new_board_button: Button
var _action_buttons: Array = []
var _menu_overlay: Control
var _menu_message_label: Label
var _continue_button: Button


func _ready() -> void:
	_rng.randomize()
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build_ui()

	if not _load_content():
		return

	_show_main_menu(
		"Restore a crash save or launch a fresh match." if _autosave_exists() else "Choose a match size to begin."
	)


func _process(delta: float) -> void:
	if _players.is_empty() or _is_game_over:
		return

	if _turn_phase != "":
		_turn_time_left = max(0.0, _turn_time_left - delta)
		if _turn_time_left <= 0.0:
			_handle_turn_timeout()

	_update_ui()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if _menu_overlay != null and _menu_overlay.visible:
		return
	if _board.is_empty() or _is_game_over:
		return

	if event is InputEventMouseMotion:
		_hovered_cell_id = _cell_at_screen_position(event.position)
		_update_ui()
		queue_redraw()
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _turn_phase != TURN_PHASE_AWAIT_MOVE:
			return

		var cell_id := _cell_at_screen_position(event.position)
		if _reachable_cells.has(cell_id):
			_move_current_player_to(cell_id, false)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("0b1120"))
	draw_circle(Vector2(size.x * 0.18, size.y * 0.2), size.y * 0.22, Color(0.07, 0.17, 0.28, 0.16))
	draw_circle(Vector2(size.x * 0.82, size.y * 0.24), size.y * 0.2, Color(0.16, 0.11, 0.26, 0.16))

	if _board.is_empty() or _players.is_empty():
		return

	_recalculate_board_transform()

	var board_rect := _get_board_rect()
	draw_rect(board_rect, Color("111827"), true)
	draw_rect(board_rect, Color("1f2937"), false, 2.0)
	var board_center: Vector2 = board_rect.position + board_rect.size * 0.5
	var loop_radius: float = minf(board_rect.size.x, board_rect.size.y) * 0.23
	draw_circle(board_center + Vector2(-board_rect.size.x * 0.22, 0.0), loop_radius, Color(0.08, 0.22, 0.28, 0.12))
	draw_circle(board_center + Vector2(board_rect.size.x * 0.22, 0.0), loop_radius, Color(0.22, 0.14, 0.08, 0.12))
	draw_circle(board_center, loop_radius * 0.48, Color(0.25, 0.25, 0.12, 0.12))
	_draw_board_grid(board_rect)
	_draw_connections()
	_draw_cells()
	_draw_mobs()
	_draw_players()


func _build_ui() -> void:
	var panel_bottom_offset := -PANEL_MARGIN - ACTION_PANEL_HEIGHT - PANEL_GAP

	var log_panel := PanelContainer.new()
	log_panel.anchor_left = 0.0
	log_panel.anchor_top = 0.0
	log_panel.anchor_right = 0.0
	log_panel.anchor_bottom = 1.0
	log_panel.offset_left = PANEL_MARGIN
	log_panel.offset_top = PANEL_MARGIN
	log_panel.offset_right = PANEL_MARGIN + LOG_PANEL_WIDTH
	log_panel.offset_bottom = panel_bottom_offset
	log_panel.add_theme_stylebox_override("panel", _make_stylebox(Color("101828"), Color("f59e0b"), 16))
	add_child(log_panel)

	var log_margin := MarginContainer.new()
	log_margin.add_theme_constant_override("margin_left", 16)
	log_margin.add_theme_constant_override("margin_top", 16)
	log_margin.add_theme_constant_override("margin_right", 16)
	log_margin.add_theme_constant_override("margin_bottom", 16)
	log_panel.add_child(log_margin)

	var log_vbox := VBoxContainer.new()
	log_vbox.add_theme_constant_override("separation", 12)
	log_margin.add_child(log_vbox)

	var log_title := Label.new()
	log_title.text = "TURN LOG"
	_style_label(log_title, 20, Color("fbbf24"))
	log_vbox.add_child(log_title)

	_log_label = Label.new()
	_style_label(_log_label, 15, Color("e5eefc"), 420.0)
	_log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_vbox.add_child(_log_label)

	var info_panel := PanelContainer.new()
	info_panel.anchor_left = 1.0
	info_panel.anchor_top = 0.0
	info_panel.anchor_right = 1.0
	info_panel.anchor_bottom = 1.0
	info_panel.offset_left = -PANEL_MARGIN - INFO_PANEL_WIDTH
	info_panel.offset_top = PANEL_MARGIN
	info_panel.offset_right = -PANEL_MARGIN
	info_panel.offset_bottom = panel_bottom_offset
	info_panel.add_theme_stylebox_override("panel", _make_stylebox(Color("0f172a"), Color("38bdf8"), 16))
	add_child(info_panel)

	var info_margin := MarginContainer.new()
	info_margin.add_theme_constant_override("margin_left", 16)
	info_margin.add_theme_constant_override("margin_top", 16)
	info_margin.add_theme_constant_override("margin_right", 16)
	info_margin.add_theme_constant_override("margin_bottom", 16)
	info_panel.add_child(info_margin)

	var info_vbox := VBoxContainer.new()
	info_vbox.add_theme_constant_override("separation", 10)
	info_margin.add_child(info_vbox)

	_title_label = Label.new()
	_title_label.text = "Board Prototype"
	_style_label(_title_label, 28, Color("f8fafc"))
	info_vbox.add_child(_title_label)

	var status_title := Label.new()
	status_title.text = "MATCH STATE"
	_style_label(status_title, 18, Color("7dd3fc"))
	info_vbox.add_child(status_title)

	_status_label = Label.new()
	_style_label(_status_label, 16, Color("dbeafe"), 96.0)
	info_vbox.add_child(_status_label)

	var active_title := Label.new()
	active_title.text = "ACTIVE HERO"
	_style_label(active_title, 18, Color("86efac"))
	info_vbox.add_child(active_title)

	_turn_label = Label.new()
	_style_label(_turn_label, 17, Color("f8fafc"), 132.0)
	info_vbox.add_child(_turn_label)

	_timer_label = Label.new()
	_style_label(_timer_label, 17, Color("fbbf24"))
	info_vbox.add_child(_timer_label)

	_roll_label = Label.new()
	_style_label(_roll_label, 16, Color("c4b5fd"))
	info_vbox.add_child(_roll_label)

	var standings_title := Label.new()
	standings_title.text = "TABLE"
	_style_label(standings_title, 18, Color("fda4af"))
	info_vbox.add_child(standings_title)

	_roster_label = Label.new()
	_style_label(_roster_label, 15, Color("e5eefc"), 120.0)
	info_vbox.add_child(_roster_label)

	var hover_title := Label.new()
	hover_title.text = "HOVERED CELL"
	_style_label(hover_title, 18, Color("fcd34d"))
	info_vbox.add_child(hover_title)

	_hover_label = Label.new()
	_style_label(_hover_label, 16, Color("fef3c7"))
	info_vbox.add_child(_hover_label)

	_detail_label = Label.new()
	_style_label(_detail_label, 15, Color("e5eefc"), 200.0)
	_detail_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info_vbox.add_child(_detail_label)

	var action_panel := PanelContainer.new()
	action_panel.anchor_left = 0.0
	action_panel.anchor_top = 1.0
	action_panel.anchor_right = 1.0
	action_panel.anchor_bottom = 1.0
	action_panel.offset_left = PANEL_MARGIN + LOG_PANEL_WIDTH + PANEL_GAP
	action_panel.offset_top = -PANEL_MARGIN - ACTION_PANEL_HEIGHT
	action_panel.offset_right = -(PANEL_MARGIN + INFO_PANEL_WIDTH + PANEL_GAP)
	action_panel.offset_bottom = -PANEL_MARGIN
	action_panel.add_theme_stylebox_override("panel", _make_stylebox(Color("111827"), Color("22c55e"), 16))
	add_child(action_panel)

	var action_margin := MarginContainer.new()
	action_margin.add_theme_constant_override("margin_left", 14)
	action_margin.add_theme_constant_override("margin_top", 14)
	action_margin.add_theme_constant_override("margin_right", 14)
	action_margin.add_theme_constant_override("margin_bottom", 14)
	action_panel.add_child(action_margin)

	var action_vbox := VBoxContainer.new()
	action_vbox.add_theme_constant_override("separation", 10)
	action_margin.add_child(action_vbox)

	var action_hint := Label.new()
	action_hint.text = "Travel the board, strike fast, and spend your action window before the timer expires."
	_style_label(action_hint, 15, Color("bbf7d0"))
	action_vbox.add_child(action_hint)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 12)
	action_vbox.add_child(action_row)

	_roll_button = Button.new()
	_roll_button.text = "Roll"
	_roll_button.pressed.connect(_on_roll_pressed)
	_style_button(_roll_button, Color("2563eb"))
	action_row.add_child(_roll_button)

	_end_turn_button = Button.new()
	_end_turn_button.text = "End Turn"
	_end_turn_button.pressed.connect(_on_end_turn_pressed)
	_style_button(_end_turn_button, Color("15803d"))
	action_row.add_child(_end_turn_button)

	_new_board_button = Button.new()
	_new_board_button.text = "Menu"
	_new_board_button.pressed.connect(_on_new_board_pressed)
	_style_button(_new_board_button, Color("7c3aed"))
	action_row.add_child(_new_board_button)

	var cell_action_row := HFlowContainer.new()
	cell_action_row.add_theme_constant_override("h_separation", 10)
	cell_action_row.add_theme_constant_override("v_separation", 10)
	cell_action_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_vbox.add_child(cell_action_row)

	for button_index in range(ACTION_BUTTON_COUNT):
		var action_button := Button.new()
		action_button.visible = false
		action_button.disabled = true
		action_button.pressed.connect(_on_action_button_pressed.bind(button_index))
		_style_button(action_button, Color("374151"))
		cell_action_row.add_child(action_button)
		_action_buttons.append(action_button)

	_menu_overlay = Control.new()
	_menu_overlay.anchor_right = 1.0
	_menu_overlay.anchor_bottom = 1.0
	_menu_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu_overlay.visible = false
	add_child(_menu_overlay)

	var dimmer := ColorRect.new()
	dimmer.anchor_right = 1.0
	dimmer.anchor_bottom = 1.0
	dimmer.color = Color(0.02, 0.04, 0.09, 0.72)
	_menu_overlay.add_child(dimmer)

	var menu_panel := PanelContainer.new()
	menu_panel.anchor_left = 0.5
	menu_panel.anchor_top = 0.5
	menu_panel.anchor_right = 0.5
	menu_panel.anchor_bottom = 0.5
	menu_panel.offset_left = -250.0
	menu_panel.offset_top = -220.0
	menu_panel.offset_right = 250.0
	menu_panel.offset_bottom = 220.0
	menu_panel.add_theme_stylebox_override("panel", _make_stylebox(Color("0f172a"), Color("f59e0b"), 20))
	_menu_overlay.add_child(menu_panel)

	var menu_margin := MarginContainer.new()
	menu_margin.add_theme_constant_override("margin_left", 20)
	menu_margin.add_theme_constant_override("margin_top", 20)
	menu_margin.add_theme_constant_override("margin_right", 20)
	menu_margin.add_theme_constant_override("margin_bottom", 20)
	menu_panel.add_child(menu_margin)

	var menu_vbox := VBoxContainer.new()
	menu_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	menu_vbox.add_theme_constant_override("separation", 14)
	menu_margin.add_child(menu_vbox)

	var menu_title := Label.new()
	menu_title.text = "RPG BOARD GAME"
	_style_label(menu_title, 34, Color("f8fafc"))
	menu_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_vbox.add_child(menu_title)

	var menu_subtitle := Label.new()
	menu_subtitle.text = "Prototype War Table"
	_style_label(menu_subtitle, 18, Color("7dd3fc"))
	menu_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_vbox.add_child(menu_subtitle)

	_menu_message_label = Label.new()
	_style_label(_menu_message_label, 15, Color("e5eefc"), 54.0)
	_menu_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_vbox.add_child(_menu_message_label)

	_continue_button = Button.new()
	_continue_button.text = "Continue Crash Save"
	_continue_button.pressed.connect(_on_continue_saved_match_pressed)
	_style_button(_continue_button, Color("2563eb"))
	menu_vbox.add_child(_continue_button)

	for player_count in [4, 6, 8]:
		var new_match_button := Button.new()
		new_match_button.text = "New %d-Player Match" % player_count
		new_match_button.pressed.connect(_on_new_match_selected.bind(player_count))
		_style_button(new_match_button, Color("7c3aed"))
		menu_vbox.add_child(new_match_button)

	var close_menu_button := Button.new()
	close_menu_button.text = "Return To Match"
	close_menu_button.pressed.connect(_on_close_menu_pressed)
	_style_button(close_menu_button, Color("15803d"))
	menu_vbox.add_child(close_menu_button)


func _make_stylebox(background: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_right = radius
	style.corner_radius_bottom_left = radius
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.18)
	style.shadow_size = 10
	return style


func _style_label(label: Label, font_size: int, color: Color, minimum_height: float = 0.0) -> void:
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color("020617"))
	label.add_theme_constant_override("outline_size", 1)
	if minimum_height > 0.0:
		label.custom_minimum_size = Vector2(0.0, minimum_height)


func _style_button(button: Button, background: Color) -> void:
	button.custom_minimum_size = Vector2(132.0, 42.0)
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", Color("f8fafc"))
	button.add_theme_color_override("font_hover_color", Color("ffffff"))
	button.add_theme_color_override("font_pressed_color", Color("ffffff"))
	button.add_theme_color_override("font_disabled_color", Color("94a3b8"))
	button.add_theme_stylebox_override("normal", _make_stylebox(background, background.lightened(0.16), 12))
	button.add_theme_stylebox_override("hover", _make_stylebox(background.lightened(0.12), background.lightened(0.28), 12))
	button.add_theme_stylebox_override("pressed", _make_stylebox(background.darkened(0.12), background.lightened(0.12), 12))
	button.add_theme_stylebox_override("disabled", _make_stylebox(Color("1f2937"), Color("334155"), 12))


func _show_main_menu(message: String = "") -> void:
	if _menu_overlay == null:
		return

	var resolved_message := message
	if resolved_message.is_empty():
		resolved_message = "Restore a crash save or launch a fresh match." if _autosave_exists() else "Choose a match size to begin."
	_menu_message_label.text = resolved_message
	_continue_button.visible = _autosave_exists()
	_continue_button.disabled = not _autosave_exists()
	_menu_overlay.visible = true
	_update_ui()


func _hide_main_menu() -> void:
	if _menu_overlay == null:
		return

	_menu_overlay.visible = false
	_update_ui()


func _autosave_exists() -> bool:
	return FileAccess.file_exists(AUTOSAVE_PATH)


func _serialize_value(value: Variant) -> Variant:
	if value is Vector2:
		return {"__type": "Vector2", "x": value.x, "y": value.y}
	if value is Color:
		return {"__type": "Color", "html": value.to_html()}
	if value is Dictionary:
		var mapped := {}
		for key in value.keys():
			mapped[str(key)] = _serialize_value(value[key])
		return mapped
	if value is Array:
		var mapped_array := []
		for item in value:
			mapped_array.append(_serialize_value(item))
		return mapped_array
	return value


func _deserialize_value(value: Variant) -> Variant:
	if value is Dictionary:
		var mapped_value: Dictionary = value
		var type_name := str(mapped_value.get("__type", ""))
		if type_name == "Vector2":
			return Vector2(float(mapped_value.get("x", 0.0)), float(mapped_value.get("y", 0.0)))
		if type_name == "Color":
			return Color(str(mapped_value.get("html", "ffffff")))

		var restored := {}
		for key in mapped_value.keys():
			restored[key] = _deserialize_value(mapped_value[key])
		return restored
	if value is Array:
		var restored_array := []
		for item in value:
			restored_array.append(_deserialize_value(item))
		return restored_array
	return value


func _save_autosave() -> void:
	if _players.is_empty() or _turn_phase == TURN_PHASE_MOVING or _is_game_over:
		return

	var payload := {
		"autosave_version": AUTOSAVE_VERSION,
		"board": _serialize_value(_board),
		"players": _serialize_value(_players),
		"property_states": _serialize_value(_property_states),
		"mob_states": _serialize_value(_mob_states),
		"boss_states": _serialize_value(_boss_states),
		"current_player_index": _current_player_index,
		"round_number": _round_number,
		"turn_phase": _turn_phase,
		"turn_time_left": _turn_time_left,
		"last_roll": _last_roll,
		"current_move_steps": _current_move_steps,
		"major_action_used": _major_action_used,
		"quick_action_used": _quick_action_used,
		"force_end_turn_after_resolution": _force_end_turn_after_resolution,
		"log_lines": _serialize_value(_log_lines),
		"next_mob_instance_id": _next_mob_instance_id,
		"final_round_triggered": _final_round_triggered,
		"final_round_target_round": _final_round_target_round,
		"winner_summary": _winner_summary,
		"raider_bonus_claimed": _serialize_value(_raider_bonus_claimed),
		"trickster_reroll_claimed": _serialize_value(_trickster_reroll_claimed)
	}

	var file := FileAccess.open(AUTOSAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Failed to write autosave at %s." % AUTOSAVE_PATH)
		return

	file.store_string(JSON.stringify(payload, "\t"))


func _load_autosave() -> bool:
	if not _autosave_exists():
		return false

	var file := FileAccess.open(AUTOSAVE_PATH, FileAccess.READ)
	if file == null:
		return false

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return false

	var data: Dictionary = parsed
	if int(data.get("autosave_version", 0)) != AUTOSAVE_VERSION:
		return false

	_board = _deserialize_value(data.get("board", {}))
	_players = _deserialize_value(data.get("players", []))
	_property_states = _deserialize_value(data.get("property_states", {}))
	_mob_states = _deserialize_value(data.get("mob_states", {}))
	_boss_states = _deserialize_value(data.get("boss_states", {}))
	_current_player_index = int(data.get("current_player_index", 0))
	_round_number = int(data.get("round_number", 1))
	_turn_phase = str(data.get("turn_phase", TURN_PHASE_AWAIT_ROLL))
	_turn_time_left = float(data.get("turn_time_left", 0.0))
	_last_roll = int(data.get("last_roll", -1))
	_current_move_steps = int(data.get("current_move_steps", 0))
	_major_action_used = bool(data.get("major_action_used", false))
	_quick_action_used = bool(data.get("quick_action_used", false))
	_force_end_turn_after_resolution = bool(data.get("force_end_turn_after_resolution", false))
	_log_lines = _deserialize_value(data.get("log_lines", []))
	_next_mob_instance_id = int(data.get("next_mob_instance_id", 1))
	_final_round_triggered = bool(data.get("final_round_triggered", false))
	_final_round_target_round = int(data.get("final_round_target_round", -1))
	_winner_summary = str(data.get("winner_summary", ""))
	_raider_bonus_claimed = _deserialize_value(data.get("raider_bonus_claimed", {}))
	_trickster_reroll_claimed = _deserialize_value(data.get("trickster_reroll_claimed", {}))
	_is_game_over = false
	_reachable_cells.clear()
	_available_actions.clear()
	_hovered_cell_id = ""
	_animating_player_index = -1
	_refresh_board_bounds()
	if _turn_phase == TURN_PHASE_READY_TO_END:
		_refresh_available_actions()
	_update_ui()
	queue_redraw()
	return true


func _clear_autosave() -> void:
	if not _autosave_exists():
		return

	DirAccess.remove_absolute(ProjectSettings.globalize_path(AUTOSAVE_PATH))


func _load_content() -> bool:
	var loader = ContentLoaderScript.new()
	var rules: Variant = loader.load_json(RULES_PATH)
	var origins: Variant = loader.load_json(ORIGINS_PATH)
	var skills: Variant = loader.load_json(SKILLS_PATH)
	var mobs: Variant = loader.load_json(MOBS_PATH)
	var bosses: Variant = loader.load_json(BOSSES_PATH)

	if typeof(rules) != TYPE_DICTIONARY:
		push_error("Rules failed to load from %s" % RULES_PATH)
		return false
	if typeof(origins) != TYPE_ARRAY:
		push_error("Origins failed to load from %s" % ORIGINS_PATH)
		return false
	if typeof(skills) != TYPE_ARRAY:
		push_error("Skills failed to load from %s" % SKILLS_PATH)
		return false
	if typeof(mobs) != TYPE_ARRAY:
		push_error("Mobs failed to load from %s" % MOBS_PATH)
		return false
	if typeof(bosses) != TYPE_ARRAY:
		push_error("Bosses failed to load from %s" % BOSSES_PATH)
		return false

	_rules = rules
	_origins = origins
	_skills = skills
	_mobs_data = mobs
	_bosses_data = bosses
	return true


func _start_new_match(player_count: int) -> void:
	_hide_main_menu()
	var generator = BoardGeneratorScript.new()
	_board = generator.generate(player_count)
	if _board.is_empty():
		return

	_property_states.clear()
	_mob_states.clear()
	_boss_states.clear()
	_raider_bonus_claimed.clear()
	_trickster_reroll_claimed.clear()
	for cell_id in _board.get("cells", {}).keys():
		var cell_data: Dictionary = _board["cells"][cell_id]
		if str(cell_data.get("type", "")) == "property":
			_property_states[cell_id] = {
				"owner_index": -1,
				"level": 0,
				"income_blocked": false
			}

	_assign_bosses_to_board()
	_players = _build_players(player_count)
	_current_player_index = 0
	_round_number = 1
	_last_roll = -1
	_current_move_steps = 0
	_major_action_used = false
	_quick_action_used = false
	_force_end_turn_after_resolution = false
	_turn_phase = ""
	_turn_time_left = 0.0
	_reachable_cells.clear()
	_available_actions.clear()
	_hovered_cell_id = ""
	_log_lines.clear()
	_animating_player_index = -1
	_next_mob_instance_id = 1
	_is_game_over = false
	_winner_summary = ""
	_final_round_triggered = false
	_final_round_target_round = -1
	_refresh_board_bounds()
	_reset_round_passives()

	var cells: Dictionary = _board.get("cells", {})
	var metadata: Dictionary = _board.get("metadata", {})
	_append_log(
		"Generated %s board with %d cells and regions %s." %
		[
			_board.get("template_key", "unknown"),
			cells.size(),
			metadata.get("selected_regions", [])
		]
	)
	_start_turn()
	_save_autosave()
	queue_redraw()


func _build_players(player_count: int) -> Array:
	var built_players := []
	var start_cell_id := "hub__sanctuary"
	var base_stats: Dictionary = _rules.get("starting_state", {}).get("base_stats", {})
	var starting_gold := int(_rules.get("starting_state", {}).get("gold", 10))
	var starting_stance := str(_rules.get("starting_state", {}).get("stance", "balanced"))

	for player_index in range(player_count):
		var origin: Dictionary = _origins[player_index % _origins.size()]
		var stats := base_stats.duplicate(true)
		for stat_name in origin.get("stat_bonuses", {}).keys():
			stats[stat_name] = int(stats.get(stat_name, 0)) + int(origin["stat_bonuses"][stat_name])

		var max_hp := 10 + int(stats.get("guard", 0)) * 2
		var starter_skill_id := str(origin.get("starter_skill_id", ""))
		built_players.append(
			{
				"name": "Player %d" % (player_index + 1),
				"origin_id": str(origin.get("id", "origin")),
				"origin_name": str(origin.get("name", "Origin")),
				"starter_skill_id": starter_skill_id,
				"passive_text": str(origin.get("passive", "")),
				"signature_stat": _signature_stat_for_origin(origin),
				"stats": stats,
				"hp": max_hp,
				"max_hp": max_hp,
				"gold": starting_gold,
				"renown": 0,
				"stance": starting_stance,
				"weapon_bonus": 0,
				"armor_bonus": 0,
				"temporary_guard_bonus": 0,
				"power_strike_ready": false,
				"skill_cooldowns": {starter_skill_id: 0},
				"cell_id": start_cell_id,
				"board_position": _cell_world_position(start_cell_id),
				"color": PLAYER_COLORS[player_index % PLAYER_COLORS.size()]
			}
		)

	return built_players


func _reset_round_passives() -> void:
	for player_index in range(_players.size()):
		_raider_bonus_claimed[player_index] = false
		_trickster_reroll_claimed[player_index] = false


func _player_has_origin(player_index: int, origin_id: String) -> bool:
	if player_index < 0 or player_index >= _players.size():
		return false

	return str(_players[player_index].get("origin_id", "")) == origin_id


func _movement_bonus_for_player(player: Dictionary) -> int:
	var mobility := int(player.get("stats", {}).get("mobility", 0))
	if mobility >= 4:
		return 2
	if mobility >= 2:
		return 1
	return 0


func _skill_by_id(skill_id: String) -> Dictionary:
	for skill_variant in _skills:
		var skill: Dictionary = skill_variant
		if str(skill.get("id", "")) == skill_id:
			return skill
	return {}


func _current_player_starter_skill() -> Dictionary:
	if _players.is_empty():
		return {}

	return _skill_by_id(str(_players[_current_player_index].get("starter_skill_id", "")))


func _player_skill_cooldown(player_index: int, skill_id: String) -> int:
	if player_index < 0 or player_index >= _players.size() or skill_id.is_empty():
		return 0

	var cooldowns: Dictionary = _players[player_index].get("skill_cooldowns", {})
	return int(cooldowns.get(skill_id, 0))


func _set_player_skill_cooldown(player_index: int, skill_id: String, turns: int) -> void:
	if player_index < 0 or player_index >= _players.size() or skill_id.is_empty():
		return

	var cooldowns: Dictionary = _players[player_index].get("skill_cooldowns", {}).duplicate(true)
	cooldowns[skill_id] = maxi(0, turns)
	_players[player_index]["skill_cooldowns"] = cooldowns


func _prepare_player_turn(player_index: int) -> void:
	if player_index < 0 or player_index >= _players.size():
		return

	_players[player_index]["temporary_guard_bonus"] = 0
	_players[player_index]["power_strike_ready"] = false

	var cooldowns: Dictionary = _players[player_index].get("skill_cooldowns", {}).duplicate(true)
	for skill_id in cooldowns.keys():
		cooldowns[skill_id] = maxi(0, int(cooldowns[skill_id]) - 1)
	_players[player_index]["skill_cooldowns"] = cooldowns


func _assign_bosses_to_board() -> void:
	var boss_cells := []
	for cell_id in _board.get("cells", {}).keys():
		var cell_data: Dictionary = _board["cells"][cell_id]
		if str(cell_data.get("type", "")) == "boss_entrance":
			boss_cells.append(str(cell_id))

	if boss_cells.is_empty() or _bosses_data.is_empty():
		return

	var shuffled_bosses := _bosses_data.duplicate(true)
	shuffled_bosses.shuffle()

	for cell_index in range(boss_cells.size()):
		var cell_id := str(boss_cells[cell_index])
		var boss_data: Dictionary = shuffled_bosses[cell_index % shuffled_bosses.size()]
		_boss_states[cell_id] = {
			"id": str(boss_data.get("id", "boss")),
			"name": str(boss_data.get("name", "Boss")),
			"hp": int(boss_data.get("hp", 12)),
			"max_hp": int(boss_data.get("hp", 12)),
			"exchange_count": int(boss_data.get("exchange_count", 3)),
			"reward_gold": int(boss_data.get("reward_gold", 6)),
			"reward_renown": int(boss_data.get("reward_renown", 4)),
			"trait": str(boss_data.get("trait", "")),
			"cleared": false
		}


func _resolve_start_turn_mob_encounter() -> bool:
	var player: Dictionary = _players[_current_player_index]
	var cell_id := str(player.get("cell_id", ""))
	var mob_id := _mob_id_on_cell(cell_id)
	if mob_id.is_empty():
		return false

	_append_log("%s starts the turn under pressure from a roaming mob." % player.get("name", "Player"))
	_resolve_mob_combat(_current_player_index, mob_id)
	if _force_end_turn_after_resolution:
		_force_end_turn_after_resolution = false
		_end_turn()
		return true

	return false


func _start_turn() -> void:
	if _is_game_over:
		return

	_turn_phase = TURN_PHASE_AWAIT_ROLL
	_turn_time_left = _turn_timer_for_player_count(_players.size())
	_last_roll = -1
	_current_move_steps = 0
	_major_action_used = false
	_quick_action_used = false
	_force_end_turn_after_resolution = false
	_reachable_cells.clear()
	_available_actions.clear()
	_animating_player_index = -1
	_prepare_player_turn(_current_player_index)

	var player: Dictionary = _players[_current_player_index]
	_append_log(
		"Round %d: %s (%s) starts at %s." %
		[
			_round_number,
			player.get("name", "Player"),
			player.get("origin_name", "Origin"),
			_cell_name(player.get("cell_id", ""))
		]
	)
	if _resolve_start_turn_mob_encounter():
		return
	_update_ui()
	_save_autosave()
	queue_redraw()


func _turn_timer_for_player_count(player_count: int) -> int:
	var timer_rules: Dictionary = _rules.get("turn_timers_seconds", {})
	if player_count <= 3:
		return int(timer_rules.get("2-3", 55))
	if player_count <= 6:
		return int(timer_rules.get("4-6", 50))
	return int(timer_rules.get("7-8", 40))


func _on_roll_pressed() -> void:
	if _turn_phase != TURN_PHASE_AWAIT_ROLL or _is_game_over:
		return

	_roll_current_turn(false)


func _on_end_turn_pressed() -> void:
	if _turn_phase != TURN_PHASE_READY_TO_END or _is_game_over:
		return

	_end_turn()


func _on_new_board_pressed() -> void:
	_show_main_menu("Resume the current match or start a fresh war table.")


func _on_continue_saved_match_pressed() -> void:
	if _load_autosave():
		_hide_main_menu()
	else:
		_show_main_menu("No valid crash save was found. Start a new match instead.")


func _on_new_match_selected(player_count: int) -> void:
	_hide_main_menu()
	_start_new_match(player_count)


func _on_close_menu_pressed() -> void:
	if _players.is_empty():
		return

	_hide_main_menu()


func _on_action_button_pressed(button_index: int) -> void:
	if button_index < 0 or button_index >= _available_actions.size():
		return
	if _turn_phase != TURN_PHASE_READY_TO_END:
		return

	var action: Dictionary = _available_actions[button_index]
	_perform_major_action(action)


func _roll_current_turn(is_auto: bool) -> void:
	var faces: Array = _rules.get("movement_die_faces", [1, 2, 2, 3, 3, 4])
	_last_roll = int(faces[_rng.randi_range(0, faces.size() - 1)])
	var mobility_bonus := _movement_bonus_for_player(_players[_current_player_index])
	_current_move_steps = _last_roll + mobility_bonus
	var current_cell_id := str(_players[_current_player_index].get("cell_id", ""))
	_reachable_cells = _build_reachable_cells(current_cell_id, _current_move_steps)
	var mobility_text := ""
	if mobility_bonus > 0:
		mobility_text = " plus %d mobility" % mobility_bonus

	if _reachable_cells.is_empty():
		_turn_phase = TURN_PHASE_READY_TO_END
		_append_log(
			"%s rolled %d%s but had no reachable destination." %
			[_players[_current_player_index].get("name", "Player"), _last_roll, mobility_text]
		)
	else:
		_turn_phase = TURN_PHASE_AWAIT_MOVE
		_append_log(
			"%s rolled %d%s and can move %d step(s) to %d cells%s." %
			[
				_players[_current_player_index].get("name", "Player"),
				_last_roll,
				mobility_text,
				_current_move_steps,
				_reachable_cells.size(),
				" automatically" if is_auto else ""
			]
		)

	_update_ui()
	queue_redraw()


func _build_reachable_cells(start_cell_id: String, max_steps: int) -> Dictionary:
	var adjacency: Dictionary = _board.get("adjacency", {})
	if not adjacency.has(start_cell_id):
		return {}

	var distances := {start_cell_id: 0}
	var parents := {}
	var queue := [start_cell_id]
	var queue_index := 0

	while queue_index < queue.size():
		var current_id := str(queue[queue_index])
		queue_index += 1
		var current_distance := int(distances[current_id])
		if current_distance >= max_steps:
			continue

		for neighbor in adjacency.get(current_id, []):
			var neighbor_id := str(neighbor)
			if distances.has(neighbor_id):
				continue

			distances[neighbor_id] = current_distance + 1
			parents[neighbor_id] = current_id
			queue.append(neighbor_id)

	var reachable := {}
	for cell_id in distances.keys():
		if cell_id == start_cell_id:
			continue

		var distance := int(distances[cell_id])
		if distance <= 0 or distance > max_steps:
			continue

		reachable[cell_id] = {
			"distance": distance,
			"path": _reconstruct_path(start_cell_id, cell_id, parents)
		}

	return reachable


func _reconstruct_path(start_cell_id: String, target_cell_id: String, parents: Dictionary) -> Array:
	var path := [target_cell_id]
	var cursor := target_cell_id

	while cursor != start_cell_id and parents.has(cursor):
		cursor = str(parents[cursor])
		path.push_front(cursor)

	return path


func _move_current_player_to(destination_cell_id: String, is_auto: bool) -> void:
	if not _reachable_cells.has(destination_cell_id):
		return
	if _animating_player_index != -1:
		return

	var player: Dictionary = _players[_current_player_index]
	var path: Array = _reachable_cells[destination_cell_id].get("path", [])
	if path.size() < 2:
		_turn_phase = TURN_PHASE_READY_TO_END
		return

	_turn_phase = TURN_PHASE_MOVING
	_animating_player_index = _current_player_index
	_reachable_cells.clear()
	_available_actions.clear()
	_append_log(
		"%s heads to %s%s." %
		[
			player.get("name", "Player"),
			_cell_name(destination_cell_id),
			" as time expires" if is_auto else ""
		]
	)
	_animate_player_path(_current_player_index, path, destination_cell_id)
	_update_ui()
	queue_redraw()


func _animate_player_path(player_index: int, path: Array, destination_cell_id: String) -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)

	var from_position := _cell_world_position(str(path[0]))
	for step_index in range(1, path.size()):
		var to_position := _cell_world_position(str(path[step_index]))
		tween.tween_method(_set_player_board_position.bind(player_index), from_position, to_position, 0.14)
		from_position = to_position

	tween.finished.connect(_finish_player_move.bind(player_index, destination_cell_id))


func _set_player_board_position(world_position: Vector2, player_index: int) -> void:
	if player_index < 0 or player_index >= _players.size():
		return

	_players[player_index]["board_position"] = world_position
	queue_redraw()


func _finish_player_move(player_index: int, destination_cell_id: String) -> void:
	if player_index < 0 or player_index >= _players.size():
		return

	_players[player_index]["cell_id"] = destination_cell_id
	_players[player_index]["board_position"] = _cell_world_position(destination_cell_id)
	_animating_player_index = -1
	_resolve_destination(destination_cell_id)


func _resolve_destination(cell_id: String) -> void:
	var cell: Dictionary = _board.get("cells", {}).get(cell_id, {})
	var cell_type := str(cell.get("type", "neutral"))
	var player: Dictionary = _players[_current_player_index]
	var player_name := str(player.get("name", "Player"))
	var message := "%s arrives at %s." % [player_name, _cell_name(cell_id)]
	var mob_id := _mob_id_on_cell(cell_id)
	if not mob_id.is_empty():
		message += " A hostile mob blocks the route."
		_append_log(message)
		_resolve_mob_combat(_current_player_index, mob_id)
		if _force_end_turn_after_resolution:
			_force_end_turn_after_resolution = false
			_turn_phase = TURN_PHASE_READY_TO_END
			_available_actions.clear()
			_end_turn()
			return
		message = "%s holds the ground at %s." % [player_name, _cell_name(cell_id)]

	match cell_type:
		"event":
			var outcome := _resolve_event_result(_current_player_index)
			message += " " + outcome
		"shrine":
			message += " The shrine's calm restores 1 HP."
			_players[_current_player_index]["hp"] = min(
				int(player.get("max_hp", 0)),
				int(player.get("hp", 0)) + 1
			)
		"property":
			message += " This property can be claimed or upgraded in a later action pass."
		"shop":
			message += " A stocked shop waits here."
		"casino":
			message += " The casino tempts risky gold plays."
		"mob_den":
			message += " A hostile den stirs nearby."
		"boss_entrance":
			message += " A dungeon challenge is available here."
		"portal":
			message += " This is a shortcut node for later movement systems."
		_:
			message += " The path is quiet."

	if int(_players[_current_player_index].get("hp", 0)) <= 0:
		_append_log(message)
		_respawn_player(_current_player_index)
		_turn_phase = TURN_PHASE_READY_TO_END
		_available_actions.clear()
		_end_turn()
		return

	_turn_phase = TURN_PHASE_READY_TO_END
	_refresh_available_actions()
	_append_log(message)

	if _turn_time_left <= 0.0:
		_append_log("%s's time expired." % player_name)
		_end_turn()
	else:
		_update_ui()
		_save_autosave()
		queue_redraw()


func _resolve_event_result(player_index: int) -> String:
	var player: Dictionary = _players[player_index]
	var fortune := int(player.get("stats", {}).get("fortune", 0))
	var event_roll := _rng.randi_range(1, 6)
	var total := event_roll + fortune
	var reroll_text := ""

	if _player_has_origin(player_index, "trickster") and not bool(_trickster_reroll_claimed.get(player_index, false)) and total <= 4:
		var reroll := _rng.randi_range(1, 6)
		var reroll_total := reroll + fortune
		if reroll_total > total:
			total = reroll_total
			reroll_text = " Trickster instinct twists the odds."
			_trickster_reroll_claimed[player_index] = true

	if total <= 3:
		_players[player_index]["gold"] = max(0, int(_players[player_index].get("gold", 0)) - 2)
		_apply_damage_to_player(player_index, 1)
		return "Event roll %d: an ambush costs 2 gold and 1 HP.%s" % [total, reroll_text]
	if total <= 5:
		_players[player_index]["gold"] = int(_players[player_index].get("gold", 0)) + 3
		return "Event roll %d: a hidden cache grants +3 gold.%s" % [total, reroll_text]
	if total <= 7:
		_players[player_index]["hp"] = min(
			int(_players[player_index].get("max_hp", 0)),
			int(_players[player_index].get("hp", 0)) + 3
		)
		return "Event roll %d: a calm blessing restores 3 HP.%s" % [total, reroll_text]
	if total <= 9:
		_grant_renown(player_index, 1)
		return "Event roll %d: a daring moment earns +1 Renown.%s" % [total, reroll_text]

	_players[player_index]["gold"] = int(_players[player_index].get("gold", 0)) + 2
	_grant_renown(player_index, 1)
	return "Event roll %d: a major break grants +2 gold and +1 Renown.%s" % [total, reroll_text]


func _end_turn() -> void:
	if _players.is_empty():
		return

	var completed_player: Dictionary = _players[_current_player_index]
	_append_log(
		"%s ends the turn with %d HP, %d gold, %d Renown." %
		[
			completed_player.get("name", "Player"),
			completed_player.get("hp", 0),
			completed_player.get("gold", 0),
			completed_player.get("renown", 0)
		]
	)

	_current_player_index += 1
	if _current_player_index >= _players.size():
		_current_player_index = 0
		_run_world_phase()
		_round_number += 1
		if _should_finish_match_after_round_increment():
			_finish_match()
			return

	_start_turn()


func _run_world_phase() -> void:
	_reset_round_passives()
	var income_summaries := []
	for property_id in _property_states.keys():
		var property_state: Dictionary = _property_states[property_id]
		var owner_index := int(property_state.get("owner_index", -1))
		var level := int(property_state.get("level", 0))
		if owner_index < 0 or level <= 0:
			continue
		if bool(property_state.get("income_blocked", false)):
			property_state["income_blocked"] = false
			_property_states[property_id] = property_state
			continue

		var income := _property_income_for_level(level)
		_players[owner_index]["gold"] = int(_players[owner_index].get("gold", 0)) + income
		income_summaries.append(
			"%s +%d from %s" %
			[
				_players[owner_index].get("name", "Player"),
				income,
				_cell_name(property_id)
			]
		)

	if income_summaries.is_empty():
		_append_log("World phase: the board resets and no property income is paid yet.")
	else:
		_append_log("World phase: %s." % ", ".join(income_summaries))

	_run_mob_world_phase()
	_refresh_available_actions()


func _property_income_for_level(level: int) -> int:
	match level:
		1:
			return int(_rules.get("property_levels", {}).get("outpost", {}).get("income", 2))
		2:
			return int(_rules.get("property_levels", {}).get("estate", {}).get("income", 3))
		3:
			return int(_rules.get("property_levels", {}).get("stronghold", {}).get("income", 4))
		_:
			return 0


func _handle_turn_timeout() -> void:
	match _turn_phase:
		TURN_PHASE_AWAIT_ROLL:
			_roll_current_turn(true)
			if _turn_phase == TURN_PHASE_AWAIT_MOVE:
				var auto_destination := _pick_default_destination()
				if not auto_destination.is_empty():
					_move_current_player_to(auto_destination, true)
			elif _turn_phase == TURN_PHASE_READY_TO_END:
				_end_turn()
		TURN_PHASE_AWAIT_MOVE:
			var destination := _pick_default_destination()
			if destination.is_empty():
				_end_turn()
			else:
				_move_current_player_to(destination, true)
		TURN_PHASE_READY_TO_END:
			_end_turn()
		_:
			pass


func _pick_default_destination() -> String:
	var best_cell_id := ""
	var best_distance := -1

	for cell_id in _reachable_cells.keys():
		var distance := int(_reachable_cells[cell_id].get("distance", 0))
		if distance > best_distance:
			best_distance = distance
			best_cell_id = str(cell_id)
		elif distance == best_distance and str(cell_id) < best_cell_id:
			best_cell_id = str(cell_id)

	return best_cell_id


func _refresh_board_bounds() -> void:
	var cells: Dictionary = _board.get("cells", {})
	if cells.is_empty():
		_board_bounds = Rect2(-1.0, -1.0, 2.0, 2.0)
		return

	var min_point := Vector2(1000000.0, 1000000.0)
	var max_point := Vector2(-1000000.0, -1000000.0)

	for cell in cells.values():
		var cell_data: Dictionary = cell
		var position := _vector2_from_value(cell_data.get("position", Vector2.ZERO))
		min_point.x = min(min_point.x, position.x)
		min_point.y = min(min_point.y, position.y)
		max_point.x = max(max_point.x, position.x)
		max_point.y = max(max_point.y, position.y)

	_board_bounds = Rect2(min_point, max_point - min_point)
	if _board_bounds.size.x < 1.0:
		_board_bounds.size.x = 1.0
	if _board_bounds.size.y < 1.0:
		_board_bounds.size.y = 1.0


func _recalculate_board_transform() -> void:
	var board_rect := _get_board_rect()
	var padded_bounds := _board_bounds.grow(90.0)
	var safe_size := Vector2(max(padded_bounds.size.x, 1.0), max(padded_bounds.size.y, 1.0))
	var scale_x := board_rect.size.x / safe_size.x
	var scale_y := board_rect.size.y / safe_size.y

	_board_scale = min(scale_x, scale_y)
	var board_center := padded_bounds.position + padded_bounds.size * 0.5
	_board_offset = board_rect.position + board_rect.size * 0.5 - board_center * _board_scale


func _get_board_rect() -> Rect2:
	var left_edge := PANEL_MARGIN + LOG_PANEL_WIDTH + PANEL_GAP
	var right_edge := size.x - PANEL_MARGIN - INFO_PANEL_WIDTH - PANEL_GAP
	var top_edge := PANEL_MARGIN
	var bottom_edge := size.y - PANEL_MARGIN - ACTION_PANEL_HEIGHT - PANEL_GAP
	return Rect2(
		Vector2(left_edge, top_edge),
		Vector2(
			max(160.0, right_edge - left_edge),
			max(160.0, bottom_edge - top_edge)
		)
	)


func _draw_board_grid(board_rect: Rect2) -> void:
	var spacing := 48.0
	var grid_color := Color(1.0, 1.0, 1.0, 0.04)

	var x := board_rect.position.x
	while x <= board_rect.end.x:
		draw_line(Vector2(x, board_rect.position.y), Vector2(x, board_rect.end.y), grid_color, 1.0)
		x += spacing

	var y := board_rect.position.y
	while y <= board_rect.end.y:
		draw_line(Vector2(board_rect.position.x, y), Vector2(board_rect.end.x, y), grid_color, 1.0)
		y += spacing


func _draw_connections() -> void:
	for connection in _board.get("connections", []):
		if connection.size() < 2:
			continue

		var left_id := str(connection[0])
		var right_id := str(connection[1])
		var left_position := _world_to_screen(_cell_world_position(left_id))
		var right_position := _world_to_screen(_cell_world_position(right_id))
		draw_line(left_position + Vector2(0.0, 2.0), right_position + Vector2(0.0, 2.0), Color(0.0, 0.0, 0.0, 0.24), 7.0)
		draw_line(
			left_position,
			right_position,
			Color("3f5168"),
			4.0
		)


func _draw_cells() -> void:
	for cell_id in _board.get("cells", {}).keys():
		var cell: Dictionary = _board["cells"][cell_id]
		var screen_position := _world_to_screen(_cell_world_position(cell_id))
		var cell_type := str(cell.get("type", "neutral"))
		var base_color: Color = CELL_COLORS.get(cell_type, Color("64748b"))

		if _reachable_cells.has(cell_id):
			draw_circle(
				screen_position,
				CELL_RADIUS + 8.0,
				Color(base_color.r, base_color.g, base_color.b, 0.22)
			)

		draw_circle(screen_position + Vector2(0.0, 3.0), CELL_RADIUS, Color(0.0, 0.0, 0.0, 0.25))
		draw_circle(screen_position, CELL_RADIUS, base_color)
		draw_circle(screen_position, CELL_RADIUS + 2.0, base_color.lightened(0.3), false, 2.0)
		_draw_cell_icon(screen_position, cell_type)
		_draw_property_state_indicator(cell_id, screen_position)
		_draw_boss_state_indicator(cell_id, screen_position)

		if cell_id == _players[_current_player_index].get("cell_id", "") and _animating_player_index == -1:
			draw_circle(screen_position, CELL_RADIUS + 7.0, Color("f8fafc"), false, 2.0)

		if cell_id == _hovered_cell_id:
			draw_circle(screen_position, CELL_RADIUS + 12.0, Color("fde68a"), false, 2.0)
	if not _reachable_cells.is_empty():
		var current_player_cell := str(_players[_current_player_index].get("cell_id", ""))
		draw_circle(_world_to_screen(_cell_world_position(current_player_cell)), CELL_RADIUS + 10.0, Color("93c5fd"), false, 2.0)


func _draw_cell_icon(screen_position: Vector2, cell_type: String) -> void:
	var icon_color := Color("f8fafc")
	match cell_type:
		"shrine":
			draw_line(screen_position + Vector2(0.0, -7.0), screen_position + Vector2(0.0, 7.0), icon_color, 1.8)
			draw_line(screen_position + Vector2(-7.0, 0.0), screen_position + Vector2(7.0, 0.0), icon_color, 1.8)
			draw_line(screen_position + Vector2(-5.0, 0.0), screen_position + Vector2(0.0, -5.0), icon_color, 1.6)
			draw_line(screen_position + Vector2(5.0, 0.0), screen_position + Vector2(0.0, -5.0), icon_color, 1.6)
			draw_line(screen_position + Vector2(-5.0, 0.0), screen_position + Vector2(0.0, 5.0), icon_color, 1.6)
			draw_line(screen_position + Vector2(5.0, 0.0), screen_position + Vector2(0.0, 5.0), icon_color, 1.6)
		"shop":
			draw_rect(Rect2(screen_position + Vector2(-5.0, -2.0), Vector2(10.0, 8.0)), icon_color, false, 1.5)
			draw_line(screen_position + Vector2(-3.0, -2.0), screen_position + Vector2(-1.0, -6.0), icon_color, 1.5)
			draw_line(screen_position + Vector2(3.0, -2.0), screen_position + Vector2(1.0, -6.0), icon_color, 1.5)
			draw_line(screen_position + Vector2(-1.0, -6.0), screen_position + Vector2(1.0, -6.0), icon_color, 1.5)
		"event":
			draw_line(screen_position + Vector2(-6.0, 0.0), screen_position + Vector2(6.0, 0.0), icon_color, 1.8)
			draw_line(screen_position + Vector2(0.0, -6.0), screen_position + Vector2(0.0, 6.0), icon_color, 1.8)
			draw_line(screen_position + Vector2(-4.0, -4.0), screen_position + Vector2(4.0, 4.0), icon_color, 1.6)
			draw_line(screen_position + Vector2(-4.0, 4.0), screen_position + Vector2(4.0, -4.0), icon_color, 1.6)
		"casino":
			draw_rect(Rect2(screen_position + Vector2(-5.0, -5.0), Vector2(10.0, 10.0)), icon_color, false, 1.4)
			draw_circle(screen_position + Vector2(-2.5, -2.5), 1.1, icon_color)
			draw_circle(screen_position + Vector2(2.5, 0.0), 1.1, icon_color)
			draw_circle(screen_position + Vector2(-2.5, 2.5), 1.1, icon_color)
		"property":
			draw_rect(Rect2(screen_position + Vector2(-5.0, -1.0), Vector2(10.0, 7.0)), icon_color, false, 1.5)
			draw_line(screen_position + Vector2(-6.0, -1.0), screen_position + Vector2(0.0, -6.0), icon_color, 1.5)
			draw_line(screen_position + Vector2(6.0, -1.0), screen_position + Vector2(0.0, -6.0), icon_color, 1.5)
			draw_line(screen_position + Vector2(-1.5, 6.0), screen_position + Vector2(-1.5, 1.0), icon_color, 1.4)
			draw_line(screen_position + Vector2(1.5, 6.0), screen_position + Vector2(1.5, 1.0), icon_color, 1.4)
		"mob_den":
			draw_line(screen_position + Vector2(-5.5, 5.0), screen_position + Vector2(-1.5, -5.0), icon_color, 1.7)
			draw_line(screen_position + Vector2(-0.5, 5.0), screen_position + Vector2(2.5, -5.0), icon_color, 1.7)
			draw_line(screen_position + Vector2(4.5, 5.0), screen_position + Vector2(6.0, -2.0), icon_color, 1.7)
		"boss_entrance":
			draw_line(screen_position + Vector2(-6.0, 5.0), screen_position + Vector2(-6.0, 0.0), icon_color, 1.7)
			draw_line(screen_position + Vector2(6.0, 5.0), screen_position + Vector2(6.0, 0.0), icon_color, 1.7)
			draw_line(screen_position + Vector2(-6.0, 5.0), screen_position + Vector2(6.0, 5.0), icon_color, 1.7)
			draw_line(screen_position + Vector2(-6.0, 0.0), screen_position + Vector2(-2.0, -6.0), icon_color, 1.7)
			draw_line(screen_position + Vector2(-2.0, -6.0), screen_position + Vector2(0.0, -1.0), icon_color, 1.7)
			draw_line(screen_position + Vector2(0.0, -1.0), screen_position + Vector2(2.0, -6.0), icon_color, 1.7)
			draw_line(screen_position + Vector2(2.0, -6.0), screen_position + Vector2(6.0, 0.0), icon_color, 1.7)
		"portal":
			draw_circle(screen_position, 5.8, icon_color, false, 1.5)
			draw_circle(screen_position + Vector2(0.0, 0.5), 2.8, icon_color, false, 1.2)
		_:
			draw_circle(screen_position, 2.2, icon_color)


func _draw_property_state_indicator(cell_id: String, screen_position: Vector2) -> void:
	if not _property_states.has(cell_id):
		return

	var property_state: Dictionary = _property_states[cell_id]
	var owner_index := int(property_state.get("owner_index", -1))
	if owner_index >= 0 and owner_index < _players.size():
		var owner_color: Color = _players[owner_index].get("color", Color.WHITE)
		draw_circle(screen_position, CELL_RADIUS + 5.0, owner_color, false, 3.0)
		var level := int(property_state.get("level", 0))
		for pip_index in range(level):
			var pip_offset := -8.0 + float(pip_index) * 8.0
			draw_circle(screen_position + Vector2(pip_offset, CELL_RADIUS + 11.0), 2.4, owner_color)

	if bool(property_state.get("income_blocked", false)):
		draw_line(screen_position + Vector2(-9.0, -9.0), screen_position + Vector2(9.0, 9.0), Color("fda4af"), 2.0)


func _draw_boss_state_indicator(cell_id: String, screen_position: Vector2) -> void:
	var boss_state: Dictionary = _boss_states.get(cell_id, {})
	if boss_state.is_empty():
		return

	var ring_color := Color("fb923c") if not bool(boss_state.get("cleared", false)) else Color("64748b")
	draw_circle(screen_position, CELL_RADIUS + 8.0, ring_color, false, 2.0)


func _draw_mobs() -> void:
	for mob_id in _mob_states.keys():
		var mob_state: Dictionary = _mob_states[mob_id]
		var cell_id := str(mob_state.get("cell_id", ""))
		var base_position := _world_to_screen(_cell_world_position(cell_id))
		var offset := Vector2(0.0, -24.0)
		var screen_position := base_position + offset
		var is_elite := int(mob_state.get("reward_renown", 0)) > 0
		var mob_color := Color("7f1d1d") if not is_elite else Color("b45309")
		draw_circle(screen_position, 8.0, Color("020617"))
		draw_circle(screen_position, 6.0, mob_color)
		if cell_id == _hovered_cell_id:
			draw_circle(screen_position, 10.0, Color("fef08a"), false, 1.5)


func _draw_players() -> void:
	var cell_groups := {}
	for player_index in range(_players.size()):
		var player: Dictionary = _players[player_index]
		var cell_id := str(player.get("cell_id", ""))
		var stationary := _player_is_stationary(player_index)
		if stationary:
			if not cell_groups.has(cell_id):
				cell_groups[cell_id] = []
			cell_groups[cell_id].append(player_index)

	for player_index in range(_players.size()):
		var player: Dictionary = _players[player_index]
		var world_position := _vector2_from_value(player.get("board_position", Vector2.ZERO))
		var screen_position := _world_to_screen(world_position)

		if _player_is_stationary(player_index):
			var cell_id := str(player.get("cell_id", ""))
			var group: Array = cell_groups.get(cell_id, [])
			var slot := group.find(player_index)
			screen_position += _token_offset_for_slot(slot, group.size())

		var color: Color = player.get("color", Color.WHITE)
		draw_circle(screen_position, TOKEN_RADIUS + 2.0, Color("020617"))
		draw_circle(screen_position, TOKEN_RADIUS, color)
		draw_circle(screen_position, TOKEN_RADIUS + 0.5, color.lightened(0.3), false, 1.0)

		if player_index == _current_player_index:
			draw_circle(screen_position, TOKEN_RADIUS + 4.0, Color("f8fafc"), false, 1.5)


func _player_is_stationary(player_index: int) -> bool:
	var player: Dictionary = _players[player_index]
	var cell_id := str(player.get("cell_id", ""))
	return _vector2_from_value(player.get("board_position", Vector2.ZERO)).distance_to(_cell_world_position(cell_id)) < 0.1


func _token_offset_for_slot(slot: int, total: int) -> Vector2:
	if total <= 1:
		return Vector2.ZERO

	var radius := 13.0
	var angle := TAU * float(slot) / float(total)
	return Vector2.RIGHT.rotated(angle) * radius


func _cell_at_screen_position(screen_position: Vector2) -> String:
	_recalculate_board_transform()
	if not _get_board_rect().has_point(screen_position):
		return ""

	var best_cell_id := ""
	var best_distance := 30.0
	for cell_id in _board.get("cells", {}).keys():
		var candidate_distance := screen_position.distance_to(_world_to_screen(_cell_world_position(cell_id)))
		if candidate_distance < best_distance:
			best_distance = candidate_distance
			best_cell_id = str(cell_id)

	return best_cell_id


func _world_to_screen(world_position: Vector2) -> Vector2:
	return world_position * _board_scale + _board_offset


func _cell_world_position(cell_id: String) -> Vector2:
	var cells: Dictionary = _board.get("cells", {})
	if not cells.has(cell_id):
		return Vector2.ZERO

	var cell: Dictionary = cells[cell_id]
	return _vector2_from_value(cell.get("position", Vector2.ZERO))


func _cell_name(cell_id: String) -> String:
	var cells: Dictionary = _board.get("cells", {})
	if not cells.has(cell_id):
		return cell_id
	return str(cells[cell_id].get("name", cell_id))


func _vector2_from_value(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO


func _phase_description() -> String:
	match _turn_phase:
		TURN_PHASE_AWAIT_ROLL:
			return "Roll the travel die to begin the turn."
		TURN_PHASE_AWAIT_MOVE:
			return "Choose a highlighted destination up to %d steps away." % _current_move_steps
		TURN_PHASE_MOVING:
			return "Resolving movement and landing effects."
		TURN_PHASE_READY_TO_END:
			if not _major_action_used and not _quick_action_used:
				return "Turn resolved. Spend your major or quick action, then end the turn."
			if not _major_action_used:
				return "Quick action spent. One major action remains."
			if not _quick_action_used:
				return "Major action spent. A quick action can still be used."
			return "All action windows spent. End the turn to pass play."
		_:
			return "Preparing match state."


func _update_ui() -> void:
	if _title_label == null:
		return

	if _players.is_empty():
		_title_label.text = "Board Prototype"
		_status_label.text = "No match loaded."
		_turn_label.text = ""
		_timer_label.text = ""
		_roll_label.text = ""
		_roster_label.text = ""
		_hover_label.text = ""
		_detail_label.text = ""
		_log_label.text = ""
		return

	var current_player: Dictionary = _players[_current_player_index]
	var starter_skill_id := str(current_player.get("starter_skill_id", ""))
	var starter_skill: Dictionary = _skill_by_id(starter_skill_id)
	var starter_skill_name := str(starter_skill.get("name", "Starter Skill"))
	var starter_skill_cooldown := _player_skill_cooldown(_current_player_index, starter_skill_id)
	_title_label.text = "%s" % _rules.get("project_name", "Board Prototype")
	_status_label.text = _match_status_text()
	_turn_label.text = (
		"Round %d\n%s (%s)\nHP %d/%d   Gold %d   Renown %d\nMight %d   Guard %d   Arcana %d\nFortune %d   Mobility %d\nGear Atk %+d   Gear Def %+d\nSkill: %s%s" %
		[
			_round_number,
			current_player.get("name", "Player"),
			current_player.get("origin_name", "Origin"),
			current_player.get("hp", 0),
			current_player.get("max_hp", 0),
			current_player.get("gold", 0),
			current_player.get("renown", 0),
			current_player.get("stats", {}).get("might", 0),
			current_player.get("stats", {}).get("guard", 0),
			current_player.get("stats", {}).get("arcana", 0),
			current_player.get("stats", {}).get("fortune", 0),
			current_player.get("stats", {}).get("mobility", 0),
			current_player.get("weapon_bonus", 0),
			current_player.get("armor_bonus", 0),
			starter_skill_name,
			" (CD %d)" % starter_skill_cooldown if starter_skill_cooldown > 0 else ""
		]
	)
	_timer_label.text = "Turn Timer: %.1fs" % _turn_time_left
	if _last_roll < 0:
		_roll_label.text = "Travel Die: -"
	else:
		var bonus := maxi(0, _current_move_steps - _last_roll)
		if bonus > 0:
			_roll_label.text = "Travel Die: %d + %d mobility = %d steps" % [_last_roll, bonus, _current_move_steps]
		else:
			_roll_label.text = "Travel Die: %d steps" % _current_move_steps
	_roster_label.text = _format_roster_text()
	_hover_label.text = "Cell: %s" % (
		"None" if _hovered_cell_id.is_empty() else _cell_name(_hovered_cell_id)
	)
	_detail_label.text = _detail_text_for_hovered_cell()
	_log_label.text = _format_log_text()

	_roll_button.disabled = _turn_phase != TURN_PHASE_AWAIT_ROLL
	_end_turn_button.disabled = _turn_phase != TURN_PHASE_READY_TO_END
	_update_action_buttons()


func _detail_text_for_hovered_cell() -> String:
	if _hovered_cell_id.is_empty():
		return "Hover over a cell to inspect it.\n\nHighlighted cells become valid move targets after rolling.\nOwned properties show owner rings and level pips on the map."

	var cell: Dictionary = _board.get("cells", {}).get(_hovered_cell_id, {})
	var lines := [
		"%s" % cell.get("name", _hovered_cell_id),
		"Type: %s" % _humanize_key(str(cell.get("type", "neutral"))),
		"Links: %d" % _board.get("adjacency", {}).get(_hovered_cell_id, []).size()
	]

	if _reachable_cells.has(_hovered_cell_id):
		lines.append("Reachable this turn in %d step(s)." % int(_reachable_cells[_hovered_cell_id].get("distance", 0)))

	var player_indices := _player_indices_on_cell(_hovered_cell_id)
	if not player_indices.is_empty():
		var player_names := []
		for player_index in player_indices:
			player_names.append(str(_players[player_index].get("name", "Player")))
		lines.append("Players: %s" % ", ".join(player_names))

	if _property_states.has(_hovered_cell_id):
		var property_state: Dictionary = _property_states[_hovered_cell_id]
		var owner_index := int(property_state.get("owner_index", -1))
		if owner_index >= 0:
			lines.append("Owner: %s" % _players[owner_index].get("name", "Player"))
			lines.append("Level: %d" % int(property_state.get("level", 0)))
			if _player_has_origin(owner_index, "warden") and int(_players[owner_index].get("hp", 0)) > 0:
				lines.append("Ward Bonus: +1 defense")
		else:
			lines.append("Owner: Neutral")
		if bool(property_state.get("income_blocked", false)):
			lines.append("Income: Blocked until next world phase")

	var boss_state: Dictionary = _boss_states.get(_hovered_cell_id, {})
	if not boss_state.is_empty():
		lines.append("Boss: %s" % boss_state.get("name", "Boss"))
		lines.append("Boss Status: %s" % ("Cleared" if bool(boss_state.get("cleared", false)) else "Active"))
		if not bool(boss_state.get("cleared", false)):
			lines.append("Boss HP: %d/%d" % [boss_state.get("hp", 0), boss_state.get("max_hp", 0)])

	var cell_mobs := _mob_ids_on_cell(_hovered_cell_id)
	for mob_id in cell_mobs:
		var mob_state: Dictionary = _mob_states[mob_id]
		lines.append("Mob: %s (%d/%d HP)" % [mob_state.get("name", "Mob"), mob_state.get("hp", 0), mob_state.get("max_hp", 0)])

	return "\n".join(lines)


func _format_roster_text() -> String:
	var lines := []
	for player_index in range(_players.size()):
		var player: Dictionary = _players[player_index]
		var prefix := "> " if player_index == _current_player_index else "  "
		lines.append(
			"%s%s  HP %d/%d  G %d  R %d  @ %s" %
			[
				prefix,
				player.get("name", "Player"),
				player.get("hp", 0),
				player.get("max_hp", 0),
				player.get("gold", 0),
				player.get("renown", 0),
				_cell_name(str(player.get("cell_id", "")))
			]
		)

	return "\n".join(lines)


func _format_log_text() -> String:
	if _log_lines.is_empty():
		return "Recent turns and combat will appear here."

	var lines := []
	for log_index in range(_log_lines.size() - 1, -1, -1):
		lines.append("- %s" % _log_lines[log_index])

	return "\n".join(lines)


func _update_action_buttons() -> void:
	for button_index in range(_action_buttons.size()):
		var action_button: Button = _action_buttons[button_index]
		if button_index >= _available_actions.size():
			action_button.visible = false
			action_button.disabled = true
			action_button.text = ""
			continue

		var action: Dictionary = _available_actions[button_index]
		var budget_type := str(action.get("budget_type", "major"))
		action_button.visible = true
		action_button.disabled = (
			_turn_phase != TURN_PHASE_READY_TO_END
			or (budget_type == "major" and _major_action_used)
			or (budget_type == "quick" and _quick_action_used)
		)
		if budget_type == "quick":
			_style_button(action_button, Color("0f766e"))
		else:
			_style_button(action_button, Color("374151"))
		action_button.text = str(action.get("label", "Action"))


func _refresh_available_actions() -> void:
	_available_actions.clear()
	if _players.is_empty() or _turn_phase != TURN_PHASE_READY_TO_END:
		return

	var player: Dictionary = _players[_current_player_index]
	var cell_id := str(player.get("cell_id", ""))
	var cell: Dictionary = _board.get("cells", {}).get(cell_id, {})
	var cell_type := str(cell.get("type", "neutral"))
	var opponents := _other_player_indices_on_cell(cell_id, _current_player_index)
	var starter_skill_id := str(player.get("starter_skill_id", ""))
	var starter_skill_cooldown := _player_skill_cooldown(_current_player_index, starter_skill_id)

	if not _major_action_used:
		for opponent_index in opponents:
			_available_actions.append(
				{
					"id": "attack_player",
					"label": "Attack %s" % _players[opponent_index].get("name", "Player"),
					"target_player_index": opponent_index,
					"budget_type": "major"
				}
			)

		match cell_type:
			"property":
				var property_state: Dictionary = _property_states.get(cell_id, {})
				var owner_index := int(property_state.get("owner_index", -1))
				var level := int(property_state.get("level", 0))
				var claim_cost := int(_rules.get("property_levels", {}).get("outpost", {}).get("claim_cost", 6))
				if owner_index == -1 and int(player.get("gold", 0)) >= claim_cost:
					_available_actions.append({"id": "claim_property", "label": "Claim Outpost", "budget_type": "major"})
				elif owner_index == _current_player_index and level < 3:
					var upgrade_cost := _property_upgrade_cost(level)
					if int(player.get("gold", 0)) >= upgrade_cost:
						_available_actions.append({"id": "upgrade_property", "label": "Upgrade Property", "budget_type": "major"})
				elif owner_index >= 0 and owner_index != _current_player_index:
					_available_actions.append({"id": "raid_property", "label": "Raid Property", "budget_type": "major"})
			"shrine":
				if int(player.get("hp", 0)) < int(player.get("max_hp", 0)) and int(player.get("gold", 0)) >= 3:
					_available_actions.append({"id": "heal_at_shrine", "label": "Heal 6 HP", "budget_type": "major"})
				var train_cost := _training_cost_for_player(player)
				if train_cost > 0 and int(player.get("gold", 0)) >= train_cost:
					_available_actions.append({"id": "train_signature_stat", "label": "Train Signature Stat", "budget_type": "major"})
			"shop":
				if int(player.get("gold", 0)) >= 5 and int(player.get("weapon_bonus", 0)) < 2:
					_available_actions.append({"id": "buy_weapon_upgrade", "label": "Sharpen Blade", "budget_type": "major"})
				if int(player.get("gold", 0)) >= 5 and int(player.get("armor_bonus", 0)) < 2:
					_available_actions.append({"id": "buy_armor_upgrade", "label": "Reinforce Mail", "budget_type": "major"})
			"casino":
				if int(player.get("gold", 0)) >= 3:
					_available_actions.append({"id": "casino_coin_flip", "label": "Coin Flip", "budget_type": "major"})
			"boss_entrance":
				var boss_state: Dictionary = _boss_states.get(cell_id, {})
				if not bool(boss_state.get("cleared", false)):
					_available_actions.append(
						{
							"id": "challenge_boss",
							"label": "Fight %s" % boss_state.get("name", "Boss"),
							"budget_type": "major"
						}
					)

		if starter_skill_id == "arc_bolt" and starter_skill_cooldown <= 0:
			for arc_action in _arc_bolt_actions_for_player(_current_player_index):
				_available_actions.append(arc_action)

	if not _quick_action_used and starter_skill_cooldown <= 0:
		match starter_skill_id:
			"power_strike":
				if not bool(player.get("power_strike_ready", false)) and _current_turn_has_physical_target(cell_id):
					_available_actions.append({"id": "power_strike", "label": "Quick: Power Strike", "budget_type": "quick"})
			"hold_fast":
				if int(player.get("temporary_guard_bonus", 0)) <= 0:
					_available_actions.append({"id": "hold_fast", "label": "Quick: Hold Fast", "budget_type": "quick"})
			"shadowstep":
				if _major_action_used:
					for destination_cell_id in _shadowstep_destination_options(cell_id):
						_available_actions.append(
							{
								"id": "shadowstep",
								"label": "Quick: Step to %s" % _cell_name(destination_cell_id),
								"target_cell_id": destination_cell_id,
								"budget_type": "quick"
							}
						)


func _current_turn_has_physical_target(cell_id: String) -> bool:
	if not _other_player_indices_on_cell(cell_id, _current_player_index).is_empty():
		return true
	if not _mob_id_on_cell(cell_id).is_empty():
		return true
	if _property_states.has(cell_id):
		var property_state: Dictionary = _property_states[cell_id]
		var owner_index := int(property_state.get("owner_index", -1))
		if owner_index >= 0 and owner_index != _current_player_index:
			return true
	var boss_state: Dictionary = _boss_states.get(cell_id, {})
	return not boss_state.is_empty() and not bool(boss_state.get("cleared", false))


func _cells_within_steps(start_cell_id: String, max_steps: int) -> Dictionary:
	var result := _build_reachable_cells(start_cell_id, max_steps)
	result[start_cell_id] = {"distance": 0, "path": [start_cell_id]}
	return result


func _arc_bolt_actions_for_player(player_index: int) -> Array:
	var actions := []
	if player_index < 0 or player_index >= _players.size():
		return actions

	var player: Dictionary = _players[player_index]
	var cells_in_range: Dictionary = _cells_within_steps(str(player.get("cell_id", "")), 3)
	for cell_id in cells_in_range.keys():
		for opponent_index in _other_player_indices_on_cell(str(cell_id), player_index):
			actions.append(
				{
					"id": "arc_bolt_player",
					"label": "Arc Bolt %s" % _players[opponent_index].get("name", "Player"),
					"target_player_index": opponent_index,
					"budget_type": "major"
				}
			)

		for mob_id in _mob_ids_on_cell(str(cell_id)):
			actions.append(
				{
					"id": "arc_bolt_mob",
					"label": "Arc Bolt %s" % _mob_states[mob_id].get("name", "Mob"),
					"target_mob_id": mob_id,
					"budget_type": "major"
				}
			)

		var boss_state: Dictionary = _boss_states.get(str(cell_id), {})
		if not boss_state.is_empty() and not bool(boss_state.get("cleared", false)):
			actions.append(
				{
					"id": "arc_bolt_boss",
					"label": "Arc Bolt %s" % boss_state.get("name", "Boss"),
					"target_boss_cell_id": str(cell_id),
					"budget_type": "major"
				}
			)

	if actions.size() > 4:
		actions = actions.slice(0, 4)
	return actions


func _shadowstep_destination_options(start_cell_id: String) -> Array:
	var destinations := []
	var scored_destinations := []
	var reachable: Dictionary = _build_reachable_cells(start_cell_id, 2)
	for cell_id_variant in reachable.keys():
		var cell_id := str(cell_id_variant)
		if cell_id == start_cell_id:
			continue
		var cell: Dictionary = _board.get("cells", {}).get(cell_id, {})
		var cell_type := str(cell.get("type", "neutral"))
		var score := 0
		match cell_type:
			"property":
				score = 5
			"shop", "shrine":
				score = 4
			"event", "casino":
				score = 3
			"boss_entrance", "portal":
				score = 2
			_:
				score = 1
		if not _other_player_indices_on_cell(cell_id, _current_player_index).is_empty():
			score += 2
		scored_destinations.append({"cell_id": cell_id, "score": score, "distance": int(reachable[cell_id].get("distance", 0))})

	scored_destinations.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("score", 0)) != int(b.get("score", 0)):
			return int(a.get("score", 0)) > int(b.get("score", 0))
		if int(a.get("distance", 0)) != int(b.get("distance", 0)):
			return int(a.get("distance", 0)) < int(b.get("distance", 0))
		return str(a.get("cell_id", "")) < str(b.get("cell_id", ""))
	)

	for scored in scored_destinations:
		destinations.append(str(scored.get("cell_id", "")))
		if destinations.size() >= 4:
			break

	return destinations


func _perform_major_action(action: Dictionary) -> void:
	var action_id := str(action.get("id", ""))
	var budget_type := str(action.get("budget_type", "major"))
	var player: Dictionary = _players[_current_player_index]
	var cell_id := str(player.get("cell_id", ""))
	var player_name := str(player.get("name", "Player"))
	var consumed := false

	match action_id:
		"power_strike":
			_players[_current_player_index]["power_strike_ready"] = true
			_set_player_skill_cooldown(_current_player_index, str(player.get("starter_skill_id", "")), int(_skill_by_id(str(player.get("starter_skill_id", ""))).get("cooldown", 2)))
			_append_log("%s primes Power Strike for the next physical hit this turn." % player_name)
			consumed = true
		"hold_fast":
			_players[_current_player_index]["temporary_guard_bonus"] = 2
			_set_player_skill_cooldown(_current_player_index, str(player.get("starter_skill_id", "")), int(_skill_by_id(str(player.get("starter_skill_id", ""))).get("cooldown", 3)))
			_append_log("%s braces with Hold Fast and gains +2 Guard until the next turn." % player_name)
			consumed = true
		"shadowstep":
			var destination_cell_id := str(action.get("target_cell_id", ""))
			if not destination_cell_id.is_empty():
				_players[_current_player_index]["cell_id"] = destination_cell_id
				_players[_current_player_index]["board_position"] = _cell_world_position(destination_cell_id)
				_set_player_skill_cooldown(_current_player_index, str(player.get("starter_skill_id", "")), int(_skill_by_id(str(player.get("starter_skill_id", ""))).get("cooldown", 3)))
				_append_log("%s slips through the lanes and shadowsteps to %s." % [player_name, _cell_name(destination_cell_id)])
				consumed = true
		"arc_bolt_player":
			consumed = _perform_arc_bolt_on_player(int(action.get("target_player_index", -1)))
		"arc_bolt_mob":
			consumed = _perform_arc_bolt_on_mob(str(action.get("target_mob_id", "")))
		"arc_bolt_boss":
			consumed = _perform_arc_bolt_on_boss(str(action.get("target_boss_cell_id", "")))
		"attack_player":
			consumed = _perform_player_attack(int(action.get("target_player_index", -1)))
		"claim_property":
			var claim_cost := int(_rules.get("property_levels", {}).get("outpost", {}).get("claim_cost", 6))
			if int(player.get("gold", 0)) >= claim_cost and _property_states.has(cell_id):
				_players[_current_player_index]["gold"] = int(player.get("gold", 0)) - claim_cost
				_property_states[cell_id]["owner_index"] = _current_player_index
				_property_states[cell_id]["level"] = 1
				_property_states[cell_id]["income_blocked"] = false
				_append_log("%s claimed %s as an Outpost for %d gold." % [player_name, _cell_name(cell_id), claim_cost])
				consumed = true
		"upgrade_property":
			if _property_states.has(cell_id):
				var state: Dictionary = _property_states[cell_id]
				var level := int(state.get("level", 0))
				var upgrade_cost := _property_upgrade_cost(level)
				if upgrade_cost > 0 and int(player.get("gold", 0)) >= upgrade_cost:
					state["level"] = level + 1
					_players[_current_player_index]["gold"] = int(player.get("gold", 0)) - upgrade_cost
					_property_states[cell_id] = state
					if int(state.get("level", 0)) == 3:
						var stronghold_renown := int(_rules.get("property_levels", {}).get("stronghold", {}).get("renown_on_upgrade", 1))
						_grant_renown(_current_player_index, stronghold_renown)
					_append_log(
						"%s upgraded %s to level %d for %d gold." %
						[player_name, _cell_name(cell_id), int(state.get("level", 0)), upgrade_cost]
					)
					consumed = true
		"raid_property":
			consumed = _perform_property_raid(cell_id)
		"heal_at_shrine":
			if int(player.get("gold", 0)) >= 3:
				_players[_current_player_index]["gold"] = int(player.get("gold", 0)) - 3
				_players[_current_player_index]["hp"] = min(
					int(player.get("max_hp", 0)),
					int(player.get("hp", 0)) + 6
				)
				_append_log("%s prayed at %s and restored 6 HP." % [player_name, _cell_name(cell_id)])
				consumed = true
		"train_signature_stat":
			consumed = _train_signature_stat()
		"buy_weapon_upgrade":
			if int(player.get("gold", 0)) >= 5 and int(player.get("weapon_bonus", 0)) < 2:
				_players[_current_player_index]["gold"] = int(player.get("gold", 0)) - 5
				_players[_current_player_index]["weapon_bonus"] = int(player.get("weapon_bonus", 0)) + 1
				_append_log("%s bought a weapon upgrade at %s." % [player_name, _cell_name(cell_id)])
				consumed = true
		"buy_armor_upgrade":
			if int(player.get("gold", 0)) >= 5 and int(player.get("armor_bonus", 0)) < 2:
				_players[_current_player_index]["gold"] = int(player.get("gold", 0)) - 5
				_players[_current_player_index]["armor_bonus"] = int(player.get("armor_bonus", 0)) + 1
				_append_log("%s bought an armor upgrade at %s." % [player_name, _cell_name(cell_id)])
				consumed = true
		"casino_coin_flip":
			consumed = _perform_casino_coin_flip()
		"challenge_boss":
			consumed = _perform_boss_challenge()
		_:
			pass

	if not consumed:
		return

	if budget_type == "quick":
		_quick_action_used = true
	else:
		_major_action_used = true
	_refresh_available_actions()
	_update_ui()
	_save_autosave()
	queue_redraw()
	if _force_end_turn_after_resolution:
		_force_end_turn_after_resolution = false
		_end_turn()


func _perform_property_raid(cell_id: String) -> bool:
	if not _property_states.has(cell_id):
		return false

	var player: Dictionary = _players[_current_player_index]
	var state: Dictionary = _property_states[cell_id]
	var owner_index := int(state.get("owner_index", -1))
	if owner_index < 0 or owner_index == _current_player_index:
		return false

	var owner: Dictionary = _players[owner_index]
	var player_name := str(player.get("name", "Player"))
	var raid_bonus: Dictionary = _consume_power_strike_bonus(_current_player_index, true)
	var raid_total := _rng.randi_range(1, 6) + int(player.get("stats", {}).get("might", 0)) + int(player.get("weapon_bonus", 0)) + int(raid_bonus.get("attack_bonus", 0))
	var defense_total := _rng.randi_range(1, 6) + _property_defense_rating(int(state.get("level", 0)), owner_index)
	var margin := raid_total - defense_total
	if margin <= 0:
		_append_log("%s failed to raid %s." % [player_name, _cell_name(cell_id)])
		return true

	var owner_gold := int(owner.get("gold", 0))
	var stolen_gold: int = int(min(4 if margin >= 3 else 3, owner_gold))
	var passive_text := ""
	if _player_has_origin(_current_player_index, "raider") and not bool(_raider_bonus_claimed.get(_current_player_index, false)) and stolen_gold < owner_gold:
		stolen_gold += 1
		_raider_bonus_claimed[_current_player_index] = true
		passive_text = " Raider instinct snatched 1 extra gold."
	_players[owner_index]["gold"] = max(0, int(owner.get("gold", 0)) - stolen_gold)
	_players[_current_player_index]["gold"] = int(player.get("gold", 0)) + stolen_gold
	_grant_renown(_current_player_index, 1)
	state["income_blocked"] = true

	var downgrade_text := ""
	if margin >= 5 and int(state.get("level", 0)) > 1:
		state["level"] = int(state.get("level", 0)) - 1
		downgrade_text = " The property was damaged and lost a level."

	_property_states[cell_id] = state
	_append_log(
		"%s raided %s, stole %d gold from %s, and blocked its next income.%s%s" %
		[player_name, _cell_name(cell_id), stolen_gold, owner.get("name", "Player"), downgrade_text, passive_text]
	)
	return true


func _train_signature_stat() -> bool:
	var player: Dictionary = _players[_current_player_index]
	var stat_name := str(player.get("signature_stat", "might"))
	var current_value := int(player.get("stats", {}).get(stat_name, 1))
	var cost := _training_cost_for_current_value(current_value)
	if cost <= 0 or int(player.get("gold", 0)) < cost:
		return false

	_players[_current_player_index]["gold"] = int(player.get("gold", 0)) - cost
	var stats: Dictionary = player.get("stats", {}).duplicate(true)
	stats[stat_name] = current_value + 1
	_players[_current_player_index]["stats"] = stats

	if stat_name == "guard":
		_players[_current_player_index]["max_hp"] = int(player.get("max_hp", 0)) + 2
		_players[_current_player_index]["hp"] = min(
			int(_players[_current_player_index].get("max_hp", 0)),
			int(player.get("hp", 0)) + 2
		)

	_append_log(
		"%s trained %s from %d to %d for %d gold." %
		[
			player.get("name", "Player"),
			_humanize_key(stat_name),
			current_value,
			current_value + 1,
			cost
		]
	)
	return true


func _perform_casino_coin_flip() -> bool:
	var player: Dictionary = _players[_current_player_index]
	if int(player.get("gold", 0)) < 3:
		return false

	_players[_current_player_index]["gold"] = int(player.get("gold", 0)) - 3
	var player_name := str(player.get("name", "Player"))
	var roll := _rng.randi_range(1, 6)
	var fortune := int(player.get("stats", {}).get("fortune", 0))
	var total := roll + fortune
	var reroll_text := ""
	if _player_has_origin(_current_player_index, "trickster") and not bool(_trickster_reroll_claimed.get(_current_player_index, false)) and total < 7:
		var reroll := _rng.randi_range(1, 6)
		var reroll_total := reroll + fortune
		if reroll_total > total:
			total = reroll_total
			reroll_text = " Trickster instinct forced a reroll."
			_trickster_reroll_claimed[_current_player_index] = true

	if total >= 7:
		_players[_current_player_index]["gold"] = int(_players[_current_player_index].get("gold", 0)) + 6
		_append_log("%s won the coin flip at the casino and came out ahead.%s" % [player_name, reroll_text])
	else:
		_append_log("%s lost the coin flip at the casino.%s" % [player_name, reroll_text])

	return true


func _consume_power_strike_bonus(player_index: int, is_physical: bool) -> Dictionary:
	if not is_physical or player_index < 0 or player_index >= _players.size():
		return {"attack_bonus": 0, "damage_bonus": 0}
	if not bool(_players[player_index].get("power_strike_ready", false)):
		return {"attack_bonus": 0, "damage_bonus": 0}

	_players[player_index]["power_strike_ready"] = false
	return {"attack_bonus": 2, "damage_bonus": 1}


func _player_guard_total(player: Dictionary) -> int:
	return int(player.get("stats", {}).get("guard", 0)) + int(player.get("armor_bonus", 0)) + int(player.get("temporary_guard_bonus", 0))


func _perform_arc_bolt_on_player(target_player_index: int) -> bool:
	if target_player_index < 0 or target_player_index >= _players.size():
		return false
	if _graph_distance_between_players(_current_player_index, target_player_index) > 3:
		return false

	var attacker: Dictionary = _players[_current_player_index]
	var defender: Dictionary = _players[target_player_index]
	var attack_total := _rng.randi_range(1, 6) + int(attacker.get("stats", {}).get("arcana", 0)) + 1
	var defense_total := _rng.randi_range(1, 6) + _player_guard_total(defender)
	var damage := maxi(1, attack_total - defense_total + 2)
	_apply_damage_to_player(target_player_index, damage)
	_set_player_skill_cooldown(_current_player_index, str(attacker.get("starter_skill_id", "")), int(_skill_by_id(str(attacker.get("starter_skill_id", ""))).get("cooldown", 2)))
	_append_log("%s hurls Arc Bolt at %s for %d damage." % [attacker.get("name", "Player"), defender.get("name", "Player"), damage])
	if int(_players[target_player_index].get("hp", 0)) <= 0:
		_handle_player_defeat(_current_player_index, target_player_index)
	return true


func _perform_arc_bolt_on_mob(mob_id: String) -> bool:
	if not _mob_states.has(mob_id):
		return false
	if _graph_distance_from_current_player(str(_mob_states[mob_id].get("cell_id", ""))) > 3:
		return false

	var attacker: Dictionary = _players[_current_player_index]
	var mob_state: Dictionary = _mob_states[mob_id]
	var attack_total := _rng.randi_range(1, 6) + int(attacker.get("stats", {}).get("arcana", 0)) + 1
	var defense_total := _rng.randi_range(1, 6) + _monster_defense_value(mob_state)
	var damage := maxi(1, attack_total - defense_total + 2)
	mob_state["hp"] = int(mob_state.get("hp", 0)) - damage
	_set_player_skill_cooldown(_current_player_index, str(attacker.get("starter_skill_id", "")), int(_skill_by_id(str(attacker.get("starter_skill_id", ""))).get("cooldown", 2)))
	_append_log("%s zaps %s for %d damage with Arc Bolt." % [attacker.get("name", "Player"), mob_state.get("name", "Mob"), damage])
	if int(mob_state.get("hp", 0)) <= 0:
		_players[_current_player_index]["gold"] = int(_players[_current_player_index].get("gold", 0)) + int(mob_state.get("reward_gold", 2))
		_grant_renown(_current_player_index, int(mob_state.get("reward_renown", 0)))
		_append_log("%s collapsed under the spell." % mob_state.get("name", "Mob"))
		_mob_states.erase(mob_id)
	else:
		_mob_states[mob_id] = mob_state
	return true


func _perform_arc_bolt_on_boss(cell_id: String) -> bool:
	var boss_state: Dictionary = _boss_states.get(cell_id, {})
	if boss_state.is_empty() or bool(boss_state.get("cleared", false)):
		return false
	if _graph_distance_from_current_player(cell_id) > 3:
		return false

	var attacker: Dictionary = _players[_current_player_index]
	var attack_total := _rng.randi_range(1, 6) + int(attacker.get("stats", {}).get("arcana", 0)) + 1
	var defense_total := _rng.randi_range(1, 6) + _monster_defense_value(boss_state)
	var damage := maxi(1, attack_total - defense_total + 2)
	boss_state["hp"] = int(boss_state.get("hp", 0)) - damage
	_set_player_skill_cooldown(_current_player_index, str(attacker.get("starter_skill_id", "")), int(_skill_by_id(str(attacker.get("starter_skill_id", ""))).get("cooldown", 2)))
	_append_log("%s lashes %s with Arc Bolt for %d damage." % [attacker.get("name", "Player"), boss_state.get("name", "Boss"), damage])
	if int(boss_state.get("hp", 0)) <= 0:
		_players[_current_player_index]["gold"] = int(_players[_current_player_index].get("gold", 0)) + int(boss_state.get("reward_gold", 6))
		_grant_renown(_current_player_index, int(boss_state.get("reward_renown", 4)))
		boss_state["cleared"] = true
		boss_state["hp"] = 0
		_append_log("%s is blasted apart, and the dungeon reward is yours." % boss_state.get("name", "Boss"))
	_boss_states[cell_id] = boss_state
	return true


func _graph_distance_from_current_player(target_cell_id: String) -> int:
	return _graph_distance_between_cells(str(_players[_current_player_index].get("cell_id", "")), target_cell_id)


func _graph_distance_between_players(left_player_index: int, right_player_index: int) -> int:
	if left_player_index < 0 or left_player_index >= _players.size() or right_player_index < 0 or right_player_index >= _players.size():
		return 999
	return _graph_distance_between_cells(str(_players[left_player_index].get("cell_id", "")), str(_players[right_player_index].get("cell_id", "")))


func _graph_distance_between_cells(start_cell_id: String, target_cell_id: String) -> int:
	if start_cell_id == target_cell_id:
		return 0
	var adjacency: Dictionary = _board.get("adjacency", {})
	if not adjacency.has(start_cell_id) or not adjacency.has(target_cell_id):
		return 999

	var distances := {start_cell_id: 0}
	var queue := [start_cell_id]
	var queue_index := 0
	while queue_index < queue.size():
		var current_cell_id := str(queue[queue_index])
		queue_index += 1
		var current_distance := int(distances[current_cell_id])
		for neighbor_variant in adjacency.get(current_cell_id, []):
			var neighbor_id := str(neighbor_variant)
			if distances.has(neighbor_id):
				continue
			distances[neighbor_id] = current_distance + 1
			if neighbor_id == target_cell_id:
				return int(distances[neighbor_id])
			queue.append(neighbor_id)

	return 999


func _perform_player_attack(target_player_index: int) -> bool:
	if target_player_index < 0 or target_player_index >= _players.size():
		return false

	var attacker: Dictionary = _players[_current_player_index]
	var defender: Dictionary = _players[target_player_index]
	if str(attacker.get("cell_id", "")) != str(defender.get("cell_id", "")):
		return false

	var attack_damage := _roll_player_damage(_current_player_index, target_player_index, true)
	_apply_damage_to_player(target_player_index, attack_damage)
	_append_log(
		"%s strikes %s for %d damage." %
		[attacker.get("name", "Player"), defender.get("name", "Player"), attack_damage]
	)
	if int(_players[target_player_index].get("hp", 0)) <= 0:
		_handle_player_defeat(_current_player_index, target_player_index)
		return true

	var counter_damage := _roll_player_damage(target_player_index, _current_player_index, true)
	_apply_damage_to_player(_current_player_index, counter_damage)
	_append_log(
		"%s counters %s for %d damage." %
		[_players[target_player_index].get("name", "Player"), attacker.get("name", "Player"), counter_damage]
	)
	if int(_players[_current_player_index].get("hp", 0)) <= 0:
		_handle_player_defeat(target_player_index, _current_player_index)

	return true


func _perform_boss_challenge() -> bool:
	var player: Dictionary = _players[_current_player_index]
	var cell_id := str(player.get("cell_id", ""))
	var boss_state: Dictionary = _boss_states.get(cell_id, {})
	if boss_state.is_empty() or bool(boss_state.get("cleared", false)):
		return false

	var player_name := str(player.get("name", "Player"))
	var boss_name := str(boss_state.get("name", "Boss"))
	var exchange_count := int(boss_state.get("exchange_count", 3))

	for exchange_index in range(exchange_count):
		var player_damage := _roll_player_vs_monster_damage(_current_player_index, boss_state)
		boss_state["hp"] = int(boss_state.get("hp", 0)) - player_damage
		_append_log("%s hits %s for %d damage." % [player_name, boss_name, player_damage])
		if int(boss_state.get("hp", 0)) <= 0:
			_players[_current_player_index]["gold"] = int(_players[_current_player_index].get("gold", 0)) + int(boss_state.get("reward_gold", 6))
			_grant_renown(_current_player_index, int(boss_state.get("reward_renown", 4)))
			boss_state["cleared"] = true
			boss_state["hp"] = 0
			_boss_states[cell_id] = boss_state
			_append_log("%s defeated %s and claimed the dungeon reward." % [player_name, boss_name])
			return true

		var boss_damage := _roll_monster_damage_to_player(boss_state, _players[_current_player_index], true)
		_apply_damage_to_player(_current_player_index, boss_damage)
		_append_log("%s lashes back for %d damage." % [boss_name, boss_damage])
		if int(_players[_current_player_index].get("hp", 0)) <= 0:
			_boss_states[cell_id] = boss_state
			_respawn_player(_current_player_index)
			_force_end_turn_after_resolution = true
			return true

	_boss_states[cell_id] = boss_state
	_append_log("%s retreats from %s, leaving it wounded at %d HP." % [player_name, boss_name, boss_state.get("hp", 0)])
	return true


func _respawn_player(player_index: int) -> void:
	if player_index < 0 or player_index >= _players.size():
		return

	var player: Dictionary = _players[player_index]
	var lost_gold: int = int(max(3, int(floor(float(player.get("gold", 0)) * 0.25))))
	var remaining_gold: int = int(max(0, int(player.get("gold", 0)) - lost_gold))
	var restored_hp: int = maxi(1, int(ceil(float(player.get("max_hp", 1)) * 0.5)))
	_players[player_index]["gold"] = remaining_gold
	_players[player_index]["hp"] = restored_hp
	_players[player_index]["cell_id"] = "hub__sanctuary"
	_players[player_index]["board_position"] = _cell_world_position("hub__sanctuary")
	_append_log("%s was defeated, lost %d gold, and respawned at Sanctuary." % [player.get("name", "Player"), lost_gold])


func _signature_stat_for_origin(origin: Dictionary) -> String:
	var bonuses: Dictionary = origin.get("stat_bonuses", {})
	var best_stat := "might"
	var best_value := -1000
	for stat_name in bonuses.keys():
		var value := int(bonuses.get(stat_name, 0))
		if value > best_value:
			best_value = value
			best_stat = str(stat_name)
	return best_stat


func _training_cost_for_player(player: Dictionary) -> int:
	var stats: Dictionary = player.get("stats", {})
	var stat_name := str(player.get("signature_stat", "might"))
	return _training_cost_for_current_value(int(stats.get(stat_name, 1)))


func _training_cost_for_current_value(current_value: int) -> int:
	if current_value >= int(_rules.get("stat_caps", {}).get("hard_cap", 5)):
		return 0

	match current_value:
		1:
			return int(_rules.get("training_costs", {}).get("1_to_2", 5))
		2:
			return int(_rules.get("training_costs", {}).get("2_to_3", 7))
		3:
			return int(_rules.get("training_costs", {}).get("3_to_4", 9))
		4:
			return int(_rules.get("training_costs", {}).get("4_to_5", 11))
		_:
			return 0


func _property_upgrade_cost(current_level: int) -> int:
	match current_level:
		1:
			return int(_rules.get("property_levels", {}).get("estate", {}).get("upgrade_cost", 6))
		2:
			return int(_rules.get("property_levels", {}).get("stronghold", {}).get("upgrade_cost", 8))
		_:
			return 0


func _property_defense_rating(level: int, owner_index: int = -1) -> int:
	var rating := 0
	match level:
		1:
			rating = int(_rules.get("property_levels", {}).get("outpost", {}).get("defense_rating", 6))
		2:
			rating = int(_rules.get("property_levels", {}).get("estate", {}).get("defense_rating", 8))
		3:
			rating = int(_rules.get("property_levels", {}).get("stronghold", {}).get("defense_rating", 11))
		_:
			rating = 0

	if owner_index >= 0 and owner_index < _players.size() and _player_has_origin(owner_index, "warden") and int(_players[owner_index].get("hp", 0)) > 0:
		rating += 1

	return rating


func _grant_renown(player_index: int, amount: int) -> void:
	if amount <= 0 or player_index < 0 or player_index >= _players.size():
		return

	_players[player_index]["renown"] = int(_players[player_index].get("renown", 0)) + amount
	_check_final_round_trigger(player_index)


func _check_final_round_trigger(player_index: int) -> void:
	if _final_round_triggered or _is_game_over:
		return

	if int(_players[player_index].get("renown", 0)) >= _renown_threshold():
		_final_round_triggered = true
		_final_round_target_round = _round_number + 1
		_append_log(
			"%s reached the Renown threshold. The current round will finish, then the final round begins." %
			[_players[player_index].get("name", "Player")]
		)


func _renown_threshold() -> int:
	var thresholds: Dictionary = _rules.get("renown_thresholds", {})
	if _players.size() <= 3:
		return int(thresholds.get("2-3", 12))
	if _players.size() <= 6:
		return int(thresholds.get("4-6", 14))
	return int(thresholds.get("7-8", 16))


func _should_finish_match_after_round_increment() -> bool:
	if _round_number > int(_rules.get("max_rounds", 10)):
		return true
	if _final_round_triggered and _round_number > _final_round_target_round:
		return true
	return false


func _finish_match() -> void:
	_is_game_over = true
	var winner_index := _find_leading_player_index()
	var winner: Dictionary = _players[winner_index]
	_winner_summary = "%s wins with %d Renown and %d gold." % [
		winner.get("name", "Player"),
		winner.get("renown", 0),
		winner.get("gold", 0)
	]
	_append_log("Match over: %s" % _winner_summary)
	_clear_autosave()
	_update_ui()


func _find_leading_player_index() -> int:
	var best_index := 0
	for player_index in range(1, _players.size()):
		if _is_player_ahead(player_index, best_index):
			best_index = player_index
	return best_index


func _is_player_ahead(candidate_index: int, incumbent_index: int) -> bool:
	var candidate: Dictionary = _players[candidate_index]
	var incumbent: Dictionary = _players[incumbent_index]
	if int(candidate.get("renown", 0)) != int(incumbent.get("renown", 0)):
		return int(candidate.get("renown", 0)) > int(incumbent.get("renown", 0))
	if int(candidate.get("gold", 0)) != int(incumbent.get("gold", 0)):
		return int(candidate.get("gold", 0)) > int(incumbent.get("gold", 0))
	return candidate_index < incumbent_index


func _match_status_text() -> String:
	if _is_game_over:
		return "Match over.\n%s" % _winner_summary

	var lines := [_phase_description(), "Renown Goal: %d" % _renown_threshold()]
	if _final_round_triggered:
		lines.append("Final Round: round %d" % _final_round_target_round)

	var leader_index := _find_leading_player_index()
	lines.append(
		"Leader: %s (%d Renown)" %
		[_players[leader_index].get("name", "Player"), _players[leader_index].get("renown", 0)]
	)
	return "\n".join(lines)


func _other_player_indices_on_cell(cell_id: String, excluded_index: int) -> Array:
	var result := []
	for player_index in range(_players.size()):
		if player_index == excluded_index:
			continue
		if str(_players[player_index].get("cell_id", "")) == cell_id:
			result.append(player_index)
	return result


func _player_indices_on_cell(cell_id: String) -> Array:
	var result := []
	for player_index in range(_players.size()):
		if str(_players[player_index].get("cell_id", "")) == cell_id:
			result.append(player_index)
	return result


func _mob_id_on_cell(cell_id: String) -> String:
	for mob_id in _mob_states.keys():
		var mob_state: Dictionary = _mob_states[mob_id]
		if str(mob_state.get("cell_id", "")) == cell_id:
			return str(mob_id)
	return ""


func _mob_ids_on_cell(cell_id: String) -> Array:
	var found := []
	for mob_id in _mob_states.keys():
		var mob_state: Dictionary = _mob_states[mob_id]
		if str(mob_state.get("cell_id", "")) == cell_id:
			found.append(str(mob_id))
	return found


func _resolve_mob_combat(player_index: int, mob_id: String) -> void:
	if not _mob_states.has(mob_id):
		return

	var player: Dictionary = _players[player_index]
	var mob_state: Dictionary = _mob_states[mob_id]
	var exchange_count := int(mob_state.get("exchange_count", 2))
	for exchange_index in range(exchange_count):
		var player_damage := _roll_player_vs_monster_damage(player_index, mob_state)
		mob_state["hp"] = int(mob_state.get("hp", 0)) - player_damage
		_append_log("%s hits %s for %d damage." % [player.get("name", "Player"), mob_state.get("name", "Mob"), player_damage])
		if int(mob_state.get("hp", 0)) <= 0:
			_players[player_index]["gold"] = int(_players[player_index].get("gold", 0)) + int(mob_state.get("reward_gold", 2))
			_grant_renown(player_index, int(mob_state.get("reward_renown", 0)))
			_append_log("%s defeated %s." % [player.get("name", "Player"), mob_state.get("name", "Mob")])
			_mob_states.erase(mob_id)
			return

		var mob_damage := _roll_monster_damage_to_player(mob_state, _players[player_index], false)
		_apply_damage_to_player(player_index, mob_damage)
		_append_log("%s mauls %s for %d damage." % [mob_state.get("name", "Mob"), player.get("name", "Player"), mob_damage])
		if int(_players[player_index].get("hp", 0)) <= 0:
			_respawn_player(player_index)
			_force_end_turn_after_resolution = true
			_mob_states[mob_id] = mob_state
			return

	_mob_states[mob_id] = mob_state


func _apply_damage_to_player(player_index: int, damage: int) -> void:
	if player_index < 0 or player_index >= _players.size():
		return

	_players[player_index]["hp"] = max(0, int(_players[player_index].get("hp", 0)) - damage)


func _handle_player_defeat(winner_index: int, loser_index: int) -> void:
	if winner_index >= 0 and winner_index < _players.size():
		_players[winner_index]["gold"] = int(_players[winner_index].get("gold", 0)) + int(_rules.get("rewards", {}).get("player_defeat_gold", 3))
		_grant_renown(winner_index, int(_rules.get("rewards", {}).get("player_defeat_renown", 2)))

	_append_log(
		"%s defeated %s in open combat." %
		[_players[winner_index].get("name", "Player"), _players[loser_index].get("name", "Player")]
	)
	_respawn_player(loser_index)
	if loser_index == _current_player_index:
		_force_end_turn_after_resolution = true


func _roll_player_damage(attacker_index: int, defender_index: int, is_physical: bool) -> int:
	var attacker: Dictionary = _players[attacker_index]
	var defender: Dictionary = _players[defender_index]
	var attack_bonus: Dictionary = _consume_power_strike_bonus(attacker_index, is_physical)
	var attack_total := _rng.randi_range(1, 6) + int(attacker.get("stats", {}).get("might", 0)) + int(attacker.get("weapon_bonus", 0)) + int(attack_bonus.get("attack_bonus", 0))
	var defense_total := _rng.randi_range(1, 6) + _player_guard_total(defender)
	return maxi(1, attack_total - defense_total + int(_rules.get("combat", {}).get("base_damage_bonus", 2)) + int(attack_bonus.get("damage_bonus", 0)))


func _roll_player_vs_monster_damage(player_index: int, monster_state: Dictionary) -> int:
	var player: Dictionary = _players[player_index]
	var physical_attack: int = int(player.get("stats", {}).get("might", 0)) + int(player.get("weapon_bonus", 0))
	var magic_attack: int = int(player.get("stats", {}).get("arcana", 0))
	var is_physical := physical_attack >= magic_attack
	var attack_stat: int = maxi(physical_attack, magic_attack)
	var attack_bonus: Dictionary = _consume_power_strike_bonus(player_index, is_physical)
	var attack_total: int = _rng.randi_range(1, 6) + attack_stat + int(attack_bonus.get("attack_bonus", 0))
	var defense_total := _rng.randi_range(1, 6) + _monster_defense_value(monster_state)
	return maxi(1, attack_total - defense_total + int(_rules.get("combat", {}).get("base_damage_bonus", 2)) + int(attack_bonus.get("damage_bonus", 0)))


func _roll_monster_damage_to_player(monster_state: Dictionary, player: Dictionary, is_boss: bool) -> int:
	var attack_total := _rng.randi_range(1, 6) + _monster_attack_value(monster_state, is_boss)
	var defense_total := _rng.randi_range(1, 6) + _player_guard_total(player)
	return maxi(1, attack_total - defense_total + int(_rules.get("combat", {}).get("base_damage_bonus", 2)))


func _monster_attack_value(monster_state: Dictionary, is_boss: bool) -> int:
	var hp_scale := int(ceil(float(monster_state.get("max_hp", 8)) / 4.0))
	return hp_scale + int(monster_state.get("exchange_count", 2)) + (2 if is_boss else 0)


func _monster_defense_value(monster_state: Dictionary) -> int:
	return int(ceil(float(monster_state.get("max_hp", 8)) / 5.0)) + int(monster_state.get("exchange_count", 2))


func _run_mob_world_phase() -> void:
	var events := []
	var den_cells := _cells_of_type("mob_den")
	for den_cell in den_cells:
		if not _mob_id_on_cell(den_cell).is_empty():
			continue
		if _rng.randf() <= 0.35:
			var spawned := _spawn_mob_at_den(den_cell)
			if not spawned.is_empty():
				events.append("%s emerges at %s" % [_mob_states[spawned].get("name", "Mob"), _cell_name(den_cell)])

	var moved_events := []
	var mob_ids := _mob_states.keys()
	for mob_id_variant in mob_ids:
		var mob_id := str(mob_id_variant)
		if not _mob_states.has(mob_id):
			continue
		var new_cell := _pick_mob_destination(_mob_states[mob_id])
		if new_cell.is_empty() or new_cell == str(_mob_states[mob_id].get("cell_id", "")):
			continue

		var old_cell := str(_mob_states[mob_id].get("cell_id", ""))
		_mob_states[mob_id]["cell_id"] = new_cell
		moved_events.append("%s prowls from %s to %s" % [_mob_states[mob_id].get("name", "Mob"), _cell_name(old_cell), _cell_name(new_cell)])

	if not events.is_empty():
		_append_log("Mob phase: %s." % ", ".join(events))
	if not moved_events.is_empty():
		_append_log("Mob movement: %s." % ", ".join(moved_events))


func _spawn_mob_at_den(cell_id: String) -> String:
	if _mobs_data.is_empty():
		return ""

	var pool := []
	for mob_data_variant in _mobs_data:
		var mob_data: Dictionary = mob_data_variant
		if str(mob_data.get("id", "")) == "elite_hunter" and _rng.randf() > 0.12:
			continue
		pool.append(mob_data)

	if pool.is_empty():
		pool = _mobs_data

	var chosen: Dictionary = pool[_rng.randi_range(0, pool.size() - 1)]
	var mob_id := "mob_%d" % _next_mob_instance_id
	_next_mob_instance_id += 1
	_mob_states[mob_id] = {
		"id": str(chosen.get("id", "mob")),
		"name": str(chosen.get("name", "Mob")),
		"cell_id": cell_id,
		"hp": int(chosen.get("hp", 6)),
		"max_hp": int(chosen.get("hp", 6)),
		"reward_gold": int(chosen.get("reward_gold", 2)),
		"reward_renown": int(chosen.get("reward_renown", 0)),
		"exchange_count": int(chosen.get("exchange_count", 2)),
		"attack_type": str(chosen.get("attack_type", "physical")),
		"trait": str(chosen.get("trait", "")),
		"home_den_cell_id": cell_id
	}
	return mob_id


func _pick_mob_destination(mob_state: Dictionary) -> String:
	var current_cell := str(mob_state.get("cell_id", ""))
	var adjacency: Dictionary = _board.get("adjacency", {})
	var options: Array = adjacency.get(current_cell, [])
	if options.is_empty():
		return current_cell

	var best_cell := current_cell
	var best_distance := INF
	var occupied_cells := {}
	for other_mob_id in _mob_states.keys():
		occupied_cells[str(_mob_states[other_mob_id].get("cell_id", ""))] = true

	for option_variant in options:
		var option := str(option_variant)
		if option != current_cell and occupied_cells.has(option):
			continue
		var distance := _distance_to_nearest_player(option)
		if distance < best_distance:
			best_distance = distance
			best_cell = option

	return best_cell


func _distance_to_nearest_player(cell_id: String) -> float:
	var distance := INF
	var world_position := _cell_world_position(cell_id)
	for player in _players:
		var player_cell := str(player.get("cell_id", ""))
		distance = min(distance, world_position.distance_to(_cell_world_position(player_cell)))
	return distance


func _cells_of_type(cell_type: String) -> Array:
	var found := []
	for cell_id in _board.get("cells", {}).keys():
		var cell_data: Dictionary = _board["cells"][cell_id]
		if str(cell_data.get("type", "")) == cell_type:
			found.append(str(cell_id))
	return found


func _humanize_key(key: String) -> String:
	return key.replace("_", " ").capitalize()


func _append_log(message: String) -> void:
	_log_lines.append(message)
	while _log_lines.size() > 12:
		_log_lines.pop_front()
	_update_ui()
