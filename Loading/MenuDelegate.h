#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>

@interface MenuDelegate : NSObject

@property BOOL advanced;
@property NSMutableArray *advancedItems;
@property NSMutableArray *advancedProcesses;

@property BOOL toggleAnimation;
@property NSImage *animate;
@property NSImage *inanimate;
@property NSImage *indeterminate;

- (void)updateMenu:(NSMenu *)menu;
- (void)beginTracking:(NSMenu *)menu;

@end
