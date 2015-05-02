#import <Cocoa/Cocoa.h>

#define LOADING_TIME 2.0
#define LOADED_TIME 15 * 60.0

@interface AppDelegate : NSObject <NSApplicationDelegate>

@property NSStatusItem *statusItem;
@property NSMenu *menu;

@property NSTimer *animator;
@property NSImage *disabled;
@property NSArray *frames;
@property int frame;
@property bool animating;

@property NSMutableArray *apps;
@property NSMutableArray *processes;
@property NSMutableArray *sources;
@property NSTimer *starter;
@property bool started;

@property NSMutableArray *advancedItems;
@property NSMutableArray *advancedProcesses;

@end
