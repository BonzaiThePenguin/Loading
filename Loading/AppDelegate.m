#import "AppDelegate.h"
#import "AppRecord.h"

#import <ServiceManagement/ServiceManagement.h>
#include <libproc.h>
#include <sys/sysctl.h>
#import <objc/runtime.h>

int parent_PID(int pid) {
	struct kinfo_proc info;
	size_t length = sizeof(struct kinfo_proc);
	int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, pid };
	if (sysctl(mib, 4, &info, &length, NULL, 0) < 0 || length == 0) return -1;
	return info.kp_eproc.e_ppid;
}

@implementation AppDelegate

@synthesize statusItem;
@synthesize menu;
@synthesize menuDelegate;

@synthesize animator;
@synthesize disabled;
@synthesize disabledInverted;
@synthesize normal;
@synthesize inverted;
@synthesize frame;
@synthesize animating;
@synthesize darkMode;

@synthesize apps;
@synthesize processes;
@synthesize sources;
@synthesize ignore;
@synthesize mapping;

@synthesize starter;
@synthesize started;

AppDelegate *_sharedDelegate = nil;
+ (AppDelegate *)sharedDelegate { return _sharedDelegate; }

// [NSStatusItem button] was added in 10.10, but before that there was a private _button selector
- (NSButton *)statusItemButton {
	SEL selector = NSSelectorFromString(@"button");
	if (![statusItem respondsToSelector:selector]) selector = NSSelectorFromString(@"_button");
	
	if ([statusItem respondsToSelector:selector]) {
		IMP imp = [statusItem methodForSelector:selector];
		NSButton *(*func)(id, SEL) = (void *)imp;
		return func(statusItem, selector);
	}
	return nil;
}

- (BOOL)isDarkMode {
	NSDictionary *domain = [[NSUserDefaults standardUserDefaults] persistentDomainForName:NSGlobalDomain];
	if (domain != nil) {
		NSString *style = [domain valueForKey:@"AppleInterfaceStyle"];
		if (style != nil) return [style isEqualToString:@"Dark"];
	}
	return false;
}

- (BOOL)isRightToLeft {
	return ([NSApp userInterfaceLayoutDirection] == NSUserInterfaceLayoutDirectionRightToLeft);
}

// setImage is deprecated, but is only called in 10.9 or older where it was not deprecated
- (void)setImage:(NSImage *)image alternate:(NSImage *)alternate {
	if ([statusItem respondsToSelector:@selector(button)]) {
		if (darkMode)
			[[statusItem button] setImage:alternate];
		else
			[[statusItem button] setImage:image];
		[[statusItem button] setAlternateImage:alternate];
	} else {
		if (darkMode)
			[statusItem setImage:alternate];
		else
			[statusItem setImage:image];
		[statusItem setAlternateImage:alternate];
	}
}

- (void)showDialog {
	NSBundle *bundle = [NSBundle mainBundle];
	NSString *icon_path = nil;
	NSURL *icon_url = nil;
	NSString *icon_file = [bundle objectForInfoDictionaryKey:@"CFBundleIconFile"];
	if (icon_file != nil) {
		icon_path = [[[bundle resourcePath] stringByAppendingString:@"/"] stringByAppendingString:icon_file];
		if ([[icon_path pathExtension] length] == 0) icon_path = [icon_path stringByAppendingPathExtension:@"icns"];
		icon_url = [NSURL URLWithString:icon_path];
	}
	
	CFOptionFlags result;
	CFUserNotificationDisplayAlert(0, kCFUserNotificationPlainAlertLevel, (CFURLRef)icon_url, NULL, NULL,
								   (CFStringRef)NSLocalizedString(@"WELCOME_TO_LOADING", nil),
								   (CFStringRef)NSLocalizedString(@"LOADING_INTRO", nil),
								   (CFStringRef)NSLocalizedString(@"OPEN_AT_LOGIN", nil),
								   (CFStringRef)NSLocalizedString(@"CANCEL", nil), NULL, &result);
	
	BOOL open_at_login = NO;
	if (result == kCFUserNotificationDefaultResponse) {
		SMLoginItemSetEnabled((CFStringRef)@"com.bonzaiapps.loader", YES); // should return YES
		open_at_login = YES;
	}
	
	NSUserDefaults *preferences = [NSUserDefaults standardUserDefaults];
	[preferences setBool:YES forKey:@"Loaded"];
	[preferences setBool:open_at_login forKey:@"Open at Login"];
	[preferences synchronize];
}


- (void)updateIgnored {
	// update the animate flag for every app and process
	
	for (long app_index = 0; app_index < [apps count]; app_index++) {
		AppRecord *app = [apps objectAtIndex:app_index];
		app.animate = ![self isPathIgnored:app.path];
	}
	
	for (long process_index = 0; process_index < [processes count]; process_index++) {
		ProcessRecord *process = [processes objectAtIndex:process_index];
		process.animate = ![self isPathIgnored:process.path];
	}
	
	NSUserDefaults *preferences = [NSUserDefaults standardUserDefaults];
	[preferences setObject:ignore forKey:@"Ignore"];
	[preferences synchronize];
}

- (void)addPathToIgnored:(NSString *)path {
	if (path == nil || [self isPathIgnored:path]) return;
	
	long index = (long)[ignore indexOfObject:path
							   inSortedRange:NSMakeRange(0, [ignore count])
									 options:(NSBinarySearchingFirstEqual | NSBinarySearchingInsertionIndex)
							 usingComparator:^(id obj1, id obj2) { return [obj1 compare:obj2]; }];
	[ignore insertObject:path atIndex:index];
	
	[self updateIgnored];
}

- (void)removePathFromIgnored:(NSString *)path {
	if (path == nil) return;
	
	long index = (long)[ignore indexOfObject:path
							   inSortedRange:NSMakeRange(0, [ignore count])
									 options:NSBinarySearchingFirstEqual
							 usingComparator:^(id obj1, id obj2) { return [obj1 compare:obj2]; }];
	
	if (index == NSNotFound) return;
	[ignore removeObjectAtIndex:index];
	
	[self updateIgnored];
}

- (BOOL)isPathIgnored:(NSString *)path {
	if (path == nil) return NO;
	
	return (NSNotFound != [ignore indexOfObject:path
								  inSortedRange:NSMakeRange(0, [ignore count])
										options:NSBinarySearchingFirstEqual
								usingComparator:^(id obj1, id obj2) { return [obj1 compare:obj2]; }]);
}

extern void *kNStatSrcKeyPID;
extern void *kNStatSrcKeyTxBytes;
extern void *kNStatSrcKeyRxBytes;

void *NStatManagerCreate(CFAllocatorRef allocator, dispatch_queue_t queue, void (^)(void *));
void NStatManagerDestroy(void *manager);

void NStatSourceSetRemovedBlock(void *source, void (^)());
void NStatSourceSetCountsBlock(void *source, void (^)(CFDictionaryRef));
void NStatSourceSetDescriptionBlock(void *source, void (^)(CFDictionaryRef));

void NStatSourceQueryDescription(void *source);
void NStatManagerQueryAllSources(void *manager, void (^)());

void NStatManagerAddAllTCP(void *manager);
void NStatManagerAddAllUDP(void *manager);

dispatch_queue_t queue;
dispatch_source_t timer;
void *manager;
__weak SourceRecord *prev_source;

// if no updates are occurring, we need to relaunch this code
- (void)start {
	if ([sources count] > 0) {
		started = YES;
		starter = nil;
		return;
	}
	
	if (manager != nil) {
		//NSLog(@"Event listener failed. Restarting...");
		NStatManagerDestroy(manager);
	}
	
	manager = NStatManagerCreate(kCFAllocatorDefault, queue, ^(void *source) {
		SourceRecord *source2 = [[SourceRecord alloc] initWithSource:source];
		long source_index;
		[SourceRecord findBySource:source within:sources atIndex:&source_index];
		[sources insertObject:source2 atIndex:source_index];
		
		NStatSourceSetRemovedBlock(source, ^() {
			long source_index;
			SourceRecord *source2 = [SourceRecord findBySource:source within:sources atIndex:&source_index];
			if (source2 != nil) {
				source2.next = nil;
				prev_source = nil;
				[sources removeObjectAtIndex:source_index];
			}
		});
		
		NStatSourceSetCountsBlock(source, ^(CFDictionaryRef desc) {
			SourceRecord *source2;
			
			if (prev_source != nil && prev_source.next != nil && prev_source.next.source == source) {
				source2 = prev_source.next;
			} else {
				long source_index;
				source2 = [SourceRecord findBySource:source within:sources atIndex:&source_index];
				if (prev_source != nil) prev_source.next = source2;
			}
			
			if (source2 != nil) {
				prev_source = source2;
				if (source2.pid == 0)
					NStatSourceQueryDescription(source);
				else {
					long up = [(NSNumber *)CFDictionaryGetValue(desc, kNStatSrcKeyTxBytes) integerValue];
					long down = [(NSNumber *)CFDictionaryGetValue(desc, kNStatSrcKeyRxBytes) integerValue];
					
					long process_index;
					pid_t pid = source2.pid;
					ProcessRecord *process = [ProcessRecord findByPID:pid within:processes atIndex:&process_index];
					
					// if the process is no longer running, but the path is the same, merge the processes
					// and/or maybe show non-running processes as light gray?
					
					if (process != nil && !process.running) {
						char pathbuf[PROC_PIDPATHINFO_MAXSIZE];
						NSString *path = nil;
						if (proc_pidpath(pid, pathbuf, sizeof(pathbuf)) > 0) {
							path = [NSString stringWithUTF8String:pathbuf];
							if ([process.path isEqualToString:path]) process.running = YES;
						}
					}
					
					if (process == nil || !process.running) {
						process = [[ProcessRecord alloc] initWithPID:pid];
						[processes insertObject:process atIndex:process_index];
						
						// add a new app if needed
					check_PID:;
						long app_index;
						AppRecord *app = nil;
						
						char pathbuf[PROC_PIDPATHINFO_MAXSIZE];
						NSString *path = nil;
						if (proc_pidpath(pid, pathbuf, sizeof(pathbuf)) > 0) {
							path = [NSString stringWithUTF8String:pathbuf];
							
							if (process.path == nil)
								process.path = path;
							
							if (path != nil && ![path hasPrefix:@"/System/Library/CoreServices/SystemUIServer.app"]) {
								// find the parent app
								
								// Looks like there are a few simple rules:
								
								// 1. first check the manual mapping from processes to apps
								NSString *path2 = nil;
								
								for (id prefix in mapping) {
									if ([path hasPrefix:prefix]) {
										path2 = [[NSWorkspace sharedWorkspace] absolutePathForAppBundleWithIdentifier:[mapping objectForKey:prefix]];
										if (path2 != nil) break;
									}
								}
								
								if (path2 != nil) {
									app = [AppRecord findByPath:path2 within:apps atIndex:&app_index];
									if (app == nil) {
										// add this app!
										app = [[AppRecord alloc] initWithPath:path2];
										app.animate = ![self isPathIgnored:app.path];
										[apps insertObject:app atIndex:app_index];
									}
								}
								
								// 2. then check for the first occurrence of ".app/" within the process' path
								if (app == nil) {
									NSRange range = [path rangeOfString:@".app/" options:NSBackwardsSearch];
									if (range.location != NSNotFound) {
										path = [path substringWithRange:NSMakeRange(0, range.location + range.length - 1)];
										app = [AppRecord findByPath:path within:apps atIndex:&app_index];
										if (app == nil) {
											// add this app!
											app = [[AppRecord alloc] initWithPath:path];
											app.animate = ![self isPathIgnored:app.path];
											[apps insertObject:app atIndex:app_index];
										}
									}
								}
								
								// 3. if that doesn't work either, get the parent process (works for Dock subprocesses and XcodeDeviceMonitor)
								if (app == nil && pid > 1) {
									int new_pid = parent_PID(pid);
									if (new_pid != pid) {
										pid = new_pid;
										goto check_PID;
									}
								}
								
								// 4. if all of those things fail, count it as a System process
								
							}
						}
						
						if (app == nil) {
							// set the parent process to the "System" app
							app = [AppRecord findByPath:@"System" within:apps atIndex:&app_index];
						}
						
						process.animate = ![self isPathIgnored:process.path];
						process.app = app;
					}
					
					process.stillRunning = YES;
					
					if (source2.up < up || source2.down < down) {
						source2.up = up;
						source2.down = down;
						process.updated = CFAbsoluteTimeGetCurrent();
						
						// when Loading first launches we have no way of knowing which apps used the network recently,
						// so give it five seconds to use the network again or it goes straight to the Loaded section
						if (!started)
							process.updated -= (LOADED_TIME - 5 * 60);
						
						if (process.app != nil)
							process.app.updated = process.updated;
					}
				}
			}
		});
		
		NStatSourceSetDescriptionBlock(source, ^(CFDictionaryRef desc) {
			SourceRecord *source2;
			
			if (prev_source != nil && prev_source.next != nil && prev_source.next.source == source) {
				source2 = prev_source.next;
			} else {
				long source_index;
				source2 = [SourceRecord findBySource:source within:sources atIndex:&source_index];
				if (prev_source != nil) prev_source.next = source2;
			}
			
			if (source2 != nil) {
				prev_source = source2;
				source2.pid = (pid_t)[(NSNumber *)CFDictionaryGetValue(desc, kNStatSrcKeyPID) integerValue];
			}
		});
	});
	
	NStatManagerAddAllTCP(manager);
	NStatManagerAddAllUDP(manager);
}


- (void)themeChanged:(NSNotification *)notification {
	darkMode = [self isDarkMode];
	
	// update the app icon!
	if (animating)
		[self setImage:[normal objectAtIndex:frame] alternate:[inverted objectAtIndex:frame]];
	else
		[self setImage:disabled alternate:disabledInverted];
}

// NSStatusItem's menu will be drawn in the wrong position if you follow the recommended behavior
// of using [NSMenuDelegate menuNeedsUpdate:] OR [NSMenuDelegate menu:updateItem:atIndex:shouldCancel:]
// The only workaround I was able to find was swizzling this selector and updating the menu here

- (void)updateMenu {
	[menuDelegate updateMenu:menu];
}

static IMP _trackMouse_original;
BOOL _trackMouse_replacement(id self, SEL _cmd, NSEvent *theEvent, NSRect cellFrame, NSView *controlView, BOOL untilMouseUp) {
	[[AppDelegate sharedDelegate] updateMenu];
	
	return ((BOOL (*)(id, SEL, NSEvent *, NSRect, NSView *, BOOL))_trackMouse_original)(self, _cmd, theEvent, cellFrame, controlView, untilMouseUp);
}

- (void)beginTracking:(NSNotification *)notification {
	[menuDelegate beginTracking:menu];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	_sharedDelegate = self;
	
	darkMode = [self isDarkMode];
	
	NSUserDefaults *preferences = [NSUserDefaults standardUserDefaults];
	[preferences registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:NO, @"Loaded", nil]];
	
	NSArray *ignoring = [preferences arrayForKey:@"Ignore"];
	if (ignoring == nil)
		ignore = [[NSMutableArray alloc] initWithCapacity:0];
	else
		ignore = [[NSMutableArray alloc] initWithArray:ignoring];
	
	statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:24.0]; // NSSquareStatusItemLength?
	[statusItem setHighlightMode:YES];
	
	AppRecord *system_app = [[AppRecord alloc] initWithPath:@"System"];
	system_app.animate = ![self isPathIgnored:system_app.path];
	
	apps = [[NSMutableArray alloc] initWithObjects:system_app, nil];
	processes = [[NSMutableArray alloc] initWithCapacity:0];
	sources = [[NSMutableArray alloc] initWithCapacity:0];
	
	mapping = @{
				@"/System/Library/StagedFrameworks/Safari/" : @"com.apple.Safari",
				@"/System/Library/PrivateFrameworks/Safari.framework/" : @"com.apple.Safari",
				@"/System/Library/PrivateFrameworks/SafariServices.framework/" : @"com.apple.Safari",
				@"/System/Library/Frameworks/WebKit.framework/" : @"com.apple.Safari",
				@"/System/Library/PrivateFrameworks/CommerceKit.framework/" : @"com.apple.AppStore",
				@"/System/Library/Frameworks/AddressBook.framework/" : @"com.apple.AddressBook",
				@"/System/Library/PrivateFrameworks/CalendarAgent.framework/" : @"com.apple.iCal",
				@"/System/Library/PrivateFrameworks/ApplePushService.framework/" : @"com.apple.notificationcenterui",
				@"/System/Library/PrivateFrameworks/WeatherKit.framework/" : @"com.apple.notificationcenterui",
				@"/Library/Application Support/Adobe/Flash Player Install Manager/" : @"com.adobe.flashplayer.installmanager"
				};
	
	disabled = [NSImage imageNamed:@"Disabled"];
	disabledInverted = [NSImage imageNamed:@"DisabledInverted"];
	
	normal = [[NSArray alloc] initWithObjects:[NSImage imageNamed:@"Normal1"], [NSImage imageNamed:@"Normal2"], [NSImage imageNamed:@"Normal3"],
			  [NSImage imageNamed:@"Normal4"], [NSImage imageNamed:@"Normal5"], [NSImage imageNamed:@"Normal6"],
			  [NSImage imageNamed:@"Normal7"], [NSImage imageNamed:@"Normal8"], [NSImage imageNamed:@"Normal9"],
			  [NSImage imageNamed:@"Normal10"], [NSImage imageNamed:@"Normal11"], [NSImage imageNamed:@"Normal12"], nil];
	
	inverted = [[NSArray alloc] initWithObjects:[NSImage imageNamed:@"Inverted1"], [NSImage imageNamed:@"Inverted2"], [NSImage imageNamed:@"Inverted3"],
				[NSImage imageNamed:@"Inverted4"], [NSImage imageNamed:@"Inverted5"], [NSImage imageNamed:@"Inverted6"],
				[NSImage imageNamed:@"Inverted7"], [NSImage imageNamed:@"Inverted8"], [NSImage imageNamed:@"Inverted9"],
				[NSImage imageNamed:@"Inverted10"], [NSImage imageNamed:@"Inverted11"], [NSImage imageNamed:@"Inverted12"], nil];
	
	animator = nil;
	animating = YES; frame = 0;
	[self stopAnimating];
	
	menu = [[NSMenu alloc] initWithTitle:NSLocalizedString(@"Loading", nil)];
	[statusItem setMenu:menu];
	menuDelegate = [[MenuDelegate alloc] init];
	
	// add a notification observer for when the user changes between light theme and dark theme
	[[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChanged:) name:@"AppleInterfaceThemeChangedNotification" object:nil];
	
	// swizzle NSStatusBarButtonCell trackMouse:inRect:ofView:untilMouseUp to avoid a bug with menu positioning (see above)
	_trackMouse_original = method_setImplementation(class_getInstanceMethod([[[self statusItemButton] cell] class], @selector(trackMouse:inRect:ofView:untilMouseUp:)), (IMP)_trackMouse_replacement);
	
	// register for the BeginTracking notification so we can install our Carbon event handler as soon as the menu is constructed
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(beginTracking:) name:NSMenuDidBeginTrackingNotification object:menu];
	
	// hook into the private NetworkStatistics framework to poll for network activity
	queue = dispatch_queue_create("com.bonzaiapps.loading", DISPATCH_QUEUE_SERIAL);
	starter = [NSTimer scheduledTimerWithTimeInterval:3.0 target:self selector:@selector(start) userInfo:nil repeats:YES];
	[self start];
	
	timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
	dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC, 0);
	dispatch_source_set_event_handler(timer, ^{
		@synchronized(apps) {
			long process_index;
			for (process_index = 0; process_index < [processes count]; process_index++) {
				ProcessRecord *process = [processes objectAtIndex:process_index];
				process.stillRunning = NO;
			}
			
			NStatManagerQueryAllSources(manager, nil);
			
			BOOL loading = NO;
			double cur_time = CFAbsoluteTimeGetCurrent();
			
			// removed unused processes and apps
			for (process_index = [processes count] - 1; process_index >= 0; process_index--) {
				ProcessRecord *process = [processes objectAtIndex:process_index];
				
				if (!process.stillRunning) {
					//if (process.running) NSLog(@"Process terminated: %@\n", process.path);
					process.running = NO;
				}
				
				if (!process.running && cur_time - process.updated >= LOADED_TIME) {
					[processes removeObjectAtIndex:process_index];
					
					AppRecord *app = process.app;
					if (app != nil) {
						// remove the parent app if no processes point to it anymore
						BOOL app_used = NO;
						long process_index2;
						for (process_index2 = 0; process_index2 < [processes count]; process_index2++) {
							process = [processes objectAtIndex:process_index2];
							if (process.app == app) {
								app_used = YES;
								break;
							}
						}
						
						if (!app_used && ![app.path isEqualToString:@"System"]) [apps removeObject:app];
					}
				} else if (!loading && process.animate && process.app.animate && cur_time - process.updated < LOADING_TIME && process.app != nil && (![process.app.path isEqualToString:@"System"] || ![process.path hasSuffix:@"/discoveryd"])) {
					loading = YES;
				}
			}
			
			if (loading != animating) {
				dispatch_async(dispatch_get_main_queue(), ^{
					if (loading) [self startAnimating];
					else [self stopAnimating];
				});
			}
		}
	});
	dispatch_resume(timer);
	
	if (![preferences boolForKey:@"Loaded"]) [self performSelectorInBackground:@selector(showDialog) withObject:nil];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
	[[NSNotificationCenter defaultCenter] removeObserver:self name:NSMenuDidBeginTrackingNotification object:menu];
	[[NSStatusBar systemStatusBar] removeStatusItem:statusItem];
	if (manager != nil) NStatManagerDestroy(manager);
}

- (void)updateAnimation {
	[self setImage:[normal objectAtIndex:frame] alternate:[inverted objectAtIndex:frame]];
	if (animating && ++frame >= [normal count]) frame = 0;
}

- (void)startAnimating {
	if (animating) return;
	animating = YES;
	if (animator == nil) animator = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(updateAnimation) userInfo:nil repeats:YES];
}

- (void)stopAnimating {
	if (!animating) return;
	animating = NO;
	if (animator != nil) {
		[animator invalidate];
		animator = nil;
	}
	
	[self setImage:disabled alternate:disabledInverted];
}

@end
