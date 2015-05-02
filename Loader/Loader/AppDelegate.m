#import "AppDelegate.h"
#include <ServiceManagement/ServiceManagement.h>

@implementation AppDelegate

// from the helper
// [[NSWorkspace sharedWorkspace] launchApplication:@"/Path/To/Main/App/Bundle", where it goes to /MacOS/executable];
// and then quit immediately

// you will need to create the directory and copy the helper app there while building
// LSUIElement for the helper needs to be set to TRUE in the Info.plist file, or LSBackgroundOnly
// click Target and go to the Build Phases tab. here go to the Copy Files detail and set Wrapper as Destination,
// Contents/Library/LoginItems/Loading Loader.app as Subpath, leave unchecked Copy only when installing and add the Helper Application binary in the list

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
	bool running = false;
	NSArray *apps = [[NSWorkspace sharedWorkspace] runningApplications];
	for (NSRunningApplication *app in apps) if ([[app bundleIdentifier] isEqualToString:@"com.bonzaiapps.loading"]) { running = true; break; }
	if (!running) [[NSWorkspace sharedWorkspace] launchApplication:[[[[[[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent] stringByDeletingLastPathComponent]
																	  stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"MacOS"] stringByAppendingPathComponent:@"Loading"]];
	[NSApp terminate:nil];
}

@end
