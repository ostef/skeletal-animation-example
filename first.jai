#import "Basic";
#import "String";
#import "Compiler";
#import "File";
#import "Process";

OUTPUT_NAME :: "anim";
OUTPUT_DIR  :: "bin/";
INT_DIR     :: "int/";

build :: ()
{
	ws := compiler_create_workspace ("Main Program");
	run_on_success := false;
	{
		options := get_build_options (ws);
		defer set_build_options (options, ws);
		args := options.compile_time_command_line;
		i := 0;
		while i < args.count
		{
			defer i += 1;
			if args[i] ==
			{
			case "run";
				run_on_success = true;
			}
		}
		options.output_type = .EXECUTABLE;
		options.output_executable_name = OUTPUT_NAME;
		options.output_path = OUTPUT_DIR;
		options.intermediate_path = INT_DIR;
		make_directory_if_it_does_not_exist (options.output_path);
		make_directory_if_it_does_not_exist (options.intermediate_path);
	}
	compiler_begin_intercept (ws);
	add_build_file ("source/main.jai", ws);
	build_success := false;
	while true
	{
		msg := compiler_wait_for_message ();
		if msg.workspace != ws
			continue;
		if msg.kind ==
		{
		case .COMPLETE;
			build_success = (cast (*Message_Complete) msg).error_code == .NONE;
			break;
		}
	}
	compiler_end_intercept (ws);

	if build_success && run_on_success
	{
		cmd := join (OUTPUT_DIR, OUTPUT_NAME);
		print ("Running %.\n", cmd);
		if !os_run_command (cmd, working_directory = OUTPUT_DIR, print_captured_output = true)
			print ("Could not run %.\n", cmd);
	}

	// Set the build options of this metaprogram workspace to not output anything.
	set_build_options_dc (.{ do_output = false, write_added_strings = false });
}

#run build ();
