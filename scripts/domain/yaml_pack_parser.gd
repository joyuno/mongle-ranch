# GDScript YAML parser — scoped to the StudyGame quiz pack schema.
#
# Not a general YAML implementation. Only handles what the workbook plugin
# emits: 2-space indent, top-level `meta:` + `questions:`, per-question
# type/q/choices/answer/explanation/tags. Strings may be plain, single-quoted,
# double-quoted, or literal-block ('|'). Lists may be block (- item) or flow ([a, b]).
#
# Justification (vs bundling a third-party YAML addon):
# - Single-file, ~250 LOC, no runtime dependency
# - Schema-aware → can refuse ambiguous quoting the way the original
#   js-yaml FAILSAFE_SCHEMA + AB-010 single-quote rule does
# - Matches the workbook plugin output 1:1; broader YAML is out of scope

class_name YAMLPackParser
extends RefCounted


# Returns the same shape PackParser does:
# { "ok": true, "pack": Dictionary } or { "ok": false, "code": String, "message": String, "line": int }
static func parse(text: String) -> Dictionary:
	var lines := _strip_bom(text).split("\n")
	# Drop trailing empty / pure-comment lines (so end-of-file is predictable)
	while not lines.is_empty() and _is_blank_or_comment(lines[-1]):
		lines.resize(lines.size() - 1)
	if lines.is_empty():
		return _err("ERR_EMPTY_FILE", "빈 YAML 파일", 0)

	var pack: Dictionary = {}
	var i := 0
	while i < lines.size():
		var raw: String = lines[i]
		if _is_blank_or_comment(raw):
			i += 1
			continue
		var indent := _leading_spaces(raw)
		if indent != 0:
			return _err("ERR_YAML_INDENT",
				"최상위 키 앞에 들여쓰기가 있음 (line %d)" % (i + 1), i + 1)
		var key_value := _split_kv(raw)
		if key_value.is_empty():
			return _err("ERR_YAML_TOPLEVEL",
				"최상위는 'meta:' 또는 'questions:' 형태여야 함 (line %d): %s" % [i + 1, raw], i + 1)
		var key: String = key_value[0]
		var inline_value: String = key_value[1]
		match key:
			"meta":
				if not inline_value.is_empty():
					return _err("ERR_YAML_META", "meta 값이 inline이 아니어야 함 (line %d)" % (i + 1), i + 1)
				var meta_result := _parse_mapping(lines, i + 1, 2)
				if meta_result.has("error"):
					return meta_result["error"]
				pack["meta"] = meta_result["value"]
				i = meta_result["next_line"]
			"questions":
				if not inline_value.is_empty():
					return _err("ERR_YAML_QUESTIONS", "questions 값이 inline이 아니어야 함 (line %d)" % (i + 1), i + 1)
				var q_result := _parse_list_of_mappings(lines, i + 1, 2)
				if q_result.has("error"):
					return q_result["error"]
				pack["questions"] = q_result["value"]
				i = q_result["next_line"]
			_:
				return _err("ERR_YAML_UNKNOWN_KEY",
					"알 수 없는 최상위 키 '%s' (line %d) — meta/questions만 허용" % [key, i + 1], i + 1)
	return { "ok": true, "pack": pack }


# -----------------------------------------------------------------------------
# Mapping at a fixed indent — returns { "value": Dictionary, "next_line": int }
# or { "error": Dictionary }.
# -----------------------------------------------------------------------------
static func _parse_mapping(lines: PackedStringArray, start: int, expected_indent: int) -> Dictionary:
	var out: Dictionary = {}
	var i := start
	while i < lines.size():
		var raw: String = lines[i]
		if _is_blank_or_comment(raw):
			i += 1
			continue
		var indent := _leading_spaces(raw)
		if indent < expected_indent:
			break
		if indent > expected_indent:
			return { "error": _err("ERR_YAML_INDENT_DEEP",
				"예상 들여쓰기 %d 초과 (line %d, got %d)" % [expected_indent, i + 1, indent], i + 1) }
		var trimmed: String = raw.substr(expected_indent)
		if trimmed.begins_with("- "):
			break  # caller (list parser) handles this
		var kv := _split_kv(trimmed)
		if kv.is_empty():
			return { "error": _err("ERR_YAML_KEY_VALUE",
				"key: value 형태가 아님 (line %d): %s" % [i + 1, raw], i + 1) }
		var key: String = kv[0]
		var inline_value: String = kv[1]

		# Literal block scalar: 'key: |'
		if inline_value == "|" or inline_value == ">":
			var block := _consume_literal_block(lines, i + 1, expected_indent + 2, inline_value == ">")
			out[key] = block["value"]
			i = block["next_line"]
			continue

		# Nested mapping (key: \n with children at deeper indent)
		if inline_value.is_empty():
			# Peek next non-blank line. If deeper indent → nested.
			var next_meaningful := _next_meaningful_line(lines, i + 1)
			if next_meaningful != -1:
				var deeper_indent := _leading_spaces(lines[next_meaningful])
				if deeper_indent > expected_indent:
					var next_trim: String = lines[next_meaningful].substr(deeper_indent)
					if next_trim.begins_with("- "):
						# List of items
						var list_result := _parse_block_list(lines, i + 1, deeper_indent)
						if list_result.has("error"):
							return list_result
						out[key] = list_result["value"]
						i = list_result["next_line"]
						continue
					else:
						# Nested mapping
						var nested := _parse_mapping(lines, i + 1, deeper_indent)
						if nested.has("error"):
							return nested
						out[key] = nested["value"]
						i = nested["next_line"]
						continue
			out[key] = ""
			i += 1
			continue

		# Inline value — may be a folded plain scalar that continues on
		# deeper-indented lines (workbook output sometimes splits a long q
		# across lines). Absorb any line whose indent > the key's indent
		# into the value, joining with a single space; preserve blank lines
		# as paragraph breaks. Quoted/flow values were already handled by the
		# _parse_scalar branches above, so this fold only fires for plain ones.
		var folded := _absorb_plain_continuation(lines, i + 1, expected_indent, inline_value)
		out[key] = _parse_scalar(folded["value"])
		i = folded["next_line"]
	return { "value": out, "next_line": i }


# Read forward from `start`, folding lines whose indent is strictly greater
# than `key_indent` into `head` (joined by a single space; runs of blank
# lines collapse to a single newline so a code-fenced continuation reads
# correctly). Stops at the first line whose indent ≤ key_indent.
static func _absorb_plain_continuation(lines: PackedStringArray, start: int, key_indent: int, head: String) -> Dictionary:
	# Don't fold if head looks like a structured value (quoted / flow list /
	# block scalar marker). _parse_scalar would interpret these specially and
	# folding would corrupt them.
	var stripped_head := head.strip_edges()
	if stripped_head.begins_with("'") or stripped_head.begins_with("\"") \
			or stripped_head.begins_with("[") or stripped_head.begins_with("{") \
			or stripped_head == "|" or stripped_head == ">":
		return { "value": head, "next_line": start }

	var collected := head
	var trailing_blank_run := 0
	var j := start
	while j < lines.size():
		var raw: String = lines[j]
		if raw.strip_edges().is_empty():
			trailing_blank_run += 1
			j += 1
			continue
		var indent := _leading_spaces(raw)
		if indent <= key_indent:
			break
		if trailing_blank_run > 0:
			collected += "\n"
			trailing_blank_run = 0
		else:
			collected += " "
		collected += raw.substr(indent)
		j += 1
	# If the loop exited on a low-indent line, j is at that line — don't include
	# trailing blanks that came right before it (they belong to the inter-key gap).
	return { "value": collected, "next_line": j }


# -----------------------------------------------------------------------------
# Block list of mappings ('- type: mcq' followed by sibling key:value at +2)
# -----------------------------------------------------------------------------
static func _parse_list_of_mappings(lines: PackedStringArray, start: int, expected_indent: int) -> Dictionary:
	var out: Array = []
	var i := start
	while i < lines.size():
		var raw: String = lines[i]
		if _is_blank_or_comment(raw):
			i += 1
			continue
		var indent := _leading_spaces(raw)
		if indent < expected_indent:
			break
		if indent > expected_indent:
			return { "error": _err("ERR_YAML_LIST_INDENT",
				"list item 들여쓰기 어긋남 (line %d)" % (i + 1), i + 1) }
		var trimmed: String = raw.substr(expected_indent)
		if not trimmed.begins_with("- "):
			break
		# First key of the item lives on the same line as the dash.
		var first_kv_raw: String = trimmed.substr(2)
		var first_kv := _split_kv(first_kv_raw)
		if first_kv.is_empty():
			return { "error": _err("ERR_YAML_LIST_ITEM",
				"list item이 mapping이 아님 (line %d)" % (i + 1), i + 1) }
		var item: Dictionary = {}
		var inline_value: String = first_kv[1]
		if inline_value == "|" or inline_value == ">":
			var block := _consume_literal_block(lines, i + 1, expected_indent + 4, inline_value == ">")
			item[first_kv[0]] = block["value"]
			i = block["next_line"]
		elif not inline_value.is_empty():
			item[first_kv[0]] = _parse_scalar(inline_value)
			i += 1
		else:
			# 'key:' with body below
			var next_meaningful := _next_meaningful_line(lines, i + 1)
			if next_meaningful != -1:
				var deeper := _leading_spaces(lines[next_meaningful])
				if deeper > expected_indent + 2:
					var next_trim: String = lines[next_meaningful].substr(deeper)
					if next_trim.begins_with("- "):
						var list_result := _parse_block_list(lines, i + 1, deeper)
						if list_result.has("error"):
							return list_result
						item[first_kv[0]] = list_result["value"]
						i = list_result["next_line"]
					else:
						var nested := _parse_mapping(lines, i + 1, deeper)
						if nested.has("error"):
							return nested
						item[first_kv[0]] = nested["value"]
						i = nested["next_line"]
				else:
					item[first_kv[0]] = ""
					i += 1
			else:
				item[first_kv[0]] = ""
				i += 1

		# Now consume the rest of the item's mapping at indent + 2.
		var rest := _parse_mapping(lines, i, expected_indent + 2)
		if rest.has("error"):
			return rest
		var rest_map: Dictionary = rest["value"]
		for k in rest_map.keys():
			item[k] = rest_map[k]
		i = rest["next_line"]
		out.append(item)
	return { "value": out, "next_line": i }


# -----------------------------------------------------------------------------
# Block list of scalars  ('- a\n- b\n- c')
# -----------------------------------------------------------------------------
static func _parse_block_list(lines: PackedStringArray, start: int, expected_indent: int) -> Dictionary:
	var out: Array = []
	var i := start
	while i < lines.size():
		var raw: String = lines[i]
		if _is_blank_or_comment(raw):
			i += 1
			continue
		var indent := _leading_spaces(raw)
		if indent < expected_indent:
			break
		if indent > expected_indent:
			return { "error": _err("ERR_YAML_LIST_SCALAR_INDENT",
				"scalar list item 들여쓰기 어긋남 (line %d)" % (i + 1), i + 1) }
		var trimmed: String = raw.substr(expected_indent)
		if not trimmed.begins_with("- "):
			break
		out.append(_parse_scalar(trimmed.substr(2)))
		i += 1
	return { "value": out, "next_line": i }


# -----------------------------------------------------------------------------
# Literal / folded block scalar — capture lines until indent drops below
# `block_indent`. Leading whitespace equal to block_indent is stripped.
# -----------------------------------------------------------------------------
static func _consume_literal_block(lines: PackedStringArray, start: int, block_indent: int, folded: bool) -> Dictionary:
	var pieces: Array[String] = []
	var i := start
	while i < lines.size():
		var raw: String = lines[i]
		if raw.strip_edges().is_empty():
			pieces.append("")
			i += 1
			continue
		var indent := _leading_spaces(raw)
		if indent < block_indent:
			break
		pieces.append(raw.substr(block_indent))
		i += 1
	# Trim trailing blank lines
	while not pieces.is_empty() and pieces[-1].is_empty():
		pieces.resize(pieces.size() - 1)
	var joined: String
	if folded:
		# '>' folds non-empty consecutive lines with single space, blanks → newline
		var folded_pieces: Array[String] = []
		var buf := ""
		for p in pieces:
			if p.is_empty():
				if not buf.is_empty():
					folded_pieces.append(buf)
					buf = ""
				folded_pieces.append("")
			else:
				buf = p if buf.is_empty() else (buf + " " + p)
		if not buf.is_empty():
			folded_pieces.append(buf)
		joined = "\n".join(folded_pieces)
	else:
		joined = "\n".join(pieces)
	return { "value": joined, "next_line": i }


# -----------------------------------------------------------------------------
# Scalar interpretation — handles single/double quotes, inline flow lists,
# integers, booleans, null. AB-010 friendly: single quotes pass through cleanly.
# -----------------------------------------------------------------------------
static func _parse_scalar(text: String):
	var t := text.strip_edges()
	if t.is_empty():
		return ""

	# Inline flow list: [a, b, c] or [1, 2, 3]
	if t.begins_with("[") and t.ends_with("]"):
		var inner: String = t.substr(1, t.length() - 2)
		var arr: Array = []
		for part in _split_flow_list(inner):
			arr.append(_parse_scalar(part))
		return arr

	# Single-quoted
	if t.begins_with("'") and t.ends_with("'"):
		return t.substr(1, t.length() - 2).replace("''", "'")

	# Double-quoted
	if t.begins_with("\"") and t.ends_with("\""):
		var dq: String = t.substr(1, t.length() - 2)
		# Minimal escape handling
		dq = dq.replace("\\\"", "\"").replace("\\n", "\n").replace("\\t", "\t").replace("\\\\", "\\")
		return dq

	# Booleans
	if t == "true": return true
	if t == "false": return false

	# Null
	if t == "null" or t == "~":
		return null

	# Integer
	if t.is_valid_int():
		return int(t)

	# Float
	if t.is_valid_float():
		return float(t)

	# Plain scalar (everything else)
	return t


# Split "a, b, 'c, d', e" honoring quotes.
static func _split_flow_list(text: String) -> Array[String]:
	var out: Array[String] = []
	var depth := 0
	var quote_char := ""
	var buf := ""
	for ch in text:
		var s: String = ch
		if not quote_char.is_empty():
			buf += s
			if s == quote_char:
				quote_char = ""
			continue
		match s:
			"'", "\"":
				quote_char = s
				buf += s
			"[", "{":
				depth += 1
				buf += s
			"]", "}":
				depth -= 1
				buf += s
			",":
				if depth == 0:
					out.append(buf.strip_edges())
					buf = ""
				else:
					buf += s
			_:
				buf += s
	if not buf.strip_edges().is_empty():
		out.append(buf.strip_edges())
	return out


# -----------------------------------------------------------------------------
# Tokenization helpers
# -----------------------------------------------------------------------------
static func _split_kv(line: String) -> Array:
	# Returns [key, value] or [] if no colon. Honors quotes in the value.
	var stripped: String = line.strip_edges(true, false)  # trim only leading
	if stripped.begins_with("#"):
		return []
	# Find the first unquoted colon.
	var quote_char := ""
	for idx in stripped.length():
		var ch: String = stripped[idx]
		if not quote_char.is_empty():
			if ch == quote_char:
				quote_char = ""
			continue
		if ch == "'" or ch == "\"":
			quote_char = ch
			continue
		if ch == ":":
			# Must be followed by space or end-of-line to count as separator
			if idx == stripped.length() - 1 or stripped[idx + 1] == " ":
				var key: String = stripped.substr(0, idx).strip_edges()
				var value: String = stripped.substr(idx + 1).strip_edges()
				# Strip trailing inline comment ( ` # ... ` outside quotes)
				value = _strip_trailing_comment(value)
				return [key, value]
	return []


static func _strip_trailing_comment(value: String) -> String:
	var quote_char := ""
	for idx in value.length():
		var ch: String = value[idx]
		if not quote_char.is_empty():
			if ch == quote_char:
				quote_char = ""
			continue
		if ch == "'" or ch == "\"":
			quote_char = ch
			continue
		if ch == "#":
			if idx == 0 or value[idx - 1] == " ":
				return value.substr(0, idx).strip_edges(false, true)
	return value


static func _is_blank_or_comment(line: String) -> bool:
	var stripped: String = line.strip_edges()
	return stripped.is_empty() or stripped.begins_with("#")


static func _leading_spaces(line: String) -> int:
	var n := 0
	while n < line.length() and line[n] == " ":
		n += 1
	return n


static func _next_meaningful_line(lines: PackedStringArray, start: int) -> int:
	var i := start
	while i < lines.size():
		if not _is_blank_or_comment(lines[i]):
			return i
		i += 1
	return -1


static func _strip_bom(text: String) -> String:
	# UTF-8 BOM (EF BB BF) shows up in Notepad-saved files. Compare via
	# codepoint instead of a literal char — Godot's compressed-binary token
	# format (script_export_mode=2 in export) strips zero-width literals
	# from string constants at bake time, so `"﻿"` would compile to ""
	# and `begins_with("")` is true for every input — silently eating the
	# first character of every YAML file when run from a .pck.
	if text.length() > 0 and text.unicode_at(0) == 0xFEFF:
		return text.substr(1)
	return text


static func _err(code: String, message: String, line: int) -> Dictionary:
	return { "ok": false, "code": code, "message": message, "line": line }
