#import "MenuDelegate.h"
#import "AppDelegate.h"
#import "AppRecord.h"

#import <ServiceManagement/ServiceManagement.h>
#import <Carbon/Carbon.h>

#define LOADING_TIME2 (LOADING_TIME + 3.0)

@implementation MenuDelegate

@synthesize advanced;
@synthesize advancedItems;
@synthesize advancedProcesses;

@synthesize toggleAnimation;
@synthesize animate;
@synthesize inanimate;
@synthesize indeterminate;

- (void)quit {
	[[NSApplication sharedApplication] terminate:self];
}

- (void)toggleOpenAtLogin:(id)sender {
	NSUserDefaults *preferences = [NSUserDefaults standardUserDefaults];
	BOOL open_at_login = ![preferences boolForKey:@"Open at Login"];
	[preferences setBool:open_at_login forKey:@"Open at Login"];
	[preferences synchronize];
	SMLoginItemSetEnabled((CFStringRef)@"com.bonzaiapps.loader", open_at_login); // should return YES
}

- (void)sendFeedback:(id)sender {
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"mailto:mike@bonzaiapps.com"]];
}

- (void)visitWebsite:(id)sender {
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://bonzaiapps.com/loading/"]];
}

- (void)about:(id)sender {
	[[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
	[[NSApplication sharedApplication] orderFrontStandardAboutPanel:sender];
}

- (void)openProcess:(id)sender {
	if (toggleAnimation) return;
	
	ProcessRecord *process = [sender representedObject];
	NSURL *url = [NSURL fileURLWithPath:process.path];
	if (url != nil)
		[[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:[NSArray arrayWithObjects:url, nil]];
}

- (void)open:(id)sender {
	if (toggleAnimation) return;
	
	AppRecord *app = [sender representedObject];
	if (app != nil) {
		if ([app.path isEqualToString:@"System"]) {
			NSURL *url = [NSURL fileURLWithPath:@"/System/"];
			if (url != nil)
				[[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:[NSArray arrayWithObjects:url, nil]];
		} else {
			NSURL *url = [NSURL fileURLWithPath:app.path];
			if (url != nil)
				[[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:[NSArray arrayWithObjects:url, nil]];
		}
	}
}

- (NSAttributedString *)wrappedText:(NSString *)text width:(float)max_width attributes:attribs {
	NSAttributedString *pathText = [[NSAttributedString alloc] initWithString:text attributes:attribs];
	
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
	
	NSString *joiner = @"\n";
	if ([[AppDelegate sharedDelegate] isRightToLeft]) joiner = @"\n\u200F";
	return [[NSAttributedString alloc] initWithString:[final componentsJoinedByString:joiner] attributes:attribs];
}

- (void)toggleAnimate:(id)obj {
	BOOL animated = NO;
	NSString *path = nil;
	
	// this will be cleaned up later
	if ([obj isKindOfClass:[AppRecord class]]) {
		animated = ((AppRecord *)obj).animate;
		path = ((AppRecord *)obj).path;
	} else if ([obj isKindOfClass:[ProcessRecord class]]) {
		animated = ((ProcessRecord *)obj).animate;
		path = ((ProcessRecord *)obj).path;
	}
	
	if (animated)
		[[AppDelegate sharedDelegate] addPathToIgnored:path];
	else
		[[AppDelegate sharedDelegate] removePathFromIgnored:path];
	
	// don't trigger the standard menu action when toggling the checkbox thingy
	toggleAnimation = YES;
}

- (void)addProcessesForApp:(AppRecord *)app toMenu:(NSMenu *)menu isLoading:(BOOL)loading atTime:(double)cur_time {
	AppDelegate *delegate = [AppDelegate sharedDelegate];
	
	long process_index;
	BOOL added = NO;
	for (process_index = 0; process_index < [delegate.processes count]; process_index++) {
		ProcessRecord *process = [delegate.processes objectAtIndex:process_index];
		if (process.app == app && process.path != nil) {
			if ((loading && cur_time - process.updated < LOADING_TIME2) ||
				(!loading && cur_time - process.updated >= LOADING_TIME2 && cur_time - process.updated < LOADED_TIME)) {
				
				NSMenuItem *item = [[NSMenuItem alloc] init];
				[item setTitle:@""];
				[menu addItem:item];
				[advancedItems addObject:item];
				[advancedProcesses addObject:process];
				added = YES;
			}
		}
	}
	
	if (added) {
		NSMenuItem *item = [[NSMenuItem alloc] init];
		[item setAttributedTitle:[[NSAttributedString alloc] initWithString:@" " attributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSFont systemFontOfSize:8.0], NSFontAttributeName, nil]]];
		[menu addItem:item];
	}
}

- (void)updateMenu:(NSMenu *)menu {
	AppDelegate *delegate = [AppDelegate sharedDelegate];
	[menu removeAllItems];
	
	@synchronized(delegate.apps) {
		AppRecord *app;
		long app_index;
		
		double cur_time = CFAbsoluteTimeGetCurrent();
		
		// add advanced details on the running processes
		advanced = (([[NSApp currentEvent] modifierFlags] & NSAlternateKeyMask) == NSAlternateKeyMask);
		
		// only list discoveryd in advanced mode
		double system_updated = 0.0;
		double discoveryd_updated = 0.0;
		ProcessRecord *discoveryd_process = nil;
		AppRecord *system_app = nil;
		advancedItems = [[NSMutableArray alloc] initWithCapacity:0];
		advancedProcesses = [[NSMutableArray alloc] initWithCapacity:0];
		
		if (!advanced) {
			for (app_index = 0; app_index < [delegate.apps count]; app_index++) {
				app = [delegate.apps objectAtIndex:app_index];
				
				if ([app.path isEqualToString:@"System"]) {
					system_updated = app.updated;
					system_app = app;
					app.updated = 0.0;
					
					long process_index;
					for (process_index = 0; process_index < [delegate.processes count]; process_index++) {
						ProcessRecord *process = [delegate.processes objectAtIndex:process_index];
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
		for (app_index = 0; app_index < [delegate.apps count]; app_index++) {
			app = [delegate.apps objectAtIndex:app_index];
			
			if (cur_time - app.updated < LOADING_TIME2)
				loading++;
			else if (cur_time - app.updated < LOADED_TIME)
				loaded++;
			
			if (advanced && cur_time - app.updated < LOADING_TIME2) {
				// apps can be listed twice if the option key was held down and there are processes that were loaded
				long process_index;
				for (process_index = 0; process_index < [delegate.processes count]; process_index++) {
					ProcessRecord *process = [delegate.processes objectAtIndex:process_index];
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
				[item setAttributedTitle:[[NSAttributedString alloc] initWithString:@" " attributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSFont systemFontOfSize:5.0], NSFontAttributeName, nil]]];
				[menu addItem:item];
			}
		}
		
		for (app_index = 0; app_index < [delegate.apps count]; app_index++) {
			app = [delegate.apps objectAtIndex:app_index];
			if (cur_time - app.updated < LOADING_TIME2) {
				item = [[NSMenuItem alloc] init];
				if ([app.path isEqualToString:@"System"])
					[item setAttributedTitle:[[NSAttributedString alloc] initWithString:NSLocalizedString(@"SYSTEM", nil) attributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSFont systemFontOfSize:0.0], NSFontAttributeName, nil]]];
				else
					[item setAttributedTitle:[[NSAttributedString alloc] initWithString:app.name attributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSFont systemFontOfSize:0.0], NSFontAttributeName, nil]]];
				[item setImage:app.icon];
				[item setRepresentedObject:app];
				[item setTarget:self];
				[item setAction:@selector(open:)];
				
				[menu addItem:item];
				
				if (advanced) [self addProcessesForApp:app toMenu:menu isLoading:YES atTime:cur_time];
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
		
		for (app_index = 0; app_index < [delegate.apps count]; app_index++) {
			app = [delegate.apps objectAtIndex:app_index];
			if (cur_time - app.updated >= LOADING_TIME2 && cur_time - app.updated < LOADED_TIME) {
				item = [[NSMenuItem alloc] init];
				if ([app.path isEqualToString:@"System"])
					[item setAttributedTitle:[[NSAttributedString alloc] initWithString:NSLocalizedString(@"SYSTEM", nil) attributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSFont systemFontOfSize:0.0], NSFontAttributeName, nil]]];
				else
					[item setAttributedTitle:[[NSAttributedString alloc] initWithString:app.name attributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSFont systemFontOfSize:0.0], NSFontAttributeName, nil]]];
				[item setImage:app.icon];
				[item setTarget:self];
				[item setAction:@selector(open:)];
				[item setRepresentedObject:app];
				[menu addItem:item];
				
				if (advanced) [self addProcessesForApp:app toMenu:menu isLoading:NO atTime:cur_time];
				
			} else if (advanced /*&& [app.path isEqualToString:@"System"]*/ && cur_time - app.updated < LOADED_TIME) {
				// the "System" app can be used twice if the option key was held down and there are processes that were loaded
				BOOL found_loaded = NO;
				long process_index;
				for (process_index = 0; process_index < [delegate.processes count]; process_index++) {
					ProcessRecord *process = [delegate.processes objectAtIndex:process_index];
					if (process.app == app && process.path != nil) {
						if (cur_time - process.updated >= LOADING_TIME2 && cur_time - process.updated < LOADED_TIME) {
							found_loaded = YES;
							break;
						}
					}
				}
				
				if (found_loaded) {
					item = [[NSMenuItem alloc] init];
					if ([app.path isEqualToString:@"System"])
						[item setAttributedTitle:[[NSAttributedString alloc] initWithString:NSLocalizedString(@"SYSTEM", nil) attributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSFont systemFontOfSize:0.0], NSFontAttributeName, nil]]];
					else
						[item setAttributedTitle:[[NSAttributedString alloc] initWithString:app.name attributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSFont systemFontOfSize:0.0], NSFontAttributeName, nil]]];
					[item setImage:app.icon];
					[item setTarget:self];
					[item setAction:@selector(open:)];
					[item setRepresentedObject:app];
					[menu addItem:item];
					
					[self addProcessesForApp:app toMenu:menu isLoading:NO atTime:cur_time];
				}
			}
		}
		
		if (discoveryd_process != nil)
			discoveryd_process.updated = discoveryd_updated;
		if (system_app != nil)
			system_app.updated = system_updated;
		
		[menu addItem:[NSMenuItem separatorItem]];
		
		NSMenu *options_menu = [[NSMenu alloc] initWithTitle:NSLocalizedString(@"OPTIONS", nil)];
		
		item = [[NSMenuItem alloc] init];
		[item setTitle:NSLocalizedString(@"OPEN_AT_LOGIN", nil)];
		if ([preferences boolForKey:@"Open at Login"]) [item setState:NSOnState];
		[item setTarget:self];
		[item setAction:@selector(toggleOpenAtLogin:)];
		[options_menu addItem:item];
		
//		item = [[NSMenuItem alloc] init];
//		[item setTitle:NSLocalizedString(@"CHECK_FOR_UPDATES", nil)];
//		if ([preferences boolForKey:@"Check for Updates"]) [item setState:NSOnState];
//		[item setTarget:self];
//		[item setAction:@selector(toggleCheckForUpdates:)];
//		[options_menu addItem:item];
		
		[options_menu addItem:[NSMenuItem separatorItem]];
		
		NSMutableAttributedString *text = [[NSMutableAttributedString alloc] init];
		[text appendAttributedString:[[NSAttributedString alloc] initWithString:@"Loading " attributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSFont boldSystemFontOfSize:0.0], NSFontAttributeName, nil]]];
		[text appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@\n", [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"]] attributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSFont systemFontOfSize:11.0], NSFontAttributeName, nil]]];
		[text appendAttributedString:[[NSAttributedString alloc] initWithString:@"bonzaiapps.com" attributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSFont systemFontOfSize:11.0], NSFontAttributeName, [NSColor colorWithCalibratedRed:0.541 green:0.705 blue:0.588 alpha:1.0], NSForegroundColorAttributeName, nil]]];
		
		item = [[NSMenuItem alloc] init];
		[item setAttributedTitle:text];
		[item setTarget:self];
		[item setAction:@selector(visitWebsite:)];
		[options_menu addItem:item];
		
		[options_menu addItem:[NSMenuItem separatorItem]];
		
		item = [[NSMenuItem alloc] init];
		[item setTitle:NSLocalizedString(@"QUIT", nil)];
		[item setTarget:self];
		[item setAction:@selector(quit)];
		[options_menu addItem:item];
		
		item = [[NSMenuItem alloc] init];
		[item setTitle:NSLocalizedString(@"OPTIONS", nil)];
		[item setSubmenu:options_menu];
		[menu addItem:item];
		
		// get the width of the menu, then create an attributed string
		float max_width = [menu size].width;
		if (max_width < 210) max_width = 210;
		
		NSMutableParagraphStyle* pathStyle = [[NSMutableParagraphStyle alloc] init];
		pathStyle.minimumLineHeight = 13.0;
		NSDictionary *attribs= @{ NSFontAttributeName:[NSFont menuFontOfSize:11.0], NSParagraphStyleAttributeName:pathStyle };
		NSDictionary *disabledAttribs= @{ NSFontAttributeName:[NSFont menuFontOfSize:11.0], NSParagraphStyleAttributeName:pathStyle, NSForegroundColorAttributeName:[NSColor colorWithCalibratedRed:0.6 green:0.6 blue:0.6 alpha:1.0] };
		
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
			
			// \u00A0 is a non-breaking space
			// \u202B forces right-to-left text direction
			NSString *joiner = @"\u00A0▸ ";
			NSString *format = @"%d %@";
			if ([[AppDelegate sharedDelegate] isRightToLeft]) {
				joiner = @"\u00A0◁\u202B ";
				format = @"\u202B%d\u00A0%@";
			}
			NSDictionary *useAttribs = attribs;
			if (!process.running) useAttribs = disabledAttribs;
			
			[item setAttributedTitle:[self wrappedText:[NSString stringWithFormat:format, process.pid, [folders componentsJoinedByString:joiner]] width:max_width attributes:useAttribs]];
			[item setIndentationLevel:1];
			[item setRepresentedObject:process];
			[item setTarget:self];
			[item setAction:@selector(openProcess:)];
			
		}
	}
}

MenuRef menuRef;
int indentWidth, columnWidth;

OSStatus eventHandler(EventHandlerCallRef inHandlerRef, EventRef inEvent, void *inUserData) {
	OSType event_class = GetEventClass(inEvent);
	OSType event_kind = GetEventKind(inEvent);
	OSStatus ret = 0;
	
	if (event_class == kEventClassMenu) {
		
		if (event_kind == kEventMenuDrawItem) {
			// draw the standard menu stuff
			ret = CallNextEventHandler(inHandlerRef, inEvent);
			
			// draw a checkmark next to the selected app or process if it can animate the menubar icon
			MenuTrackingData tracking_data;
			GetMenuTrackingData(menuRef, &tracking_data);
			
			MenuItemIndex item_index;
			GetEventParameter(inEvent, kEventParamMenuItemIndex, typeMenuItemIndex, nil, sizeof(item_index), nil, &item_index);
			
			if (tracking_data.itemSelected == item_index) {
				AppDelegate *delegate = [AppDelegate sharedDelegate];
				NSMenuItem *selectedItem = [delegate.menu highlightedItem];
				if (selectedItem != nil && [selectedItem representedObject] != nil) {
					// The calling function clips the CGContextRef to the bounds of the current menu item that should be drawn
					// and translates to (menu_left, menubar_height), so it would seem like we can just draw at item_rect.origin.y.
					// Unfortunately the origin for the coordinate system is defined to be the lower-left corner, when all of the
					// coordinates given here are from the upper-left corner.
					// It's supposed to pass in kEventParamContextHeight so we can flip the CGContextRef properly, but does not.
					
					// Without this value there's no way to draw into the context as provided here, so this nasty hack is needed.
					
					HIRect item_rect;
					GetEventParameter(inEvent, kEventParamMenuItemBounds, typeHIRect, nil, sizeof(item_rect), nil, &item_rect);
					
					CGContextRef context;
					GetEventParameter(inEvent, kEventParamCGContextRef, typeCGContextRef, nil, sizeof(context), nil, &context);
					
					// first REMOVE a state from the graphics stack, instead of pushing onto the stack
					// this is to remove the clipping and translation values that are completely useless without the context height value
					extern void *CGContextCopyTopGState(CGContextRef);
					void *state = CGContextCopyTopGState(context);
					
					CGContextRestoreGState(context);
					
					// then magically discover that kEventParamMenuItemBounds and GetMenuTrackingData.virtualMenuTop give the correct values
					// GetEventParameter(kEventParamVirtualMenuTop) does NOT give the correct value – it's another bug with the APIs
					
					long indentLevel = [selectedItem indentationLevel];
					CGRect draw_rect = CGRectMake(indentLevel * indentWidth + round((columnWidth - 10) * 0.5), item_rect.origin.y - tracking_data.virtualMenuTop + round((item_rect.size.height - 10) * 0.5), 10, 10);
					if ([delegate isRightToLeft]) draw_rect.origin.x = item_rect.size.width - draw_rect.origin.x - draw_rect.size.width;
					
					BOOL animate = NO;
					if ([[selectedItem representedObject] isKindOfClass:[AppRecord class]])
						animate = ((AppRecord *)[selectedItem representedObject]).animate;
					else if ([[selectedItem representedObject] isKindOfClass:[ProcessRecord class]])
						animate = ((ProcessRecord *)[selectedItem representedObject]).animate;
					
					// I didn't feel like figuring out how to flip the CGImage here, so I flipped the assets themselves
					// (yes, I'm serious)
					
					NSImage *image;
					if (!animate)
						image = delegate.menuDelegate.inanimate;
					else if ([[selectedItem representedObject] isKindOfClass:[ProcessRecord class]] && !((ProcessRecord *)[selectedItem representedObject]).app.animate)
						image = delegate.menuDelegate.indeterminate;
					else
						image = delegate.menuDelegate.animate;
					
					CGContextDrawImage(context, draw_rect, [image CGImageForProposedRect:&draw_rect context:NULL hints:nil]);
					
					// and push a dummy graphics state onto the stack so the calling function can pop it again and be none the wiser
					CGContextSaveGState(context);
					
					extern void CGContextReplaceTopGState(CGContextRef, void *);
					CGContextReplaceTopGState(context, state);
					
					extern void CGGStateRelease(void *);
					CGGStateRelease(state);
					
				}
			}
		}
	} else if (event_class == kEventClassMouse) {
		if (event_kind == kEventMouseUp) {
			AppDelegate *delegate = [AppDelegate sharedDelegate];
			NSMenuItem *selectedItem = [delegate.menu highlightedItem];
			if (selectedItem != nil && [selectedItem representedObject] != nil) {
				MenuTrackingData trackingData;
				GetMenuTrackingData(menuRef, &trackingData);
				
				HIPoint point; // HIPoint is the same as CGPoint
				GetEventParameter(inEvent, kEventParamMouseLocation, typeHIPoint, nil, sizeof(point), nil, &point);
				
				long indentLevel = [selectedItem indentationLevel];
				long left = indentLevel * indentWidth;
				if ([delegate isRightToLeft]) left = (trackingData.itemRect.right - trackingData.itemRect.left) - left - columnWidth;
				
				if (point.x > trackingData.itemRect.left + left && point.x < trackingData.itemRect.left + left + columnWidth) {
					// toggle whether to ignore this app/process
					[delegate.menuDelegate toggleAnimate:[selectedItem representedObject]];
				}
			}
			
			// call the standard mouse up handler, which will trigger the menu action
			ret = CallNextEventHandler(inHandlerRef, inEvent);
		}
	}
	
	return ret;
}

- (void)beginTracking:(NSMenu *)menu {
	toggleAnimation = NO;
	
	// install a Carbon event handler to custom draw the checkbox to the left of each app and process
	if (menuRef == nil) {
		extern MenuRef _NSGetCarbonMenu(NSMenu *);
		extern EventTargetRef GetMenuEventTarget(MenuRef);
		
		GetThemeMetric(kThemeMetricMenuIndentWidth, &indentWidth);
		GetThemeMetric(kThemeMetricMenuMarkColumnWidth, &columnWidth);
		
		menuRef = _NSGetCarbonMenu(menu);
		if (menuRef == nil) return;
		
		EventTypeSpec events[4];
		events[0].eventClass = kEventClassMenu;
		events[0].eventKind = kEventMenuBeginTracking;
		events[1].eventClass = kEventClassMenu;
		events[1].eventKind = kEventMenuChangeTrackingMode;
		events[2].eventClass = kEventClassMenu;
		events[2].eventKind = kEventMenuDrawItem;
		events[3].eventClass = kEventClassMouse;
		events[3].eventKind = kEventMouseUp;
		
		InstallEventHandler(GetMenuEventTarget(menuRef), NewEventHandlerUPP(&eventHandler), GetEventTypeCount(events), events, nil, nil);
	}
	
	if (menuRef != nil) {
		// set the kMenuItemAttrCustomDraw attrib for every app and process menu item
		// this attribute is needed in order to receive the kMenuEventDrawItem event in the Carbon event handler
		extern OSStatus ChangeMenuItemAttributes(MenuRef, MenuItemIndex, MenuItemAttributes, MenuItemAttributes);
		for (long index = 0; index < [[menu itemArray] count]; index++) {
			if ([(NSMenuItem *)[[menu itemArray] objectAtIndex:index] representedObject] != nil)
				ChangeMenuItemAttributes(menuRef, index, kMenuItemAttrCustomDraw, 0);
		}
	}
}

- (id)init {
	if ((self = [super init])) {
		animate = [NSImage imageNamed:@"Animate"];
		inanimate = [NSImage imageNamed:@"Inanimate"];
		indeterminate = [NSImage imageNamed:@"Indeterminate"];
	}
	return self;
}

@end
