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
g_slider_font : *simp.Dynamic_Font;
g_input_font : *simp.Dynamic_Font;
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
				g_control_camera = !g_control_camera;
			if event.key_code == .F4 && event.alt_pressed
				g_running = false;
		}
	}
}

is_key_down :: inline (key : Key_Code) -> bool #must
{
	return (input_button_states[cast (s64) key] & .DOWN) != 0;
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
		mat._11,
		mat._22,
		mat._33
	);

	return translation, rotation, scale;
}

init_fonts :: ()
{
	g_font = simp.get_font_at_size ("data", "OpenSans-Regular.ttf", 22);
	assert (g_font != null);
	g_slider_font = simp.get_font_at_size ("data", "OpenSans-Italic.ttf", 16);
	assert (g_slider_font != null);
	g_input_font = simp.get_font_at_size ("data", "OpenSans-Regular.ttf", 16);
	assert (g_input_font != null);
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
	delta_time := 0.1667;
	pose := make_pose_for_skeleton (*mesh);
	while g_running
	{
		frame_start := current_time_monotonic ();
		reset_temporary_storage ();
		update_window_events ();
		for get_window_resizes ()
			simp.update_window (it.window);
		for events_this_frame
			handle_window_event (it);
		
		update_flying_camera (*g_camera, delta_time);
		reset_to_bind_pose (*pose);
		sample_animation (g_anim, g_params.animation_time, *pose);
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
		if g_params.show_skeleton
		{
			glDepthMask (GL_FALSE);
			glDisable (GL_DEPTH_TEST);
			draw_pose (pose, Matrix4_Identity, xyzw (g_params.skeleton_color, 1));
		}
		
		if !g_control_camera
			update_ui (delta_time);

		swap_buffers (g_window);
		sleep_milliseconds (10);
		frame_end := current_time_monotonic ();
		delta_time = cast (float) to_float64_seconds (frame_end - frame_start);
	}
}
