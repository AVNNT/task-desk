class_name FocusEntry
extends RefCounted

## One completed pomodoro round. Entries are the source of truth: the totals
## shown in the stats bar are derived from this list, not tracked separately.

var started_unix := 0
var seconds := 0
var tags: PackedStringArray = PackedStringArray()
var complete := true

func _init(p_started_unix := 0, p_seconds := 0, p_tags := PackedStringArray(), p_complete := true) -> void:
	started_unix = p_started_unix
	seconds = p_seconds
	tags = p_tags
	complete = p_complete

func minutes() -> int:
	return int(seconds / 60.0)

## Local calendar day as YYYY-MM-DD, used to pick the log file.
## Must stay a valid filename: no colons or other Windows-reserved characters.
func day_key() -> String:
	return Time.get_date_string_from_unix_time(started_unix)

func clock_string() -> String:
	var d := Time.get_datetime_dict_from_unix_time(started_unix)
	return "%02d:%02d" % [d.hour, d.minute]

func to_dict() -> Dictionary:
	return {
		"started_unix": started_unix,
		"seconds": seconds,
		"tags": Array(tags),
		"complete": complete,
	}

static func from_dict(data: Dictionary) -> FocusEntry:
	var parsed: PackedStringArray = PackedStringArray()
	for tag in data.get("tags", []):
		parsed.append(str(tag).to_lower())

	return FocusEntry.new(
		int(data.get("started_unix", 0)),
		int(data.get("seconds", 0)),
		parsed,
		bool(data.get("complete", true))
	)
