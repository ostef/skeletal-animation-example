g_params : struct
{
	mesh_names : []string;
	mesh_index : s32;
	animation_names : []string;
	animation_index : s32;
	skeleton_color := Vector3.{ 1, 1, 1 };
	show_skeleton := true;
	show_mesh := true;
	show_animation := true;
	animation_time := 0.0;	// In samples
	animation_speed_in_fps := 30.0;
	interpolation_mode := Interpolation_Mode.LINEAR;
};

update_ui :: (delta_time : float)
{
	using g_params;

	glDisable (GL_DEPTH_TEST);
	glDepthMask (GL_FALSE);

	simp.set_shader_for_color ();
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
	dropdown_theme := getrect.default_overall_theme.dropdown_theme;
	dropdown_theme.theme_for_current_value.font = g_dropdown_font;
	dropdown_theme.theme_for_each_choice.font = g_dropdown_font;
	dropdown_theme.theme_for_current_choice.font = g_dropdown_font;

	k := g_current_window_height / 45.0;
	pad := cast (float) g_font.character_height * 1.6;
	dropdown_offset := w * 0.2;
	dropdown_width  := w * 0.1;
	r := getrect.get_rect (
		k, h - k * 2,
		k, xx g_font.character_height
	);
	// Mesh selection
	{
		r.w = xx simp.prepare_text (g_font, "Mesh: ");
		getrect.label (r, "Mesh: ", *label_theme);
		r.x += dropdown_offset;
		defer r.x -= dropdown_offset;
		r.w = dropdown_width;
		getrect.dropdown (
			r,
			mesh_names,
			*mesh_index,
			*dropdown_theme
		);
	}
	r.y -= pad;
	// Animation selection
	{
		r.w = xx simp.prepare_text (g_font, "Animation: ");
		getrect.label (r, "Animation: ", *label_theme);
		r.x += dropdown_offset;
		defer r.x -= dropdown_offset;
		r.w = dropdown_width;
		getrect.dropdown (
			r,
			animation_names,
			*animation_index,
			*dropdown_theme
		);
	}
	r.y -= pad;
	// Show Skeleton checkbox
	{
		r.w = r.h + xx simp.prepare_text (g_checkbox_font, "Show Skeleton");
		pressed := getrect.base_checkbox (r, "Show Skeleton", show_skeleton, *checkbox_theme);
		show_skeleton ^= pressed;
	}
	r.y -= pad;
	// Show Mesh checkbox
	{
		r.w = r.h + xx simp.prepare_text (g_checkbox_font, "Show Mesh");
		pressed := getrect.base_checkbox (r, "Show Mesh", show_mesh, *checkbox_theme);
		show_mesh ^= pressed;
	}
	r.y -= pad;
	// Show Animations checkbox
	{
		r.w = r.h + xx simp.prepare_text (g_checkbox_font, "Show Animations");
		pressed := getrect.base_checkbox (r, "Show Animations", show_animation, *checkbox_theme);
		show_animation ^= pressed;
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
		sample_count := 0;
		if animation_index > 0
		{
			anim := table_find_pointer (*g_loaded_animations, animation_names[animation_index]);
			sample_count = anim.sample_count;
		}
		text := tprint ("Animation Time: %.00", sample_count);
		r.w = w * 0.1 + xx simp.prepare_text (g_slider_font, text);
		getrect.slider (r, *animation_time, 0.0, xx sample_count, 1.0, *slider_theme, "Animation Time: ", "");
	}
	r.y -= pad;
	// Interpolation mode
	{
		r.w = xx simp.prepare_text (g_font, "Interpolation Mode: ");
		getrect.label (r, "Interpolation Mode: ", *label_theme);
		r.x += dropdown_offset;
		defer r.x -= dropdown_offset;
		r.w = dropdown_width;
		getrect.dropdown (
			r,
			string.[ "Nearest", "Linear", "Linear, slerp" ],
			cast (*s32) *interpolation_mode,
			*dropdown_theme
		);
	}

	r = getrect.get_rect (k, pad, k, k);
	{
		TEXT :: "Use ESC to toggle camera controls, WSADEQ to move, SHIFT to speed up, ALT+F4 to quit";
		r.w = k + xx simp.prepare_text (g_font, TEXT);
		getrect.label (r, TEXT, *label_theme);
	}

	getrect.draw_popups ();
}
