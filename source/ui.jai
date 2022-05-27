g_params : struct
{
	play_animations := true;
	show_skeleton   := true;
	skeleton_color := Vector3.{ 1, 1, 1 };
	animation_time := 0.0;
	animation_speed_in_fps := 30.0;
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
	checkbox_theme : getrect.Checkbox_Theme;
	checkbox_theme.font = g_font;
	slider_theme : getrect.Slider_Theme;
	slider_theme.foreground.font = g_slider_font;
	text_theme : getrect.Text_Input_Theme;
	text_theme.font = g_input_font;
	text_theme.alignment = .Right;

	k := cast (float) g_font.character_height;
	r := getrect.get_rect (
		k, h - k * 2,
		k, xx g_font.character_height
	);
	// Play Animations checkbox
	{
		r.w = k + xx simp.prepare_text (g_font, "Play Animations");
		pressed := getrect.base_checkbox (r, "Play Animations", play_animations, *checkbox_theme);
		play_animations ^= pressed;
	}
	r.y -= k * 2;
	// Show Skeleton checkbox
	{
		r.w = k + xx simp.prepare_text (g_font, "Show Skeleton");
		pressed := getrect.base_checkbox (r, "Show Skeleton", show_skeleton, *checkbox_theme);
		show_skeleton ^= pressed;
	}
	r.y -= k * 2;
	// Animation speed slider
	{
		r.w = w * 0.1 + xx simp.prepare_text (g_slider_font, "Animation Speed: 120.00 FPS");
		getrect.slider (r, *animation_speed_in_fps, 0.0, 120.0, 1.0, *slider_theme, "Animation Speed: ", "FPS");
	}
	r.y -= k * 2;
	// Animation time slider
	{
		text := tprint ("Animation Time: %.00", g_anim.sample_count);
		r.w = w * 0.1 + xx simp.prepare_text (g_slider_font, text);
		getrect.slider (r, *animation_time, 0.0, xx g_anim.sample_count, 1.0, *slider_theme, "Animation Time: ", "");
	}

	/*
	// @Todo: make a subwindow for the color picker
	// Colors
	r = getrect.get_rect (k, k * 2, k * 10, k * 10);
	color_picker_theme := getrect.default_overall_theme.color_picker_theme;
	getrect.color_picker (r, *g_params.skeleton_color, *color_picker_theme);
	*/

	getrect.draw_popups ();
}
