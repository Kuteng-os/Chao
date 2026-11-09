extends RefCounted
## GUI dispatch follows sibling order, whereas the fan is painted using z_index.
## Resolve the whole fan once per query so a covered sibling cannot eat input.
static func pick(faces: Array, canvas_point: Vector2) -> Control:
	var selected: Control = null
	var selected_z := -1
	for face in faces:
		if not is_instance_valid(face) or not face.is_visible_in_tree() or not face.has_meta("rest_position"): continue
		var rest := Transform2D(float(face.get_meta("rest_rotation",0.0)),Vector2.ZERO)
		rest.origin=face.get_meta("rest_position")+face.pivot_offset-rest.basis_xform(face.pivot_offset)
		var transform: Transform2D=face.get_parent().get_global_transform_with_canvas()*rest
		if not Rect2(Vector2.ZERO,face.size).has_point(transform.affine_inverse()*canvas_point): continue
		var z: int=int(face.get_meta("rest_z",0))
		if z>selected_z: selected=face;selected_z=z
	if selected!=null: return selected
	# The raised part remains interactive above the original fan footprint.
	for face in faces:
		if not is_instance_valid(face) or not face.is_visible_in_tree() or not face.extended_hover: continue
		if Rect2(Vector2.ZERO,face.size).has_point(face.get_global_transform_with_canvas().affine_inverse()*canvas_point): return face
	return null
