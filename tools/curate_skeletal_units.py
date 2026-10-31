#!/usr/bin/env python3
"""Curate matching KayKit humanoid rigs, native clips, and hand tools.

Requires only Python's standard library. Source packs stay outside the exported
asset set. Run with --characters, --animations, and --tools to rebuild, or
--validate-only to check the curated GLBs without source packs.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
import struct
from pathlib import Path

import import_kit_props as kit

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "frost_mines_assets" / "models" / "packs"
COMMON = {
    "idle": ("General", "Idle_A", None, True),
    "walk": ("MovementBasic", "Walking_A", None, True),
    "death": ("General", "Death_A", None, False),
}
ROLES = {
    "miner": {
        "character": "Barbarian",
        "tools": [("pickaxe", "Pickaxe", "handslot.r")],
        "clips": {"attack": ("CombatMelee", "Melee_1H_Attack_Chop", None, False),
                  "mine": ("Tools", "Pickaxe", (0.0, 2.0), True)},
    },
    "swordsman": {
        "character": "Knight",
        "tools": [("sword_1handed", "Sword", "handslot.r"), ("shield_round", "Shield", "handslot.l")],
        "clips": {"attack": ("CombatMelee", "Melee_1H_Attack_Slice_Diagonal", None, False)},
    },
    "archer": {
        "character": "Ranger",
        "tools": [("bow", "Bow", "handslot.l")],
        "simplify": 0.78,
        "clips": {"attack": ("CombatRanged", "Ranged_Bow_Release", None, False)},
    },
    "wizard": {
        "character": "Mage",
        "tools": [("staff", "Staff", "handslot.r")],
        "clips": {"attack": ("CombatRanged", "Ranged_Magic_Shoot", None, False)},
    },
    "engineer": {
        "character": "Rogue",
        "tools": [("wrench_A", "Wrench", "handslot.r")],
        "clips": {"attack": ("Tools", "Hammer", (0.0, 1.333333), False),
                  "repair": ("Tools", "Hammering", (0.0, 1.333333), True)},
    },
}
COMPONENTS = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2), 5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}
COUNTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def embedded(path: Path) -> tuple[dict, bytes]:
    document, buffers = kit.read_source(path)
    binary = bytearray()
    offsets = {}
    for index, data in enumerate(buffers):
        binary.extend(b"\0" * (-len(binary) % 4))
        offsets[index] = len(binary)
        binary.extend(data)
    for view in document.get("bufferViews", []):
        view["byteOffset"] = view.get("byteOffset", 0) + offsets[view.get("buffer", 0)]
        view["buffer"] = 0
    for image in document.get("images", []):
        if "bufferView" in image:
            continue
        data = (path.parent / image["uri"]).read_bytes()
        binary.extend(b"\0" * (-len(binary) % 4))
        view = len(document["bufferViews"])
        document["bufferViews"].append({"buffer": 0, "byteOffset": len(binary), "byteLength": len(data)})
        binary.extend(data)
        image.pop("uri")
        image["bufferView"] = view
    document["buffers"] = [{"byteLength": len(binary)}]
    return document, bytes(binary)


def accessor_values(document: dict, binary: bytes, index: int) -> list[tuple]:
    accessor = document["accessors"][index]
    view = document["bufferViews"][accessor["bufferView"]]
    code, size = COMPONENTS[accessor["componentType"]]
    count = COUNTS[accessor["type"]]
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    stride = view.get("byteStride", size * count)
    return [struct.unpack_from("<" + code * count, binary, start + i * stride) for i in range(accessor["count"])]


def append_accessor(document: dict, binary: bytearray, values: list[tuple], component: int, kind: str) -> int:
    binary.extend(b"\0" * (-len(binary) % 4))
    offset = len(binary)
    code, _ = COMPONENTS[component]
    for value in values:
        binary.extend(struct.pack("<" + code * len(value), *value))
    view = len(document["bufferViews"])
    document["bufferViews"].append({"buffer": 0, "byteOffset": offset, "byteLength": len(binary) - offset})
    flat = [x for value in values for x in value]
    result = {"bufferView": view, "componentType": component, "count": len(values), "type": kind}
    if kind == "SCALAR":
        result.update(min=[min(flat)], max=[max(flat)])
    document["accessors"].append(result)
    return len(document["accessors"]) - 1


def simplify_primitive(document: dict, binary: bytes, primitive: dict, fraction: float) -> tuple[int, int]:
    attributes = primitive["attributes"]
    positions = accessor_values(document, binary, attributes["POSITION"])
    joints = accessor_values(document, binary, attributes["JOINTS_0"])
    weights = accessor_values(document, binary, attributes["WEIGHTS_0"])
    uvs = accessor_values(document, binary, attributes["TEXCOORD_0"])
    indices = [v[0] for v in accessor_values(document, binary, primitive["indices"])]
    target = math.ceil(len(indices) / 3 * fraction)
    cell = 0.01
    while True:
        clusters = {}
        remap = []
        for index, position in enumerate(positions):
            dominant = joints[index][weights[index].index(max(weights[index]))]
            key = tuple(math.floor(v / cell) for v in position) + (dominant,) + tuple(round(v / 0.1) for v in uvs[index])
            if key not in clusters:
                clusters[key] = []
            clusters[key].append(index)
            remap.append(clusters[key])
        representatives = [group[0] for group in clusters.values()]
        lookup = {id(group): i for i, group in enumerate(clusters.values())}
        remap = [lookup[id(group)] for group in remap]
        triangles = [tuple(remap[i] for i in indices[i:i + 3]) for i in range(0, len(indices), 3)]
        triangles = [tri for tri in triangles if len(set(tri)) == 3]
        if len(triangles) <= target or cell >= 0.08:
            break
        cell *= 1.2
    if cell > 0.08:
        raise ValueError("Could not simplify mesh safely")
    vertices = []
    for group in clusters.values():
        vertices.append({
            name: tuple(sum(values[index][axis] for index in group) / len(group) for axis in range(len(values[0])))
            if name in ("POSITION", "NORMAL") else values[group[0]]
            for name, values in [(name, accessor_values(document, binary, source)) for name, source in attributes.items()]
        })
    for name, accessor_index in attributes.items():
        kind = document["accessors"][accessor_index]["type"]
        component = document["accessors"][accessor_index]["componentType"]
        values = [vertex[name] for vertex in vertices]
        if name == "NORMAL":
            values = [tuple(v / max(math.sqrt(sum(x * x for x in value)), 1e-12) for v in value) for value in values]
        attributes[name] = append_accessor(document, binary, values, component, kind)
    primitive["indices"] = append_accessor(document, binary, [(i,) for tri in triangles for i in tri], 5125, "SCALAR")
    return len(indices) // 3, len(triangles)


def merge_source(document: dict, binary: bytearray, source: dict, source_binary: bytes, include_visuals: bool = True) -> dict:
    binary.extend(b"\0" * (-len(binary) % 4))
    base = len(binary)
    binary.extend(source_binary)
    offsets = {}
    for name in ["bufferViews", "accessors", "materials", "textures", "images", "meshes"]:
        offsets[name] = len(document.get(name, []))
    for view in source.get("bufferViews", []):
        copied = copy.deepcopy(view)
        copied["buffer"] = 0
        copied["byteOffset"] = copied.get("byteOffset", 0) + base
        document["bufferViews"].append(copied)
    names = ["accessors", "images", "meshes"] if include_visuals else ["accessors"]
    for name in names:
        for item in source.get(name, []):
            copied = copy.deepcopy(item)
            if name == "accessors" and "bufferView" in copied:
                copied["bufferView"] += offsets["bufferViews"]
            elif name == "images" and "bufferView" in copied:
                copied["bufferView"] += offsets["bufferViews"]
            document[name].append(copied)
    if not include_visuals:
        return offsets
    for sampler in source.get("samplers", []):
        document.setdefault("samplers", []).append(copy.deepcopy(sampler))
    for texture in source.get("textures", []):
        copied = copy.deepcopy(texture)
        if "source" in copied:
            copied["source"] += offsets["images"]
        document["textures"].append(copied)
    for material in source.get("materials", []):
        copied = copy.deepcopy(material)
        for key in ["baseColorTexture", "metallicRoughnessTexture", "normalTexture", "occlusionTexture", "emissiveTexture"]:
            def update(value):
                if isinstance(value, dict):
                    if key in value:
                        value[key]["index"] += offsets["textures"]
                    for child in value.values():
                        update(child)
                elif isinstance(value, list):
                    for child in value:
                        update(child)
        update(copied)
        copied["pbrMetallicRoughness"] = copied.get("pbrMetallicRoughness", {})
        copied["pbrMetallicRoughness"]["metallicFactor"] = 0.0
        copied["pbrMetallicRoughness"]["roughnessFactor"] = 0.92
        document["materials"].append(copied)
    for mesh in document["meshes"][offsets["meshes"]:]:
        for primitive in mesh["primitives"]:
            primitive["attributes"] = {key: value + offsets["accessors"] for key, value in primitive["attributes"].items()}
            if "indices" in primitive:
                primitive["indices"] += offsets["accessors"]
            if "material" in primitive:
                primitive["material"] += offsets["materials"]
    return offsets


def add_tool(document: dict, binary: bytearray, path: Path, name: str, bone: str) -> None:
    source, source_binary = embedded(path)
    offsets = merge_source(document, binary, source, source_binary)
    root = source["scenes"][source.get("scene", 0)]["nodes"][0]
    copied = copy.deepcopy(source["nodes"][root])
    copied["mesh"] += offsets["meshes"]
    copied.pop("children", None)
    mesh_index = len(document["nodes"])
    document["nodes"].append(copied)
    node_index = len(document["nodes"])
    document["nodes"].append({"name": "Attachment" + name + "__" + bone.replace(".", "_"), "children": [mesh_index], "extras": {"mineattack_bone": bone}})
    document["scenes"][document.get("scene", 0)]["nodes"].append(node_index)


def add_clip(document: dict, binary: bytearray, path: Path, source_name: str, alias: str, trim: tuple | None) -> None:
    source, source_binary = embedded(path)
    original = next((a for a in source["animations"] if a.get("name") == source_name), None)
    if original is None:
        raise ValueError(f"Missing clip {source_name} in {path}")
    by_name = {node["name"]: i for i, node in enumerate(document["nodes"])}
    for channel in original["channels"]:
        target = channel["target"]
        node_name = source["nodes"][target["node"]]["name"]
        if node_name not in by_name:
            raise ValueError(f"Native rig mismatch: {node_name}")
        if node_name in ("root", "Rig_Medium") and target["path"] == "translation":
            values = accessor_values(source, source_binary, original["samplers"][channel["sampler"]]["output"])
            if max(abs(v[i]) for v in values for i in range(3)) > 0.0001:
                raise ValueError(f"Root translation in {source_name}; select an in-place source")
    offsets = merge_source(document, binary, source, source_binary, include_visuals=False)
    channels = []
    samplers = []
    for channel in original["channels"]:
        sampler = original["samplers"][channel["sampler"]]
        copied = copy.deepcopy(sampler)
        if trim is not None:
            times = accessor_values(source, source_binary, sampler["input"])
            outputs = accessor_values(source, source_binary, sampler["output"])
            if sampler.get("interpolation", "LINEAR") not in ("LINEAR", "STEP"):
                raise ValueError(f"Unsupported trim interpolation in {source_name}")
            selected = [trim[0]] + [time[0] for time in times if trim[0] < time[0] < trim[1]] + [trim[1]]
            trimmed = []
            for time in selected:
                right = next((i for i, value in enumerate(times) if value[0] >= time), len(times) - 1)
                left = max(0, right - 1)
                span = max(times[right][0] - times[left][0], 0.000001)
                weight = 0.0 if sampler.get("interpolation") == "STEP" else max(0.0, min(1.0, (time - times[left][0]) / span))
                value = tuple(a + (b - a) * weight for a, b in zip(outputs[left], outputs[right]))
                if channel["target"]["path"] == "rotation":
                    length = math.sqrt(sum(x * x for x in value))
                    value = tuple(x / length for x in value)
                trimmed.append(value)
            component = source["accessors"][sampler["input"]]["componentType"]
            copied["input"] = append_accessor(document, binary, [(time - trim[0],) for time in selected], component, "SCALAR")
            kind = source["accessors"][sampler["output"]]["type"]
            component = source["accessors"][sampler["output"]]["componentType"]
            copied["output"] = append_accessor(document, binary, trimmed, component, kind)
        else:
            copied["input"] += offsets["accessors"]
            copied["output"] += offsets["accessors"]
        target = channel["target"]
        target["node"] = by_name[source["nodes"][target["node"]]["name"]]
        copied_channel = copy.deepcopy(channel)
        copied_channel["sampler"] = len(samplers)
        samplers.append(copied)
        channels.append(copied_channel)
    document.setdefault("animations", []).append({"name": alias, "channels": channels, "samplers": samplers,
        "extras": {"source_clip": source_name, "in_place": True}})


def merge_character(document: dict, binary: bytearray) -> None:
    primitives = [primitive for mesh in document["meshes"] for primitive in mesh["primitives"]]
    if len({primitive.get("material", 0) for primitive in primitives}) != 1:
        raise ValueError("Expected one shared character material")
    attributes = list(primitives[0]["attributes"])
    vertices = {name: [] for name in attributes}
    indices = []
    for mesh in document["meshes"]:
        for primitive in mesh["primitives"]:
            if list(primitive["attributes"]) != attributes or primitive.get("mode", 4) != 4:
                raise ValueError("Incompatible body primitive")
            offset = len(vertices["POSITION"])
            for name, source in primitive["attributes"].items():
                vertices[name].extend(accessor_values(document, bytes(binary), source))
            indices.extend(index[0] + offset for index in accessor_values(document, bytes(binary), primitive["indices"]))
    merged = {name: append_accessor(document, binary, values, document["accessors"][primitives[0]["attributes"][name]]["componentType"],
        document["accessors"][primitives[0]["attributes"][name]]["type"]) for name, values in vertices.items()}
    body_name = next(mesh["name"] for mesh in document["meshes"] if mesh["name"].endswith("_Body"))
    primitive = {"attributes": merged, "indices": append_accessor(document, binary, [(index,) for index in indices], 5125, "SCALAR"),
        "material": primitives[0].get("material", 0)}
    document["meshes"] = [{"name": body_name, "primitives": [primitive]}]
    body_node = None
    for index, node in enumerate(document["nodes"]):
        if "mesh" not in node:
            continue
        if any(key in node for key in ["matrix", "translation", "rotation", "scale"]):
            raise ValueError("Unexpected transformed skin mesh; normalize before merging")
        if node.get("name") == body_name:
            body_node = index
        else:
            node.pop("mesh")
            node.pop("skin", None)
            for parent in document["nodes"]:
                if "children" in parent and index in parent["children"]:
                    parent["children"].remove(index)
    if body_node is None:
        raise ValueError("Missing character body mesh node")
    document["nodes"][body_node]["mesh"] = 0


def build(role: str, config: dict, characters: Path, animations: Path, tools: Path) -> tuple[dict, bytes, dict]:
    character = characters / "Characters" / "gltf" / (config["character"] + ".glb")
    document, binary = embedded(character)
    binary = bytearray(binary)
    for material in document.get("materials", []):
        material["pbrMetallicRoughness"]["metallicFactor"] = 0.0
        material["pbrMetallicRoughness"]["roughnessFactor"] = 0.92
    if "simplify" in config:
        for mesh in document["meshes"]:
            if mesh["name"].endswith(("Cape", "Quiver")):
                continue
            for primitive in mesh["primitives"]:
                simplify_primitive(document, binary, primitive, config["simplify"])
    merge_character(document, binary)
    sources = {str(character.relative_to(ROOT)): sha(character)}
    for filename, name, bone in config["tools"]:
        source = tools / "Assets" / "gltf" / (filename + ".gltf")
        if not source.exists():
            source = characters / "Assets" / "gltf" / (filename + ".gltf")
        add_tool(document, binary, source, name, bone)
        sources[str(source.relative_to(ROOT))] = sha(source)
    clips = dict(COMMON)
    clips.update(config["clips"])
    for alias, (category, name, trim, loops) in clips.items():
        source = animations / "Animations" / "gltf" / "Rig_Medium" / ("Rig_Medium_" + category + ".glb")
        add_clip(document, binary, source, name, alias, trim)
        sources[str(source.relative_to(ROOT))] = sha(source)
    document["asset"]["generator"] = "MineAttack matching-rig KayKit curator"
    document["asset"]["extras"] = {"mineattack_role": role, "mineattack_sources": sources,
        "mineattack_loops": [alias for alias, spec in clips.items() if spec[3]]}
    document["buffers"] = [{"byteLength": len(binary)}]
    output = OUTPUT / ("unit_kaykit_" + role + ".glb")
    kit.write_glb(output, document, bytes(binary))
    report = validate(output)
    report["sources"] = sources
    report["path"] = str(output.relative_to(ROOT))
    return document, bytes(binary), report


def validate(path: Path) -> dict:
    document, buffers = kit.read_glb(path)
    binary = buffers[0]
    if any("uri" in image for image in document.get("images", [])):
        raise ValueError(f"{path}: external texture remains")
    if len(document.get("skins", [])) != 1:
        raise ValueError(f"{path}: expected one native skin")
    if sum(1 for node in document["nodes"] if "mesh" in node and "skin" in node) != 1:
        raise ValueError(f"{path}: expected one merged skinned body mesh")
    names = {animation["name"] for animation in document.get("animations", [])}
    required = {"idle", "walk", "attack", "death"}
    role = document["asset"].get("extras", {}).get("mineattack_role")
    required.update({"mine"} if role == "miner" else {"repair"} if role == "engineer" else set())
    if not required.issubset(names):
        raise ValueError(f"{path}: missing {required - names}")
    node_names = {node.get("name") for node in document["nodes"]}
    if not {"root", "hips", "handslot.r", "handslot.l"}.issubset(node_names):
        raise ValueError(f"{path}: native Rig_Medium bones missing")
    for animation in document["animations"]:
        for channel in animation["channels"]:
            target = channel["target"]
            if document["nodes"][target["node"]].get("name") in ("root", "Rig_Medium") and target["path"] == "translation":
                values = accessor_values(document, binary, animation["samplers"][channel["sampler"]]["output"])
                if max(abs(v[i]) for v in values for i in range(3)) > 0.0001:
                    raise ValueError(f"{path}: {animation['name']} contains root translation")
    _, triangles = kit.scene_geometry(document, buffers)
    if triangles > 8000:
        raise ValueError(f"{path}: {triangles} triangles exceeds 8000")
    return {"key": path.stem, "triangles": triangles, "clips": sorted(names), "sha256": sha(path)}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--characters", type=Path)
    parser.add_argument("--animations", type=Path)
    parser.add_argument("--tools", type=Path)
    parser.add_argument("--validate-only", action="store_true")
    args = parser.parse_args()
    if args.validate_only:
        for path in sorted(OUTPUT.glob("unit_kaykit_*.glb")):
            print(json.dumps(validate(path), sort_keys=True))
        return
    if not all([args.characters, args.animations, args.tools]):
        parser.error("all three source directories are required to rebuild")
    for role, config in ROLES.items():
        _, _, report = build(role, config, args.characters.resolve(), args.animations.resolve(), args.tools.resolve())
        print(json.dumps(report, sort_keys=True))


if __name__ == "__main__":
    main()
