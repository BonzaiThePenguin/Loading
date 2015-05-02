#import <Foundation/Foundation.h>

@interface AppRecord : NSObject

@property NSImage *icon;
@property NSString *name;
@property NSString *path;
@property double updated;

+ (AppRecord *)findByPath:(NSString *)path within:(NSArray *)array atIndex:(long *)index;

- (id)initWithPath:(NSString *)path;
@end


@interface ProcessRecord : NSObject

@property int pid;
@property NSString *path;
@property AppRecord *app;
@property double updated;
@property bool running;
@property bool stillRunning;

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
