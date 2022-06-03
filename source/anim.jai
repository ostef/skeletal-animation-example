// In general, the names we use are a bit confusing because we have
// a sampled animation that comes from your disk, and we want to
// produce an animation on your screen. So there are terms that we
// use in the two contexts. To try and disambiguate:
//
//   * a joint is in general a coordinate system that is part of a
// hierarchy. There are different Joint structs for different contexts.
//
//   * a Skeleton is the set of joints forming a hierarchy. It
// is stored in the Skinned_Mesh. The joints in it does not
// move to produce an animation, they are just used as reference
// to produce the final pose that you see on your screen.
// The joint structure for this is Skeleton.Joint.
//
//   * a Skeleton_Pose is a snapshot of the joint hierarchy of a
// specific Skeleton. This is used to produce the skinning information to
// move the mesh you see on the screen and uses a Skeleton for reference.
// The joint structure for this is Skeleton_Pose.Joint.
//
//   * a Sampled_Animation is a set of poses (though we don't store it that way),
// sampled from your animation editing program most of the time.
// This struct, contrary to a Skeleton_Pose, isn't associated to a
// specific Skeleton, that way you can use a Sampled_Animation to apply
// movement to a skeleton that does not have all the joints present in the
// animation (and might have others that are not present). This is why a
// Sampled_Animation does not have an explicitely defined hierarchy for
// its joints, even though the joints' position/orientation/scale are expressed locally.

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

// The way we store animation data is very bad for cache.
// It would probably be better to have all the joint samples
// for each **pose** in the animation be contiguous, but we have
// all the joint samples for each **joint** contiguous.
Sampled_Animation :: struct
{
	sample_count : s64;
	joints : []Joint_Animation;
}

Skeleton_Pose :: struct
{
	Joint :: struct
	{
		parent : *~s16 Joint;
		#as using sample : Joint_Sample;
		// This is the transform matrix of the Joint in model space.
		// It is used for skinning matrices generation.
		model_space_transform := Matrix4_Identity;
	}

	skeleton : *Skeleton;
	joints : []Joint;
	skinning_matrices : []Matrix4;
}

load_animation_from_file :: (anim : *Sampled_Animation, filename : string) -> bool
{
	parse_joint :: (handler : *Text_File_Handler, anim : *Sampled_Animation) -> bool
	{
		line, ok := consume_next_line (handler);
		joint := *anim.joints.data[anim.joints.count];
		if !ok
			return error_out (handler, "Could not parse joint name.");
		anim.joints.count += 1;
		// We don't make sure the name does not exist already
		// first, but let's keep this simple.
		joint.name = copy_string (line);
		joint.samples = NewArray (anim.sample_count, Joint_Sample);
		for i : 0..anim.sample_count - 1
		{
			sample := *joint.samples[i];
			sample.local_position, ok = parse_vector3 (handler);
			if !ok
				return error_out (handler, "Could not parse joint local position.");
			sample.local_orientation, ok = parse_quaternion (handler);
			if !ok
				return error_out (handler, "Could not parse joint local orientation.");
			sample.local_scale, ok = parse_vector3 (handler);
			if !ok
				return error_out (handler, "Could not parse joint local scale.");
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

// Allocate a pose for a given skeleton and set it to the bind pose
make_pose_for_skeleton :: (skeleton : *Skeleton) -> Skeleton_Pose #must
{
	result : Skeleton_Pose;
	result.skeleton = skeleton;
	result.joints = NewArray (skeleton.joints.count, Skeleton_Pose.Joint);
	
	for * result.joints
	{
		joint_in_skeleton := *skeleton.joints[it_index];
		if joint_in_skeleton.parent
		{
			parent_id := joint_in_skeleton.parent - skeleton.joints.data;
			it.parent = *result.joints[parent_id];
		}
		else
			it.parent = null;
	}

	reset_to_bind_pose (*result);

	return result;
}

free_pose :: (pose : *Skeleton_Pose)
{
	free (pose.joints.data);
	free (pose.skinning_matrices.data);
	pose.skeleton = null;
	pose.joints = .[];
	pose.skinning_matrices = .[];
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
	// To interpolate joints, we use linear interpolation. This is
	// fine for translation and scale, but for orientation we have
	// to do it a bit differently due to the way quaternions work.
	// In short, we can only use normalized quaternions to represent
	// rotation in 3D, so to interpolate two quaternions we use
	// normalized linear interpolation (hence the name nlerp) which
	// is just a normal lerp followed by normalization.
	// There is another method of interpolation called spherical
	// interpolation (slerp), which is slower but has benefits over
	// nlerp that in many cases are not noticeable. To not go into too
	// much details, here are things that you can read to understand
	// quaternions and interpolation:
	//   * Visualizing quaternions, an explorable video series by 3Blue1Brown:
	//    https://eater.net/quaternions
	//   * Foundations of Game Engine Development, Volume 1: Mathematics by Eric Lengyel
	//   * Understanding Slerp then not using it by Jonathan Blow (the link seems dead):
	//    http://number-none.com/product/Understanding%20Slerp,%20Then%20Not%20Using%20It/

	// When interpolating two quaternions together, because it can
	// be thought of a point on a sphere, there are multiple
	// possible straight paths we can take. In our case, we want the
	// shortest path so this is what the following functions do:
	nlerp_shortest :: (a : Quaternion, b : Quaternion, t : float) -> Quaternion #must
	{
		first  := a;
		second := b;
		// When thinking about the axis-angle representation of the quaternions,
		// if the dot product is negative, that means that the axes or rotation are
		// at least 90 degrees apart. Negating the axis and angle (the whole quaternion)
		// makes the quaternions' axes less than 90 degrees apart in that case, without
		// changing the rotation the quaternion represents, and makes the interpolation
		// take the shortest path.
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

// Sample an animation into `pose', at a given time. Our implementation
// and data layout is not very cache friendly because it reads data in a
// lot of different places, but for this example this is fine.
// What we do is that the samples for a joint J are all contiguous,
// but the best thing to do would probably be to have all joint samples
// for a pose P be contiguous, and we'd iterate over all the joints in
// the first pose, then the second pose to interpolate them.
sample_animation :: (
	using anim : Sampled_Animation,
	time_in_samples : float,
	pose : *Skeleton_Pose,
	interpolation_mode := Interpolation_Mode.LINEAR
)
{
	time_in_samples = fmod (time_in_samples, cast (float) sample_count);
	for joint : joints
	{
		// Ideally we would be caching the results of all these
		// hash table lookups in a flat array, but for simplicity
		// we don't do it.
		joint_index, ok := table_find (pose.skeleton.name_to_joint_id, joint.name);
		if !ok
			continue;
		first_index  := cast (s64) time_in_samples;
		second_index := (first_index + 1) % sample_count;
		first  := joint.samples[first_index];
		second := joint.samples[second_index];
		pose.joints[joint_index].sample = interpolate_joint_samples (
			first,
			second,
			// Because time is in samples, this will result in
			// something between 0 and 1, which is what we want
			time_in_samples - first_index,
			interpolation_mode
		);
	}
}

// After we've done the sampling of the animation, and maybe other
// operations on the pose, we can calculate the pose transforms that
// will be used to generate the skinning matrices. This is a separate
// function from generate_skinning_matrices because we might need
// those transforms for other purposes (though we don't in this program).
calculate_pose_transforms :: (using pose : *Skeleton_Pose)
{
	for * joints
	{
		local_transform := make_translation_matrix4 (it.local_position)
			* make_scale_matrix4 (it.local_scale)
			* rotation_matrix(Matrix4, it.local_orientation);
		if it.parent
			it.model_space_transform = it.parent.model_space_transform * local_transform;
		else
			it.model_space_transform = local_transform;
	}
}

// A skinning matrix is the difference between the bind pose and the actual pose we want,
// or, in other words, a matrix that represents how much we need to move/rotate/scale
// the vertices for them to go into the desired position.
// For reference, if the pose is the same as the bind pose, that means we don't want to
// move the vertices at all, and the model space transform and inverse bind transform
// cancel each other out (resulting in identity matrices everywhere).
// This is also why we use the inverse of the bind transform: you can kind of think of multiplying
// by the inverse as taking the difference between the two coordinate spaces.
generate_skinning_matrices :: (using pose : *Skeleton_Pose, transpose_result : bool)
{
	// The skinning matrices array isn't allocated as long as you don't call this function.
	if !skinning_matrices.data
		skinning_matrices = NewArray (joints.count, Matrix4, initialized = false);
	calculate_pose_transforms (pose);
	for i : 0..skinning_matrices.count - 1
	{
		skinning_matrices[i] = joints[i].model_space_transform * skeleton.joints[i].inverse_bind_transform;
		if transpose_result
			transpose (*skinning_matrices[i]);
	}
}
