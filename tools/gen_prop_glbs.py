#!/usr/bin/env python3
"""Deterministically author MineAttack's prop GLBs (plans/06-asset-import-pipeline.md).

The prop workshop mirrors tools/gen_unit_glbs.py (same GLBWriter approach, same
PBR convention) but stays standalone per the plan: no imports from the unit
tool. Props are the third model category after structures and units — neutral
surface dressing for plan 07's scatter system, loaded through the
structure-style path (ModelManifest + StructureModelLoader) minus gameplay.

Conventions enforced here (identical to the house GLBs):
- glTF 2.0 binary, embedded PNG atlas only (256^2 painted, no external URIs)
- unit normals, indexed triangle primitives
- PBR metallicFactor 0.0 / roughnessFactor 0.92, doubleSided
- base at min-y 0 (normalized after authoring)

World units follow the R4/R7 contract (Presentation3D.WORLD_SCALE 0.01,
1 cell = 0.32 world units, a humanoid is ~0.36 tall). Prop height bands:
- prop_boulder: 0.18..0.26 (target 0.22), 150..400 tris
- prop_pine:    0.40..0.48 (target 0.44), 200..500 tris
- prop_stump:   0.13..0.17 (target 0.15), 100..250 tris
- prop_crate:   0.14..0.18 (target 0.16), 100..200 tris

Requires Pillow only for the painted atlas PNGs. No network, model service, or
Godot installation is used. Run from any directory; output is repository-local.
"""

from __future__ import annotations

import argparse
import io
import json
import math
import random
import struct
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Iterable, Sequence

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "frost_mines_assets" / "models" / "props"
PROPS = ("prop_boulder", "prop_pine", "prop_stump", "prop_crate")
MATERIALS = ("stone", "bark", "foliage", "wood", "snow")
TARGET_HEIGHTS = {"prop_boulder": 0.22, "prop_pine": 0.44, "prop_stump": 0.15, "prop_crate": 0.16}
TRI_BANDS = {
    "prop_boulder": (150, 400),
    "prop_pine": (200, 500),
    "prop_stump": (100, 250),
    "prop_crate": (100, 200),
}
Vec3 = tuple[float, float, float]
Vec2 = tuple[float, float]


def vadd(a: Vec3, b: Vec3) -> Vec3:
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def vsub(a: Vec3, b: Vec3) -> Vec3:
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def vmul(a: Vec3, s: float) -> Vec3:
    return (a[0] * s, a[1] * s, a[2] * s)


def dot(a: Vec3, b: Vec3) -> float:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def cross(a: Vec3, b: Vec3) -> Vec3:
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def norm(a: Vec3) -> Vec3:
    length = math.sqrt(max(dot(a, a), 1e-20))
    return (a[0] / length, a[1] / length, a[2] / length)


@dataclass
class MeshData:
    positions: list[Vec3] = field(default_factory=list)
    normals: list[Vec3] = field(default_factory=list)
    uvs: list[Vec2] = field(default_factory=list)
    indices: list[int] = field(default_factory=list)

    def add(self, positions: Sequence[Vec3], normals: Sequence[Vec3], uvs: Sequence[Vec2], indices: Iterable[int]) -> None:
        offset = len(self.positions)
        self.positions.extend(positions)
        self.normals.extend(normals)
        self.uvs.extend(uvs)
        self.indices.extend(offset + i for i in indices)


class PropModel:
    """Single-node prop: named parts are material buckets only (no pivots)."""

    def __init__(self, kind: str) -> None:
        self.kind = kind
        self.parts: dict[str, MeshData] = {}

    def mesh(self, material: str) -> MeshData:
        return self.parts.setdefault(material, MeshData())

    def uv(self, material: str, u: float, v: float) -> Vec2:
        slot = MATERIALS.index(material)
        col, row = slot % 4, slot // 4
        return ((col + 0.035 + 0.93 * (u % 1.0)) / 4.0, (row + 0.035 + 0.93 * (v % 1.0)) / 4.0)

    def normalize_height(self, target: float) -> None:
        flat = [p for data in self.parts.values() for p in data.positions]
        lo = min(p[1] for p in flat)
        hi = max(p[1] for p in flat)
        factor = target / (hi - lo)
        shift = -lo * factor
        for data in self.parts.values():
            data.positions = [(p[0] * factor, p[1] * factor + shift, p[2] * factor) for p in data.positions]
            data.normals = [norm(n) for n in data.normals]

    def ellipsoid(
        self,
        material: str,
        center: Vec3,
        radii: Vec3,
        segments: int,
        rings: int,
        sculpt: Callable[[float, float, Vec3], Vec3] | None = None,
    ) -> None:
        positions: list[Vec3] = []
        normals: list[Vec3] = []
        uvs: list[Vec2] = []
        for j in range(rings + 1):
            phi = math.pi * j / rings
            for i in range(segments + 1):
                theta = math.tau * i / segments
                unit = (math.sin(phi) * math.cos(theta), math.cos(phi), math.sin(phi) * math.sin(theta))
                p = (center[0] + radii[0] * unit[0], center[1] + radii[1] * unit[1], center[2] + radii[2] * unit[2])
                if sculpt:
                    p = sculpt(theta, phi, p)
                positions.append(p)
                normals.append(norm((unit[0] / radii[0], unit[1] / radii[1], unit[2] / radii[2])))
                uvs.append(self.uv(material, i / segments, j / rings))
        indices: list[int] = []
        stride = segments + 1
        for j in range(rings):
            for i in range(segments):
                a = j * stride + i
                b = a + stride
                indices.extend((a, a + 1, b, a + 1, b + 1, b))
        self.mesh(material).add(positions, normals, uvs, indices)

    def tube(
        self,
        material: str,
        points: Sequence[Vec3],
        radii: Sequence[float],
        sides: int,
        caps: bool = False,
    ) -> None:
        positions: list[Vec3] = []
        normals: list[Vec3] = []
        uvs: list[Vec2] = []
        for j, p in enumerate(points):
            tangent = norm(vsub(points[min(j + 1, len(points) - 1)], points[max(j - 1, 0)]))
            ref = (0.0, 0.0, 1.0) if abs(tangent[2]) < 0.9 else (0.0, 1.0, 0.0)
            u = norm(cross(tangent, ref))
            v = norm(cross(tangent, u))
            for i in range(sides + 1):
                angle = math.tau * i / sides
                radial = vadd(vmul(u, math.cos(angle)), vmul(v, math.sin(angle)))
                positions.append(vadd(p, vmul(radial, radii[j])))
                normals.append(radial)
                uvs.append(self.uv(material, i / sides, j / max(1, len(points) - 1)))
        indices: list[int] = []
        stride = sides + 1
        for j in range(len(points) - 1):
            for i in range(sides):
                a = j * stride + i
                b = a + stride
                indices.extend((a, a + 1, b, a + 1, b + 1, b))
        if caps:
            for end, ring_index in ((-1, 0), (1, len(points) - 1)):
                tangent = norm(vsub(points[min(ring_index + 1, len(points) - 1)], points[max(ring_index - 1, 0)]))
                normal = vmul(tangent, end)
                center_index = len(positions)
                positions.append(points[ring_index])
                normals.append(normal)
                uvs.append(self.uv(material, 0.5, 0.5))
                start = len(positions)
                for i in range(sides):
                    angle = math.tau * i / sides
                    radial = vadd(vmul(u, math.cos(angle)), vmul(v, math.sin(angle)))
                    positions.append(vadd(points[ring_index], vmul(radial, radii[ring_index])))
                    normals.append(normal)
                    uvs.append(self.uv(material, 0.5 + 0.45 * math.cos(angle), 0.5 + 0.45 * math.sin(angle)))
                for i in range(sides):
                    tri = (center_index, start + i, start + (i + 1) % sides)
                    indices.extend(tri[::-1] if end < 0 else tri)
        self.mesh(material).add(positions, normals, uvs, indices)

    def disc(self, material: str, center: Vec3, radius: float, segments: int) -> None:
        positions: list[Vec3] = [center]
        normals: list[Vec3] = [(0.0, 1.0, 0.0)]
        uvs: list[Vec2] = [self.uv(material, 0.5, 0.5)]
        for i in range(segments):
            angle = math.tau * i / segments
            positions.append((center[0] + radius * math.cos(angle), center[1], center[2] + radius * math.sin(angle)))
            normals.append((0.0, 1.0, 0.0))
            uvs.append(self.uv(material, 0.5 + 0.45 * math.cos(angle), 0.5 + 0.45 * math.sin(angle)))
        indices: list[int] = []
        for i in range(segments):
            current = 1 + i
            nxt = 1 + (i + 1) % segments
            indices.extend((0, nxt, current))
        self.mesh(material).add(positions, normals, uvs, indices)

    def box(self, material: str, center: Vec3, size: Vec3) -> None:
        cx, cy, cz = center
        hx, hy, hz = size[0] * 0.5, size[1] * 0.5, size[2] * 0.5
        corners: dict[tuple[int, int, int], Vec3] = {
            (sx, sy, sz): (cx + sx * hx, cy + sy * hy, cz + sz * hz)
            for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)
        }
        faces = [
            ([corners[(1, -1, -1)], corners[(1, -1, 1)], corners[(1, 1, 1)], corners[(1, 1, -1)]], (1.0, 0.0, 0.0)),
            ([corners[(-1, -1, 1)], corners[(-1, -1, -1)], corners[(-1, 1, -1)], corners[(-1, 1, 1)]], (-1.0, 0.0, 0.0)),
            ([corners[(-1, 1, -1)], corners[(1, 1, -1)], corners[(1, 1, 1)], corners[(-1, 1, 1)]], (0.0, 1.0, 0.0)),
            ([corners[(-1, -1, 1)], corners[(1, -1, 1)], corners[(1, -1, -1)], corners[(-1, -1, -1)]], (0.0, -1.0, 0.0)),
            ([corners[(-1, -1, -1)], corners[(1, -1, -1)], corners[(1, 1, -1)], corners[(-1, 1, -1)]], (0.0, 0.0, -1.0)),
            ([corners[(1, -1, 1)], corners[(-1, -1, 1)], corners[(-1, 1, 1)], corners[(1, 1, 1)]], (0.0, 0.0, 1.0)),
        ]
        positions: list[Vec3] = []
        normals: list[Vec3] = []
        uvs: list[Vec2] = []
        indices: list[int] = []
        for face, normal in faces:
            start = len(positions)
            for corner, uv in zip(face, ((0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0))):
                positions.append(corner)
                normals.append(normal)
                uvs.append(self.uv(material, uv[0], uv[1]))
            indices.extend((start, start + 1, start + 2, start, start + 2, start + 3))
        self.mesh(material).add(positions, normals, uvs, indices)


def lumpy(center: Vec3, amp: float, phase: float) -> Callable[[float, float, Vec3], Vec3]:
    """Deterministic radial wobble around a rock's center."""

    def sculpt(theta: float, phi: float, p: Vec3) -> Vec3:
        d = 1.0 + amp * (
            0.6 * math.sin(theta * 3.0 + phase)
            + 0.4 * math.cos(phi * 5.0 - phase)
            + 0.25 * math.sin(theta * 7.0 + phi * 3.0)
        )
        return (
            center[0] + (p[0] - center[0]) * d,
            center[1] + (p[1] - center[1]) * d,
            center[2] + (p[2] - center[2]) * d,
        )

    return sculpt


def add_pine_tier(m: PropModel, y0: float, y1: float, radius: float, segments: int, snow: bool) -> None:
    m.tube("foliage", [(0.0, y0, 0.0), (0.0, y1, 0.0)], [radius, 0.0015], segments)
    if snow:
        frac = 0.55
        snow_y = y0 + (1.0 - frac) * (y1 - y0) + 0.004
        m.disc("snow", (0.0, snow_y, 0.0), radius * frac, 9)


def build_boulder(m: PropModel) -> None:
    m.ellipsoid("stone", (0.0, 0.075, 0.0), (0.115, 0.08, 0.10), 10, 6, lumpy((0.0, 0.075, 0.0), 0.15, 1.0))
    m.ellipsoid("stone", (0.085, 0.045, 0.055), (0.055, 0.045, 0.05), 7, 5, lumpy((0.085, 0.045, 0.055), 0.2, 2.0))
    m.ellipsoid("stone", (-0.08, 0.035, -0.05), (0.045, 0.035, 0.04), 6, 4, lumpy((-0.08, 0.035, -0.05), 0.22, 3.0))


def build_pine(m: PropModel) -> None:
    m.tube("bark", [(0.0, 0.0, 0.0), (0.0, 0.07, 0.0), (0.005, 0.15, 0.005)], [0.024, 0.019, 0.012], 7, caps=True)
    tiers = 7
    for i in range(tiers):
        y0 = 0.085 + i * 0.048
        y1 = y0 + 0.115
        radius = 0.135 - i * 0.017
        add_pine_tier(m, y0, y1, radius, 11, snow=i >= tiers - 3)


def build_stump(m: PropModel) -> None:
    m.tube("bark", [(0.0, 0.0, 0.0), (0.0, 0.05, 0.0), (0.004, 0.13, 0.002)], [0.075, 0.062, 0.054], 9)
    m.disc("wood", (0.004, 0.1315, 0.002), 0.052, 9)
    for k in range(4):
        angle = math.tau * k / 4.0 + 0.35
        dx, dz = math.cos(angle), math.sin(angle)
        m.tube(
            "bark",
            [(dx * 0.05, 0.032, dz * 0.05), (dx * 0.10, 0.012, dz * 0.10), (dx * 0.135, 0.0, dz * 0.135)],
            [0.028, 0.018, 0.004],
            5,
        )
    m.tube("wood", [(0.04, 0.09, 0.01), (0.078, 0.118, 0.02)], [0.016, 0.001], 5)


def build_crate(m: PropModel) -> None:
    m.box("wood", (0.0, 0.065, 0.0), (0.13, 0.13, 0.13))
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            m.box("bark", (sx * 0.066, 0.065, sz * 0.066), (0.02, 0.145, 0.02))
    for y in (0.03, 0.10):
        m.box("bark", (0.0, y, 0.0), (0.148, 0.02, 0.148))
    m.box("bark", (0.0, 0.142, 0.0), (0.148, 0.018, 0.036))
    m.box("bark", (0.0, 0.142, 0.0), (0.036, 0.018, 0.148))


BUILDERS = {
    "prop_boulder": build_boulder,
    "prop_pine": build_pine,
    "prop_stump": build_stump,
    "prop_crate": build_crate,
}


PROP_PALETTE = {
    "stone": (98, 108, 119),
    "bark": (72, 57, 44),
    "foliage": (72, 94, 76),
    "wood": (108, 80, 53),
    "snow": (222, 233, 242),
}


def painted_atlas(kind: str) -> bytes:
    rng = random.Random(2306 + sum(ord(c) for c in kind))
    image = Image.new("RGB", (256, 256))
    draw = ImageDraw.Draw(image)
    tile = 64
    for slot, material in enumerate(MATERIALS):
        ox, oy = (slot % 4) * tile, (slot // 4) * tile
        base = PROP_PALETTE[material]
        for y in range(tile):
            for x in range(tile):
                wave = 7.0 * math.sin(x * 0.17 + y * 0.07) + 5.0 * math.cos(y * 0.21 - x * 0.04)
                grain = rng.uniform(-5.0, 5.0)
                shade = int(wave + grain)
                image.putpixel((ox + x, oy + y), tuple(max(0, min(255, c + shade)) for c in base))
        for _ in range(22):
            x, y = ox + rng.randrange(tile), oy + rng.randrange(tile)
            length = rng.randrange(5, 22)
            shade = rng.choice((-18, -10, 10, 17))
            color = tuple(max(0, min(255, c + shade)) for c in base)
            draw.line((x, y, min(ox + tile - 1, x + length), max(oy, y - length // 4)), fill=color, width=rng.choice((1, 2, 3)))
        draw.line((ox + 2, oy + 3, ox + tile - 3, oy + 3), fill=tuple(min(255, c + 22) for c in base), width=2)
    image = image.filter(ImageFilter.GaussianBlur(0.45))
    output = io.BytesIO()
    image.save(output, format="PNG", optimize=True)
    return output.getvalue()


class GLBWriter:
    def __init__(self) -> None:
        self.buffer = bytearray()
        self.views: list[dict] = []
        self.accessors: list[dict] = []

    def view(self, data: bytes, target: int | None = None) -> int:
        while len(self.buffer) % 4:
            self.buffer.append(0)
        index = len(self.views)
        view = {"buffer": 0, "byteOffset": len(self.buffer), "byteLength": len(data)}
        if target is not None:
            view["target"] = target
        self.views.append(view)
        self.buffer.extend(data)
        return index

    def accessor(self, values: Sequence[Sequence[float]] | Sequence[int], kind: str, component: int = 5126, target: int = 34962) -> int:
        if component == 5126:
            data = b"".join(struct.pack("<" + "f" * len(v), *v) for v in values)  # type: ignore[arg-type]
        elif component == 5125:
            data = b"".join(struct.pack("<I", v) for v in values)  # type: ignore[arg-type]
        else:
            raise ValueError(component)
        index = len(self.accessors)
        accessor = {"bufferView": self.view(data, target), "componentType": component, "count": len(values), "type": kind}
        if kind == "VEC3":
            accessor["min"] = [min(v[i] for v in values) for i in range(3)]  # type: ignore[index]
            accessor["max"] = [max(v[i] for v in values) for i in range(3)]  # type: ignore[index]
        self.accessors.append(accessor)
        return index

    def write(self, model: PropModel) -> bytes:
        image_view = self.view(painted_atlas(model.kind))
        materials = []
        for name in MATERIALS:
            materials.append({
                "name": name,
                "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicFactor": 0.0, "roughnessFactor": 0.92},
                "doubleSided": True,
            })
        primitives = []
        for name, data in model.parts.items():
            if not data.indices:
                continue
            primitives.append({
                "attributes": {
                    "POSITION": self.accessor(data.positions, "VEC3"),
                    "NORMAL": self.accessor(data.normals, "VEC3"),
                    "TEXCOORD_0": self.accessor(data.uvs, "VEC2"),
                },
                "indices": self.accessor(data.indices, "SCALAR", 5125, 34963),
                "material": MATERIALS.index(name),
                "mode": 4,
            })
        document = {
            "asset": {"version": "2.0", "generator": "MineAttack deterministic prop workshop"},
            "scene": 0,
            "scenes": [{"name": model.kind, "nodes": [0]}],
            "nodes": [{"name": model.kind, "mesh": 0}],
            "meshes": [{"name": model.kind + "Mesh", "primitives": primitives}],
            "materials": materials,
            "textures": [{"name": model.kind + "_painted_atlas", "source": 0, "sampler": 0}],
            "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 33071, "wrapT": 33071}],
            "images": [{"name": model.kind + "_atlas", "mimeType": "image/png", "bufferView": image_view}],
            "bufferViews": self.views,
            "accessors": self.accessors,
            "buffers": [{"byteLength": len(self.buffer)}],
        }
        json_chunk = json.dumps(document, separators=(",", ":"), sort_keys=True).encode("utf-8")
        json_chunk += b" " * ((-len(json_chunk)) % 4)
        bin_chunk = bytes(self.buffer) + b"\0" * ((-len(self.buffer)) % 4)
        total = 12 + 8 + len(json_chunk) + 8 + len(bin_chunk)
        return struct.pack("<4sII", b"glTF", 2, total) + struct.pack("<I4s", len(json_chunk), b"JSON") + json_chunk + struct.pack("<I4s", len(bin_chunk), b"BIN\0") + bin_chunk


def parse_glb(path: Path) -> tuple[dict, bytes]:
    raw = path.read_bytes()
    if len(raw) < 20 or raw[:4] != b"glTF":
        raise ValueError(f"{path.name}: not GLB")
    version, declared = struct.unpack_from("<II", raw, 4)
    if version != 2 or declared != len(raw):
        raise ValueError(f"{path.name}: bad version/length")
    offset = 12
    document = None
    binary = None
    while offset < len(raw):
        length, kind = struct.unpack_from("<I4s", raw, offset)
        offset += 8
        chunk = raw[offset:offset + length]
        if len(chunk) != length:
            raise ValueError(f"{path.name}: truncated chunk")
        if kind == b"JSON":
            document = json.loads(chunk.decode("utf-8"))
        elif kind == b"BIN\0":
            binary = chunk
        offset += length
    if document is None or binary is None:
        raise ValueError(f"{path.name}: missing JSON/BIN")
    return document, binary


def accessor_values(document: dict, binary: bytes, index: int) -> list[tuple[float, ...]]:
    accessor = document["accessors"][index]
    view = document["bufferViews"][accessor["bufferView"]]
    components = {"SCALAR": 1, "VEC2": 2, "VEC3": 3}[accessor["type"]]
    formats = {5126: "f", 5125: "I", 5123: "H"}
    fmt = "<" + formats[accessor["componentType"]] * components
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    stride = view.get("byteStride", struct.calcsize(fmt))
    return [struct.unpack_from(fmt, binary, start + i * stride) for i in range(accessor["count"])]


def validate(path: Path) -> dict[str, float | int]:
    document, binary = parse_glb(path)
    kind = path.stem
    if kind not in TRI_BANDS:
        raise ValueError(f"{path.name}: unknown prop kind '{kind}'")
    if document["asset"]["version"] != "2.0" or any("uri" in image for image in document.get("images", [])):
        raise ValueError(f"{path.name}: invalid asset or external image")
    if any(not math.isfinite(value) for node in document["nodes"] for value in node.get("translation", [0, 0, 0])):
        raise ValueError(f"{path.name}: non-finite transform")
    triangles = 0
    minimum = [float("inf")] * 3
    maximum = [float("-inf")] * 3
    for node in document["nodes"]:
        if "mesh" not in node:
            continue
        for primitive in document["meshes"][node["mesh"]]["primitives"]:
            if primitive.get("mode", 4) != 4:
                raise ValueError(f"{path.name}: non-triangle primitive")
            if "TEXCOORD_0" not in primitive["attributes"]:
                raise ValueError(f"{path.name}: primitive missing UVs")
            triangles += document["accessors"][primitive["indices"]]["count"] // 3
            normals = accessor_values(document, binary, primitive["attributes"]["NORMAL"])
            if any(abs(sum(c * c for c in normal) - 1.0) > 0.02 for normal in normals):
                raise ValueError(f"{path.name}: non-unit normal")
            positions = accessor_values(document, binary, primitive["attributes"]["POSITION"])
            for p in positions:
                for axis in range(3):
                    minimum[axis] = min(minimum[axis], p[axis])
                    maximum[axis] = max(maximum[axis], p[axis])
    low_tri, high_tri = TRI_BANDS[kind]
    if not low_tri <= triangles <= high_tri:
        raise ValueError(f"{path.name}: {triangles} triangles outside {low_tri}..{high_tri}")
    if abs(minimum[1]) > 0.0001:
        raise ValueError(f"{path.name}: base min-y is {minimum[1]:.5f}, expected 0")
    height = maximum[1] - minimum[1]
    target = TARGET_HEIGHTS[kind]
    if abs(height - target) > 0.02:
        raise ValueError(f"{path.name}: height {height:.4f} not within 0.02 of target {target}")
    for material in document["materials"]:
        pbr = material["pbrMetallicRoughness"]
        if pbr.get("metallicFactor") != 0.0 or abs(pbr.get("roughnessFactor") - 0.92) > 0.001:
            raise ValueError(f"{path.name}: PBR convention drift")
    return {"triangles": triangles, "height": height, "width": maximum[0] - minimum[0], "depth": maximum[2] - minimum[2]}


def generate() -> list[tuple[str, dict[str, float | int]]]:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    report = []
    for kind in PROPS:
        model = PropModel(kind)
        BUILDERS[kind](model)
        model.normalize_height(TARGET_HEIGHTS[kind])
        path = OUT_DIR / f"{kind}.glb"
        path.write_bytes(GLBWriter().write(model))
        report.append((kind, validate(path)))
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--validate-only", action="store_true", help="validate existing GLBs without regenerating")
    args = parser.parse_args()
    if args.validate_only:
        report = [(kind, validate(OUT_DIR / f"{kind}.glb")) for kind in PROPS]
    else:
        report = generate()
    for kind, stats in report:
        print(f"{kind:14s} {stats['triangles']:4d} tris  h={stats['height']:.3f}  w={stats['width']:.3f}  d={stats['depth']:.3f}")
    print(f"Validated {len(report)} embedded-texture GLB 2.0 prop files; all pass their budgets.")


if __name__ == "__main__":
    main()
