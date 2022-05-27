g_params : struct
{
	show_skeleton := true;
	skeleton_color := Vector3.{ 1, 1, 1 };
	show_bind_pose := true;
	play_animations := true;
	animation_time := 0.0;
	animation_speed_in_fps := 30.0;
	interpolation_mode := Interpolation_Mode.LINEAR;
};

update_ui :: (delta_time : float)
{
	using g_params;

	glDisable (GL_DEPTH_TEST);
	glDepthMask (GL_FALSE);

	current_time := to_float64_seconds (current_time_monotonic ());
	w, h := simp.get_render_dimensions (g_window);
	getrect.ui_per_frame_update (g_window, w, h, current_time);

	// Init themes
	label_theme : getrect.Label_Theme;
	label_theme.font = g_font;
	checkbox_theme : getrect.Checkbox_Theme;
	checkbox_theme.font = g_checkbox_font;
	slider_theme : getrect.Slider_Theme;
	slider_theme.foreground.font = g_slider_font;

	k := 16.0;
	pad := cast (float) g_font.character_height * 1.6;
	r := getrect.get_rect (
		k, h - k * 2,
		k, xx g_font.character_height
	);
	// Show Skeleton checkbox
	{
		r.w = r.h + xx simp.prepare_text (g_checkbox_font, "Show Skeleton");
		pressed := getrect.base_checkbox (r, "Show Skeleton", show_skeleton, *checkbox_theme);
		show_skeleton ^= pressed;
	}
	r.y -= pad;
	// Show Bind Pose checkbox
	{
		r.w = r.h + xx simp.prepare_text (g_checkbox_font, "Show Bind Pose");
		pressed := getrect.base_checkbox (r, "Show Bind Pose", show_bind_pose, *checkbox_theme);
		show_bind_pose ^= pressed;
	}
	r.y -= pad;
	// Play Animations checkbox
	{
		r.w = r.h + xx simp.prepare_text (g_checkbox_font, "Play Animations");
		pressed := getrect.base_checkbox (r, "Play Animations", play_animations, *checkbox_theme);
		play_animations ^= pressed;
	}
	r.y -= pad;
	// Animation speed slider
	{
		r.w = w * 0.1 + xx simp.prepare_text (g_slider_font, "Animation Speed: 120.00 FPS");
		getrect.slider (r, *animation_speed_in_fps, 0.0, 120.0, 1.0, *slider_theme, "Animation Speed: ", "FPS");
	}
	r.y -= pad;
	// Animation time slider
	{
		text := tprint ("Animation Time: %.00", g_anim.sample_count);
		r.w = w * 0.1 + xx simp.prepare_text (g_slider_font, text);
		getrect.slider (r, *animation_time, 0.0, xx g_anim.sample_count, 1.0, *slider_theme, "Animation Time: ", "");
	}
	r.y -= pad;
	// Interpolation mode
	{
		r.w = xx simp.prepare_text (g_font, "Interpolation Mode:");
		getrect.label (r, "Interpolation Mode:", *label_theme);
		r.y -= pad;
		modes := string.[ "Nearest", "Linear" ];
		TAB :: 20.0;
		r.x += TAB;
		for modes
		{
			r.w = r.h + xx simp.prepare_text (g_checkbox_font, it);
			getrect.radio_button (r, it, *interpolation_mode, cast (Interpolation_Mode) it_index, *checkbox_theme, it_index);
			r.y -= pad;
		}
		r.x -= TAB;
	}

	r = getrect.get_rect (k, pad, k, k);
	{
		TEXT :: "Use ESC to toggle camera controls, WSADEQ to move, SHIFT to speed up";
		r.w = k + xx simp.prepare_text (g_font, TEXT);
		getrect.label (r, TEXT, *label_theme);
	}
	/*
	r.y += pad + r.h;
	// Colors
	{
		r.w = k * 10;
		r.h = k * 10;
		// @Todo: make a subwindow for the color picker
		color_picker_theme := getrect.default_overall_theme.color_picker_theme;
		getrect.color_picker (r, *g_params.skeleton_color, *color_picker_theme);
	}
	*/

	getrect.draw_popups ();
}
