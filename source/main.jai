#import "Basic";
#import "String";
#import "Window_Creation";
#import "Input";
// Math Matrices are row-major. In other words,
// you have [row 0][row 1][row 2][...] in memory.
#import "Math";
#import "GL";
#import "Hash_Table";

#load "parse.jai";
#load "render.jai";
#load "camera.jai";
#load "mesh.jai";
#load "anim.jai";

g_window : Window_Type;
g_camera : Camera;
g_running : bool;

handle_window_event :: (event : Event)
{
	if event.type ==
	{
	case .QUIT;
		g_running = false;
	case .KEYBOARD;
		if event.key_pressed && event.key_code == .ESCAPE
			g_running = false;
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

main :: ()
{
	g_window = create_window (1280, 720, "Skeletal Animation");
	defer print ("Program ended gracefully.\n");
	gl_create_context (g_window);
	gl_load (*gl);
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
	anim : Sampled_Animation;
	ok = load_animation_from_file (*anim, "data/Run_F.anim");
	if !ok
	{
		log_error ("Could not load Run_F animation.");
		return;
	}
	glClearColor (0.1, 0.1, 0.1, 1);
	glEnable (GL_DEPTH_TEST);
	g_running = true;
	anim_time := 0.0;
	delta_time := 0.1667;
	pose := make_pose_for_skeleton (*mesh);
	while g_running
	{
		frame_start := current_time_monotonic ();
		reset_temporary_storage ();
		update_window_events ();
		for events_this_frame
			handle_window_event (it);
		
		update_flying_camera (*g_camera, delta_time);
		reset_to_bind_pose (*pose);
		//sample_animation (anim, anim_time, *pose);
		//anim_time += delta_time;
		skinning_matrices := generate_skinning_matrices (*pose, temp);

		glClear (GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
		draw_mesh (mesh, Matrix4_Identity, skinning_matrices);
		draw_line (xyz (0, 0, 0), xyz (1, 0, 0), xyzw (1, 0, 0, 1));
		draw_line (xyz (0, 0, 0), xyz (0, 1, 0), xyzw (0, 1, 0, 1));
		draw_line (xyz (0, 0, 0), xyz (0, 0, -1), xyzw (0, 0, 1, 1));
		glDisable (GL_DEPTH_TEST);
		glDepthMask (GL_FALSE);
		draw_pose (pose, Matrix4_Identity, xyzw (1, 1, 1, 1));
		glDepthMask (GL_TRUE);
		glEnable (GL_DEPTH_TEST);
		swap_buffers (g_window);
		sleep_milliseconds (10);
		frame_end := current_time_monotonic ();
		delta_time = cast (float) to_float64_seconds (frame_end - frame_start);
	}
}
