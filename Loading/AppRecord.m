#import "AppRecord.h"
#import <Cocoa/Cocoa.h>

@implementation AppRecord

@synthesize icon;
@synthesize name;
@synthesize path;
@synthesize updated;
@synthesize animate;

+ (AppRecord *)findByPath:(NSString *)path within:(NSArray *)array atIndex:(long *)index {
	// if the array is empty, set the insertion point to the first item in the array
	if (array == nil || [array count] == 0 || path == nil) {
		*index = 0;
		return nil;
	}
	
	long low = 0, high = [array count] - 1, mid;
	
	while (low < high) {
		mid = low + ((high - low) / 2);
		if ([path compare:((AppRecord *)[array objectAtIndex:mid]).path] == NSOrderedDescending)
			low = mid + 1;
		else
			high = mid;
	}
	
	*index = low;
	if (*index < [array count] && [path compare:((AppRecord *)[array objectAtIndex:*index]).path] == NSOrderedDescending) (*index)++;
	if (*index < [array count] && [path compare:((AppRecord *)[array objectAtIndex:*index]).path] == NSOrderedSame) return ((AppRecord *)[array objectAtIndex:*index]);
	
	return nil;
}

- (id)initWithPath:(NSString *)path2 {
	if ((self = [super init])) {
		self.updated = 0.0;
		self.path = path2;
		self.icon = nil;
		self.animate = YES;
		self.name = nil;
		
		// load a name and icon for this application path
		if ([path2 isEqualToString:@"System"]) {
			self.name = @"System";
			self.icon = [[NSWorkspace sharedWorkspace] iconForFileType:NSFileTypeForHFSTypeCode(kSystemFolderIcon)];
		} else {
			NSString *cur_path = path;
			while (cur_path != nil) {
				NSBundle *bundle = [NSBundle bundleWithPath:cur_path];
				if (bundle != nil) {
					if (self.name == nil) {
						NSString *app_name = [bundle objectForInfoDictionaryKey:@"CFBundleDisplayName"];
						if (app_name == nil) app_name = [bundle objectForInfoDictionaryKey:@"CFBundleName"];
						if (app_name == nil) {
							// use the file name, minus the .app extension
							app_name = [[cur_path lastPathComponent] stringByDeletingPathExtension];
						}
						if (app_name != nil) self.name = app_name;
					}
					
					// this is a bit tricky because not all apps have CFBundleIconFile defined,
					// and NSWorkspace.iconForFile always returns an icon even if it fails (in which case it returns a generic app icon)
					// therefore use two passes, once with CFBundleIconFile, and again without it
					// and force override the icon in special circumstances like for Notification Center (see below)
					
					if ([bundle objectForInfoDictionaryKey:@"CFBundleIconFile"] != nil) {
						NSImage *icon2;
						if ((icon2 = [[NSWorkspace sharedWorkspace] iconForFile:cur_path]) && icon2.valid) {
							self.icon = icon2;
							break;
						}
					}
				}
				
				// no icon was found yet
				// if this app bundle is embedded inside another app bundle, try again with the parent bundle
				NSRange range = [cur_path rangeOfString:@".app/" options:NSBackwardsSearch];
				if (range.location != NSNotFound) {
					cur_path = [cur_path substringWithRange:NSMakeRange(0, range.location + range.length - 1)];
				} else {
					break;
				}
			}
			
			// if no icon was found, try again but without the check for CFBundleIconFile
			if (self.icon == nil) {
				NSString *cur_path = path;
				while (cur_path != nil) {
					NSBundle *bundle = [NSBundle bundleWithPath:cur_path];
					if (bundle != nil) {
						NSImage *icon2;
						if ((icon2 = [[NSWorkspace sharedWorkspace] iconForFile:cur_path]) && icon2.valid) {
							self.icon = icon2;
							break;
						}
					}
					NSRange range = [cur_path rangeOfString:@".app/" options:NSBackwardsSearch];
					if (range.location != NSNotFound) {
						cur_path = [cur_path substringWithRange:NSMakeRange(0, range.location + range.length - 1)];
					} else {
						break;
					}
				}
			}
			
			if (/*self.icon == nil*/true) {
				// see if we can magically determine the correct icon for it
				NSString *icon_path = nil; NSImage *icon2;
				
				// so far only Notification Center is supported
				if ([self.path hasPrefix:@"/System/Library/CoreServices/NotificationCenter.app"])
					icon_path = @"/System/Library/PreferencePanes/Notifications.prefPane";
				
				if (icon_path != nil) {
					if ((icon2 = [[NSWorkspace sharedWorkspace] iconForFile:icon_path]) && icon2.valid) {
						self.icon = icon2;
					}
				}
			}
			
			if (self.icon == nil) {
				// give it a "blank app" icon
				static NSImage *blank_app = nil;
				if (blank_app == nil) {
					blank_app = [[NSWorkspace sharedWorkspace] iconForFileType:NSFileTypeForHFSTypeCode(kGenericApplicationIcon)];
				}
				self.icon = blank_app;
			}
		}
		
		if (self.icon != nil) {
			[self.icon setSize:NSMakeSize(16, 16)];
		}
		
		if (self.name == nil) {
			self.name = @"Unknown";
		}
	}
	return self;
}

@end

@implementation ProcessRecord

@synthesize pid;
@synthesize path;
@synthesize app;
@synthesize updated;
@synthesize refreshed;
@synthesize running;
@synthesize animate;

+ (ProcessRecord *)findByPID:(int)pid within:(NSArray *)array atIndex:(long *)index {
	// if the array is empty, set the insertion point to the first item in the array
	if (array == nil || [array count] == 0) {
		*index = 0;
		return nil;
	}
	
	long low = 0, high = [array count] - 1, mid;
	
	while (low < high) {
		mid = low + ((high - low) / 2);
		if (pid > ((ProcessRecord *)[array objectAtIndex:mid]).pid)
			low = mid + 1;
		else
			high = mid;
	}
	
	*index = low;
	if (*index < [array count] && pid > ((ProcessRecord *)[array objectAtIndex:*index]).pid) (*index)++;
	if (*index < [array count] && pid == ((ProcessRecord *)[array objectAtIndex:*index]).pid) {
		// if the process is no longer running and there's another process with the same PID, return the running one!
		ProcessRecord *process = [array objectAtIndex:*index];
		if (!process.running) {
			for (long index2 = *index + 1; index2 < [array count]; index2++) {
				ProcessRecord *process2 = [array objectAtIndex:index2];
				if (process2.pid != process.pid) break;
				if (process2.running) {
					*index = index2;
					return process2;
				}
			}
		 }
		
		return process;
	}
	
	return nil;
}

- (id)initWithPID:(pid_t)pid2 {
	if ((self = [super init])) {
		pid = pid2;
		app = nil;
		path = nil;
		updated = 0.0;
		refreshed = CFAbsoluteTimeGetCurrent();
		animate = YES;
		running = YES;
	}
	return self;
}

@end


@implementation SourceRecord

@synthesize source;
@synthesize pid;
@synthesize up;
@synthesize down;
@synthesize next;

+ (SourceRecord *)findBySource:(void *)source within:(NSArray *)array atIndex:(long *)index {
	// if the array is empty, set the insertion point to the first item in the array
	if (array == nil || [array count] == 0) {
		*index = 0;
		return nil;
	}
	
	long low = 0, high = [array count] - 1, mid;
	
	while (low < high) {
		mid = low + ((high - low) / 2);
		if (source > ((SourceRecord *)[array objectAtIndex:mid]).source)
			low = mid + 1;
		else
			high = mid;
	}
	
	*index = low;
	if (*index < [array count] && source > ((SourceRecord *)[array objectAtIndex:*index]).source) (*index)++;
	if (*index < [array count] && source == ((SourceRecord *)[array objectAtIndex:*index]).source) return [array objectAtIndex:*index];
	
	return nil;
}

- (id)initWithSource:(void *)source2 {
	if ((self = [super init])) {
		source = source2;
		pid = 0;
	}
	return self;
}

@end
