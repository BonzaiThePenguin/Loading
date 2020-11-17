#import <Foundation/Foundation.h>

@interface AppRecord : NSObject

@property NSImage *icon;
@property NSString *name;
@property NSString *path;
@property double updated;
@property BOOL animate;

+ (AppRecord *)findByPath:(NSString *)path within:(NSArray *)array atIndex:(long *)index;

- (id)initWithPath:(NSString *)path;
@end


@interface ProcessRecord : NSObject

@property int pid;
@property NSString *path;
@property AppRecord *app;
@property CFAbsoluteTime updated;
@property CFAbsoluteTime refreshed;
@property BOOL animate;
@property BOOL running;

+ (ProcessRecord *)findByPID:(int)pid within:(NSArray *)array atIndex:(long *)index;

- (id)initWithPID:(pid_t)pid;
@end


@interface SourceRecord : NSObject

@property void *source;
@property pid_t pid;
@property long up;
@property long down;
@property SourceRecord *next;

+ (SourceRecord *)findBySource:(void *)source within:(NSArray *)array atIndex:(long *)index;

- (id)initWithSource:(void *)source;
@end
