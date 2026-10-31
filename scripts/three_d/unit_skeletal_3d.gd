class_name UnitSkeletal3D
extends RefCounted


static func prepare(instance: Node3D, entry: Dictionary) -> Dictionary:
	var skeletons := instance.find_children("*", "Skeleton3D", true, false)
	var players := instance.find_children("*", "AnimationPlayer", true, false)
	if skeletons.size() != 1 or players.size() != 1:
		return {}
	var skeleton := skeletons[0] as Skeleton3D
	var player := players[0] as AnimationPlayer
	for bone in ["root", "hips", "handslot.r", "handslot.l"]:
		if skeleton.find_bone(bone) < 0:
			return {}
	for clip in entry.get("skeletal_clips", []):
		if not player.has_animation(StringName(str(clip))):
			return {}
		var animation := player.get_animation(StringName(str(clip)))
		for track in range(animation.get_track_count()):
			var path := str(animation.track_get_path(track))
			if animation.track_get_type(track) == Animation.TYPE_POSITION_3D \
					and (path.ends_with(":root") or path.ends_with(":Rig_Medium")):
				return {}
	for clip in entry.get("skeletal_loops", []):
		var name := StringName(str(clip))
		if player.has_animation(name):
			player.get_animation(name).loop_mode = Animation.LOOP_LINEAR
	player.playback_process_mode = AnimationPlayer.ANIMATION_PROCESS_MANUAL
	for node in instance.find_children("Attachment*", "Node3D", true, false):
		var parts := str(node.name).split("__")
		if parts.size() != 2:
			return {}
		var bone := parts[1].replace("_", ".")
		if skeleton.find_bone(bone) < 0:
			return {}
		var attachment := BoneAttachment3D.new()
		attachment.name = str(node.name) + "Bone"
		skeleton.add_child(attachment)
		attachment.bone_name = bone
		node.get_parent().remove_child(node)
		node.owner = null
		attachment.add_child(node)
		(node as Node3D).transform = Transform3D.IDENTITY
	var role := str(entry.get("skeletal_role", ""))
	if role == "miner":
		_add_miner_lamp(skeleton)
	elif role == "engineer":
		_add_engineer_pack(skeleton)
	elif role == "wizard":
		_add_wizard_glow(skeleton)
	_add_faction_badges(skeleton, role)
	return {"skeleton": skeleton, "animation_player": player}


static func _rest_global(skeleton: Skeleton3D, bone: int) -> Transform3D:
	var result := skeleton.get_bone_rest(bone)
	var parent := skeleton.get_bone_parent(bone)
	return _rest_global(skeleton, parent) * result if parent >= 0 else result


static func _at_bone(skeleton: Skeleton3D, bone: String, local_pos: Vector3) -> Node3D:
	var attachment := BoneAttachment3D.new()
	skeleton.add_child(attachment)
	attachment.bone_name = bone
	var holder := Node3D.new()
	attachment.add_child(holder)
	var index := skeleton.find_bone(bone)
	holder.transform = _rest_global(skeleton, index).affine_inverse() * Transform3D(Basis.IDENTITY, local_pos)
	return holder


static func _material(slot: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = slot
	mat.roughness = ArtStyle3D.MATERIAL_ROUGHNESS
	return mat


static func _array_mesh(primitive: PrimitiveMesh) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, primitive.get_mesh_arrays())
	return mesh


static func _box(parent: Node3D, size: Vector3, pos: Vector3, slot: String) -> MeshInstance3D:
	var primitive := BoxMesh.new()
	primitive.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = _array_mesh(primitive)
	instance.position = pos
	instance.set_surface_override_material(0, _material(slot))
	parent.add_child(instance)
	return instance


static func _add_miner_lamp(skeleton: Skeleton3D) -> void:
	var holder := _at_bone(skeleton, "head", Vector3(0.0, 2.15, -0.55))
	_box(holder, Vector3(0.17, 0.13, 0.08), Vector3.ZERO, "glow_lamp")
	_box(holder, Vector3(0.62, 0.15, 0.10), Vector3(0.0, -0.16, 0.07), "team")
	var pack := _at_bone(skeleton, "chest", Vector3(0.0, 1.35, 0.46))
	_box(pack, Vector3(0.68, 0.72, 0.30), Vector3.ZERO, "wood")
	_box(pack, Vector3(0.72, 0.12, 0.32), Vector3(0.0, 0.25, 0.0), "accent")


static func _add_engineer_pack(skeleton: Skeleton3D) -> void:
	var holder := _at_bone(skeleton, "chest", Vector3(0.0, 1.45, 0.46))
	holder.name = "ToolBackpack"
	_box(holder, Vector3(0.66, 0.75, 0.32), Vector3.ZERO, "accent")
	var roll := MeshInstance3D.new()
	var primitive := CylinderMesh.new()
	primitive.top_radius = 0.15
	primitive.bottom_radius = 0.15
	primitive.height = 0.72
	primitive.radial_segments = 8
	roll.mesh = _array_mesh(primitive)
	roll.rotation.z = PI * 0.5
	roll.position.y = 0.45
	roll.set_surface_override_material(0, _material("wood"))
	holder.add_child(roll)


static func _add_wizard_glow(skeleton: Skeleton3D) -> void:
	var staff := skeleton.find_child("AttachmentStaff__handslot_r", true, false) as Node3D
	if staff != null:
		_box(staff, Vector3(0.18, 0.18, 0.18), Vector3(0.04, 1.18, 0.0), "glow_staff")


static func _add_faction_badges(skeleton: Skeleton3D, role: String) -> void:
	var front := -0.58 if role == "wizard" else -0.40
	var holder := _at_bone(skeleton, "chest", Vector3(0.0, 1.5, front))
	for faction in ["Arcane", "Brute", "Industrial"]:
		var badge := Node3D.new()
		badge.name = "Faction" + faction
		holder.add_child(badge)
		var mesh := _box(badge, Vector3(0.17, 0.17, 0.04), Vector3.ZERO, "accent")
		if faction == "Arcane":
			mesh.rotation.z = PI * 0.25
		elif faction == "Industrial":
			mesh.scale = Vector3(0.65, 1.25, 1.0)
