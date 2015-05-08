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
		
		if ([path2 isEqualToString:@"System"]) {
			self.name = @"System";
			NSImage *icon2 = [[NSWorkspace sharedWorkspace] iconForFileType:NSFileTypeForHFSTypeCode(kFinderIcon)];
			[icon2 setSize:NSMakeSize(16, 16)];
			self.icon = icon2;
			
		} else {
			self.name = @"Unknown";
			
			NSBundle *bundle = [NSBundle bundleWithPath:path];
			if (bundle != nil) {
				NSString *app_name = [bundle objectForInfoDictionaryKey:@"CFBundleDisplayName"];
				if (app_name == nil) app_name = [bundle objectForInfoDictionaryKey:@"CFBundleName"];
				if (app_name == nil) {
					// use the file name, minus the .app extension
					app_name = [[path lastPathComponent] stringByDeletingPathExtension];
				}
				if (app_name != nil) self.name = app_name;
				
				NSString *icon_name, *icon_path; NSImage *icon2;
				if ((icon_name = [bundle objectForInfoDictionaryKey:@"CFBundleIconFile"]) &&
					(icon_path = [[[bundle resourcePath] stringByAppendingString:@"/"] stringByAppendingString:icon_name])) {
					if ([[icon_path pathExtension] length] == 0) icon_path = [icon_path stringByAppendingPathExtension:@"icns"];
					if ((icon2 = [[NSImage alloc] initByReferencingFile:icon_path])) {
						[icon2 setSize:NSMakeSize(16, 16)];
						self.icon = icon2;
					}
				}
			}
			
			if (self.icon == nil) {
				// see if we can magically determine the correct icon for it
				NSString *icon_path = nil; NSImage *icon2;
				
				// so far only Notification Center is supported
				if ([self.path hasPrefix:@"/System/Library/CoreServices/NotificationCenter.app"])
					icon_path = @"/System/Library/PreferencePanes/Notifications.prefPane/Contents/Resources/Notifications.icns";
				
				if (icon_path != nil && (icon2 = [[NSImage alloc] initByReferencingFile:icon_path])) {
					[icon2 setSize:NSMakeSize(16, 16)];
					self.icon = icon2;
				}
			}
			
			if (self.icon == nil) {
				// give it a "blank app" icon
				NSImage *icon2 = [[NSWorkspace sharedWorkspace] iconForFileType:NSFileTypeForHFSTypeCode(kGenericApplicationIcon)];
				[icon2 setSize:NSMakeSize(16, 16)];
				self.icon = icon2;
			}
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
@synthesize running;
@synthesize stillRunning;
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
		animate = YES;
		running = YES;
		stillRunning = YES;
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
