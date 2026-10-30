#!/usr/bin/env python3
"""Deterministically author MineAttack's R7 unit GLBs with local geometry.

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
OUT_DIR = ROOT / "frost_mines_assets" / "models" / "units"
UNITS = ("miner", "swordsman", "archer", "wizard", "dragon", "pigeon", "engineer", "crawler")
MATERIALS = ("body", "cloth", "steel", "skin", "wood", "team", "accent", "glow_lamp", "glow_staff", "glow_eyes")
FACTIONS = ("FactionArcane", "FactionBrute", "FactionIndustrial")
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


@dataclass
class NodeDef:
    name: str
    parent: int | None
    translation: Vec3 = (0.0, 0.0, 0.0)


class UnitModel:
    def __init__(self, kind: str) -> None:
        self.kind = kind
        self.nodes = [NodeDef(kind, None)]
        self.parts: dict[int, dict[str, MeshData]] = {}
        self.body = self.node("Body", 0)

    def node(self, name: str, parent: int = 0, position: Vec3 = (0.0, 0.0, 0.0)) -> int:
        index = len(self.nodes)
        self.nodes.append(NodeDef(name, parent, position))
        return index

    def mesh(self, node: int, material: str) -> MeshData:
        return self.parts.setdefault(node, {}).setdefault(material, MeshData())

    def normalize_height(self, target: float) -> None:
        minimum = float("inf")
        maximum = float("-inf")
        for node_index, by_material in self.parts.items():
            offset = 0.0
            cursor: int | None = node_index
            while cursor is not None:
                offset += self.nodes[cursor].translation[1]
                cursor = self.nodes[cursor].parent
            for data in by_material.values():
                minimum = min(minimum, min(p[1] + offset for p in data.positions))
                maximum = max(maximum, max(p[1] + offset for p in data.positions))
        factor = target / (maximum - minimum)
        for by_material in self.parts.values():
            for data in by_material.values():
                data.positions = [vmul(p, factor) for p in data.positions]
                data.normals = [norm(p) for p in data.normals]
        for node in self.nodes:
            node.translation = vmul(node.translation, factor)
        self.nodes[self.body].translation = (0.0, -minimum * factor, 0.0)

    def uv(self, material: str, u: float, v: float) -> Vec2:
        slot = MATERIALS.index(material)
        col, row = slot % 4, slot // 4
        return ((col + 0.035 + 0.93 * (u % 1.0)) / 4.0, (row + 0.035 + 0.93 * (v % 1.0)) / 4.0)

    def ellipsoid(
        self,
        node: int,
        material: str,
        center: Vec3,
        radii: Vec3,
        segments: int = 10,
        rings: int = 6,
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
        self.mesh(node, material).add(positions, normals, uvs, indices)

    def tube(
        self,
        node: int,
        material: str,
        points: Sequence[Vec3],
        radii: Sequence[float | tuple[float, float]],
        sides: int = 8,
        caps: bool = True,
    ) -> None:
        positions: list[Vec3] = []
        normals: list[Vec3] = []
        uvs: list[Vec2] = []
        frames: list[tuple[Vec3, Vec3, Vec3]] = []
        for j, p in enumerate(points):
            tangent = norm(vsub(points[min(j + 1, len(points) - 1)], points[max(j - 1, 0)]))
            ref = (0.0, 0.0, 1.0) if abs(tangent[2]) < 0.9 else (0.0, 1.0, 0.0)
            u = norm(cross(tangent, ref))
            v = norm(cross(tangent, u))
            frames.append((tangent, u, v))
            radius = radii[j]
            ru, rv = (radius, radius) if isinstance(radius, (float, int)) else radius
            for i in range(sides + 1):
                angle = math.tau * i / sides
                radial = vadd(vmul(u, math.cos(angle)), vmul(v, math.sin(angle)))
                positions.append(vadd(p, (radial[0] * ru, radial[1] * ru, radial[2] * rv)))
                normals.append(norm(radial))
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
                tangent, u, v = frames[ring_index]
                normal = vmul(tangent, end)
                center_index = len(positions)
                positions.append(points[ring_index])
                normals.append(normal)
                uvs.append(self.uv(material, 0.5, 0.5))
                radius = radii[ring_index]
                ru, rv = (radius, radius) if isinstance(radius, (float, int)) else radius
                start = len(positions)
                for i in range(sides):
                    angle = math.tau * i / sides
                    radial = vadd(vmul(u, math.cos(angle)), vmul(v, math.sin(angle)))
                    positions.append(vadd(points[ring_index], (radial[0] * ru, radial[1] * ru, radial[2] * rv)))
                    normals.append(normal)
                    uvs.append(self.uv(material, 0.5 + 0.45 * math.cos(angle), 0.5 + 0.45 * math.sin(angle)))
                for i in range(sides):
                    tri = (center_index, start + i, start + (i + 1) % sides)
                    indices.extend(tri[::-1] if end < 0 else tri)
        self.mesh(node, material).add(positions, normals, uvs, indices)

    def triangles(self, node: int, material: str, triangles: Sequence[tuple[Vec3, Vec3, Vec3]]) -> None:
        positions: list[Vec3] = []
        normals: list[Vec3] = []
        uvs: list[Vec2] = []
        indices: list[int] = []
        for tri in triangles:
            normal = norm(cross(vsub(tri[1], tri[0]), vsub(tri[2], tri[0])))
            start = len(positions)
            positions.extend(tri)
            normals.extend((normal, normal, normal))
            for p in tri:
                uvs.append(self.uv(material, p[0] * 9.0 + p[2] * 3.0, p[1] * 9.0 + p[2] * 3.0))
            indices.extend((start, start + 1, start + 2))
        self.mesh(node, material).add(positions, normals, uvs, indices)

    def blade(self, node: int, material: str, outline: Sequence[Vec2], z: float, thickness: float) -> None:
        positions: list[Vec3] = []
        normals: list[Vec3] = []
        uvs: list[Vec2] = []
        indices: list[int] = []
        count = len(outline)
        for side in (-1.0, 1.0):
            for x, y in outline:
                positions.append((x, y, z + side * thickness * 0.5))
                normals.append((0.0, 0.0, side))
                uvs.append(self.uv(material, x * 12.0, y * 12.0))
        for i in range(1, count - 1):
            indices.extend((0, i + 1, i))
            indices.extend((count, count + i, count + i + 1))
        for i in range(count):
            j = (i + 1) % count
            start = len(positions)
            positions.extend((positions[i], positions[j], positions[count + j], positions[count + i]))
            edge = norm(vsub(positions[start + 1], positions[start]))
            normals.extend([norm((edge[1], -edge[0], 0.0))] * 4)
            uvs.extend([self.uv(material, 0.0, 0.0), self.uv(material, 1.0, 0.0), self.uv(material, 1.0, 1.0), self.uv(material, 0.0, 1.0)])
            indices.extend((start, start + 1, start + 2, start, start + 2, start + 3))
        self.mesh(node, material).add(positions, normals, uvs, indices)

    def torus(self, node: int, material: str, center: Vec3, major: float, minor: float, segments: int = 10, sides: int = 5) -> None:
        positions: list[Vec3] = []
        normals: list[Vec3] = []
        uvs: list[Vec2] = []
        for i in range(segments + 1):
            a = math.tau * i / segments
            for j in range(sides + 1):
                b = math.tau * j / sides
                n = (math.cos(a) * math.cos(b), math.sin(a) * math.cos(b), math.sin(b))
                positions.append((center[0] + (major + minor * math.cos(b)) * math.cos(a), center[1] + (major + minor * math.cos(b)) * math.sin(a), center[2] + minor * math.sin(b)))
                normals.append(n)
                uvs.append(self.uv(material, i / segments, j / sides))
        indices: list[int] = []
        stride = sides + 1
        for i in range(segments):
            for j in range(sides):
                a = i * stride + j
                b = a + stride
                indices.extend((a, b, a + 1, a + 1, b, b + 1))
        self.mesh(node, material).add(positions, normals, uvs, indices)


PALETTE = {
    "body": (91, 105, 119), "cloth": (61, 72, 88), "steel": (116, 132, 143),
    "skin": (190, 157, 129), "wood": (104, 77, 51), "team": (202, 207, 211),
    "accent": (211, 208, 201), "glow_lamp": (255, 205, 119),
    "glow_staff": (208, 183, 255), "glow_eyes": (255, 168, 79),
}


def painted_atlas(kind: str) -> bytes:
    rng = random.Random(1707 + sum(ord(c) for c in kind))
    image = Image.new("RGB", (256, 256))
    draw = ImageDraw.Draw(image)
    tile = 64
    for slot, material in enumerate(MATERIALS):
        ox, oy = (slot % 4) * tile, (slot // 4) * tile
        base = PALETTE[material]
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


def humanoid_base(model: UnitModel, height: float, robe: bool = False) -> dict[str, int]:
    body = model.body
    if robe:
        model.tube(body, "team", [(0, 0.015, 0), (0, 0.10, 0), (0, 0.22, 0)], [(0.088, 0.072), (0.075, 0.06), (0.064, 0.052)], 12)
    else:
        for side, name in ((-1, "LegL"), (1, "LegR")):
            leg = model.node(name, body, (side * 0.035, 0.115, 0.008))
            model.tube(leg, "cloth", [(0, 0, 0), (side * 0.003, -0.055, 0), (0, -0.10, -0.004)], [0.024, 0.021, 0.018], 8)
            model.ellipsoid(leg, "wood", (0, -0.102, -0.013), (0.027, 0.015, 0.039), 8, 5)
    model.tube(body, "team", [(0, 0.105, 0.006), (0, 0.17, 0), (0, 0.235, -0.003)], [(0.058, 0.044), (0.071, 0.048), (0.063, 0.043)], 12)
    model.tube(body, "accent", [(0, 0.112, 0.005), (0, 0.126, 0.004)], [(0.061, 0.047), (0.061, 0.047)], 12)
    model.ellipsoid(body, "skin", (0, 0.278, -0.008), (0.047, 0.052, 0.044), 12, 7,
                    lambda _t, _p, v: (v[0], v[1] - (0.008 if v[1] < 0.265 else 0), v[2] - (0.009 if v[2] < -0.035 else 0)))
    model.ellipsoid(body, "skin", (0, 0.274, -0.052), (0.012, 0.014, 0.013), 8, 5)
    arms = {}
    for side, name in ((-1, "ArmL"), (1, "ArmR")):
        arm = model.node(name, body, (side * 0.071, 0.224, 0))
        model.tube(arm, "team", [(0, 0, 0), (side * 0.008, -0.05, 0.005), (side * 0.004, -0.092, -0.006)], [0.025, 0.021, 0.016], 8)
        model.ellipsoid(arm, "skin", (side * 0.004, -0.103, -0.008), (0.018, 0.021, 0.017), 8, 5)
        arms[name] = arm
    arms["Body"] = body
    return arms


def add_miner(model: UnitModel) -> None:
    p = humanoid_base(model, 0.38)
    body = model.body
    model.ellipsoid(body, "steel", (0, 0.319, -0.003), (0.063, 0.035, 0.057), 12, 6)
    model.tube(body, "steel", [(0, 0.304, 0), (0, 0.312, 0)], [(0.071, 0.063), (0.071, 0.063)], 12)
    model.ellipsoid(body, "glow_lamp", (0, 0.322, -0.058), (0.018, 0.014, 0.012), 10, 6)
    model.ellipsoid(body, "wood", (0, 0.18, 0.061), (0.056, 0.071, 0.03), 10, 6)
    model.tube(body, "accent", [(-0.052, 0.245, 0.065), (0.052, 0.245, 0.065)], [0.014, 0.014], 8)
    tool = model.node("Tool", body, (0.082, 0.202, -0.01))
    model.tube(tool, "wood", [(0, -0.13, 0.025), (0, 0.095, -0.045)], [0.009, 0.008], 8)
    model.tube(tool, "steel", [(-0.075, 0.096, -0.045), (0, 0.108, -0.045), (0.075, 0.096, -0.045)], [0.004, 0.014, 0.004], 7)


def add_swordsman(model: UnitModel) -> None:
    humanoid_base(model, 0.39)
    body = model.body
    model.ellipsoid(body, "steel", (0, 0.319, 0), (0.055, 0.047, 0.051), 12, 7)
    model.tube(body, "steel", [(0, 0.351, 0.015), (0, 0.385, 0.022)], [0.018, 0.002], 7)
    model.ellipsoid(body, "accent", (-0.093, 0.18, -0.024), (0.019, 0.073, 0.056), 12, 7)
    model.tube(body, "steel", [(-0.102, 0.12, -0.033), (-0.102, 0.24, -0.033)], [0.009, 0.009], 7)
    tool = model.node("Tool", body, (0.083, 0.17, -0.022))
    model.blade(tool, "steel", [(-0.012, 0), (0.012, 0), (0.009, 0.175), (0, 0.215), (-0.009, 0.175)], -0.006, 0.009)
    model.tube(tool, "accent", [(-0.036, 0.004, -0.006), (0.036, 0.004, -0.006)], [0.008, 0.008], 7)
    model.tube(tool, "wood", [(0, -0.045, -0.006), (0, 0.005, -0.006)], [0.009, 0.009], 7)


def add_archer(model: UnitModel) -> None:
    humanoid_base(model, 0.37)
    body = model.body
    model.ellipsoid(body, "cloth", (0, 0.302, 0.012), (0.061, 0.064, 0.055), 12, 7,
                    lambda _t, _p, v: (v[0], v[1] + (0.018 if v[1] > 0.33 else 0), v[2]))
    model.ellipsoid(body, "skin", (0, 0.283, -0.041), (0.035, 0.035, 0.018), 10, 6)
    model.tube(body, "wood", [(-0.04, 0.13, 0.058), (-0.035, 0.255, 0.065)], [(0.025, 0.02), (0.021, 0.018)], 9)
    for x in (-0.048, -0.034, -0.02):
        model.tube(body, "accent", [(x, 0.22, 0.066), (x, 0.29, 0.072)], [0.003, 0.002], 5)
    tool = model.node("Tool", body, (-0.086, 0.19, -0.025))
    model.tube(tool, "wood", [(0, -0.14, 0.035), (-0.025, -0.075, 0), (-0.032, 0, -0.01), (-0.025, 0.075, 0), (0, 0.14, 0.035)], [0.005, 0.007, 0.008, 0.007, 0.005], 7)
    model.tube(tool, "steel", [(0, -0.14, 0.035), (-0.005, 0, 0.025), (0, 0.14, 0.035)], [0.0015, 0.0015, 0.0015], 4, False)


def add_wizard(model: UnitModel) -> None:
    humanoid_base(model, 0.40, robe=True)
    body = model.body
    model.tube(body, "team", [(0, 0.315, 0), (0, 0.325, 0)], [(0.098, 0.083), (0.098, 0.083)], 14)
    model.tube(body, "accent", [(0, 0.326, 0.006), (0.008, 0.36, 0.01), (-0.009, 0.397, 0.018)], [(0.061, 0.052), (0.035, 0.03), (0.002, 0.002)], 12)
    tool = model.node("Tool", body, (0.091, 0.16, -0.015))
    model.tube(tool, "wood", [(0, -0.145, 0.015), (0, 0.17, -0.005)], [0.008, 0.007], 8)
    model.ellipsoid(tool, "glow_staff", (0, 0.188, -0.006), (0.022, 0.027, 0.022), 10, 6)
    model.tube(tool, "steel", [(-0.025, 0.168, -0.006), (0, 0.153, -0.006), (0.025, 0.168, -0.006)], [0.004, 0.005, 0.004], 6)


def add_engineer(model: UnitModel) -> None:
    humanoid_base(model, 0.36)
    body = model.body
    model.ellipsoid(body, "steel", (0, 0.316, 0), (0.06, 0.036, 0.055), 12, 6)
    model.tube(body, "accent", [(0, 0.303, 0), (0, 0.31, 0)], [(0.068, 0.06), (0.068, 0.06)], 12)
    model.ellipsoid(body, "wood", (0, 0.183, 0.063), (0.059, 0.074, 0.032), 10, 6)
    model.tube(body, "steel", [(-0.055, 0.245, 0.066), (0.055, 0.245, 0.066)], [0.012, 0.012], 8)
    tool = model.node("Tool", body, (0.083, 0.17, -0.02))
    model.tube(tool, "steel", [(0, -0.075, 0), (0, 0.065, 0)], [0.009, 0.011], 8)
    model.tube(tool, "steel", [(-0.027, 0.09, 0), (-0.02, 0.06, 0), (0.02, 0.06, 0), (0.027, 0.09, 0)], [0.007, 0.011, 0.011, 0.007], 7)


def add_dragon(model: UnitModel) -> None:
    body = model.body
    model.ellipsoid(body, "team", (0, 0.35, 0.015), (0.145, 0.145, 0.24), 14, 9,
                    lambda t, _p, v: (v[0], v[1] + 0.018 * math.cos(t * 2), v[2]))
    model.ellipsoid(body, "cloth", (0, 0.285, -0.015), (0.115, 0.07, 0.20), 12, 7)
    model.tube(body, "team", [(0, 0.42, -0.15), (0, 0.50, -0.25), (0, 0.545, -0.32)], [0.085, 0.067, 0.06], 12)
    model.ellipsoid(body, "team", (0, 0.55, -0.35), (0.075, 0.065, 0.105), 12, 7)
    model.ellipsoid(body, "body", (0, 0.515, -0.432), (0.063, 0.035, 0.07), 10, 6)
    for side in (-1, 1):
        model.ellipsoid(body, "glow_eyes", (side * 0.052, 0.568, -0.408), (0.012, 0.01, 0.014), 8, 5)
        model.tube(body, "steel", [(side * 0.047, 0.593, -0.31), (side * 0.064, 0.646, -0.275), (side * 0.074, 0.683, -0.24)], [0.016, 0.01, 0.001], 7)
        for z in (-0.12, 0.14):
            model.tube(body, "body", [(side * 0.09, 0.29, z), (side * 0.115, 0.15, z - 0.015), (side * 0.12, 0.04, z - 0.035)], [0.045, 0.032, 0.024], 9)
            model.ellipsoid(body, "body", (side * 0.12, 0.025, z - 0.06), (0.04, 0.025, 0.065), 9, 5)
    for side, name in ((1, "WingL"), (-1, "WingR")):
        wing = model.node(name, body, (side * 0.115, 0.455, 0.015))
        root = (0.0, 0.0, 0.0)
        elbow = (side * 0.19, 0.095, 0.005)
        tip = (side * 0.46, 0.05, 0.08)
        trail1 = (side * 0.29, -0.045, 0.20)
        trail2 = (side * 0.13, -0.065, 0.17)
        model.triangles(wing, "team", [(root, elbow, trail2), (elbow, trail1, trail2), (elbow, tip, trail1)])
        model.tube(wing, "body", [root, elbow, tip], [0.018, 0.012, 0.002], 7)
        model.tube(wing, "body", [elbow, trail1], [0.007, 0.002], 6)
        model.tube(wing, "accent", [trail2, trail1, tip], [0.004, 0.004, 0.002], 6)
    tail = model.node("Tail", body, (0, 0.34, 0.22))
    model.tube(tail, "team", [(0, 0, 0), (0.025, -0.025, 0.16), (-0.015, -0.06, 0.32), (0, -0.035, 0.44)], [0.06, 0.04, 0.022, 0.002], 10)


def add_pigeon(model: UnitModel) -> None:
    body = model.body
    model.ellipsoid(body, "team", (0, 0.062, 0), (0.034, 0.037, 0.052), 12, 7)
    model.ellipsoid(body, "body", (0, 0.093, -0.039), (0.025, 0.027, 0.027), 10, 6)
    model.tube(body, "wood", [(0, 0.091, -0.058), (0, 0.089, -0.08)], [0.01, 0.001], 6)
    for side, name in ((1, "WingL"), (-1, "WingR")):
        wing = model.node(name, body, (side * 0.027, 0.074, 0))
        model.triangles(wing, "cloth", [((0, 0, -0.025), (side * 0.09, 0.006, 0.015), (side * 0.025, -0.01, 0.038)), ((0, 0, -0.025), (side * 0.025, -0.01, 0.038), (0, -0.008, 0.025))])
        model.tube(wing, "accent", [(0, 0, -0.02), (side * 0.085, 0.006, 0.014)], [0.004, 0.001], 5)
    model.triangles(body, "accent", [((-0.025, 0.064, 0.035), (0.025, 0.064, 0.035), (0, 0.05, 0.088))])
    for side in (-1, 1):
        model.tube(body, "wood", [(side * 0.013, 0.04, 0), (side * 0.013, 0.006, -0.005)], [0.003, 0.002], 5)


def add_crawler(model: UnitModel) -> None:
    body = model.body
    model.ellipsoid(body, "body", (0, 0.074, 0.025), (0.082, 0.06, 0.19), 14, 8,
                    lambda t, _p, v: (v[0] * (1 + 0.08 * math.cos(t * 3)), v[1], v[2]))
    model.ellipsoid(body, "team", (0, 0.068, -0.18), (0.068, 0.048, 0.075), 12, 7)
    for side in (-1, 1):
        model.ellipsoid(body, "glow_eyes", (side * 0.04, 0.083, -0.235), (0.011, 0.009, 0.012), 8, 5)
        for i in range(3):
            z = -0.09 + i * 0.105
            model.tube(body, "body", [(side * 0.06, 0.065, z), (side * 0.115, 0.045, z + 0.015), (side * 0.135, 0.008, z - 0.025)], [0.014, 0.01, 0.003], 7)
    for i in range(4):
        z = -0.09 + i * 0.085
        model.tube(body, "accent", [(0, 0.118, z), (0, 0.157 - i * 0.006, z + 0.022)], [0.018, 0.001], 6)


def add_factions(model: UnitModel, head_y: float, head_z: float, scale: float, back_y: float, back_z: float) -> None:
    body = model.body
    arcane = model.node("FactionArcane", body)
    brute = model.node("FactionBrute", body)
    industrial = model.node("FactionIndustrial", body)
    s = scale
    for side in (-1, 1):
        model.tube(arcane, "accent", [(side * 0.055 * s, back_y, back_z), (side * 0.072 * s, back_y + 0.055 * s, back_z + 0.01 * s)], [0.014 * s, 0.001], 5)
        model.tube(brute, "steel", [(side * 0.037 * s, head_y, head_z), (side * 0.068 * s, head_y + 0.025 * s, head_z + 0.015 * s), (side * 0.078 * s, head_y + 0.052 * s, head_z + 0.028 * s)], [0.013 * s, 0.009 * s, 0.001], 7)
        model.ellipsoid(brute, "body", (side * 0.068 * s, back_y - 0.045 * s, back_z), (0.034 * s, 0.018 * s, 0.038 * s), 8, 5)
        model.torus(industrial, "accent", (side * 0.023 * s, head_y - 0.01 * s, head_z - 0.041 * s), 0.019 * s, 0.005 * s, 10, 5)
        model.ellipsoid(industrial, "accent", (side * 0.046 * s, back_y - 0.05 * s, back_z), (0.006 * s, 0.006 * s, 0.006 * s), 6, 4)
    model.tube(industrial, "accent", [(-0.046 * s, head_y + 0.012 * s, head_z - 0.034 * s), (0.046 * s, head_y + 0.012 * s, head_z - 0.034 * s)], [0.004 * s, 0.004 * s], 6)
    model.tube(industrial, "body", [(0.042 * s, back_y - 0.08 * s, back_z + 0.025 * s), (0.042 * s, back_y + 0.025 * s, back_z + 0.025 * s)], [0.012 * s, 0.009 * s], 8)


BUILDERS = {
    "miner": add_miner, "swordsman": add_swordsman, "archer": add_archer,
    "wizard": add_wizard, "dragon": add_dragon, "pigeon": add_pigeon,
    "engineer": add_engineer, "crawler": add_crawler,
}
FACTION_ARGS = {
    "miner": (0.325, -0.003, 1.0, 0.245, 0.06),
    "swordsman": (0.35, 0, 1.0, 0.245, 0.035),
    "archer": (0.335, 0.008, 1.0, 0.24, 0.06),
    "wizard": (0.355, 0.008, 1.0, 0.245, 0.035),
    "dragon": (0.59, -0.32, 1.8, 0.47, 0.08),
    "pigeon": (0.10, -0.04, 0.43, 0.075, 0.035),
    "engineer": (0.325, 0, 1.0, 0.245, 0.065),
    "crawler": (0.09, -0.18, 1.15, 0.12, 0.04),
}


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

    def write(self, model: UnitModel) -> bytes:
        image_view = self.view(painted_atlas(model.kind))
        materials = []
        for name in MATERIALS:
            material = {
                "name": name,
                "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicFactor": 0.0, "roughnessFactor": 0.92},
                "doubleSided": True,
            }
            if name.startswith("glow_"):
                material["emissiveTexture"] = {"index": 0}
                material["emissiveFactor"] = [1.0, 0.72 if name != "glow_staff" else 0.85, 0.38 if name == "glow_lamp" else 0.65]
            materials.append(material)
        meshes: list[dict] = []
        node_mesh: dict[int, int] = {}
        for node_index, by_material in model.parts.items():
            primitives = []
            for name, data in by_material.items():
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
            node_mesh[node_index] = len(meshes)
            meshes.append({"name": model.nodes[node_index].name + "Mesh", "primitives": primitives})
        nodes = []
        children: dict[int, list[int]] = {}
        for i, node in enumerate(model.nodes):
            if node.parent is not None:
                children.setdefault(node.parent, []).append(i)
        for i, node in enumerate(model.nodes):
            item = {"name": node.name, "translation": list(node.translation)}
            if i in children:
                item["children"] = children[i]
            if i in node_mesh:
                item["mesh"] = node_mesh[i]
            nodes.append(item)
        document = {
            "asset": {"version": "2.0", "generator": "MineAttack deterministic R7 unit workshop"},
            "scene": 0, "scenes": [{"name": model.kind, "nodes": [0]}], "nodes": nodes, "meshes": meshes,
            "materials": materials,
            "textures": [{"name": model.kind + "_painted_atlas", "source": 0, "sampler": 0}],
            "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 33071, "wrapT": 33071}],
            "images": [{"name": model.kind + "_atlas", "mimeType": "image/png", "bufferView": image_view}],
            "bufferViews": self.views, "accessors": self.accessors,
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
    names = {node.get("name") for node in document["nodes"]}
    humanoid_pivots = {"ArmL", "ArmR", "Tool"} if path.stem == "wizard" else {"ArmL", "ArmR", "LegL", "LegR", "Tool"}
    pivot_contract = {
        "dragon": {"WingL", "WingR", "Tail"},
        "pigeon": {"WingL", "WingR"},
        "crawler": set(),
    }.get(path.stem, humanoid_pivots)
    required = {"Body", *FACTIONS, *pivot_contract}
    if not required.issubset(names):
        raise ValueError(f"{path.name}: missing {sorted(required - names)}")
    if document["asset"]["version"] != "2.0" or any("uri" in image for image in document.get("images", [])):
        raise ValueError(f"{path.name}: invalid asset or external image")
    if any(not math.isfinite(value) for node in document["nodes"] for value in node.get("translation", [0, 0, 0])):
        raise ValueError(f"{path.name}: non-finite transform")
    triangles = 0
    minimum = [float("inf")] * 3
    maximum = [float("-inf")] * 3
    for mesh in document["meshes"]:
        for primitive in mesh["primitives"]:
            if primitive.get("mode", 4) != 4:
                raise ValueError(f"{path.name}: non-triangle primitive")
            triangles += document["accessors"][primitive["indices"]]["count"] // 3
            normals = accessor_values(document, binary, primitive["attributes"]["NORMAL"])
            if any(abs(sum(c * c for c in normal) - 1.0) > 0.02 for normal in normals):
                raise ValueError(f"{path.name}: non-unit normal")
    parents = {child: i for i, node in enumerate(document["nodes"]) for child in node.get("children", [])}
    for node_index, node in enumerate(document["nodes"]):
        if "mesh" not in node:
            continue
        offset = [0.0, 0.0, 0.0]
        cursor: int | None = node_index
        while cursor is not None:
            translation = document["nodes"][cursor].get("translation", [0, 0, 0])
            offset = [offset[axis] + translation[axis] for axis in range(3)]
            cursor = parents.get(cursor)
        for primitive in document["meshes"][node["mesh"]]["primitives"]:
            positions = accessor_values(document, binary, primitive["attributes"]["POSITION"])
            for p in positions:
                for axis in range(3):
                    world = p[axis] + offset[axis]
                    minimum[axis] = min(minimum[axis], world)
                    maximum[axis] = max(maximum[axis], world)
    if triangles < 500 or triangles > 8000:
        raise ValueError(f"{path.name}: {triangles} triangles outside 500..8000")
    if abs(minimum[1]) > 0.0001:
        raise ValueError(f"{path.name}: base min-y is {minimum[1]:.5f}, expected 0")
    height = maximum[1] - minimum[1]
    bands = {"dragon": (0.66, 0.74), "pigeon": (0.10, 0.14), "crawler": (0.14, 0.18)}
    low, high = bands.get(path.stem, (0.34, 0.405))
    if not low <= height <= high:
        raise ValueError(f"{path.name}: height {height:.4f} outside {low}..{high}")
    for material in document["materials"]:
        pbr = material["pbrMetallicRoughness"]
        if pbr.get("metallicFactor") != 0.0 or abs(pbr.get("roughnessFactor") - 0.92) > 0.001:
            raise ValueError(f"{path.name}: PBR convention drift")
    return {"triangles": triangles, "height": height, "width": maximum[0] - minimum[0], "depth": maximum[2] - minimum[2]}


def generate() -> list[tuple[str, dict[str, float | int]]]:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    report = []
    for kind in UNITS:
        model = UnitModel(kind)
        BUILDERS[kind](model)
        add_factions(model, *FACTION_ARGS[kind])
        target_height = {"miner": 0.38, "swordsman": 0.39, "archer": 0.37, "wizard": 0.40, "dragon": 0.70, "pigeon": 0.12, "engineer": 0.36, "crawler": 0.16}[kind]
        model.normalize_height(target_height)
        path = OUT_DIR / f"{kind}.glb"
        path.write_bytes(GLBWriter().write(model))
        report.append((kind, validate(path)))
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--validate-only", action="store_true", help="validate existing GLBs without regenerating")
    args = parser.parse_args()
    if args.validate_only:
        report = [(kind, validate(OUT_DIR / f"{kind}.glb")) for kind in UNITS]
    else:
        report = generate()
    for kind, stats in report:
        print(f"{kind:10s} {stats['triangles']:4d} tris  h={stats['height']:.3f}  w={stats['width']:.3f}  d={stats['depth']:.3f}")
    print(f"Validated {len(report)} embedded-texture GLB 2.0 files; all include faction variants and pass the 8000-triangle gate.")


if __name__ == "__main__":
    main()
