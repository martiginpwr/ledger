extends RefCounted
class_name ContentLoader


func load_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Failed to open JSON file: %s" % path)
		return null

	var raw_text := file.get_as_text()
	var parsed: Variant = JSON.parse_string(raw_text)
	if parsed == null and raw_text.strip_edges() != "null":
		push_error("Failed to parse JSON file: %s" % path)

	return parsed
