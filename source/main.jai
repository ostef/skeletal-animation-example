#import "Basic";
#import "Window_Creation";
#import "Input";
render :: #import "Render";

g_window : Window_Type;
g_running : bool;

main :: ()
{
	g_window = create_window (1280, 720, "Skeletal Animation");
	defer print ("Program ended gracefully.\n");

	g_running = true;
	while g_running
	{
		reset_temporary_storage ();
		update_window_events ();
		for events_this_frame
		{
			if it.type ==
			{
			case .QUIT;
				g_running = false;
			case .KEYBOARD;
				if it.key_pressed && it.key_code == .ESCAPE
					g_running = false;
			}
		}
		swap_buffers (g_window);
		sleep_milliseconds (10);
	}
}
