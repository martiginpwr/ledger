extends RefCounted
class_name BoardGenerator

const BOARD_RULES_PATH := "res://data/balance/board_generation.json"
const REGION_MODULES_PATH := "res://data/content/region_modules.json"
const ContentLoaderScript = preload("res://scripts/core/content_loader.gd")

var _rng := RandomNumberGenerator.new()
var _board_rules: Dictionary = {}
var _region_modules: Dictionary = {}


func _init(seed: int = 0) -> void:
	if seed == 0:
		_rng.randomize()
	else:
		_rng.seed = seed

	if ContentLoaderScript == null:
		push_error("ContentLoader script failed to preload.")
		return

	var loader = ContentLoaderScript.new()
	var board_rules: Variant = loader.load_json(BOARD_RULES_PATH)
	if typeof(board_rules) == TYPE_DICTIONARY:
		_board_rules = board_rules

	var region_modules: Variant = loader.load_json(REGION_MODULES_PATH)
	if typeof(region_modules) == TYPE_DICTIONARY:
		_region_modules = region_modules


func generate(player_count: int) -> Dictionary:
	if _board_rules.is_empty() or _region_modules.is_empty():
		push_error("Board generation data is missing.")
		return {}

	var template_key := _template_key_for_player_count(player_count)
	var templates: Dictionary = _board_rules.get("templates", {})
	var template: Dictionary = templates.get(template_key, {})
	if template.is_empty():
		push_error("No board template found for player count key %s." % template_key)
		return {}

	var hub_data: Dictionary = _region_modules.get("hub", {})
	var region_pool: Array = _region_modules.get("regions", [])
	if hub_data.is_empty() or region_pool.is_empty():
		push_error("Region module data is incomplete.")
		return {}

	var board := {
		"player_count": player_count,
		"template_key": template_key,
		"cells": {},
		"adjacency": {},
		"connections": [],
		"edge_keys": {},
		"metadata": {}
	}

	_instantiate_module(board, hub_data, "hub", Vector2.ZERO, 0.0)

	var wanted_regions := int(template.get("outer_regions", 0))
	var selected_regions: Array = _pick_regions(region_pool, wanted_regions)
	var selected_region_ids: Array = []
	var region_instances: Array = []
	var slot_layouts: Array = _slot_layouts_for_region_count(selected_regions.size())

	for index in range(selected_regions.size()):
		var region_data: Dictionary = selected_regions[index]
		var region_id := str(region_data.get("id", "region_%d" % index))
		var prefix := "region_%d_%s" % [index, region_id]
		var slot: Dictionary = slot_layouts[index]
		var anchor_point: Vector2 = slot.get("origin", Vector2.ZERO)
		var rotation: float = float(slot.get("rotation", 0.0))
		var hub_anchor_global_id := "hub__%s" % str(slot.get("hub_anchor", "gate_north"))

		var anchors: Dictionary = _instantiate_module(board, region_data, prefix, anchor_point, rotation)

		_connect_cells(board, hub_anchor_global_id, str(anchors.get("entry", "")))

		selected_region_ids.append(region_id)
		region_instances.append(
			{
				"region_id": region_id,
				"slot_index": index,
				"cross_links": anchors.get("cross_links", [])
			}
		)

	var created_cross_links := _create_cross_links(
		board,
		region_instances,
		_candidate_cross_link_slot_pairs(selected_regions.size()),
		int(template.get("cross_links", 0))
	)

	board["metadata"] = {
		"selected_regions": selected_region_ids,
		"cross_links": created_cross_links,
		"cell_type_counts": _count_cell_types(board.get("cells", {}))
	}

	board.erase("edge_keys")
	return board


func _template_key_for_player_count(player_count: int) -> String:
	if player_count <= 3:
		return "2-3"
	if player_count <= 6:
		return "4-6"
	return "7-8"


func _pick_regions(region_pool: Array, wanted_regions: int) -> Array:
	var candidates := region_pool.duplicate(true)
	var picked := []

	while picked.size() < wanted_regions and not candidates.is_empty():
		var index := _rng.randi_range(0, candidates.size() - 1)
		picked.append(candidates[index])
		candidates.remove_at(index)

	return picked


func _instantiate_module(
	board: Dictionary,
	module_data: Dictionary,
	prefix: String,
	origin: Vector2,
	rotation: float
) -> Dictionary:
	for raw_cell in module_data.get("cells", []):
		var cell_data: Dictionary = raw_cell.duplicate(true)
		var local_id := str(cell_data.get("id", "cell"))
		var global_id := "%s__%s" % [prefix, local_id]
		var local_position := _vector2_from_value(cell_data.get("position", [0, 0]))
		var world_position := origin + local_position.rotated(rotation)

		cell_data["id"] = global_id
		cell_data["local_id"] = local_id
		cell_data["module_id"] = prefix
		cell_data["position"] = world_position

		board["cells"][global_id] = cell_data
		board["adjacency"][global_id] = []

	for raw_connection in module_data.get("connections", []):
		if raw_connection.size() < 2:
			continue

		var from_id := "%s__%s" % [prefix, str(raw_connection[0])]
		var to_id := "%s__%s" % [prefix, str(raw_connection[1])]
		_connect_cells(board, from_id, to_id)

	var entry_global_id := ""
	var entry_local_id := str(module_data.get("entry_cell", ""))
	if not entry_local_id.is_empty():
		entry_global_id = "%s__%s" % [prefix, entry_local_id]

	var cross_link_globals := []
	for local_anchor in module_data.get("cross_link_cells", []):
		cross_link_globals.append("%s__%s" % [prefix, str(local_anchor)])

	return {
		"entry": entry_global_id,
		"cross_links": cross_link_globals
	}


func _create_cross_links(board: Dictionary, region_instances: Array, candidate_pairs: Array, desired_count: int) -> Array:
	var created := []
	var used_anchor_ids := {}

	for pair_variant in candidate_pairs:
		if created.size() >= desired_count:
			break
		var pair: Array = pair_variant
		if pair.size() < 2:
			continue
		var left_index := int(pair[0])
		var right_index := int(pair[1])
		if left_index >= region_instances.size() or right_index >= region_instances.size() or left_index == right_index:
			continue

		var left_region: Dictionary = region_instances[left_index]
		var right_region: Dictionary = region_instances[right_index]

		var left_anchor := _pick_unused_anchor(left_region.get("cross_links", []), used_anchor_ids)
		var right_anchor := _pick_unused_anchor(right_region.get("cross_links", []), used_anchor_ids)
		if left_anchor.is_empty() or right_anchor.is_empty():
			continue

		_connect_cells(board, left_anchor, right_anchor)
		used_anchor_ids[left_anchor] = true
		used_anchor_ids[right_anchor] = true
		created.append([left_anchor, right_anchor])

	return created


func _pick_unused_anchor(candidates: Array, used_anchor_ids: Dictionary) -> String:
	var available := []
	for candidate in candidates:
		var candidate_id := str(candidate)
		if not used_anchor_ids.has(candidate_id):
			available.append(candidate_id)

	if available.is_empty():
		return ""

	return available[_rng.randi_range(0, available.size() - 1)]


func _connect_cells(board: Dictionary, left_id: String, right_id: String) -> void:
	if left_id.is_empty() or right_id.is_empty():
		return
	if not board["cells"].has(left_id) or not board["cells"].has(right_id):
		return

	var edge_key := _normalized_edge_key(left_id, right_id)
	if board["edge_keys"].has(edge_key):
		return

	board["edge_keys"][edge_key] = true
	board["connections"].append([left_id, right_id])
	board["adjacency"][left_id].append(right_id)
	board["adjacency"][right_id].append(left_id)


func _normalized_edge_key(left_id: String, right_id: String) -> String:
	if left_id < right_id:
		return "%s|%s" % [left_id, right_id]
	return "%s|%s" % [right_id, left_id]


func _count_cell_types(cells: Dictionary) -> Dictionary:
	var counts := {}
	for cell in cells.values():
		var cell_data: Dictionary = cell
		var cell_type := str(cell_data.get("type", "unknown"))
		counts[cell_type] = int(counts.get(cell_type, 0)) + 1
	return counts


func _vector2_from_value(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO


func _cell_world_position(board: Dictionary, cell_id: String) -> Vector2:
	var cells: Dictionary = board.get("cells", {})
	if not cells.has(cell_id):
		return Vector2.ZERO

	var cell_data: Dictionary = cells[cell_id]
	return _vector2_from_value(cell_data.get("position", Vector2.ZERO))


func _slot_layouts_for_region_count(region_count: int) -> Array:
	match region_count:
		3:
			return [
				{"origin": Vector2(-220.0, -150.0), "rotation": PI, "hub_anchor": "gate_peak"},
				{"origin": Vector2(220.0, -150.0), "rotation": 0.0, "hub_anchor": "gate_east"},
				{"origin": Vector2(0.0, 255.0), "rotation": PI / 2.0, "hub_anchor": "gate_south"}
			]
		4:
			return [
				{"origin": Vector2(-220.0, -150.0), "rotation": PI, "hub_anchor": "gate_peak"},
				{"origin": Vector2(-220.0, 150.0), "rotation": PI, "hub_anchor": "gate_west"},
				{"origin": Vector2(220.0, -150.0), "rotation": 0.0, "hub_anchor": "gate_east"},
				{"origin": Vector2(220.0, 150.0), "rotation": 0.0, "hub_anchor": "gate_south"}
			]
		_:
			return [
				{"origin": Vector2(-220.0, -150.0), "rotation": PI, "hub_anchor": "gate_peak"},
				{"origin": Vector2(-220.0, 150.0), "rotation": PI, "hub_anchor": "gate_west"},
				{"origin": Vector2(220.0, -150.0), "rotation": 0.0, "hub_anchor": "gate_east"},
				{"origin": Vector2(220.0, 150.0), "rotation": 0.0, "hub_anchor": "gate_south"},
				{"origin": Vector2(0.0, -345.0), "rotation": -PI / 2.0, "hub_anchor": "gate_north"}
			]


func _candidate_cross_link_slot_pairs(region_count: int) -> Array:
	match region_count:
		3:
			return [[0, 1], [0, 2], [1, 2]]
		4:
			return [[0, 1], [2, 3], [0, 2], [1, 3]]
		_:
			return [[0, 1], [2, 3], [0, 4], [2, 4], [1, 3]]
