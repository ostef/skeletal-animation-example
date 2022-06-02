Vertex :: struct
{
	position : Vector3;
	normal   : Vector3;
	// We can have at most 4 weights, but they have to sum up
	// to 1, so the last one can be calculated and we don't store it.
	weights  : Vector3;
	joints   : [4]s16;
}

Skinned_Mesh :: struct
{
	#as using skeleton : Skeleton;
	vertices : []Vertex;
	indices  : []u32;
	vao, vbo, ibo : GLuint;
}

#assert MAX_JOINTS <= 0x7fff "MAX_JOINTS can't exceed the max of an s16, since we use that for joint ids.";

// The skeleton is separate from the mesh so that you
// can operate on a skeleton without refering to a mesh.
Skeleton :: struct
{
	Joint :: struct
	{
		id : s16;
		// This is the matrix of the joint in the rest position,
		// relative to the parent's coordinate system
		local_bind_transform : Matrix4;
		// This is the inverse of the matrix of the joint in model space.
		// Why we have this matrix is explained in anim.jai:generate_skinning_matrices
		inverse_bind_transform : Matrix4;
		// Here's an example of using relative pointers:
		// With relative pointers, you can have pointers that
		// are relative to the place they are declared (i.e.
		// the address that parent points to is relative to the
		// address of parent itself).
		// This is very useful when you want to save space, because
		// you can decide the size of the pointer, and when serializing
		// or deserializing data, since the pointers won't move relative
		// to each other.
		// Here, we know we can't have more than 1000 joints, so we use
		// 2 byte integers as pointers.
		parent : *~s16 Joint;
	}

	name_to_joint_id : Table (string, s16);
	joints : []Joint;	// Root joint is joints[0]
}

// In a real game engine, we would use binary file formats, but this
// shows how you can use the Text_File_Handler. Maybe we should have
// a binary file format though, to show how you can load these.
load_mesh_from_file :: (mesh : *Skinned_Mesh, filename : string) -> bool
{
	parse_joint :: (handler : *Text_File_Handler, mesh : *Skinned_Mesh) -> bool
	{
		name, ok := consume_next_line (handler);
		if !ok
			return false;
		joint := *mesh.joints.data[mesh.joints.count];
		joint.id = xx mesh.joints.count;
		table_add (*mesh.name_to_joint_id, copy_string (name), joint.id);
		mesh.joints.count += 1;
		joint.local_bind_transform, ok = parse_matrix4 (handler);
		// Parse parent id
		parent_id : s16;
		parent_id, ok = parse_int (handler, s16);
		if !ok
			return false;
		// Set the inverse bind transform to the model space transform first.
		// We will invert the matrices after everything has been calculated.
		// @Robustness: We don't check if the parent_id is valid!
		if parent_id >= 0
		{
			joint.parent = *mesh.joints.data[parent_id];
			joint.inverse_bind_transform = joint.parent.inverse_bind_transform * joint.local_bind_transform;
		}
		else
		{
			joint.parent = null;
			joint.inverse_bind_transform = joint.local_bind_transform;
		}

		return true;
	}

	parse_vertex :: (handler : *Text_File_Handler, mesh : *Skinned_Mesh) -> bool
	{
		ok : bool;
		vertex : Vertex;
		vertex.position, ok = parse_vector3 (handler);
		if !ok
			return false;
		vertex.normal, ok = parse_vector3 (handler);
		if !ok
			return false;
		vertex.weights, ok = parse_vector3 (handler);
		if !ok
			return false;
		vertex.joints, ok = parse_int_tuple (handler, 4, s16);
		if !ok
			return false;
		mesh.vertices.data[mesh.vertices.count] = vertex;
		mesh.vertices.count += 1;

		return true;
	}

	parse_triangle :: (handler : *Text_File_Handler, mesh : *Skinned_Mesh) -> bool
	{
		tri, ok := parse_int_tuple (handler, 3, u32);
		if !ok
			return false;
		mesh.indices.data[mesh.indices.count + 0] = tri[0];
		mesh.indices.data[mesh.indices.count + 1] = tri[1];
		mesh.indices.data[mesh.indices.count + 2] = tri[2];
		mesh.indices.count += 3;
		return true;
	}

	handler : Text_File_Handler;
	defer deinit (*handler);

	found_slash, dir, basename := split_from_right (filename, #char "/");
	if !found_slash then basename = filename;
	start_file (*handler, basename, filename, optional = false);
	if handler.failed
		return false;

	if handler.version != 1
		return error_out (handler, "Invalid version number.");

	joint_count, ok := parse_ident_and_int_line (*handler, "joint_count");
	if !ok
		return false;
	if joint_count > MAX_JOINTS
		return error_out (handler, "Too many joints (expected at most %, got %).", MAX_JOINTS, joint_count);

	vertex_count : s64;
	vertex_count, ok = parse_ident_and_int_line (*handler, "vertex_count");
	if !ok
		return false;

	triangle_count : s64;
	triangle_count, ok = parse_ident_and_int_line (*handler, "triangle_count");
	if !ok
		return false;

	// We set the count of the joints, vertices and indices arrays
	// to 0 and increment it each time we parse an element.
	all_data := alloc (size_of (Skeleton.Joint) * joint_count
		+ size_of (Vertex) * vertex_count
		+ size_of (u32) * triangle_count * 3
	);

	mesh.joints.data = all_data;
	mesh.joints.count = 0;
	init (*mesh.name_to_joint_id, joint_count);

	mesh.vertices.data = all_data + size_of (Skeleton.Joint) * joint_count;
	mesh.vertices.count = 0;

	mesh.indices.data = all_data + size_of (Skeleton.Joint) * joint_count + size_of (Vertex) * vertex_count;
	mesh.indices.count = 0;

	// Parse joints
	line, found := consume_next_line (*handler);
	if line != "joints:"
		return error_out (handler, "Expected 'joints:', got '%' instead.", line);
	for i : 0..joint_count - 1
		if !parse_joint (*handler, mesh)
			return false;

	for * mesh.joints
		it.inverse_bind_transform = inverse (it.inverse_bind_transform);

	// Parse vertices
	line, found = consume_next_line (*handler);
	if line != "vertices:"
		return error_out (handler, "Expected 'vertices:', got '%' instead.", line);
	for i : 0..vertex_count - 1
		if !parse_vertex (*handler, mesh)
			return false;

	// Parse triangles
	line, found = consume_next_line (*handler);
	if line != "triangles:"
		return error_out (handler, "Expected 'triangles:', got '%' instead.", line);
	for i : 0..triangle_count - 1
		if !parse_triangle (*handler, mesh)
			return false;

	line, found = consume_next_line (*handler);
	if found
		return error_out (handler, "Expected EOF.");

	return true;
}
