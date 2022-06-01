g_mesh_shader : GLuint;
g_line_shader : GLuint;
g_line_vao, g_line_vbo : GLuint;
g_big_data_ubo : GLuint;

GL_BIG_DATA_UNIFORM_BINDING :: 0;

// Used for line rendering
Vertex_Pos_Color :: struct
{
	position : Vector3;
	color : Vector4;
}

#scope_file

// In OpenGL land, we write programs in the GLSL language to
// (usually) be executed on the GPU.
// The 'vertex shader' is the first shader to be executed. It
// takes as input the data for a vertex, which we define, and
// it is responsible for transforming that vertex in any way it
// wants (such as applying the model transform, the camera projection).
// The 'fragment shader' is the last shader to be executed. It
// executes per-pixel, and takes as input anything that you want,
// and as output it gives the color of the pixel.
create_shader_program :: (vertex_source : string, fragment_source : string) -> GLuint, bool
{
	check_compile_errors :: (shader : GLuint) -> bool, info_log : string
	{
		success : s32;
		glGetShaderiv (shader, GL_COMPILE_STATUS, *success);
		if !success
		{
			info_len : s32;
			glGetShaderiv (shader, GL_INFO_LOG_LENGTH, *info_len);
			info_data := cast (*u8) alloc (info_len, temp);
			glGetShaderInfoLog (shader, xx info_len, xx *info_len, info_data);
			result : string;
			result.data = info_data;
			result.count = info_len;

			return false, result;
		}

		return true, "";
	}

	check_link_errors :: (program : GLuint) -> bool, info_log : string
	{
		success : s32;
		glGetProgramiv (program, GL_LINK_STATUS, *success);
		if !success
		{
			info_len : s32;
			glGetProgramiv (program, GL_INFO_LOG_LENGTH, *info_len);
			info_data := cast (*u8) alloc (info_len, temp);
			glGetProgramInfoLog (program, xx info_len, xx *info_len, info_data);
			result : string;
			result.data = info_data;
			result.count = info_len;

			return false, result;
		}

		return true, "";
	}

	// OpenGL requires us to create at least a vertex shader and a
	// fragment shader, to create a shader program that it can execute.
	vs := glCreateShader (GL_VERTEX_SHADER);
	defer glDeleteShader (vs);
	glShaderSource (vs, 1, *vertex_source.data, null);
	glCompileShader (vs);
	ok, info_log := check_compile_errors (vs);
	if !ok
	{
		log_error ("Could not compile vertex shader: %", info_log);
		return 0, false;
	}
	
	fs := glCreateShader (GL_FRAGMENT_SHADER);
	defer glDeleteShader (fs);
	glShaderSource (fs, 1, *fragment_source.data, null);
	glCompileShader (fs);
	ok, info_log = check_compile_errors (fs);
	if !ok
	{
		log_error ("Could not compile fragment shader: %", info_log);
		return 0, false;
	}

	result := glCreateProgram ();
	glAttachShader (result, vs);
	glAttachShader (result, fs);
	glLinkProgram (result);
	ok, info_log = check_link_errors (result);
	if !ok
	{
		log_error ("Could not link shader program: %", info_log);
		glDeleteProgram (result);
		return 0, false;
	}

	return result, true;
}

#scope_export

init_rendering_objects :: () -> bool
{
	// Check if we can store enough data for the skinning
	// information in a shader uniform block.
	uniform_block_size : s32;
	glGetIntegerv (GL_MAX_UNIFORM_BLOCK_SIZE, *uniform_block_size);
	assert (uniform_block_size >= MAX_JOINTS * size_of (Matrix4),
		"OpenGL implementation does not allow storing more than % bytes in uniform block, but we need at least % for skinning information. Recompile the program with a smaller MAX_JOINTS value.",
		uniform_block_size, MAX_JOINTS * size_of (Matrix4));

	// Create the shader programs we will use throughout
	// our application to render meshes and lines.
	// The source of these programs are at the end of the file.
	ok : bool;
	g_mesh_shader, ok = create_shader_program (MESH_VERTEX_SHADER, MESH_FRAGMENT_SHADER);
	if !ok
		return false;
	// We need to bind the block in the mesh shader to a binding point
	// that we define to be GL_BIG_DATA_UNIFORM_BINDING
	big_data_uniform_index := glGetUniformBlockIndex (g_mesh_shader, "Big_Data");
	glUniformBlockBinding (g_mesh_shader, big_data_uniform_index, GL_BIG_DATA_UNIFORM_BINDING);

	g_line_shader, ok = create_shader_program (LINE_VERTEX_SHADER, LINE_FRAGMENT_SHADER);
	if !ok
		return false;

	// Create line objects. We have a vertex buffer that we fill
	// every time we want to draw a line.
	glGenVertexArrays (1, *g_line_vao);
	glBindVertexArray (g_line_vao);
	glGenBuffers (1, *g_line_vbo);
	glBindBuffer (GL_ARRAY_BUFFER, g_line_vbo);
	glBufferData (GL_ARRAY_BUFFER, size_of (Vertex_Pos_Color) * 2, null, GL_DYNAMIC_DRAW);
	glEnableVertexAttribArray (0);
	glVertexAttribPointer (0, 3, GL_FLOAT, GL_FALSE, size_of (Vertex_Pos_Color), cast (*void) 0);
	glEnableVertexAttribArray (1);
	glVertexAttribPointer (1, 4, GL_FLOAT, GL_FALSE, size_of (Vertex_Pos_Color), cast (*void) size_of (Vector3));

	glBindVertexArray (0);
	glBindBuffer (GL_ARRAY_BUFFER, 0);

	// Create big data uniform buffer object
	glGenBuffers (1, *g_big_data_ubo);
	glBindBuffer (GL_UNIFORM_BUFFER, g_big_data_ubo);
	// Allocate the data for the uniform buffer. This data will
	// be filled with all the skinning matrices.
	glBufferData (GL_UNIFORM_BUFFER, size_of (Matrix4) * MAX_JOINTS, null, GL_DYNAMIC_DRAW);
	glBindBuffer (GL_UNIFORM_BUFFER, 0);
	glBindBufferBase (GL_UNIFORM_BUFFER, GL_BIG_DATA_UNIFORM_BINDING, g_big_data_ubo);

	return true;
}

init_mesh_rendering_objects :: (using mesh : *Skinned_Mesh)
{
	// OpenGL stuff... We need a vertex buffer, that holds
	// all our vertices, and an index buffer, that holds
	// all of our indices. We also need a vertex array, that
	// holds the information of the layout of our vertex buffer.
	glGenBuffers (1, *vbo);
	glBindBuffer (GL_ARRAY_BUFFER, vbo);
	defer glBindBuffer (GL_ARRAY_BUFFER, 0);
	glBufferData (GL_ARRAY_BUFFER, size_of (Vertex) * vertices.count, vertices.data, GL_STATIC_DRAW);

	glGenBuffers (1, *ibo);
	glBindBuffer (GL_ELEMENT_ARRAY_BUFFER, ibo);
	defer glBindBuffer (GL_ELEMENT_ARRAY_BUFFER, 0);
	glBufferData (GL_ELEMENT_ARRAY_BUFFER, size_of (u32) * indices.count, indices.data, GL_STATIC_DRAW);

	glGenVertexArrays (1, *vao);
	glBindVertexArray (vao);
	defer glBindVertexArray (0);
	glEnableVertexAttribArray (0);
	glVertexAttribPointer (0, 3, GL_FLOAT, GL_FALSE, size_of (Vertex), cast (*void) 0);
	glEnableVertexAttribArray (1);
	glVertexAttribPointer (1, 3, GL_FLOAT, GL_FALSE, size_of (Vertex), cast (*void) size_of (Vector3));
	glEnableVertexAttribArray (2);
	glVertexAttribPointer (2, 3, GL_FLOAT, GL_FALSE, size_of (Vertex), cast (*void) (2 * size_of (Vector3)));
	glEnableVertexAttribArray (3);
	glVertexAttribIPointer (3, 4, GL_SHORT, size_of (Vertex), cast (*void) (3 * size_of (Vector3)));
}

draw_line :: inline (start : Vector3, end : Vector3, color : Vector4)
{
	draw_line (start, end, color, color);
}

// This is maybe the slowest way possible to draw a line!
draw_line :: (start : Vector3, end : Vector3, start_color : Vector4, end_color : Vector4)
{
	data : [2]Vertex_Pos_Color = ---;
	data[0].position = start;
	data[0].color    = start_color;
	data[1].position = end;
	data[1].color    = end_color;

	glBindVertexArray (g_line_vao);
	glBindBuffer (GL_ARRAY_BUFFER, g_line_vbo);
	// Fill the vertex buffer with our two line vertices
	glBufferSubData (GL_ARRAY_BUFFER, 0, size_of (Vertex_Pos_Color) * 2, data.data);
	glUseProgram (g_line_shader);
	glUniformMatrix4fv (glGetUniformLocation (g_line_shader, "u_View_Projection_Matrix"), 1, GL_TRUE, *g_camera.view_projection_matrix.coef[0][0]);
	glDrawArrays (GL_LINES, 0, 2);
}

draw_mesh :: (using mesh : Skinned_Mesh, model_matrix : Matrix4, skinning_matrices : []Matrix4)
{
	assert (skinning_matrices.count <= MAX_JOINTS, "Skinning matrices array cannot have more than % elements for now.");

	// Fill the uniform buffer with the skinning data
	glBindBuffer (GL_UNIFORM_BUFFER, g_big_data_ubo);
	glBufferSubData (GL_UNIFORM_BUFFER, 0, size_of (Matrix4) * skinning_matrices.count, skinning_matrices.data);
	glBindBuffer (GL_UNIFORM_BUFFER, 0);

	glBindVertexArray (vao);
	glBindBuffer (GL_ARRAY_BUFFER, vbo);
	glBindBuffer (GL_ELEMENT_ARRAY_BUFFER, ibo);
	glUseProgram (g_mesh_shader);

	glUniformMatrix4fv (glGetUniformLocation (g_mesh_shader, "u_Model_Matrix"), 1, GL_TRUE, *model_matrix.coef[0][0]);
	glUniformMatrix4fv (glGetUniformLocation (g_mesh_shader, "u_View_Projection_Matrix"), 1, GL_TRUE, *g_camera.view_projection_matrix.coef[0][0]);

	glDrawElements (GL_TRIANGLES, cast (u32) indices.count, GL_UNSIGNED_INT, null);
}

draw_skeleton :: (using skeleton : Skeleton, transform : Matrix4, color : Vector4)
{
	draw_joint :: (joint : *Joint, transform : Matrix4, color : Vector4) -> joint_position : Vector3
	{
		model_space_transform := inverse (joint.inverse_bind_transform);
		world_space_transform := transform * model_space_transform;
		start := xyz (
			world_space_transform._14,
			world_space_transform._24,
			world_space_transform._34
		);

		for * :children joint
		{
			end := draw_joint (it, transform, color);
			draw_line (start, end, color);
		}

		return start;
	}

	if skeleton.joints.count > 0
		draw_joint (*skeleton.joints[0], transform, color);
}

draw_pose :: (pose : Skeleton_Pose, transform : Matrix4, color : Vector4)
{
	draw_joint :: (pose : Skeleton_Pose, joint : *Skeleton.Joint, transform : Matrix4, color : Vector4) -> joint_position : Vector3
	{
		joint_pose := *pose.joints[joint.id];
		world_space_transform := transform * joint_pose.model_space_transform;
		start := xyz (
			world_space_transform._14,
			world_space_transform._24,
			world_space_transform._34
		);

		for * :children joint
		{
			end := draw_joint (pose, it, transform, color);
			draw_line (start, end, color);
		}

		return start;
	}

	if pose.joints.count > 0
		draw_joint (pose, *pose.skeleton.joints[0], transform, color);
}

// Following is the vertex and fragment shaders for rendering
// skinned meshes and lines.

MESH_VERTEX_SHADER :: #insert #run sprint (#string END
#string GLSL
#version 330 core

// These will be replaced with the values we defined in the Jai source code
const int MAX_JOINTS  = %1;
const int MAX_WEIGHTS = %2;

layout (location = 0) in vec3 a_Position;
layout (location = 1) in vec3 a_Normal;
layout (location = 2) in vec3 a_Weights;
layout (location = 3) in ivec4 a_Joint_Ids;

uniform mat4 u_Model_Matrix;
uniform mat4 u_View_Projection_Matrix;
// A simple uniform variable cannot hold a lot of data,
// so we use a uniform block to store the skinning information.
// A uniform block can hold more data, and we check if the
// OpenGL implementation allows us to store enough at the
// start of the program.
layout (std140) uniform Big_Data
{
	mat4 u_Skinning_Matrices[MAX_JOINTS];
};

out vec3 Normal;

void main ()
{
	vec3 model_position = vec3 (0);
	vec3 model_normal = vec3 (0);
	if (a_Joint_Ids[0] == -1)
	{
		model_position = a_Position;
		model_normal   = a_Normal;
	}
	for (int i = 0; i < MAX_WEIGHTS && a_Joint_Ids[i] != -1; i += 1)
	{
		int joint_id = a_Joint_Ids[i];
		float weight;
		if (i == MAX_WEIGHTS - 1)
			weight = 1 - (a_Weights.x + a_Weights.y + a_Weights.z);
		else
			weight = a_Weights[i];
		mat4 skinning_matrix = u_Skinning_Matrices[joint_id];
		vec3 pose_position = (skinning_matrix * vec4 (a_Position, 1)).xyz;
		model_position += pose_position * weight;
		vec3 pose_normal = (skinning_matrix * vec4 (a_Normal, 0)).xyz;
		model_normal += pose_normal * weight;
	}
	gl_Position = u_View_Projection_Matrix * u_Model_Matrix * vec4 (model_position, 1);
	Normal = model_normal.xyz;
}
GLSL
END, MAX_JOINTS, MAX_WEIGHTS);

MESH_FRAGMENT_SHADER :: #string GLSL
#version 330 core

in vec3 Normal;

out vec4 Frag_Color;

void main ()
{
	Frag_Color = vec4 (Normal, 1);
}
GLSL

LINE_VERTEX_SHADER :: #string GLSL
#version 330 core

layout (location = 0) in vec3 a_Position;
layout (location = 1) in vec4 a_Color;

uniform mat4 u_View_Projection_Matrix;

out vec4 Color;

void main ()
{
	gl_Position = u_View_Projection_Matrix * vec4 (a_Position, 1);
	Color = a_Color;
}
GLSL

LINE_FRAGMENT_SHADER :: #string GLSL
#version 330 core

in vec4 Color;

out vec4 Frag_Color;

void main ()
{
	Frag_Color = Color;
}
GLSL
