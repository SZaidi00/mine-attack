#!/usr/bin/env python3
"""Curate static kit props into MineAttack's embedded, ground-normalized GLBs.

Usage:
    python3 tools/import_kit_props.py --source /path/to/pack/glTF \
        --prop Rock_Medium_1.gltf=pack_rock_medium_1=0.28
    python3 tools/import_kit_props.py --validate-only

The source pack is never required at runtime. Each --prop is
SOURCE=KEY=TARGET_HEIGHT; uniform scale preserves the authored proportions and
the resulting footprint is reported in MineAttack cells (0.32 world units).
Only Python's standard library is required.

--validate-only strictly re-checks every committed static kit prop (embedded
textures, PBR convention, ground/height normalization). GLBs registered as
"skeletal" in frost_mines_assets/models/model_manifest.json are skipped with
a notice — their skins, clips, and root motion are owned and validated by
`python3 tools/curate_skeletal_units.py --validate-only`.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import math
import struct
from pathlib import Path
from typing import Iterable
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = ROOT / "frost_mines_assets" / "models" / "packs"
MANIFEST = ROOT / "frost_mines_assets" / "models" / "model_manifest.json"
CELL_WORLD = 0.32
Mat4 = tuple[float, ...]
Vec3 = tuple[float, float, float]


def identity() -> Mat4:
    return (1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0)


def multiply(a: Mat4, b: Mat4) -> Mat4:
    return tuple(sum(a[k * 4 + row] * b[col * 4 + k] for k in range(4)) for col in range(4) for row in range(4))


def node_matrix(node: dict) -> Mat4:
    if "matrix" in node:
        return tuple(float(v) for v in node["matrix"])
    translation = node.get("translation", [0.0, 0.0, 0.0])
    x, y, z, w = node.get("rotation", [0.0, 0.0, 0.0, 1.0])
    scale = node.get("scale", [1.0, 1.0, 1.0])
    rotation = (
        1.0 - 2.0 * (y * y + z * z), 2.0 * (x * y + w * z), 2.0 * (x * z - w * y), 0.0,
        2.0 * (x * y - w * z), 1.0 - 2.0 * (x * x + z * z), 2.0 * (y * z + w * x), 0.0,
        2.0 * (x * z + w * y), 2.0 * (y * z - w * x), 1.0 - 2.0 * (x * x + y * y), 0.0,
        0.0, 0.0, 0.0, 1.0,
    )
    return multiply(multiply(
        (1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0,
         float(translation[0]), float(translation[1]), float(translation[2]), 1.0),
        rotation),
        (float(scale[0]), 0.0, 0.0, 0.0, 0.0, float(scale[1]), 0.0, 0.0,
         0.0, 0.0, float(scale[2]), 0.0, 0.0, 0.0, 0.0, 1.0))


def transform_point(m: Mat4, p: Vec3) -> Vec3:
    return (
        m[0] * p[0] + m[4] * p[1] + m[8] * p[2] + m[12],
        m[1] * p[0] + m[5] * p[1] + m[9] * p[2] + m[13],
        m[2] * p[0] + m[6] * p[1] + m[10] * p[2] + m[14],
    )


def read_glb(path: Path) -> tuple[dict, list[bytes]]:
    raw = path.read_bytes()
    if raw[:4] != b"glTF":
        raise ValueError(f"{path}: not a GLB")
    _, version, _ = struct.unpack_from("<III", raw, 0)
    if version != 2:
        raise ValueError(f"{path}: unsupported GLB version {version}")
    document = None
    binary = None
    offset = 12
    while offset + 8 <= len(raw):
        length, kind = struct.unpack_from("<II", raw, offset)
        offset += 8
        chunk = raw[offset:offset + length]
        offset += length
        if kind == 0x4E4F534A:
            document = json.loads(chunk.decode("utf-8"))
        elif kind == 0x004E4942:
            binary = chunk
    if document is None:
        raise ValueError(f"{path}: missing JSON chunk")
    buffers = []
    for index, buffer in enumerate(document.get("buffers", [])):
        if "uri" in buffer:
            raise ValueError(f"{path}: buffer {index} still has an external URI")
        if index > 0 or binary is None:
            raise ValueError(f"{path}: expected one embedded BIN buffer")
        buffers.append(binary[:buffer["byteLength"]])
    return document, buffers


def read_source(path: Path) -> tuple[dict, list[bytes]]:
    if path.suffix.lower() == ".glb":
        return read_glb(path)
    document = json.loads(path.read_text(encoding="utf-8"))
    buffers = []
    for buffer in document.get("buffers", []):
        uri = buffer.get("uri")
        if uri is None:
            raise ValueError(f"{path}: glTF buffer has no URI; use GLB input")
        if uri.startswith("data:"):
            buffers.append(base64.b64decode(uri.split(",", 1)[1]))
        else:
            buffers.append((path.parent / unquote(uri)).resolve().read_bytes())
    return document, buffers


def write_glb(path: Path, document: dict, binary: bytes) -> None:
    json_bytes = json.dumps(document, separators=(",", ":")).encode("utf-8")
    json_bytes += b" " * ((4 - len(json_bytes) % 4) % 4)
    binary += b"\x00" * ((4 - len(binary) % 4) % 4)
    total = 12 + 8 + len(json_bytes) + 8 + len(binary)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as handle:
        handle.write(struct.pack("<III", 0x46546C67, 2, total))
        handle.write(struct.pack("<II", len(json_bytes), 0x4E4F534A))
        handle.write(json_bytes)
        handle.write(struct.pack("<II", len(binary), 0x004E4942))
        handle.write(binary)


def positions(document: dict, buffers: list[bytes], accessor_index: int) -> Iterable[Vec3]:
    accessor = document["accessors"][accessor_index]
    if accessor.get("type") != "VEC3" or accessor.get("componentType") != 5126 or "bufferView" not in accessor:
        raise ValueError(f"POSITION accessor {accessor_index} must be a non-sparse float VEC3")
    view = document["bufferViews"][accessor["bufferView"]]
    data = buffers[view.get("buffer", 0)]
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    stride = view.get("byteStride", 12)
    for index in range(accessor["count"]):
        yield struct.unpack_from("<fff", data, start + index * stride)


def scene_geometry(document: dict, buffers: list[bytes]) -> tuple[list[Vec3], int]:
    scene_index = document.get("scene", 0)
    scene = document["scenes"][scene_index]
    points: list[Vec3] = []
    triangles = 0

    def visit(node_index: int, parent: Mat4) -> None:
        nonlocal triangles
        node = document["nodes"][node_index]
        matrix = multiply(parent, node_matrix(node))
        if "mesh" in node:
            for primitive in document["meshes"][node["mesh"]].get("primitives", []):
                if primitive.get("mode", 4) != 4:
                    continue
                points.extend(transform_point(matrix, p) for p in positions(document, buffers, primitive["attributes"]["POSITION"]))
                count = document["accessors"][primitive["indices"]]["count"] if "indices" in primitive else document["accessors"][primitive["attributes"]["POSITION"]]["count"]
                triangles += count // 3
        for child in node.get("children", []):
            visit(child, matrix)

    for root in scene.get("nodes", []):
        visit(root, identity())
    return points, triangles


def bounds(points: list[Vec3]) -> tuple[Vec3, Vec3, Vec3]:
    if not points:
        raise ValueError("scene has no triangle POSITION data")
    low = tuple(min(p[i] for p in points) for i in range(3))
    high = tuple(max(p[i] for p in points) for i in range(3))
    size = tuple(high[i] - low[i] for i in range(3))
    return low, high, size


def embed_and_normalize(source: Path, key: str, target_height: float) -> tuple[dict, bytes, dict]:
    document, source_buffers = read_source(source)
    binary = bytearray()
    buffer_bases: dict[int, int] = {}
    for index, data in enumerate(source_buffers):
        binary += b"\x00" * ((4 - len(binary) % 4) % 4)
        buffer_bases[index] = len(binary)
        binary += data
    for view in document.get("bufferViews", []):
        old_buffer = view.get("buffer", 0)
        view["buffer"] = 0
        view["byteOffset"] = view.get("byteOffset", 0) + buffer_bases[old_buffer]
    for image in document.get("images", []):
        uri = image.get("uri")
        if uri is None:
            continue
        if uri.startswith("data:"):
            data = base64.b64decode(uri.split(",", 1)[1])
        else:
            data = (source.parent / unquote(uri)).resolve().read_bytes()
        binary += b"\x00" * ((4 - len(binary) % 4) % 4)
        view_index = len(document.setdefault("bufferViews", []))
        document["bufferViews"].append({"buffer": 0, "byteOffset": len(binary), "byteLength": len(data)})
        binary += data
        image.pop("uri")
        image["bufferView"] = view_index
        if "mimeType" not in image:
            image["mimeType"] = "image/png" if data[:8] == b"\x89PNG\r\n\x1a\n" else "image/jpeg"
    document["buffers"] = [{"byteLength": len(binary)}]
    buffers = [bytes(binary)]

    points, triangles = scene_geometry(document, buffers)
    low, high, size = bounds(points)
    if size[1] <= 0.000001 or target_height <= 0.0:
        raise ValueError(f"{source}: invalid source or target height")
    scale = target_height / size[1]
    center_x = (low[0] + high[0]) * 0.5
    center_z = (low[2] + high[2]) * 0.5
    scene_index = document.get("scene", 0)
    scene = document["scenes"][scene_index]
    wrapper_index = len(document["nodes"])
    document["nodes"].append({
        "name": key,
        "children": scene.get("nodes", []),
        "scale": [scale, scale, scale],
        "translation": [-center_x * scale, -low[1] * scale, -center_z * scale],
        "extras": {"mineattack_target_height": target_height, "mineattack_source": source.name},
    })
    scene["nodes"] = [wrapper_index]
    for material in document.get("materials", []):
        pbr = material.setdefault("pbrMetallicRoughness", {})
        pbr["metallicFactor"] = 0.0
        pbr["roughnessFactor"] = 0.92
    document.setdefault("asset", {})["generator"] = "MineAttack curated kit-prop importer (source geometry retained)"
    final_points, final_triangles = scene_geometry(document, buffers)
    final_low, _, final_size = bounds(final_points)
    report = {
        "key": key,
        "source": source.name,
        "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
        "triangles": final_triangles,
        "footprint": [round(final_size[0] / CELL_WORLD, 4), round(final_size[2] / CELL_WORLD, 4)],
        "height": round(final_size[1], 4),
        "min_y": round(final_low[1], 6),
    }
    return document, bytes(binary), report


def skeletal_filenames() -> set[str]:
    """Basenames of pack GLBs the shared manifest registers as skeletal rigs.

    Those files are curated and validated by tools/curate_skeletal_units.py,
    so this tool's --validate-only delegates them instead of applying the
    static kit-prop normalization checks.
    """
    try:
        entries = json.loads(MANIFEST.read_text(encoding="utf-8"))
    except Exception as exc:
        raise SystemExit(f"cannot read model manifest {MANIFEST}: {exc}") from exc
    return {Path(entry["path"]).name for entry in entries
            if entry.get("skeletal") and entry.get("path")}


def validate(path: Path) -> dict:
    document, buffers = read_glb(path)
    if any("uri" in image for image in document.get("images", [])):
        raise ValueError(f"{path}: external image URI remains")
    for material in document.get("materials", []):
        pbr = material.get("pbrMetallicRoughness", {})
        if pbr.get("metallicFactor") != 0.0 or pbr.get("roughnessFactor") != 0.92:
            raise ValueError(f"{path}: PBR convention mismatch")
    points, triangles = scene_geometry(document, buffers)
    low, _, size = bounds(points)
    scene = document["scenes"][document.get("scene", 0)]
    root = document["nodes"][scene["nodes"][0]]
    target = float(root.get("extras", {}).get("mineattack_target_height", 0.0))
    if abs(low[1]) > 0.0001 or target <= 0.0 or abs(size[1] - target) > 0.001:
        raise ValueError(f"{path}: ground/height normalization mismatch: min-y={low[1]}, height={size[1]}, target={target}")
    return {"key": root.get("name", path.stem), "triangles": triangles, "height": round(size[1], 4), "min_y": round(low[1], 6)}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, help="Directory containing the source glTF models")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--prop", action="append", default=[], metavar="SOURCE=KEY=HEIGHT")
    parser.add_argument("--validate-only", action="store_true")
    args = parser.parse_args()
    if args.validate_only:
        paths = sorted(args.output.glob("*.glb"))
        if not paths:
            raise SystemExit(f"no curated GLBs found in {args.output}")
        skeletal = skeletal_filenames()
        skipped = 0
        validated = 0
        for path in paths:
            if path.name in skeletal:
                print(f"Skipping {path.name}: skeletal rig in model_manifest.json "
                      "(validated by tools/curate_skeletal_units.py --validate-only)")
                skipped += 1
                continue
            report = validate(path)
            report["output_sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
            print(json.dumps(report, sort_keys=True))
            validated += 1
        print(f"Validated {validated} curated props")
        if skipped:
            print(f"Delegated {skipped} skeletal rig(s) to tools/curate_skeletal_units.py --validate-only")
        return
    if args.source is None or not args.prop:
        parser.error("--source and at least one --prop are required unless --validate-only is used")
    for spec in args.prop:
        try:
            filename, key, height_text = spec.rsplit("=", 2)
            source = args.source / filename
            document, binary, report = embed_and_normalize(source, key, float(height_text))
            output = args.output / f"{key}.glb"
            write_glb(output, document, binary)
            check = validate(output)
            report["output_sha256"] = hashlib.sha256(output.read_bytes()).hexdigest()
            report["path"] = str(output.relative_to(ROOT)) if output.is_relative_to(ROOT) else str(output)
            report["validated_triangles"] = check["triangles"]
            print(json.dumps(report, sort_keys=True))
        except Exception as exc:
            raise SystemExit(f"{spec}: {exc}") from exc


if __name__ == "__main__":
    main()
