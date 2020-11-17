#import <Cocoa/Cocoa.h>
#import "MenuDelegate.h"

#define LOADING_TIME 2.0
#define LOADED_TIME 15 * 60.0

@interface AppDelegate : NSObject <NSApplicationDelegate>

+ (AppDelegate *)sharedDelegate;

@property NSStatusItem *statusItem;
@property NSMenu *menu;
@property MenuDelegate *menuDelegate;

@property NSTimer *animator;
@property NSImage *disabled;
@property NSArray *normal;
@property int frame;
@property BOOL animating;

@property NSMutableArray *apps;
@property NSMutableArray *processes;
@property NSMutableArray *sources;
@property NSMutableArray *ignore;
@property NSDictionary *mapping;

@property NSTimer *starter;
@property BOOL started;

- (BOOL)isBigSur;
- (BOOL)isRightToLeft;

- (void)checkForUpdates;
- (void)disableCheckForUpdates;

- (void)addPathToIgnored:(NSString *)path;
- (void)removePathFromIgnored:(NSString *)path;
- (BOOL)isPathIgnored:(NSString *)path;

@end
