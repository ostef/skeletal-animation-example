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

#load "parse.jai";
#load "render.jai";
#load "camera.jai";
#load "mesh.jai";
#load "anim.jai";
#load "ui.jai";

g_window : Window_Type;
g_camera : Camera;
g_running : bool;
g_control_camera : bool;

g_font : *simp.Dynamic_Font;
g_checkbox_font : *simp.Dynamic_Font;
g_slider_font : *simp.Dynamic_Font;
g_dropdown_font : *simp.Dynamic_Font;

g_loaded_meshes : Table (string, Skinned_Mesh);
g_loaded_animations : Table (string, Sampled_Animation);

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
	g_font = simp.get_font_at_size ("data", "OpenSans-Regular.ttf", 20);
	assert (g_font != null);
	g_checkbox_font = simp.get_font_at_size ("data", "OpenSans-Regular.ttf", 18);
	assert (g_checkbox_font != null);
	g_slider_font = simp.get_font_at_size ("data", "OpenSans-Italic.ttf", 16);
	assert (g_slider_font != null);
	g_dropdown_font = g_slider_font;
}

find_and_load_assets :: inline ()
{
	visitor :: (info : *File_Visit_Info, data : *void)
	{
		if info.is_directory
			return;
		if ends_with (info.full_name, ".mesh")
		{
			mesh : Skinned_Mesh;
			mesh_name := info.short_name;
			mesh_name.count -= ".mesh".count;
			loaded := load_mesh_from_file (*mesh, info.full_name);
			if loaded
			{
				init_rendering_objects (*mesh);
				table_add (*g_loaded_meshes, copy_string (mesh_name), mesh);
			}
			else
				log_error ("Could not load % mesh.", mesh_name);
		}
		else if ends_with (info.full_name, ".anim")
		{
			anim : Sampled_Animation;
			anim_name := info.short_name;
			anim_name.count -= ".anim".count;
			loaded := load_animation_from_file (*anim, info.full_name);
			if loaded
				table_add (*g_loaded_animations, copy_string (anim_name), anim);
			else
				log_error ("Could not load % animation.", anim_name);
		}
	}

	visit_files ("data", true, null, visitor, visit_directories = true);
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
	find_and_load_assets ();

	g_camera.position = xyz (0, 1, 4);
	g_running = true;
	delta_time := 0.01667;
	set_camera_control (true);
	glEnable (GL_BLEND);
	glBlendFunc (GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
	while g_running
	{
		frame_start := current_time_monotonic ();
		reset_temporary_storage ();
		update_window_events ();
		for get_window_resizes ()
			simp.update_window (it.window);
		for events_this_frame
			handle_window_event (it);
		
		if !input_application_has_focus && g_control_camera
			set_camera_control (false);
		if g_control_camera
		{
			x, y, w, h := get_dimensions (g_window, false);
			set_mouse_pointer_position (w / 2, h / 2);
		}

		update_flying_camera (*g_camera, delta_time);
		mesh : *Skinned_Mesh;
		if g_params.mesh_index > 0
			mesh = table_find_pointer (*g_loaded_meshes, g_params.mesh_names[g_params.mesh_index]);
		anim : *Sampled_Animation;
		if g_params.animation_index > 0
			anim = table_find_pointer (*g_loaded_animations, g_params.animation_names[g_params.animation_index]);
		pose : Skeleton_Pose;
		if mesh
		{
			pose = make_pose_for_skeleton (mesh, allocator = temp);
			reset_to_bind_pose (*pose);
		}
		if mesh && anim && g_params.show_animation
			sample_animation (
				anim,
				g_params.animation_time,
				*pose,
				g_params.interpolation_mode
			);
			
		if anim
		{
			g_params.animation_time += delta_time * g_params.animation_speed_in_fps;
			g_params.animation_time = fmod (g_params.animation_time, xx anim.sample_count);
		}
		else
			g_params.animation_time = 0;
		skinning_matrices : []Matrix4;
		if mesh
			skinning_matrices = generate_skinning_matrices (*pose, temp);

		glDepthMask (GL_TRUE);
		glEnable (GL_DEPTH_TEST);
		simp.clear_render_target (0.1, 0.1, 0.1, 1);
		glClear (GL_DEPTH_BUFFER_BIT);
		if mesh && g_params.show_mesh
			draw_mesh (mesh, Matrix4_Identity, skinning_matrices);
		// Draw coordinate axes
		draw_line (xyz (0, 0, 0), xyz (1, 0, 0), xyzw (1, 0, 0, 1));
		draw_line (xyz (0, 0, 0), xyz (0, 1, 0), xyzw (0, 1, 0, 1));
		draw_line (xyz (0, 0, 0), xyz (0, 0, -1), xyzw (0, 0, 1, 1));
		// Draw grid
		for i : -10..10
			draw_line (xyz (xx i, 0, -10), xyz (xx i, 0, 10), xyzw (0.4, 0.4, 0.4, 1));
		for i : -10..10
			draw_line (xyz (-10, 0, xx i), xyz (10, 0, xx i), xyzw (0.4, 0.4, 0.4, 1));
		if mesh && g_params.show_skeleton
		{
			// Disable depth mask and testing so we can see
			// the skeleton through other things
			glDepthMask (GL_FALSE);
			glDisable (GL_DEPTH_TEST);
			draw_pose (pose, Matrix4_Identity, xyzw (g_params.skeleton_color, 1));
		}
		
		update_ui (delta_time);

		swap_buffers (g_window);
		sleep_milliseconds (10);
		frame_end := current_time_monotonic ();
		delta_time = cast (float) to_float64_seconds (frame_end - frame_start);
	}
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
