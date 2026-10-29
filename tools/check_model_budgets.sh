#!/usr/bin/env bash
# R4 model budget gate (roadmap/3d-visual-revamp/02-asset-pipeline.md
# conventions 4-5): reads frost_mines_assets/models/model_manifest.json and
# verifies, per entry, that the GLB's triangle count stays under tri_gate and
# that no embedded texture exceeds 2048^2, plus the 64 MB total embedded-texture
# web budget across all entries.
#
# Uses trimesh when importable, else pygltflib, else a built-in pure-python
# GLB parser (GLB header + JSON chunk; that inline parser is the default on
# machines without those packages — do NOT pip install anything).
#
# Exit codes: 0 = PASS, 1 = budget FAIL, 2 = tooling error.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT/frost_mines_assets/models/model_manifest.json"

python3 - "$MANIFEST" "$ROOT" <<'PYEOF'
import json
import os
import struct
import sys

manifest_path = sys.argv[1]
project_root = sys.argv[2]
TOTAL_TEXTURE_BUDGET = 64 * 1024 * 1024
MAX_TEX_DIM = 2048

problems = []  # tooling errors -> exit 2
failures = []  # budget violations -> exit 1


def fail(msg):
    failures.append(msg)


def tool_error(msg):
    problems.append(msg)


# ── GLB parsing ──

class GLB:
    """Minimal GLB reader: JSON chunk + BIN chunk + image byte windows."""

    def __init__(self, path):
        with open(path, "rb") as f:
            data = f.read()
        if data[:4] != b"glTF":
            raise ValueError("not a GLB (bad magic)")
        _, version, _length = struct.unpack_from("<III", data, 0)
        if version != 2:
            raise ValueError("unsupported GLB version %d" % version)
        off = 12
        self.json = None
        self.bin_chunk = None
        while off + 8 <= len(data):
            clen, ctype = struct.unpack_from("<II", data, off)
            off += 8
            chunk = data[off:off + clen]
            off += clen
            if ctype == 0x4E4F534A:  # 'JSON'
                self.json = json.loads(chunk.decode("utf-8"))
            elif ctype == 0x004E4942:  # 'BIN'
                self.bin_chunk = chunk
        if self.json is None:
            raise ValueError("no JSON chunk")

    def tri_count(self):
        g = self.json
        total = 0
        for mesh in g.get("meshes", []):
            for prim in mesh.get("primitives", []):
                if "indices" in prim:
                    total += g["accessors"][prim["indices"]]["count"] // 3
                else:
                    total += g["accessors"][prim["attributes"]["POSITION"]]["count"] // 3
        return total

    def images(self):
        """Yield (name, byte_length, byte_window) per image. Embedded images
        are read from the BIN chunk; URI-referenced ones from disk next to
        the GLB."""
        g = self.json
        views = g.get("bufferViews", [])
        base = os.path.dirname(os.path.abspath(self.path)) if hasattr(self, "path") else ""
        for img in g.get("images", []):
            name = img.get("name", "?")
            if "bufferView" in img:
                view = views[img["bufferView"]]
                start = view.get("byteOffset", 0)
                end = start + view["byteLength"]
                yield name, view["byteLength"], self.bin_chunk[start:end] if self.bin_chunk else None
            elif "uri" in img:
                p = os.path.join(base, img["uri"])
                if os.path.isfile(p):
                    with open(p, "rb") as f:
                        yield name, os.path.getsize(p), f.read()
                else:
                    yield name, 0, None
                    tool_error("image missing on disk: %s" % p)
            else:
                tool_error("image with neither bufferView nor uri: %s" % name)


def jpeg_dims(data):
    # SOF markers carry height/width (big-endian) after a length field.
    off = 2
    while off + 9 < len(data):
        if data[off] != 0xFF:
            off += 1
            continue
        marker = data[off + 1]
        if marker in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7,
                      0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
            h, w = struct.unpack_from(">HH", data, off + 5)
            return w, h
        if marker in (0xD8, 0x01) or 0xD0 <= marker <= 0xD7:
            off += 2
            continue
        seg = struct.unpack_from(">H", data, off + 2)[0]
        off += 2 + seg
    return None


def png_dims(data):
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        w, h = struct.unpack_from(">II", data, 16)
        return w, h
    return None


def image_dims(data, mime):
    if data is None:
        return None
    if mime == "image/png" or data[:4] == b"\x89PNG":
        return png_dims(data)
    if mime == "image/jpeg" or data[:2] == b"\xff\xd8":
        return jpeg_dims(data)
    return None


# ── trimesh / pygltflib fast paths (used when installed) ──

def tris_via_trimesh(path):
    import trimesh  # type: ignore
    scene = trimesh.load(path, force="scene")
    total = 0
    for geom in scene.geometry.values():
        total += len(geom.faces) if hasattr(geom, "faces") else 0
    return total


def tris_via_pygltflib(path):
    from pygltflib import GLTF2  # type: ignore
    g = GLTF2().load_binary(path)
    total = 0
    for mesh in g.meshes or []:
        for prim in mesh.primitives or []:
            if prim.indices is not None:
                total += g.accessors[prim.indices].count // 3
            else:
                total += g.accessors[prim.attributes.POSITION].count // 3
    return total


def load_glb(path):
    glb = GLB(path)
    glb.path = path
    return glb


# ── main ──

try:
    with open(manifest_path) as f:
        entries = json.load(f)
except Exception as e:
    print("TOOLING ERROR: cannot read manifest %s: %s" % (manifest_path, e))
    sys.exit(2)

use_lib = None
try:
    import trimesh  # noqa: F401
    use_lib = "trimesh"
except ImportError:
    try:
        import pygltflib  # noqa: F401
        use_lib = "pygltflib"
    except ImportError:
        use_lib = "inline"

print("model budget check (%s parser)" % use_lib)
hdr = "%-18s %10s %8s %10s %9s  %s" % ("key", "tris", "gate", "tex bytes", "max tex", "textures")
print(hdr)
print("─" * len(hdr))
total_tex = 0

for e in entries:
    key = e.get("key", "?")
    rel = e.get("path", "")
    # res:// maps to the project root passed in from the shell wrapper.
    path = os.path.join(project_root, rel[len("res://"):]) if rel.startswith("res://") else rel
    if not os.path.isfile(path):
        tool_error("%s: GLB missing: %s" % (key, rel))
        continue
    gate = int(e.get("tri_gate", 0))

    try:
        if use_lib == "trimesh":
            tris = tris_via_trimesh(path)
            glb = load_glb(path)  # images still need the inline reader
        elif use_lib == "pygltflib":
            tris = tris_via_pygltflib(path)
            glb = load_glb(path)
        else:
            glb = load_glb(path)
            tris = glb.tri_count()
    except Exception as ex:
        tool_error("%s: failed to parse %s: %s" % (key, rel, ex))
        continue

    tex_bytes = 0
    max_dim = 0
    tex_notes = []
    for name, nbytes, window in glb.images():
        tex_bytes += nbytes
        dims = image_dims(window, None)
        if dims is not None:
            max_dim = max(max_dim, dims[0], dims[1])
            if dims[0] > MAX_TEX_DIM or dims[1] > MAX_TEX_DIM:
                fail("%s: texture %s is %dx%d (> %d^2)" % (key, name, dims[0], dims[1], MAX_TEX_DIM))
            tex_notes.append("%s:%dx%d" % (name, dims[0], dims[1]))
        else:
            tex_notes.append("%s:?" % name)
    total_tex += tex_bytes

    if tris > gate:
        fail("%s: %d tris over gate %d" % (key, tris, gate))

    print("%-18s %10d %8d %10d %9s  %s" % (
        key, tris, gate, tex_bytes,
        ("%dx" % max_dim) if max_dim else "?",
        ", ".join(tex_notes) if tex_notes else "no textures"))

print("─" * 72)
print("total embedded texture bytes: %d (%.1f MB, budget %.0f MB)" %
      (total_tex, total_tex / 1048576.0, TOTAL_TEXTURE_BUDGET / 1048576.0))
if total_tex > TOTAL_TEXTURE_BUDGET:
    fail("total texture bytes %d exceed the %d web budget" % (total_tex, TOTAL_TEXTURE_BUDGET))

for p in problems:
    print("TOOLING ERROR: %s" % p)
for f_ in failures:
    print("FAIL: %s" % f_)

if problems:
    sys.exit(2)
if failures:
    print("RESULT: FAIL (%d violation(s))" % len(failures))
    sys.exit(1)
print("RESULT: PASS")
sys.exit(0)
PYEOF
