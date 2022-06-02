#import "Basic";
#import "String";
#import "Window_Creation";
#import "Input";
// Math Matrices are row-major. In other words,
// you have [row 0][row 1][row 2][...] in memory.
#import "Math";
#import "File_Utilities";
#import "GL";
#import "Hash_Table";

simp :: #import "Simp";
getrect :: #import "GetRect";

#load "parse_utils.jai";
#load "render.jai";
#load "camera.jai";
#load "mesh.jai";
#load "anim.jai";
#load "ui.jai";

MAX_WEIGHTS :: 4;
MAX_JOINTS :: 1000;

g_window : Window_Type;
g_camera : Camera;
g_running : bool;
g_control_camera : bool;

g_font : *simp.Dynamic_Font;
g_checkbox_font : *simp.Dynamic_Font;
g_slider_font : *simp.Dynamic_Font;
g_dropdown_font : *simp.Dynamic_Font;

// We are using hash tables to store our meshes and animations,
// but in a real game we would have a better data structure(s), like
// a Bucket_Array (a hash table would still be useful to look-up asset
// by their name).
g_loaded_meshes : Table (string, Skinned_Mesh);
g_loaded_animations : Table (string, Sampled_Animation);
g_mesh : *Skinned_Mesh;
g_pose : Skeleton_Pose;

update_mesh :: (index : s64)
{
	free_pose (*g_pose);
	if index == 0
		g_mesh = null;
	else
	{
		g_mesh = table_find_pointer (*g_loaded_meshes, g_params.mesh_names[index]);
		assert (g_mesh != null);
		g_pose = make_pose_for_skeleton (g_mesh);
	}
	g_params.mesh_index = xx index;
}

handle_window_event :: (event : Event)
{
	getrect.getrect_handle_event (event);
	if event.type ==
	{
	case .QUIT;
		g_running = false;
	case .KEYBOARD;
		if event.key_pressed
		{
			if event.key_code == .ESCAPE
				set_camera_control (!g_control_camera);
			if event.key_code == .F4 && event.alt_pressed
				g_running = false;
		}
	}
}

set_camera_control :: inline (control : bool)
{
	g_control_camera = control;
	if g_control_camera
		hide_cursor ();
	else
		show_cursor ();
}

// Simp also has an init_fonts routine, but it's fine to define
// our own because we namespace the module when importing it!
init_fonts :: ()
{
	g_font = simp.get_font_at_size ("data/fonts", "OpenSans-Regular.ttf", 20);
	assert (g_font != null);
	g_checkbox_font = simp.get_font_at_size ("data/fonts", "OpenSans-Regular.ttf", 18);
	assert (g_checkbox_font != null);
	g_slider_font = simp.get_font_at_size ("data/fonts", "OpenSans-Italic.ttf", 16);
	assert (g_slider_font != null);
	g_dropdown_font = g_slider_font;
}

find_and_load_meshes_and_animations :: inline ()
{
	visitor :: (info : *File_Visit_Info, data : *void)
	{
		if info.is_directory
			return;
		path, basename, ext := path_decomp (info.full_name);
		if ext == "mesh"
		{
			mesh : Skinned_Mesh;
			loaded := load_mesh_from_file (*mesh, info.full_name);
			if loaded
			{
				init_mesh_rendering_objects (*mesh);
				table_add (*g_loaded_meshes, copy_string (basename), mesh);
			}
			else
				log_error ("Could not load % mesh.", basename);
		}
		else if ext == "anim"
		{
			anim : Sampled_Animation;
			loaded := load_animation_from_file (*anim, info.full_name);
			if loaded
				table_add (*g_loaded_animations, copy_string (basename), anim);
			else
				log_error ("Could not load % animation.", basename);
		}
	}

	visit_files ("data", true, null, visitor, visit_directories = true);
	// Initialize the asset names arrays.
	// This is used in the UI to choose the current mesh and animation.
	g_params.mesh_names = NewArray (g_loaded_meshes.count + 1, string);
	g_params.mesh_names[0] = "None";
	i := 1;
	for val, name : g_loaded_meshes
	{
		g_params.mesh_names[i] = name;
		i += 1;
	}
	g_params.animation_names = NewArray (g_loaded_animations.count + 1, string);
	g_params.animation_names[0] = "None";
	i = 1;
	for val, name : g_loaded_animations
	{
		g_params.animation_names[i] = name;
		i += 1;
	}

	// Start the program with a mesh and some animation
	g_params.mesh_index = xx (g_params.mesh_names.count - 1);
	g_params.animation_index = xx (g_params.animation_names.count - 1);
}

main :: ()
{
	g_window = create_window (1280, 720, "Skeletal Animation");
	defer print ("Program ended gracefully.\n");
	simp.set_render_target (g_window);
	getrect.ui_init ();
	init_fonts ();
	if !init_rendering_objects ()
		return;
	find_and_load_meshes_and_animations ();

	// Position the camera in a nice way
	g_camera.position = xyz (1, 1.3, 2.3);
	g_camera.euler_angles.x = -20 * PI / 180.0;
	g_camera.euler_angles.y = 10 * PI / 180.0;
	g_running = true;
	delta_time := 0.01667;
	glEnable (GL_BLEND);
	glBlendFunc (GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
	while g_running
	{
		frame_start := current_time_monotonic ();
		reset_temporary_storage ();
		update_window_events ();
		for events_this_frame
			handle_window_event (it);

		update_frame (delta_time);

		glDepthMask (GL_TRUE);
		glEnable (GL_DEPTH_TEST);
		simp.update_window (g_window);
		simp.clear_render_target (0.1, 0.1, 0.1, 1);
		glClear (GL_DEPTH_BUFFER_BIT);
		if g_mesh && g_params.show_mesh
			draw_mesh (g_mesh, Matrix4_Identity, g_pose.skinning_matrices);
		// Draw coordinate axes
		draw_line (.{}, .{x=1}, .{x=1, w=1});
		draw_line (.{}, .{y=1}, .{y=1, w=1});
		draw_line (.{}, .{z=1}, .{z=1, w=1});
		// Draw grid
		for i : -10..10
			draw_line (xyz (xx i, 0, -10), xyz (xx i, 0, 10), .{0.4, 0.4, 0.4, 1});
		for i : -10..10
			draw_line (xyz (-10, 0, xx i), xyz (10, 0, xx i), .{0.4, 0.4, 0.4, 1});

		if g_mesh && g_params.show_skeleton
		{
			// Disable depth mask and testing so we can see
			// the skeleton through other things
			glDepthMask (GL_FALSE);
			glDisable (GL_DEPTH_TEST);
			draw_pose (g_pose, Matrix4_Identity, xyzw (g_params.skeleton_color, 1));
		}

		update_ui (delta_time);

		swap_buffers (g_window);
		sleep_milliseconds (10);
		frame_end := current_time_monotonic ();
		delta_time = cast (float) to_float64_seconds (frame_end - frame_start);
	}
}

update_frame :: (delta_time : float)
{
	if !input_application_has_focus && g_control_camera
		set_camera_control (false);
	// Lock the cursor in the middle of the screen when controlling the camera
	if g_control_camera
	{
		x, y, w, h := get_dimensions (g_window, false);
		set_mouse_pointer_position (w / 2, h / 2);
	}

	update_flying_camera (*g_camera, delta_time);

	// Update the mesh if the user selected another one.
	// Ideally we would only call table_find_pointer when we know
	// the user selected another mesh, but I can't find a way to
	// do that in GetRect.
	new_mesh : *Skinned_Mesh;
	if g_params.mesh_index == 0
		new_mesh = null;
	else
		new_mesh = table_find_pointer (*g_loaded_meshes, g_params.mesh_names[g_params.mesh_index]);

	if g_mesh != new_mesh
	{
		g_mesh = new_mesh;
		// We changed the mesh, so reallocate a new pose
		free_pose (*g_pose);
		if g_mesh
			g_pose = make_pose_for_skeleton (g_mesh);
	}

	anim : *Sampled_Animation;
	if g_params.animation_index > 0
		anim = table_find_pointer (*g_loaded_animations, g_params.animation_names[g_params.animation_index]);
	else
		anim = null;

	if g_mesh
	{
		// We reset to the bind pose because the animation
		// might not have all of the joints our pose has.
		reset_to_bind_pose (*g_pose);
		if anim && g_params.show_animation
		{
			sample_animation (
				anim,
				g_params.animation_time,
				*g_pose,
				g_params.interpolation_mode
			);
		}
	}

	// Increment animation time
	if anim
	{
		g_params.animation_time += delta_time * g_params.animation_speed_in_fps;
		g_params.animation_time = fmod (g_params.animation_time, xx anim.sample_count);
	}
	else
		g_params.animation_time = 0;

	// We transpose the result because OpenGL stores matrices in column-major
	if g_mesh
		generate_skinning_matrices (*g_pose, transpose_result = true);
}

// Things that we define ourselves but they probably should be
// added to the appropriate modules:

is_key_down :: inline (key : Key_Code) -> bool #must
{
	return (input_button_states[cast (s64) key] & .DOWN) != 0;
}

show_cursor :: inline ()
{
	#if OS == .WINDOWS
	{
		win32 :: #import "Windows";
		win32.ShowCursor (1);
	}
	else
	{
		// @Todo!
	}
}

hide_cursor :: inline ()
{
	#if OS == .WINDOWS
	{
		win32 :: #import "Windows";
		win32.ShowCursor (0);
	}
	else
	{
		// @Todo!
	}
}

set_mouse_pointer_position :: inline (x : int, y : int)
{
	#if OS == .WINDOWS
	{
		// Windows module does not have SetCursorPos
		// win32 :: #import "Windows";
		// win32.SetCursorPos (xx x, xx y);
		// Hugh...
		user32 :: #foreign_system_library "User32";
		SetCursorPos :: (x : s32, y : s32) -> s32 #foreign user32;
		SetCursorPos (xx x, xx y);
	}
	else
	{
		// @Todo!
	}
}

// This is incomplete, and won't work for matrices that have shear.
// In that case we would use a polar decomposition, so this assumes
// your matrix does not have shear.
decompose_transform :: inline (mat : Matrix4) -> translation : Vector3, rotation : Quaternion, scale : Vector3
{
	translation := xyz (
		mat._14,
		mat._24,
		mat._34
	);
	rotation := get_rotation (mat);
	scale := xyz (
		length (xyz (mat._11, mat._21, mat._31)),
		length (xyz (mat._12, mat._22, mat._32)),
		length (xyz (mat._13, mat._23, mat._33))
	);

	return translation, rotation, scale;
}
