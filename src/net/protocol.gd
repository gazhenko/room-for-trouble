class_name NetProtocol
extends RefCounted
## Message contract (§20.3). Client→server messages are bounded JSON objects
## with explicit schemas; unknown fields, forged seats, nonfinite numbers,
## invalid enums and oversized payloads are rejected without side effects.
## Server→client payloads are compressed var_to_bytes primitives (no objects).

const VERSION := 1
const MAX_HELLO := 2048
const MAX_INPUT := 1024
const MAX_OTHER := 8192
const CODE_ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"   # Crockford Base32

const SCHEMAS := {
	"hello": {"protocol": TYPE_FLOAT, "build_tag": TYPE_STRING, "content_hash": TYPE_STRING, "?probe": TYPE_BOOL},
	"create_room": {"local_seat_count": TYPE_FLOAT, "?chars": TYPE_ARRAY},
	"join_room": {"room_code": TYPE_STRING, "local_seat_count": TYPE_FLOAT, "?chars": TYPE_ARRAY},
	"reconnect": {"room_id": TYPE_STRING, "reconnect_token": TYPE_STRING, "last_ack": TYPE_FLOAT},
	"lobby_command": {"sequence": TYPE_FLOAT, "seat": TYPE_FLOAT, "action": TYPE_STRING, "?value": TYPE_NIL},
	"input_frame": {"shift_id": TYPE_FLOAT, "frames": TYPE_ARRAY},
	"leave_room": {},
	"heartbeat": {"sequence": TYPE_FLOAT, "t": TYPE_FLOAT},
	"result_ack": {"result_id": TYPE_STRING},
}
const LOBBY_ACTIONS := ["ready", "unready", "char", "cos", "select_level", "difficulty", "start", "start_ready",
	"pause", "resume", "skip", "leader_option", "assists", "modifiers", "seed", "mode"]

static func max_size(type: String) -> int:
	match type:
		"hello", "join_room", "create_room", "reconnect": return MAX_HELLO
		"input_frame": return MAX_INPUT
	return MAX_OTHER

## Returns {} when invalid, else the parsed message.
static func parse_client(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() > MAX_OTHER or bytes.size() < 2:
		return {}
	var txt := bytes.get_string_from_utf8()
	if txt.length() == 0:
		return {}
	var json := JSON.new()
	if json.parse(txt) != OK:
		return {}
	var d = json.data
	if not d is Dictionary or not d.has("type") or not d["type"] is String:
		return {}
	var t: String = d["type"]
	if not SCHEMAS.has(t):
		return {}
	if bytes.size() > max_size(t):
		return {}
	var schema: Dictionary = SCHEMAS[t]
	for k in d:
		if k == "type":
			continue
		if not schema.has(k) and not schema.has("?" + k):
			return {}
	for k in schema:
		var opt: bool = k.begins_with("?")
		var key: String = k.substr(1) if opt else k
		if not d.has(key):
			if opt:
				continue
			return {}
		var want: int = schema[k]
		if want != TYPE_NIL and typeof(d[key]) != want:
			return {}
		if typeof(d[key]) == TYPE_FLOAT and (is_nan(d[key]) or is_inf(d[key])):
			return {}
	if not _depth_ok(d, 0):
		return {}
	return d

static func _depth_ok(v, depth: int) -> bool:
	if depth > 6:
		return false
	if v is Dictionary:
		if v.size() > 64:
			return false
		for k in v:
			if not _depth_ok(v[k], depth + 1):
				return false
	elif v is Array:
		if v.size() > 64:
			return false
		for x in v:
			if not _depth_ok(x, depth + 1):
				return false
	return true

## Sanitises one input frame from the network into the sim's frame shape.
static func clean_frame(f) -> Dictionary:
	if not f is Dictionary:
		return {}
	for k in f:
		if not k in ["seat", "ax", "az", "held", "pressed", "pick", "seq"]:
			return {}
	var out := {}
	for k in ["seat", "ax", "az", "held", "pressed", "pick", "seq"]:
		var v = f.get(k, 0 if k != "pick" else -1)
		if not (v is float or v is int) or is_nan(float(v)) or is_inf(float(v)):
			return {}
		out[k] = int(v)
	if absi(out["ax"]) > 127 or absi(out["az"]) > 127:
		return {}
	if out["held"] < 0 or out["held"] > 255 or out["pressed"] < 0 or out["pressed"] > 255:
		return {}
	if out["pick"] < -1 or out["pick"] > 3:
		return {}
	return out

static func encode_client(d: Dictionary) -> PackedByteArray:
	return JSON.stringify(d).to_utf8_buffer()

static func encode_server(d: Dictionary) -> PackedByteArray:
	var raw := var_to_bytes(d)
	var c := raw.compress(FileAccess.COMPRESSION_DEFLATE)
	var out := PackedByteArray()
	out.resize(4)
	out.encode_u32(0, raw.size())
	out.append_array(c)
	return out

static func decode_server(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 4:
		return {}
	var n := bytes.decode_u32(0)
	if n > 4 * 1024 * 1024:
		return {}
	var raw := bytes.slice(4).decompress(n, FileAccess.COMPRESSION_DEFLATE)
	var v = bytes_to_var(raw)
	return v if v is Dictionary else {}

static func new_code(crypto: Crypto) -> String:
	var b := crypto.generate_random_bytes(8)
	var s := ""
	for i in 8:
		s += CODE_ALPHABET[b[i] % 32]
	return s

static func normalize_code(s: String) -> String:
	var out := ""
	for ch in s.to_upper():
		match ch:
			"O": out += "0"
			"I", "L": out += "1"
			"-", " ": pass
			_:
				if CODE_ALPHABET.contains(ch):
					out += ch
	return out

static func pretty_code(code: String) -> String:
	if code.length() == 8:
		return code.substr(0, 4) + "-" + code.substr(4, 4)
	return code
