class_name Store
extends RefCounted

## Reads and writes tasks, focus entries and settings to user:// so they
## survive a restart. Every failure path is non-fatal: a missing or corrupt
## file just starts fresh.

const SAVE_VERSION := 2

## Overridable so tests can redirect to a scratch file.
static var default_path := "user://taskdesk.json"

var save_path := default_path
var tasks: Array[TaskData] = []
var entries: Array[FocusEntry] = []
var log_dir := FocusLog.DEFAULT_DIR

# Settings that live outside the round loop.
var work_seconds := 1500
var round_count := 4

func is_empty() -> bool:
	return tasks.is_empty()

func add_task(task: TaskData) -> void:
	tasks.append(task)

func clear() -> void:
	tasks.clear()

func clear_entries() -> void:
	entries.clear()

func all_tags() -> PackedStringArray:
	var seen: Array[String] = []
	for task in tasks:
		for tag in task.tags:
			if not seen.has(tag):
				seen.append(tag)
	seen.sort()
	return PackedStringArray(seen)

# Every tag that could be suggested, so the current task's tags are not
# suggested against while you are still typing them.
func suggest_tags(query: String, exclude: PackedStringArray = PackedStringArray(), limit := 6) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	var lowered := query.to_lower()

	for tag in all_tags():
		if exclude.has(tag):
			continue
		if lowered.is_empty() or tag.begins_with(lowered):
			result.append(tag)
			if result.size() >= limit:
				break

	return result

# ---- Focus entries: the source of truth for all stats ----

func add_entry(entry: FocusEntry) -> void:
	entries.append(entry)

func total_seconds() -> int:
	var sum := 0
	for entry in entries:
		sum += entry.seconds
	return sum

func total_minutes() -> int:
	return int(total_seconds() / 60.0)

## A session is a full set of rounds, so count entries that finished a
## complete round plus the number of full sets in the remainder.
func sessions_completed() -> int:
	if round_count <= 0:
		return 0
	var complete_rounds := 0
	for entry in entries:
		if entry.complete:
			complete_rounds += 1
	return int(complete_rounds / round_count)

func to_dict() -> Dictionary:
	var task_dicts: Array = []
	for task in tasks:
		task_dicts.append(task.to_dict())

	var entry_dicts: Array = []
	for entry in entries:
		entry_dicts.append(entry.to_dict())

	return {
		"version": SAVE_VERSION,
		"log_dir": log_dir,
		"work_seconds": work_seconds,
		"round_count": round_count,
		"tasks": task_dicts,
		"entries": entry_dicts,
	}

func save() -> bool:
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_warning("Store: could not open %s (error %d)" % [save_path, FileAccess.get_open_error()])
		return false

	file.store_string(JSON.stringify(to_dict(), "\t"))
	file.close()
	return true

func load_from_disk() -> bool:
	if not FileAccess.file_exists(save_path):
		return false

	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		push_warning("Store: could not read %s (error %d)" % [save_path, FileAccess.get_open_error()])
		return false

	var text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Store: save file is not valid JSON, starting fresh")
		return false

	var data: Dictionary = parsed

	log_dir = str(data.get("log_dir", FocusLog.DEFAULT_DIR))
	work_seconds = int(data.get("work_seconds", 1500))
	round_count = int(data.get("round_count", 4))

	tasks.clear()
	for entry in data.get("tasks", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var task := TaskData.from_dict(entry)
		if not task.get_title().is_empty():
			tasks.append(task)

	entries.clear()
	for entry_data in data.get("entries", []):
		if typeof(entry_data) != TYPE_DICTIONARY:
			continue
		var parsed_entry := FocusEntry.from_dict(entry_data)
		if parsed_entry.started_unix > 0:
			entries.append(parsed_entry)

	return true
