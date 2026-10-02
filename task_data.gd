class_name TaskData
extends RefCounted

## A task's data, kept separate from its UI so it can be saved to disk.
## The TaskRow node is a view over one of these.

var title: String
var tags: PackedStringArray

func _init(p_title := "", p_tags := PackedStringArray()) -> void:
	title = p_title
	tags = p_tags

## Splits user input like 'write docs #work #urgent' into a title and tags.
## A word is a tag only if it is '#' followed by tag characters; anything
## else (including '##double') stays in the title.
static func parse_input(raw: String) -> TaskData:
	var title_parts: Array[String] = []
	var found: Array[String] = []

	for word in raw.split(" ", false):
		if _is_tag(word):
			var tag := word.substr(1).to_lower()
			if not found.has(tag):
				found.append(tag)
		else:
			title_parts.append(word)

	return TaskData.new(" ".join(title_parts), PackedStringArray(found))

static func _is_tag(word: String) -> bool:
	if not word.begins_with("#") or word.length() < 2:
		return false

	for i in range(1, word.length()):
		var code := word.unicode_at(i)
		var is_digit := code >= 48 and code <= 57
		var is_lower := code >= 97 and code <= 122
		var is_upper := code >= 65 and code <= 90
		if not (is_digit or is_lower or is_upper or word[i] == "_" or word[i] == "-"):
			return false

	return true

## Returns "" when there is nothing worth saving.
func get_title() -> String:
	return title.strip_edges()

func has_tags() -> bool:
	return tags.size() > 0

func to_dict() -> Dictionary:
	return {"title": title, "tags": Array(tags)}

static func from_dict(data: Dictionary) -> TaskData:
	var parsed_tags: PackedStringArray = PackedStringArray()
	for tag in data.get("tags", []):
		parsed_tags.append(str(tag).to_lower())

	return TaskData.new(str(data.get("title", "")), parsed_tags)
