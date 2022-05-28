import bpy
import mathutils

from typing import (
	List,
	Dict,
	Tuple
)
from bpy.props import (
	BoolProperty,
	EnumProperty
)
from bpy_extras.io_utils import (
	ExportHelper,
	orientation_helper,
	axis_conversion
)

class Joint_Sample:
	def __init__ (
		self,
		local_position : Tuple[float, float, float],
		local_orientation : Tuple[float, float, float, float],
		local_scale : Tuple[float, float, float]
	):
		self.local_position = local_position
		self.local_orientation = local_orientation
		self.local_scale = local_scale

class Joint_Animation:
	def __init__ (
		self,
		name : str
	):
		self.name = name
		self.samples : List[Joint_Sample] = []

class Sampled_Animation:
	def __init__ (
		self
	):
		self.sample_count : int = 0
		self.name_to_joint_id : Dict[str, int] = {}
		self.joints : List[Joint_Animation] = []

	def from_action (
		blender_obj : bpy.types.Object,
		blender_action : bpy.types.Action,
		frame_begin : int,
		frame_end : int,
		transform_matrix : mathutils.Matrix
	):
		def append_pose (
			anim : Sampled_Animation,
			pose : bpy.types.Pose
		):
			for bone in pose.bones:
				# @Note (stefan): Is it possible for a bone to
				# spawn in the middle of an animation ? For now
				# we don't allow this to happen.
				if bone.name not in anim.name_to_joint_id:
					continue
				matrix = transform_matrix @ bone.matrix
				if bone.parent is not None:
					parent_matrix = transform_matrix @ bone.parent.matrix
					matrix = parent_matrix.inverted () @ matrix
				location, orientation, scale = matrix.decompose ()
				joint_index = anim.name_to_joint_id[bone.name]
				anim.joints[joint_index].samples.append (
					Joint_Sample (
						tuple (location),
						(
							orientation[1],
							orientation[2],
							orientation[3],
							orientation[0]
						),
						tuple (scale)
					)
				)

		result = Sampled_Animation ()
		prev_action = blender_obj.animation_data.action
		prev_frame  = bpy.context.scene.frame_current
		blender_obj.animation_data.action = blender_action

		# Initialize the joint animations array and name dict
		bpy.context.scene.frame_set (frame_begin)
		for bone in blender_obj.pose.bones:
			if not bone.bone.use_deform:
				continue
			joint_index = len (result.joints)
			joint_anim = Joint_Animation (bone.name)
			result.joints.append (joint_anim)
			result.name_to_joint_id.update ({ bone.name : joint_index })
		# Go through each frame in the animation and add the pose to the anim
		for frame in range (frame_begin, frame_end):
			bpy.context.scene.frame_set (frame)
			append_pose (result, blender_obj.pose)
		bpy.context.scene.frame_set (prev_frame)
		blender_obj.animation_data.action = prev_action
		# Make sure we have the same number of samples for each joint
		if len (result.joints) > 0:
			result.sample_count = len (result.joints[0].samples)
		for joint in result.joints:
			if len (joint.samples) != result.sample_count:
				raise Exception (f"Inconsistent sample count for joints in animation {blender_action.name}.")

		return result

	def write_text (self, filename : str):
		with open (filename, "wb") as file:
			fw = file.write
			fw (b"[1]\n\n")	# Version
			fw (b"joint_count %u\n" % len (self.joints))
			fw (b"sample_count %u\n\n" % self.sample_count)
			for joint in self.joints:
				fw (b"%s\n\n" % bytes (joint.name, 'UTF-8'))
				for sample in joint.samples:
					fw (b"%.6f %.6f %.6f\n" % sample.local_position[:])
					fw (b"%.6f %.6f %.6f %.6f\n" % sample.local_orientation[:])
					fw (b"%.6f %.6f %.6f\n\n" % sample.local_scale[:])

def export_animations (
	context : bpy.types.Context,
	filename : str,
	use_action_frame_range : bool,
	use_selection : bool,
	apply_transform : bool,
	axis_conversion_matrix : mathutils.Matrix
):
	import os

	if bpy.ops.object.mode_set.poll ():
		bpy.ops.object.mode_set (mode = 'OBJECT')
	if use_selection:
		objs = context.selected_objects
	else:
		objs = context.scene.objects
	exported_actions : List[bpy.types.Action] = []
	for obj in objs:
		if obj.animation_data is None or obj.pose is None:
			continue
		action = obj.animation_data.action
		if action is None or action in exported_actions:
			continue
		transform_matrix = mathutils.Matrix.Identity (4)
		if apply_transform:
			transform_matrix = transform_matrix @ obj.matrix_world
		if axis_conversion_matrix is not None:
			transform_matrix = transform_matrix @ axis_conversion_matrix.to_4x4 ()
		output_filename = os.path.join (os.path.dirname (filename), action.name) + Exporter.filename_ext
		if use_action_frame_range:
			frame_begin, frame_end = (
				int (action.frame_range[0]),
				int (action.frame_range[1])
			)
		else:
			frame_begin, frame_end = (
				int (context.scene.frame_start),
				int (context.scene.frame_end)
			)
		anim = Sampled_Animation.from_action (obj, action, frame_begin, frame_end, transform_matrix)
		anim.write_text (output_filename)
		print (f"Exported animation clip {action.name} to file {output_filename}.\n")
		exported_actions.append (action)

@orientation_helper (axis_forward = '-Z', axis_up = 'Y')
class Exporter (bpy.types.Operator, ExportHelper):
	"""Export animation data"""
	bl_idname = "export.anim_example_anim"
	bl_label = "Export sampled animation (.anim)"
	bl_options = { 'REGISTER', 'UNDO' }
	filename_ext = ".anim"

	use_selection : BoolProperty (
		name = "Only Selected",
		description = "Export only the active action of the selected objects.",
		default = True
	)
	apply_transform : BoolProperty (
		name = "Apply object transform",
		description = "Apply the object transform matrix when exporting animations.",
		default = True
	)
	use_action_frame_range : BoolProperty (
		name = "Use action frame range",
		description = "Use the action frame range rather than the scene frame range.",
		default = False
	)

	def execute (self, context : bpy.types.Context):
		context.window.cursor_set ('WAIT')
		export_animations (
			context,
			self.filepath,
			self.use_action_frame_range,
			self.use_selection,
			self.apply_transform,
			axis_conversion (to_forward = self.axis_forward, to_up = self.axis_up)
		)
		context.window.cursor_set ('DEFAULT')

		return { 'FINISHED' }

def export_menu_func (self, context : bpy.types.Context):
	self.layout.operator (Exporter.bl_idname)
