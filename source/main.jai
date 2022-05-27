#import "Basic";
#import "String";
#import "Window_Creation";
#import "Input";
// Math Matrices are row-major. In other words,
// you have [row 0][row 1][row 2][...] in memory.
#import "Math";
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
g_font : *simp.Dynamic_Font;
g_checkbox_font : *simp.Dynamic_Font;
g_slider_font : *simp.Dynamic_Font;
g_control_camera := false;
g_anim : Sampled_Animation;

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

	mesh : Skinned_Mesh;
	ok := load_mesh_from_file (*mesh, "data/Mannequin.mesh");
	if !ok
	{
		log_error ("Could not load Mannequin mesh.");
		return;
	}
	init_rendering_objects (*mesh);
	ok = load_animation_from_file (*g_anim, "data/Run_F.anim");
	if !ok
	{
		log_error ("Could not load Run_F animation.");
		return;
	}
	// @Hack: provide a way to trim animations when exporting them
	g_anim.sample_count -= 4;
	g_camera.position = xyz (0, 1, 4);
	g_running = true;
	delta_time := 0.01667;
	pose := make_pose_for_skeleton (*mesh);
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
		reset_to_bind_pose (*pose);
		if !g_params.show_bind_pose
			sample_animation (
				g_anim,
				g_params.animation_time,
				*pose,
				g_params.interpolation_mode
			);
		if g_params.play_animations
			g_params.animation_time += delta_time * g_params.animation_speed_in_fps;
		g_params.animation_time = fmod (g_params.animation_time, xx g_anim.sample_count);
		skinning_matrices := generate_skinning_matrices (*pose, temp);

		glDepthMask (GL_TRUE);
		glEnable (GL_DEPTH_TEST);
		simp.clear_render_target (0.1, 0.1, 0.1, 1);
		glClear (GL_DEPTH_BUFFER_BIT);
		draw_mesh (mesh, Matrix4_Identity, skinning_matrices);
		draw_line (xyz (0, 0, 0), xyz (1, 0, 0), xyzw (1, 0, 0, 1));
		draw_line (xyz (0, 0, 0), xyz (0, 1, 0), xyzw (0, 1, 0, 1));
		draw_line (xyz (0, 0, 0), xyz (0, 0, -1), xyzw (0, 0, 1, 1));
		for i : -10..10
			draw_line (xyz (xx i, 0, -10), xyz (xx i, 0, 10), xyzw (0.4, 0.4, 0.4, 1));
		for i : -10..10
			draw_line (xyz (-10, 0, xx i), xyz (10, 0, xx i), xyzw (0.4, 0.4, 0.4, 1));
		if g_params.show_skeleton
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
