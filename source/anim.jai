Joint_Sample :: struct
{
	local_position : Vector3;
	local_orientation : Quaternion;
	local_scale : Vector3;
}

Joint_Animation :: struct
{
	name : string;
	samples : []Joint_Sample;
}

Sampled_Animation :: struct
{
	sample_count : s64;
	joints : []Joint_Animation;
}

Skeleton_Pose :: struct
{
	Joint :: struct
	{
		#as using sample : Joint_Sample;
		// This matrix is calculated right before
		// passing it to the shader
		model_space_transform := Matrix4_Identity;
	}

	skeleton : *Skeleton;
	joints : []Joint;
}

load_animation_from_file :: (anim : *Sampled_Animation, filename : string) -> bool
{
	parse_joint :: (handler : *Text_File_Handler, anim : *Sampled_Animation) -> bool
	{
		line, ok := consume_next_line (handler);
		joint := *anim.joints.data[anim.joints.count];
		anim.joints.count += 1;
		joint.name = copy_string (line);
		joint.samples = NewArray (anim.sample_count, Joint_Sample);
		for i : 0..anim.sample_count - 1
		{
			sample := *joint.samples[i];
			sample.local_position, ok = parse_vector3 (handler);
			sample.local_orientation, ok = parse_quaternion (handler);
			sample.local_scale, ok = parse_vector3 (handler);
		}

		return true;
	}

	// Here's one example of how you can use a Text_File_Handler to parse
	// our custom animation file.
	// By default, a Text_File_Handler will interpret anything starting
	// with a # character as a comment until the end of the line.
	// See Text_File_Handler.comment_character.
	// By default, it also reads the first characters in the file with the
	// following pattern [number] as a version number.
	// See Text_File_Handler.do_version_number
	handler : Text_File_Handler;
	defer deinit (*handler);
	found_slash, dir, basename := split_from_right (filename, #char "/");
	if !found_slash
		basename = filename;
	start_file (*handler, basename, filename, optional = false);
	if handler.failed
		return false;
	if handler.version != 1
		return error_out (handler, "Invalid version number.");
	joint_count, ok := parse_ident_and_int_line (*handler, "joint_count");
	if !ok
		return false;
	anim.sample_count, ok = parse_ident_and_int_line (*handler, "sample_count");
	if !ok
		return false;
	anim.joints.data = alloc (size_of (Joint_Animation) * joint_count);
	memset (anim.joints.data, 0, size_of (Joint_Animation) * joint_count);
	for i : 0..joint_count - 1
		if !parse_joint (*handler, anim)
			return false;

	return true;
}

make_pose_for_skeleton :: (skeleton : *Skeleton, allocator := context.allocator) -> Skeleton_Pose #must
{
	result : Skeleton_Pose;
	result.skeleton = skeleton;
	result.joints = NewArray (skeleton.joints.count, Skeleton_Pose.Joint, allocator = allocator);
	reset_to_bind_pose (*result);
	return result;
}

reset_to_bind_pose :: (using pose : *Skeleton_Pose)
{
	for * joints
	{
		it.local_position,
		it.local_orientation,
		it.local_scale = decompose_transform (skeleton.joints[it_index].local_bind_transform);
	}
}

Interpolation_Mode :: enum s32
{
	NEAREST :: 0;
	LINEAR  :: 1;
	LINEAR_SLERP :: 2;
}

interpolate_joint_samples :: inline (
	a : Joint_Sample,
	b : Joint_Sample,
	t : float,
	interpolation_mode : Interpolation_Mode
) -> Joint_Sample #must
{
	nlerp_shortest :: (a : Quaternion, b : Quaternion, t : float) -> Quaternion #must
	{
		first  := a;
		second := b;
		if dot (first, second) < 0
			second = negate (second);
		
		return nlerp (first, second, t);
	}

	slerp_shortest :: (a : Quaternion, b : Quaternion, t : float) -> Quaternion #must
	{
		first  := a;
		second := b;
		if dot (first, second) < 0
			second = negate (second);

		return slerp (first, second, t);
	}

	result : Joint_Sample = ---;
	if #complete interpolation_mode ==
	{
	case .NEAREST;
		if t < 0.5 then result = a;
		else            result = b;
	case .LINEAR;
		t = clamp (t, 0, 1);
		result.local_position    = lerp (a.local_position, b.local_position, t);
		result.local_orientation = nlerp_shortest (a.local_orientation, b.local_orientation, t);
		result.local_scale       = lerp (a.local_scale, b.local_scale, t);
	case .LINEAR_SLERP;
		t = clamp (t, 0, 1);
		result.local_position    = lerp (a.local_position, b.local_position, t);
		result.local_orientation = slerp_shortest (a.local_orientation, b.local_orientation, t);
		result.local_scale       = lerp (a.local_scale, b.local_scale, t);
	}
	return result;
}

sample_animation :: (
	using anim : Sampled_Animation,
	time : float,
	pose : *Skeleton_Pose,
	interpolation_mode := Interpolation_Mode.LINEAR
)
{
	time = fmod (time, cast (float) sample_count);
	for joint : joints
	{
		joint_index, ok := table_find (pose.skeleton.name_to_joint_id, joint.name);
		if !ok
			continue;
		first_index  := cast (s64) time;
		second_index := (first_index + 1) % sample_count;
		first  := joint.samples[first_index];
		second := joint.samples[second_index];
		pose.joints[joint_index].sample = interpolate_joint_samples (
			first,
			second,
			time - first_index,
			interpolation_mode
		);
	}
}

calculate_pose_transforms :: (using pose : *Skeleton_Pose)
{
	calculate_joint_transforms :: (pose : *Skeleton_Pose, skeleton_joint : *Skeleton.Joint, parent_transform : Matrix4)
	{
		using joint_pose := *pose.joints[skeleton_joint.id];
		local_transform := make_translation_matrix4 (local_position)
			* make_scale_matrix4 (local_scale)
			* rotation_matrix(Matrix4, local_orientation);
		model_space_transform = parent_transform * local_transform;
		for * :children skeleton_joint
			calculate_joint_transforms (pose, it, model_space_transform);
	}

	calculate_joint_transforms (pose, *skeleton.joints[0], Matrix4_Identity);
}

generate_skinning_matrices :: (using pose : *Skeleton_Pose, allocator : Allocator, transpose_result : bool) -> []Matrix4 #must
{
	calculate_pose_transforms (pose);
	result := NewArray (joints.count, Matrix4, initialized = false, allocator = allocator);
	for i : 0..result.count - 1
	{
		result[i] = joints[i].model_space_transform * skeleton.joints[i].inverse_bind_transform;
		if transpose_result
			transpose (*result[i]);
	}

	return result;
}
