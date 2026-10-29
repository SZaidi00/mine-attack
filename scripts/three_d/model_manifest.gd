## R4 structure-model manifest (roadmap/3d-visual-revamp/02-asset-pipeline.md
## conventions 1-5): the source of truth for which textured GLB replaces which
## procedural structure recipe, and how the import must be normalized.
##
## The manifest lives in frost_mines_assets/models/model_manifest.json (plain
## JSON, not a .tres) so the CI budget gate tools/check_model_budgets.sh reads
## the exact same file — keep the two consumers in sync.
##
## Entry fields:
## - key: structure id used by StructureProxy3D ("building_player", ...).
## - path: res:// path of the imported .glb.
## - footprint: [w, h] target size in cells (CELL = 32 px of sim space); the
##   loader scales the model uniformly so its XZ bounds match footprint*CELL.
## - height: expected world-unit height AFTER normalization (recorded at
##   import time; informational for future LOD/variant work).
## - tri_gate: hard face-budget gate from 02-asset-pipeline.md convention 4.
## - accent_slots: lowercase material-name substrings rebound as faction
##   accents at load time ([] when the model ships no named accent material).
## - glow_slots: lowercase material-name substrings treated as emissive glow
##   ([] when window glow is baked into the albedo texture instead).
## - origin: "center" (XZ center at the node origin) or "corner" (origin on a
##   cell corner — mine entries; the loader adds the +CELL*0.5 shaft offset).
## - fallback_on_potato: keep the procedural recipe as the Potato fallback.
##
## Starter-set note (R4): every starter GLB ships exactly ONE material named
## "material_<uuid>" (Tripo API export) with the window/lamp glow baked into
## the albedo texture and no emissive slot, so accent_slots/glow_slots are
## honestly empty; accent/glow rebinding activates for future named models.
class_name ModelManifest
extends RefCounted

const MANIFEST_PATH := "res://frost_mines_assets/models/model_manifest.json"

## Face-budget gates from 02-asset-pipeline.md convention 4 — validate()
## rejects entries whose tri_gate is not one of these.
const TRI_GATES: Array[int] = [6000, 8000, 12000, 25000, 60000]

static var _entries: Array = []
static var _by_key: Dictionary = {}
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(MANIFEST_PATH):
		push_warning("ModelManifest: %s missing" % MANIFEST_PATH)
		return
	var text := FileAccess.get_file_as_string(MANIFEST_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not parsed is Array:
		push_warning("ModelManifest: %s is not a JSON array" % MANIFEST_PATH)
		return
	for e in parsed:
		if e is Dictionary and e.has("key"):
			_entries.append(e)
			_by_key[str(e["key"])] = e


## Manifest entry for a structure key, {} when missing.
static func entry_for(key: String) -> Dictionary:
	_load()
	return _by_key.get(key, {})


static func keys() -> Array:
	_load()
	var out: Array = []
	for e in _entries:
		out.append(str(e.get("key", "")))
	return out


## Human-readable problems with the manifest (empty = valid). The budget
## script checks files/tris; this checks the entry semantics so tests can
## assert the manifest stays honest as entries are added.
static func validate() -> PackedStringArray:
	_load()
	var problems := PackedStringArray()
	var seen := {}
	for e in _entries:
		var key := str(e.get("key", ""))
		if key.is_empty():
			problems.append("entry without a key")
			continue
		if seen.has(key):
			problems.append("duplicate key: %s" % key)
		seen[key] = true
		var path := str(e.get("path", ""))
		if path.is_empty():
			problems.append("%s: missing path" % key)
		elif not FileAccess.file_exists(path):
			problems.append("%s: file missing: %s" % [key, path])
		var origin := str(e.get("origin", ""))
		if origin != "center" and origin != "corner":
			problems.append("%s: unknown origin '%s'" % [key, origin])
		var fp: Variant = e.get("footprint", null)
		if fp == null or not fp is Array or fp.size() != 2 \
				or float(fp[0]) <= 0.0 or float(fp[1]) <= 0.0:
			problems.append("%s: footprint must be [w>0, h>0]" % key)
		if float(e.get("height", 0.0)) <= 0.0:
			problems.append("%s: height must be > 0" % key)
		if not int(e.get("tri_gate", 0)) in TRI_GATES:
			problems.append("%s: tri_gate %s not one of %s" % [key, e.get("tri_gate"), TRI_GATES])
		for slot_key in ["accent_slots", "glow_slots"]:
			if not e.get(slot_key, []) is Array:
				problems.append("%s: %s must be an array" % [key, slot_key])
	return problems
