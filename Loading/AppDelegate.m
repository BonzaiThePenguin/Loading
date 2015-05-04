#import "AppDelegate.h"
#import "AppRecord.h"

#import <ServiceManagement/ServiceManagement.h>
#include <libproc.h>
#include <sys/sysctl.h>
#import <objc/runtime.h>

#define LOADING_TIME2 (LOADING_TIME + 3.0)

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

@synthesize animator;
@synthesize disabled;
@synthesize frames;
@synthesize frame;
@synthesize animating;

@synthesize apps;
@synthesize processes;
@synthesize sources;
@synthesize starter;
@synthesize started;

@synthesize advancedItems;
@synthesize advancedProcesses;

AppDelegate *_sharedDelegate;
+ (AppDelegate *)sharedDelegate { return _sharedDelegate; }

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

- (void)setImage:(NSImage *)image {
	if ([statusItem respondsToSelector:@selector(button)])
		[[statusItem button] setImage:image];
	else
		[statusItem setImage:image];
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
	
	bool open_at_login = false;
	if (result == kCFUserNotificationDefaultResponse) {
		SMLoginItemSetEnabled((CFStringRef)@"com.bonzaiapps.loader", YES); // should return YES
		open_at_login = true;
	}
	
	NSUserDefaults *preferences = [NSUserDefaults standardUserDefaults];
	[preferences setBool:YES forKey:@"Loaded"];
	[preferences setBool:open_at_login forKey:@"Open at Login"];
	[preferences synchronize];
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
		started = true;
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
							if ([process.path isEqualToString:path]) process.running = true;
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
								// 1. first check for the first occurrence of ".app/" within the process' path
								NSRange range = [path rangeOfString:@".app/"];
								if (range.location != NSNotFound) {
									path = [path substringWithRange:NSMakeRange(0, range.location + range.length - 1)];
									app = [AppRecord findByPath:path within:apps atIndex:&app_index];
									if (app == nil) {
										// add this app!
										app = [[AppRecord alloc] initWithPath:path];
										[apps insertObject:app atIndex:app_index];
									}
								}
								
								// 2. if that fails, if the name is in the format "com.apple.Safari.whatever", get the bundle matching that bundle ID
								if (app == nil) {
									if ([path rangeOfString:@"com.apple.Safari"].location != NSNotFound
										|| [path rangeOfString:@"com.apple.WebKit"].location != NSNotFound
										|| [path hasPrefix:@"/System/Library/StagedFrameworks/Safari/"]) {
										
										NSString *path2 = [[NSWorkspace sharedWorkspace] absolutePathForAppBundleWithIdentifier:@"com.apple.Safari"];
										if (path2 != nil) {
											app = [AppRecord findByPath:path2 within:apps atIndex:&app_index];
											if (app == nil) {
												// add this app!
												app = [[AppRecord alloc] initWithPath:path2];
												[apps insertObject:app atIndex:app_index];
											}
										}
									} else if ([path hasPrefix:@"/System/Library/PrivateFrameworks/CommerceKit.framework/"]) {
										NSString *path2 = [[NSWorkspace sharedWorkspace] absolutePathForAppBundleWithIdentifier:@"com.apple.AppStore"];
										if (path2 != nil) {
											app = [AppRecord findByPath:path2 within:apps atIndex:&app_index];
											if (app == nil) {
												// add this app!
												app = [[AppRecord alloc] initWithPath:path2];
												[apps insertObject:app atIndex:app_index];
											}
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
						
						process.app = app;
					}
					
					process.stillRunning = true;
					
					if (source2.up < up || source2.down < down) {
						source2.up = up;
						source2.down = down;
						process.updated = CFAbsoluteTimeGetCurrent();
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

- (void)quit {
	[[NSApplication sharedApplication] terminate:self];
}

- (void)toggleOpenAtLogin:(id)sender {
	NSUserDefaults *preferences = [NSUserDefaults standardUserDefaults];
	bool open_at_login = ![preferences boolForKey:@"Open at Login"];
	[preferences setBool:open_at_login forKey:@"Open at Login"];
	[preferences synchronize];
	SMLoginItemSetEnabled((CFStringRef)@"com.bonzaiapps.loader", open_at_login); // should return YES
}

- (NSAttributedString *)wrappedText:(NSString *)text width:(float)max_width {
	NSMutableParagraphStyle* pathStyle = [[NSMutableParagraphStyle alloc] init];
	pathStyle.minimumLineHeight = 13.0;
	
	NSDictionary *pathAttribs= @{ NSFontAttributeName:[NSFont menuFontOfSize:11.0], NSParagraphStyleAttributeName:pathStyle };
	
	NSAttributedString *pathText = [[NSAttributedString alloc] initWithString:text attributes:pathAttribs];
	
	CTFramesetterRef fs = CTFramesetterCreateWithAttributedString((__bridge CFAttributedStringRef)pathText);
	CGMutablePathRef path2 = CGPathCreateMutable();
	CGPathAddRect(path2, nil, CGRectMake(0, 0, max_width, CGFLOAT_MAX));
	CTFrameRef f = CTFramesetterCreateFrame(fs, CFRangeMake(0, 0), path2, NULL);
	CTFrameDraw(f, nil);
	
	NSArray* lines = (__bridge NSArray*)CTFrameGetLines(f);
	NSMutableArray *final = [[NSMutableArray alloc] initWithCapacity:0];
	for (id aLine in lines) {
		CFRange range = CTLineGetStringRange((__bridge CTLineRef)aLine);
		[final addObject:[text substringWithRange:NSMakeRange(range.location, range.length)]];
	}
	
	CGPathRelease(path2);
	CFRelease(f);
	CFRelease(fs);
	
	return [[NSAttributedString alloc] initWithString:[final componentsJoinedByString:@"\n"] attributes:pathAttribs];
}

- (void)openProcess:(id)sender {
	ProcessRecord *process = [sender representedObject];
	NSURL *url = [NSURL fileURLWithPath:process.path];
	if (url != nil)
		[[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:[NSArray arrayWithObjects:url, nil]];
}

- (void)open:(id)sender {
	AppRecord *app = [sender representedObject];
	if (app != nil) {
		NSURL *url = nil;
		if ([app.path isEqualToString:@"System"])
			url = [NSURL fileURLWithPath:@"/System/"];
		else
			url = [NSURL fileURLWithPath:app.path];
		if (url != nil)
			[[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:[NSArray arrayWithObjects:url, nil]];
	}
}

- (void)addProcessesForApp:(AppRecord *)app isLoading:(bool)loading atTime:(double)cur_time {
	long process_index;
	bool added = false;
	for (process_index = 0; process_index < [processes count]; process_index++) {
		ProcessRecord *process = [processes objectAtIndex:process_index];
		if (process.app == app && process.path != nil) {
			if ((loading && cur_time - process.updated < LOADING_TIME2) ||
				(!loading && cur_time - process.updated >= LOADING_TIME2 && cur_time - process.updated < LOADED_TIME)) {
				
				NSMenuItem *item = [[NSMenuItem alloc] init];
				[item setTitle:@""];
				[menu addItem:item];
				[advancedItems addObject:item];
				[advancedProcesses addObject:process];
				added = true;
			}
		}
	}
	
	if (added) {
		NSMenuItem *item = [[NSMenuItem alloc] init];
		[item setAttributedTitle:[[NSAttributedString alloc] initWithString:@" " attributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSFont systemFontOfSize:8.0], NSFontAttributeName, nil]]];
		[menu addItem:item];
	}
}

- (void)updateMenu {
	[menu removeAllItems];
	
	@synchronized(apps) {
		AppRecord *app;
		long app_index;
		
		double cur_time = CFAbsoluteTimeGetCurrent();
		
		// add advanced details on the running processes
		bool advanced = (([[NSApp currentEvent] modifierFlags] & NSAlternateKeyMask));
		
		// only list discoveryd in advanced mode
		double system_updated = 0.0;
		double discoveryd_updated = 0.0;
		ProcessRecord *discoveryd_process = nil;
		AppRecord *system_app = nil;
		advancedItems = [[NSMutableArray alloc] initWithCapacity:0];
		advancedProcesses = [[NSMutableArray alloc] initWithCapacity:0];
		
		if (!advanced) {
			for (app_index = 0; app_index < [apps count]; app_index++) {
				app = [apps objectAtIndex:app_index];
				
				if ([app.path isEqualToString:@"System"]) {
					system_updated = app.updated;
					system_app = app;
					app.updated = 0.0;
					
					long process_index;
					for (process_index = 0; process_index < [processes count]; process_index++) {
						ProcessRecord *process = [processes objectAtIndex:process_index];
						if (process.app == app && process.path != nil) {
							if (![process.path hasSuffix:@"/discoveryd"]) {
								if (process.updated > app.updated)
									app.updated = process.updated;
							} else {
								discoveryd_updated = process.updated;
								discoveryd_process = process;
								process.updated = 0.0;
							}
						}
					}
					
					break;
				}
			}
		}
		
		int loaded = 0, loading = 0;
		for (app_index = 0; app_index < [apps count]; app_index++) {
			app = [apps objectAtIndex:app_index];
			
			if (cur_time - app.updated < LOADING_TIME2)
				loading++;
			else if (cur_time - app.updated < LOADED_TIME)
				loaded++;
			
			if (advanced && cur_time - app.updated < LOADING_TIME2) {
				// apps can be listed twice if the option key was held down and there are processes that were loaded
				long process_index;
				for (process_index = 0; process_index < [processes count]; process_index++) {
					ProcessRecord *process = [processes objectAtIndex:process_index];
					if (process.app == app && process.path != nil) {
						if (cur_time - process.updated >= LOADING_TIME2 && cur_time - process.updated < LOADED_TIME) {
							loaded++;
							break;
						}
					}
				}
			}
		}
		
		NSMenuItem *item;
		
		NSUserDefaults *preferences = [NSUserDefaults standardUserDefaults];
		
		if (loading > 0 || loaded == 0) {
			item = [[NSMenuItem alloc] init];
			[item setAttributedTitle:[[NSAttributedString alloc] initWithString:NSLocalizedString(@"LOADING", nil)
																	 attributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSFont boldSystemFontOfSize:11.0], NSFontAttributeName, nil]]];
			[menu addItem:item];
			
			if (advanced && loading > 0) {
				item = [[NSMenuItem alloc] init];
				//[item setView:[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 7)]];
				[item setAttributedTitle:[[NSAttributedString alloc] initWithString:@" " attributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSFont systemFontOfSize:5.0], NSFontAttributeName, nil]]];
				[menu addItem:item];
			}
		}
		
		for (app_index = 0; app_index < [apps count]; app_index++) {
			app = [apps objectAtIndex:app_index];
			if (cur_time - app.updated < LOADING_TIME2) {
				item = [[NSMenuItem alloc] init];
				if ([app.path isEqualToString:@"System"])
					[item setTitle:NSLocalizedString(@"SYSTEM", nil)];
				else
					[item setTitle:app.name];
				[item setImage:app.icon];
				[item setRepresentedObject:app];
				[item setTarget:self];
				[item setAction:@selector(open:)];
				
				[menu addItem:item];
				
				if (advanced) [self addProcessesForApp:app isLoading:true atTime:cur_time];
			}
		}
		
		if (loaded > 0) {
			if (loading > 0)
				[menu addItem:[NSMenuItem separatorItem]];
			
			item = [[NSMenuItem alloc] init];
			[item setAttributedTitle:[[NSAttributedString alloc] initWithString:NSLocalizedString(@"LOADED", nil)
																	 attributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSFont boldSystemFontOfSize:11.0], NSFontAttributeName, nil]]];
			[menu addItem:item];
			
			if (advanced) {
				item = [[NSMenuItem alloc] init];
				[item setAttributedTitle:[[NSAttributedString alloc] initWithString:@" " attributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSFont systemFontOfSize:5.0], NSFontAttributeName, nil]]];
				[menu addItem:item];
			}
		}
		
		for (app_index = 0; app_index < [apps count]; app_index++) {
			app = [apps objectAtIndex:app_index];
			if (cur_time - app.updated >= LOADING_TIME2 && cur_time - app.updated < LOADED_TIME) {
				item = [[NSMenuItem alloc] init];
				if ([app.path isEqualToString:@"System"])
					[item setTitle:NSLocalizedString(@"SYSTEM", nil)];
				else
					[item setTitle:app.name];
				[item setImage:app.icon];
				[item setTarget:self];
				[item setAction:@selector(open:)];
				[item setRepresentedObject:app];
				[menu addItem:item];
				
				if (advanced) [self addProcessesForApp:app isLoading:false atTime:cur_time];
				
			} else if (advanced /*&& [app.path isEqualToString:@"System"]*/ && cur_time - app.updated < LOADED_TIME) {
				// the "System" app can be used twice if the option key was held down and there are processes that were loaded
				bool found_loaded = false;
				long process_index;
				for (process_index = 0; process_index < [processes count]; process_index++) {
					ProcessRecord *process = [processes objectAtIndex:process_index];
					if (process.app == app && process.path != nil) {
						if (cur_time - process.updated >= LOADING_TIME2 && cur_time - process.updated < LOADED_TIME) {
							found_loaded = true;
							break;
						}
					}
				}
				
				if (found_loaded) {
					item = [[NSMenuItem alloc] init];
					if ([app.path isEqualToString:@"System"])
						[item setTitle:NSLocalizedString(@"SYSTEM", nil)];
					else
						[item setTitle:app.name];
					[item setImage:app.icon];
					[item setTarget:self];
					[item setAction:@selector(open:)];
					[item setRepresentedObject:app];
					[menu addItem:item];
					
					[self addProcessesForApp:app isLoading:false atTime:cur_time];
				}
			}
		}
		
		if (discoveryd_process != nil)
			discoveryd_process.updated = discoveryd_updated;
		if (system_app != nil)
			system_app.updated = system_updated;
		
		[menu addItem:[NSMenuItem separatorItem]];
		
		item = [[NSMenuItem alloc] init];
		[item setTitle:NSLocalizedString(@"OPEN_AT_LOGIN", nil)];
		if ([preferences boolForKey:@"Open at Login"]) [item setState:NSOnState];
		[item setTarget:self];
		[item setAction:@selector(toggleOpenAtLogin:)];
		[menu addItem:item];
		
		item = [[NSMenuItem alloc] init];
		[item setTitle:NSLocalizedString(@"QUIT", nil)];
		[item setTarget:self];
		[item setAction:@selector(quit)];
		[menu addItem:item];
		
		// get the width of the menu, then create an attributed string
		float max_width = [menu size].width;
		if (max_width < 210) max_width = 210;
		
		for (long index = 0; index < [advancedProcesses count]; index++) {
			ProcessRecord *process = [advancedProcesses objectAtIndex:index];
			NSMenuItem *item = [advancedItems objectAtIndex:index];
			
			NSString *path = process.path;
			NSMutableArray *folders = [[NSMutableArray alloc] initWithCapacity:0];
			NSFileManager *manager = [NSFileManager defaultManager];
			while (path != nil && ![path isEqualToString:@"/"]) {
				[folders insertObject:[manager displayNameAtPath:path] atIndex:0];
				path = [path stringByDeletingLastPathComponent];
			}
			
			// remove the /Contents/MacOS/Process if it's the same as the app name
			if ([folders count] > 4 &&
				[[folders objectAtIndex:([folders count] - 2)] isEqualToString:@"MacOS"] &&
				[[folders objectAtIndex:([folders count] - 3)] isEqualToString:@"Contents"] &&
				[[folders objectAtIndex:([folders count] - 4)] isEqualToString:[folders objectAtIndex:([folders count] - 1)]]) {
				[folders removeObjectAtIndex:([folders count] - 1)];
				[folders removeObjectAtIndex:([folders count] - 1)];
				[folders removeObjectAtIndex:([folders count] - 1)];
			}
			
			[item setIndentationLevel:1];
			[item setAttributedTitle:[self wrappedText:[NSString stringWithFormat:@"%d %@", process.pid, [folders componentsJoinedByString:@"\u00A0▸ "]] width:max_width]];
			[item setRepresentedObject:process];
			[item setTarget:self];
			[item setAction:@selector(openProcess:)];
			
		}
	}
}

static IMP _trackMouse_original;
BOOL _trackMouse_replacement(id self, SEL _cmd, NSEvent *theEvent, NSRect cellFrame, NSView *controlView, BOOL untilMouseUp) {
	[[AppDelegate sharedDelegate] updateMenu];
	
	return ((BOOL (*)(id, SEL, NSEvent *, NSRect, NSView *, BOOL))_trackMouse_original)(self, _cmd, theEvent, cellFrame, controlView, untilMouseUp);
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	_sharedDelegate = self;
	
	statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:24.0]; // NSSquareStatusItemLength?
	[statusItem setHighlightMode:YES];
	
	apps = [[NSMutableArray alloc] initWithObjects:[[AppRecord alloc] initWithPath:@"System"], nil];
	processes = [[NSMutableArray alloc] initWithCapacity:0];
	sources = [[NSMutableArray alloc] initWithCapacity:0];
	
	disabled = [NSImage imageNamed:@"Disabled"];
	[disabled setTemplate:YES];
	
	frames = [[NSArray alloc] initWithObjects:[NSImage imageNamed:@"Frame1"], [NSImage imageNamed:@"Frame2"], [NSImage imageNamed:@"Frame3"],
			  [NSImage imageNamed:@"Frame4"], [NSImage imageNamed:@"Frame5"], [NSImage imageNamed:@"Frame6"],
			  [NSImage imageNamed:@"Frame7"], [NSImage imageNamed:@"Frame8"], [NSImage imageNamed:@"Frame9"],
			  [NSImage imageNamed:@"Frame10"], [NSImage imageNamed:@"Frame11"], [NSImage imageNamed:@"Frame12"], nil];
	
	long frame_index;
	for (frame_index = 0; frame_index < [frames count]; frame_index++) {
		NSImage *image = [frames objectAtIndex:frame_index];
		[image setTemplate:YES];
	}
	
	animator = nil;
	animating = true; frame = 0;
	[self stopAnimating];
	
	menu = [[NSMenu alloc] initWithTitle:NSLocalizedString(@"Loading", nil)];
	[statusItem setMenu:menu];
	
	// swizzle NSStatusBarButtonCell trackMouse:inRect:ofView:untilMouseUp
	_trackMouse_original = method_setImplementation(class_getInstanceMethod([[[self statusItemButton] cell] class], @selector(trackMouse:inRect:ofView:untilMouseUp:)), (IMP)_trackMouse_replacement);
	
	
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
				process.stillRunning = false;
			}
			
			NStatManagerQueryAllSources(manager, nil);
			
			bool loading = false;
			double cur_time = CFAbsoluteTimeGetCurrent();
			
			// removed unused processes and apps
			for (process_index = [processes count] - 1; process_index >= 0; process_index--) {
				ProcessRecord *process = [processes objectAtIndex:process_index];
				
				if (!process.stillRunning) {
					//if (process.running) NSLog(@"Process terminated: %@\n", process.path);
					process.running = false;
				}
				
				if (!process.running && cur_time - process.updated >= LOADED_TIME) {
					[processes removeObjectAtIndex:process_index];
					
					AppRecord *app = process.app;
					if (app != nil) {
						// remove the parent app if no processes point to it anymore
						bool app_used = false;
						long process_index2;
						for (process_index2 = 0; process_index2 < [processes count]; process_index2++) {
							process = [processes objectAtIndex:process_index2];
							if (process.app == app) {
								app_used = true;
								break;
							}
						}
						
						if (!app_used) [apps removeObject:app];
					}
				} else if (!loading && cur_time - process.updated < LOADING_TIME && process.app != nil && (![process.app.path isEqualToString:@"System"] || ![process.path hasSuffix:@"/discoveryd"])) {
					loading = true;
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
	
	
	NSUserDefaults *preferences = [NSUserDefaults standardUserDefaults];
	[preferences registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:NO, @"Loaded", nil]];
	
	if (![preferences boolForKey:@"Loaded"]) [self performSelectorInBackground:@selector(showDialog) withObject:nil];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
	[[NSStatusBar systemStatusBar] removeStatusItem:statusItem];
	if (manager != nil) NStatManagerDestroy(manager);
}

- (void)updateAnimation {
	[self setImage:[frames objectAtIndex:frame]];
	if (animating && ++frame >= 12) frame = 0;
}

- (void)startAnimating {
	if (animating) return;
	animating = true;
	if (animator == nil) animator = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(updateAnimation) userInfo:nil repeats:YES];
}

- (void)stopAnimating {
	if (!animating) return;
	animating = false;
	if (animator != nil) {
		[animator invalidate];
		animator = nil;
	}
	
	[self setImage:disabled];
}

@end
