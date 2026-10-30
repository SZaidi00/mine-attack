#!/usr/bin/env python3
"""Resize embedded GLB textures to the 2048^2 import cap.

R4 mitigation for 02-asset-pipeline.md convention 5 ("Cap 2048^2 per model,
resize at import if larger"): the Tripo starter GLBs embed 4096x4096 Color /
NormalGL / ORM textures. Godot's glTF importer has no downscale option for
embedded textures, so this tool performs the sanctioned "resize at import"
step mechanically: every embedded image larger than 2048^2 is Lanczos-resized
to 2048^2 and re-encoded (PNG stays PNG, JPEG stays JPEG), the BIN chunk is
rebuilt with 4-byte-aligned bufferViews, and the GLB is rewritten in place.
Triangle data is copied verbatim — only image byte windows change.

Also resizes the standalone duplicate texture files next to each GLB (same
pixels, kept in sync for any external reference).

Safe to re-run: images already <= 2048^2 are left untouched.

Usage: tools/resize_glb_textures.py [--max=N] [--only=SUBSTR]

--max=N         override the 2048^2 cap (e.g. --max=1024 to downscale the
                structure GLBs for the perf pass)
--only=SUBSTR   process only manifest entries whose path contains SUBSTR
                (e.g. --only=/structures/)
"""
import json
import os
import struct
import sys

MAX_DIM = 2048
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join(ROOT, "frost_mines_assets", "models", "model_manifest.json")

try:
    from PIL import Image
except ImportError:
    sys.exit("PIL (Pillow) is required for texture downscaling")


def parse_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    if data[:4] != b"glTF":
        raise ValueError("not a GLB")
    _, version, _ = struct.unpack_from("<III", data, 0)
    if version != 2:
        raise ValueError("unsupported GLB version")
    off = 12
    gltf = None
    bin_chunk = None
    while off + 8 <= len(data):
        clen, ctype = struct.unpack_from("<II", data, off)
        off += 8
        chunk = data[off:off + clen]
        off += clen
        if ctype == 0x4E4F534A:
            gltf = json.loads(chunk.decode("utf-8"))
        elif ctype == 0x004E4942:
            bin_chunk = chunk
    if gltf is None or bin_chunk is None:
        raise ValueError("GLB missing JSON or BIN chunk")
    return gltf, bytearray(bin_chunk)


def build_glb(path, gltf, bin_buf):
    json_bytes = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    json_bytes += b" " * ((4 - len(json_bytes) % 4) % 4)
    bin_pad = (4 - len(bin_buf) % 4) % 4
    bin_bytes = bytes(bin_buf) + b"\x00" * bin_pad
    total = 12 + 8 + len(json_bytes) + 8 + len(bin_bytes)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(json_bytes), 0x4E4F534A))
        f.write(json_bytes)
        f.write(struct.pack("<II", len(bin_bytes), 0x004E4942))
        f.write(bin_bytes)


def resize_image(raw, max_dim):
    """Return (new_bytes, changed, kind) — kind 'png' or 'jpeg'."""
    from io import BytesIO
    kind = "png" if raw[:4] == b"\x89PNG" else "jpeg"
    img = Image.open(BytesIO(raw))
    if max(img.size) <= max_dim:
        return raw, False, kind
    img = img.resize((max_dim, max_dim), Image.LANCZOS)
    out = BytesIO()
    if kind == "png":
        img.save(out, format="PNG", optimize=True)
    else:
        img.save(out, format="JPEG", quality=92)
    return out.getvalue(), True, kind


def process_glb(path, max_dim=MAX_DIM):
    gltf, bin_buf = parse_glb(path)
    views = gltf.get("bufferViews", [])
    images = gltf.get("images", [])
    image_views = {img["bufferView"] for img in images if "bufferView" in img}
    if not image_views:
        print("  %s: no embedded images" % os.path.basename(path))
        return
    # Decode + resize every image window first.
    replacements = {}
    for idx in sorted(image_views):
        view = views[idx]
        start = view.get("byteOffset", 0)
        raw = bytes(bin_buf[start:start + view["byteLength"]])
        new, changed, kind = resize_image(raw, max_dim)
        if changed:
            replacements[idx] = new
            print("  %s: bufferView %d (%s) %d -> %d bytes"
                  % (os.path.basename(path), idx, kind, len(raw), len(new)))
    if not replacements:
        print("  %s: all images already <= %d^2" % (os.path.basename(path), max_dim))
        return
    # Rebuild the BIN buffer in original bufferView order, 4-byte aligned,
    # substituting resized images. Vertex/index data is copied verbatim.
    ordered = sorted(range(len(views)), key=lambda i: views[i].get("byteOffset", 0))
    new_buf = bytearray()
    for idx in ordered:
        view = views[idx]
        start = view.get("byteOffset", 0)
        raw = bytes(bin_buf[start:start + view["byteLength"]])
        data = replacements.get(idx, raw)
        pad = (4 - len(new_buf) % 4) % 4
        new_buf += b"\x00" * pad
        view["byteOffset"] = len(new_buf)
        view["byteLength"] = len(data)
        new_buf += data
    gltf["buffers"][0]["byteLength"] = len(new_buf)
    build_glb(path, gltf, new_buf)


def process_external(glb_path, max_dim=MAX_DIM):
    """Resize the standalone duplicate textures next to the GLB (named
    <model>_<image name>.<ext>)."""
    base = os.path.dirname(glb_path)
    gltf, _ = parse_glb(glb_path)
    for img in gltf.get("images", []):
        name = img.get("name")
        if not name:
            continue
        for f in sorted(os.listdir(base)):
            if not (f.endswith(".jpg") or f.endswith(".png")):
                continue
            if not f.endswith(name + os.path.splitext(f)[1]):
                continue
            p = os.path.join(base, f)
            with open(p, "rb") as fh:
                raw = fh.read()
            new, changed, _kind = resize_image(raw, max_dim)
            if changed:
                with open(p, "wb") as fh:
                    fh.write(new)
                print("  %s: %d -> %d bytes" % (f, len(raw), len(new)))


def main():
    max_dim = MAX_DIM
    only = ""
    for arg in sys.argv[1:]:
        if arg.startswith("--max="):
            max_dim = int(arg[len("--max="):])
        elif arg.startswith("--only="):
            only = arg[len("--only="):]
    with open(MANIFEST) as f:
        entries = json.load(f)
    for e in entries:
        rel = e.get("path", "")
        if not rel.startswith("res://"):
            continue
        if only and only not in rel:
            continue
        path = os.path.join(ROOT, rel[len("res://"):])
        print("%s:" % e.get("key", rel))
        process_glb(path, max_dim)
        process_external(path, max_dim)
    print("done")


if __name__ == "__main__":
    main()
