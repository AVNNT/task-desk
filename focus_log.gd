class_name FocusLog
extends RefCounted

## Renders focus entries to markdown, one file per calendar day.
##
## Files are regenerated from the entry list rather than appended to, so a
## deleted or half-written log can always be rebuilt identically.

const DEFAULT_DIR := "user://focus"

static var log_dir := DEFAULT_DIR

static func set_log_dir(path: String) -> void:
	var trimmed := path.strip_edges()
	log_dir = trimmed if not trimmed.is_empty() else DEFAULT_DIR

static func path_for_day(day: String) -> String:
	return log_dir.path_join("%s.md" % day)

## Absolute form, for opening in a file manager.
static func absolute_dir() -> String:
	return ProjectSettings.globalize_path(log_dir)

static func entries_for_day(entries: Array[FocusEntry], day: String) -> Array[FocusEntry]:
	var result: Array[FocusEntry] = []
	for entry in entries:
		if entry.day_key() == day:
			result.append(entry)
	return result

static func days_in_order(entries: Array[FocusEntry]) -> PackedStringArray:
	# Most recent day first.
	var days: Array[String] = []
	for entry in entries:
		var day := entry.day_key()
		if not days.has(day):
			days.append(day)
	days.sort()
	days.reverse()
	return PackedStringArray(days)

static func render_day(day: String, entries: Array[FocusEntry]) -> String:
	var total_seconds := 0
	var complete_count := 0
	for entry in entries:
		total_seconds += entry.seconds
		if entry.complete:
			complete_count += 1

	var hours := int(total_seconds / 3600)
	var minutes := int(total_seconds % 3600 / 60)

	var summary := "%dm" % minutes
	if hours > 0:
		summary = "%dh %dm" % [hours, minutes]

	var lines: Array[String] = []
	lines.append("# %s" % day)
	lines.append("")
	lines.append("**%s focused · %d %s · %d of %d rounds complete**" % [
		summary,
		entries.size(),
		"round" if entries.size() == 1 else "rounds",
		complete_count,
		entries.size(),
	])
	lines.append("")
	lines.append("## Rounds")
	lines.append("")

	for entry in entries:
		var duration := "%dm" % entry.minutes()
		if entry.seconds < 60:
			duration = "%ds" % entry.seconds

		var tags := ""
		if not entry.tags.is_empty():
			var prefixes: Array[String] = []
			for tag in entry.tags:
				prefixes.append("#" + tag)
			tags = " · " + " ".join(prefixes)

		var result := "" if entry.complete else " · ended early"
		lines.append("- `%s` **%s**%s%s" % [entry.clock_string(), duration, tags, result])

	lines.append("")
	return "\n".join(lines)

## Rewrites the file for the days touched by these entries.
static func write_days(entries: Array[FocusEntry]) -> PackedStringArray:
	var written: PackedStringArray = PackedStringArray()

	var dir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(log_dir))
	if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
		push_warning("FocusLog: could not create %s (error %d)" % [log_dir, dir_error])
		return written

	for day in days_in_order(entries):
		var day_entries := entries_for_day(entries, day)
		if day_entries.is_empty():
			continue

		var file := FileAccess.open(path_for_day(day), FileAccess.WRITE)
		if file == null:
			push_warning("FocusLog: could not write %s (error %d)" % [day, FileAccess.get_open_error()])
			continue

		file.store_string(render_day(day, day_entries))
		file.close()
		written.append(path_for_day(day))

	return written
