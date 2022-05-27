#import "Text_File_Handler";

error_out :: inline (handler : Text_File_Handler, str : string, args : ..Any) -> bool
{
	error (handler, str, ..args);
	return false;
}

// Parse a line in the format IDENTIFIER INTEGER
parse_ident_and_int_line :: (handler : *Text_File_Handler, expected_ident : string) -> int, bool
{
	line, found := consume_next_line (handler);
	if !found
		return 0, false;
	val : int;
	ok : bool;
	ident, right := break_by_spaces (line);
	if ident != expected_ident
		return 0, error_out (handler, "Expected '%'.", expected_ident);
	val, ok, right = string_to_int (right);
	if !ok
		return 0, error_out (handler, "Expected an integer after '%'.", expected_ident);
	right = trim (right);
	if right.count != 0
		return 0, error_out (handler, "Expected nothing after INTEGER, got %.", right);
	if val < 0
		return 0, error_out (handler, "Expected a positive integer.");
	return val, true;
}

parse_int :: (handler : *Text_File_Handler, $Int_Type := s64) -> Int_Type, bool
#modify {
	info := cast (*Type_Info) Int_Type;
	return info.type == .INTEGER;
}
{
	line, ok := consume_next_line (handler);
	if !ok
		return 0, error_out (handler, "Unexpected EOF.");
	val : s64;
	val, ok, line = string_to_int (line);
	if !ok
		return 0, error_out (handler, "Expected an integer.");
	// @Cleanup: This will fail if the integer is out of bounds, but
	// we probably should check for overflow ourselves
	result := cast (Int_Type) val;
	line = trim_left (line);
	if line.count > 0
		return 0, error_out (handler, "Expected end of line.");
	return result, true;
}

// Parse a line in the format INTEGER INTEGER INTEGER ...
parse_int_tuple :: (handler : *Text_File_Handler, $count : int, $Int_Type := s64) -> [count]Int_Type, bool
#modify {
	info := cast (*Type_Info) Int_Type;
	return info.type == .INTEGER;
}
{
	result : [count]Int_Type = ---;
	line, ok := consume_next_line (handler);
	if !ok
		return result, error_out (handler, "Unexpected EOF.");
	for i : 0..count - 1
	{
		val : s64;
		val, ok, line = string_to_int (line);
		if !ok
			return result, error_out (handler, "Expected an integer for %th component of % tuple[%].", i, Int_Type, count);
		// @Cleanup: This will fail if the integer is out of bounds, but
		// we probably should check for overflow ourselves
		result[i] = xx val;
		line = trim_left (line);
	}
	if line.count > 0
		return result, error_out (handler, "Expected end of line.");
	return result, true;
}

// Parse a line in the format FLOAT FLOAT FLOAT ...
parse_float_tuple :: (handler : *Text_File_Handler, $count : int) -> [count]float, bool
{
	result : [count]float = ---;
	line, ok := consume_next_line (handler);
	if !ok
		return result, error_out (handler, "Unexpected EOF.");
	for i : 0..count - 1
	{
		result[i], ok, line = string_to_float (line);
		if !ok
			return result, error_out (handler, "Expected a floating point number for %th component of float tuple[%].", i, count);
		line = trim_left (line);
	}
	if line.count > 0
		return result, error_out (handler, "Expected end of line.");
	return result, true;
}

parse_vector3 :: (handler : *Text_File_Handler) -> Vector3, bool
{
	components, ok := parse_float_tuple (handler, 3);
	if !ok
		return .{}, false;
	result : Vector3 = ---;
	result.component = components;
	return result, true;
}

parse_vector4 :: (handler : *Text_File_Handler) -> Vector4, bool
{
	components, ok := parse_float_tuple (handler, 4);
	if !ok
		return .{}, false;
	result : Vector4 = ---;
	result.component = components;
	return result, true;
}

parse_quaternion :: (handler : *Text_File_Handler) -> Quaternion, bool
{
	components, ok := parse_float_tuple (handler, 4);
	if !ok
		return .{}, false;
	result : Quaternion = ---;
	result.component = components;
	return result, true;
}

parse_matrix4 :: (handler : *Text_File_Handler) -> Matrix4, bool
{
	result : Matrix4 = ---;
	for row : 0..3
	{
		components, ok := parse_float_tuple (handler, 4);
		if !ok
			return .{}, false;
		result.coef[row] = components;
	}
	return result, true;
}
