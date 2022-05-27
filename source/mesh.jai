Vertex :: struct
{
	position : Vector3;
	normal   : Vector3;
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

Skeleton :: struct
{
	Joint :: struct
	{
		id : s16;
		local_\ bind_transform : Matrix4;
		inverse_bind_transform : Matrix4;
		// Here's an example of using relative pointers:
		// With relative pointers, you can have pointers that
		// are relative to the place they are declared (i.e.
		// the address that parent points to is relative to the
		// address of parent itself).
		// This is very useful when you want to save space, because
		// you can decide the size of the pointer, and when serializing
		// or deserializing data.
		// Here, we know we can't have more than 32767 joints, so we use
		// 2 byte integers as pointers.
		parent       : *~s16 Joint;
		first_child  : *~s16 Joint;
		//prev_sibling : *~s16 Joint;	// We don't need that one for now
		next_sibling : *~s16 Joint;
	}

	name_to_joint_id : Table (string, s16);
	joints : []Joint;	// Root joint is joints[0]
}

// for_expansion
children :: (joint : *Skeleton.Joint, body : Code, flags : For_Flags) #expand
{
	current := joint.first_child;
	`it_index := 0;
	while current
	{
		defer current = current.next_sibling;
		defer it_index += 1;
		#if (flags & .POINTER) == .POINTER
			`it := current;
		else
			`it := <<current;
		#insert (remove = #assert false) body;
	}
}

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
		// Parse children
		child_count : s16;
		child_count, ok = parse_int (handler, s16);
		if !ok
			return false;
		if child_count > 0
		{
			line, ok := consume_next_line (handler);
			if !ok
				return error_out (handler, "Unexpected EOF.");
			current : *Skeleton.Joint;
			for i : 0..child_count - 1
			{
				id : int;
				id, ok, line = string_to_int (line);
				if !ok || child_count < 0 || child_count > 0x7fff
					return error_out (handler, "Expected an integer in the range [0;%].", 0x7fff);
				if i == 0
					joint.first_child = *mesh.joints.data[id];
				mesh.joints.data[id].parent = joint;
				if current
					current.next_sibling = *mesh.joints.data[id];
				current = *mesh.joints.data[id];
				line = trim_left (line);
			}
			if line.count > 0
				return error_out (handler, "Expected end of line.");
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
	if joint_count > 0x7fff
		return error_out (handler, "Too many joints (expected at most %, got %).", 0x7fff, joint_count);
	mesh.joints.data = alloc (size_of (Skeleton.Joint) * joint_count);
	memset (mesh.joints.data, 0, size_of (Skeleton.Joint) * joint_count);
	init (*mesh.name_to_joint_id, joint_count);
	vertex_count : s64;
	vertex_count, ok = parse_ident_and_int_line (*handler, "vertex_count");
	if !ok
		return false;
	mesh.vertices.data = alloc (size_of (Vertex) * vertex_count);
	triangle_count : s64;
	triangle_count, ok = parse_ident_and_int_line (*handler, "triangle_count");
	if !ok
		return false;
	mesh.indices.data = alloc (size_of (u32) * triangle_count * 3);
	// Parse joints
	line, found := consume_next_line (*handler);
	if line != "joints:"
		return error_out (handler, "Expected 'joints:', got '%' instead.", line);
	for i : 0..joint_count - 1
		if !parse_joint (*handler, mesh)
			return false;
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
	calculate_joint_transforms (mesh);

	return true;
}

init_rendering_objects :: (using mesh : *Skinned_Mesh)
{
	glGenVertexArrays (1, *vao);
	glBindVertexArray (vao);
	glGenBuffers (1, *vbo);
	glBindBuffer (GL_ARRAY_BUFFER, vbo);
	glBufferData (GL_ARRAY_BUFFER, size_of (Vertex) * vertices.count, vertices.data, GL_STATIC_DRAW);
	glGenBuffers (1, *ibo);
	glBindBuffer (GL_ELEMENT_ARRAY_BUFFER, ibo);
	glBufferData (GL_ELEMENT_ARRAY_BUFFER, size_of (u32) * indices.count, indices.data, GL_STATIC_DRAW);
	glEnableVertexAttribArray (0);
	glVertexAttribPointer (0, 3, GL_FLOAT, GL_FALSE, size_of (Vertex), cast (*void) 0);
	glEnableVertexAttribArray (1);
	glVertexAttribPointer (1, 3, GL_FLOAT, GL_FALSE, size_of (Vertex), cast (*void) size_of (Vector3));
	glEnableVertexAttribArray (2);
	glVertexAttribPointer (2, 3, GL_FLOAT, GL_FALSE, size_of (Vertex), cast (*void) (2 * size_of (Vector3)));
	glEnableVertexAttribArray (3);
	glVertexAttribIPointer (3, 4, GL_SHORT, size_of (Vertex), cast (*void) (3 * size_of (Vector3)));

	glBindVertexArray (0);
	glBindBuffer (GL_ARRAY_BUFFER, 0);
	glBindBuffer (GL_ELEMENT_ARRAY_BUFFER, 0);
}

calculate_joint_transforms :: (using skeleton : *Skeleton)
{
	calculate_for_one_joint :: (using joint : *Joint, parent_transform : Matrix4)
	{
		bind_transform := local_bind_transform * parent_transform;
		inverse_bind_transform = inverse (bind_transform);
		for * :children joint
			calculate_for_one_joint (it, bind_transform);
	}

	if joints.count > 0
		calculate_for_one_joint (*joints[0], Matrix4_Identity);
}
