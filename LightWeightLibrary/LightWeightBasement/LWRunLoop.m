//
//  LWRunLoop.m
//  lwrunloop
//
//  Created by wuyunfeng on 15/10/27.
//  Copyright © 2015年 wuyunfeng open source. All rights reserved.
//

#import "LWRunLoop.h"
#include <sys/unistd.h>
#include <pthread.h>
#import "NSThread+Looper.h"
#import "LWMessageQueue.h"
#import "LWSystemClock.h"
#import "LWTimer.h"
#import "LWNativeRunLoop.h"
static pthread_once_t mTLSKeyOnceToken = PTHREAD_ONCE_INIT;
static pthread_key_t mTLSKey;


NSString * const  LWDefaultRunLoop = @"LWDefaultRunLoop";
NSString * const  LWRunLoopCommonModes = @"LWRunLoopCommonModes";
NSString * const  LWRunLoopModeReserve1 = @"LWRunLoopModeReserve1";
NSString * const  LWRunLoopModeReserve2 = @"LWRunLoopModeReserve2";
NSString * const  LWTrackingRunLoopMode = @"LWTrackingRunLoopMode";

@implementation LWRunLoop
{
    LWMessageQueue *_queue;
    NSString *_currentRunLoopMode;
}

void initTLSKey(void)
{
    pthread_key_create(&mTLSKey, destructor);
}

void destructor(void * data)
{
    LWRunLoop *pSelf = (__bridge LWRunLoop *)data;
    [pSelf destoryFds];
}

- (void)destoryFds
{
    _queue = nil;
}

#pragma mark - Public Method
+ (instancetype)currentLWRunLoop
{
    int result = pthread_once(& mTLSKeyOnceToken, initTLSKey);
    NSAssert(result == 0, @"pthread_once failure");
    LWRunLoop *instance = (__bridge LWRunLoop *)pthread_getspecific(mTLSKey);
    if (instance == nil) {
        instance = [[[self class] alloc] init];
        [[NSThread currentThread] setLooper:instance];
        pthread_setspecific(mTLSKey, (__bridge const void *)(instance));
    }
    return instance;
}

#pragma mark run this loop forever
- (void)run
{
    [self runMode:LWDefaultRunLoop];
}

#pragma mark run this loop at specific mode
- (void)runMode:(NSString *)mode
{
    _currentRunLoopMode = mode;
    _queue.queueRunMode = _currentRunLoopMode;
    while (YES) {
        LWMessage *msg = [_queue next:_queue.queueRunMode];
        [msg performSelectorForTarget];
        [self necessaryInvocationForThisLoop:msg];
    }
}

- (void)changeRunLoopMode:(NSString *)targetMode
{
    _currentRunLoopMode = targetMode;
    _queue.queueRunMode = _currentRunLoopMode;
}

- (void)necessaryInvocationForThisLoop:(LWMessage *)msg
{
    if ([msg.data isKindOfClass:[LWTimer class]]) { // LWTimer: periodical perform selector
        LWTimer *timer = msg.data;
        if (timer.repeat) {
            msg.when = timer.timeInterval; // must
            [self postMessage:msg];
        }
    }
}

#pragma mark -
#pragma mark NSPort Relative API
- (void)addPort:(LWPort *)aPort forMode:(NSString *)mode
{
    if ([aPort isKindOfClass:[LWSocketPort class]]) {
        LWSocketPort *socketTypePort = (LWSocketPort *)aPort;
        int fd = socketTypePort.socket;
        LWSocketPortRoleType roleType = socketTypePort.roleType;
        LWPortContext context = socketTypePort.context;
        if (LWSocketPortRoleTypeLeader == roleType) {
            [_queue.nativeRunLoop addFd:fd type:LWNativeRunLoopFdSocketServerType filter:LWNativeRunLoopEventFilterRead callback:context.LWPortContextCallBack data:&context];
        } else {
            [_queue.nativeRunLoop addFd:fd type:LWNativeRunLoopFdSocketClientType filter:LWNativeRunLoopEventFilterRead callback:context.LWPortContextCallBack data:&context];
        }
    }
}

- (void)removePort:(LWPort *)aPort forMode:(NSString *)mode
{
    
}


#pragma mark - Private
- (instancetype)init
{
    if (self = [super init]) {
        _queue = [LWMessageQueue defaultInstance];
    }
    
    return self;
}

#pragma mark - Post
- (void)postTarget:(id)target withAction:(SEL)aSel withObject:(id)arg afterDelay:(NSInteger)delayMillis
{
    NSInteger when = [LWSystemClock uptimeMillions] + delayMillis;
    LWMessage *message = [[LWMessage alloc] initWithTarget:target aSel:aSel withArgument:arg at:when];
    [_queue enqueueMessage:message when:when];
}

- (void)postMessage:(LWMessage *)msg
{
    NSInteger when = msg.when + [LWSystemClock uptimeMillions];
    [_queue enqueueMessage:msg when:when];
}

- (NSString *)currentMode
{
    if (_currentRunLoopMode) {
        return _currentRunLoopMode;
    }
    return LWDefaultRunLoop;
}

- (void)dealloc
{

}

@end
