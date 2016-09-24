//
//  LWNativeLoop.m
//  LightWeightRunLoop
//
//  Created by wuyunfeng on 15/11/28.
//  Copyright © 2015年 com.wuyunfeng.open. All rights reserved.
//

#import "LWNativeRunLoop.h"
// unix standard
#include <sys/unistd.h>

//SYNOPSIS For Kevent
#include <sys/event.h>
#include <sys/types.h>
#include <sys/time.h>

#include <fcntl.h>
#include <pthread.h>
#include <sys/errno.h>
#include <sys/socket.h>
#include <netinet/in.h>
#define MAX_EVENT_COUNT 16
#import "LWPortClientInfo.h"

typedef struct Request {
    int fd;
    LWNativeRunLoopFdType type;
    LWNativeRunLoopCallBack callback;
    void *info;
}Request;

@implementation LWNativeRunLoop
{
    int _mReadPipeFd;
    int _mWritePipeFd;
    int _kq;
    NSMutableArray *_fds;
    NSMutableDictionary *_requests;
    NSMutableDictionary *_portClients;
    int _leader;
}

- (instancetype)init
{
    if (self = [super init]) {
        [self prepareRunLoopInit];
    }
    return self;
}

#pragma mark - Run loop
- (void)nativeRunLoopFor:(NSInteger)timeoutMillis
{
    struct kevent events[MAX_EVENT_COUNT];
    struct timespec *waitTime = NULL;
    if (timeoutMillis == -1) {
        waitTime = NULL;
    } else {
        waitTime = (struct timespec *)malloc(sizeof(struct timespec));
        waitTime->tv_sec = timeoutMillis / 1000;
        waitTime->tv_nsec = timeoutMillis % 1000 * 1000 * 1000;
    }
    int ret = kevent(_kq, NULL, 0, events, MAX_EVENT_COUNT, waitTime);
    NSAssert(ret != -1, @"Failure in kevent().  errno=%d", errno);
    free(waitTime);
    waitTime = NULL; // avoid wild pointer
    for (int i = 0; i < ret; i++) {
        int fd = (int)events[i].ident;
        int event = events[i].filter;
        if (fd == _mReadPipeFd) { // for pipe read fd
            if (event & EVFILT_READ) {
                //must read mReadWakeFd, or result in readwake always wake
                [self nativePollRunLoop];
            } else {
                continue;
            }
        } else if (_leader == fd){//for LWPort leader fd
            if (event & EVFILT_READ) {
                struct sockaddr_in clientAddr;
                socklen_t len = sizeof(struct sockaddr);
                int client = accept(fd, (struct sockaddr *)&clientAddr, &len);
                LWPortClientInfo *portInfo = [LWPortClientInfo new];
                portInfo.port = clientAddr.sin_port;
                portInfo.fd = client;
                [_portClients setValue:portInfo forKey:[NSString stringWithFormat:@"%d", clientAddr.sin_port]];
                [self makeFdNonBlocking:client];
                [self kevent:fd filter:EVFILT_READ action:EV_ADD];
            }
        } else { // read for LWPort follower fd, then notify leader
            if (event & EVFILT_READ) {
                int length = 0;
                ssize_t nRead;
                do {
                    nRead = read(fd, &length, 4);
                } while (nRead == -1 && EINTR == errno);
                if (nRead == -1) {
                    //The file was marked for non-blocking I/O, and no data were ready to be read.
                    if (EAGAIN == errno) {
                        continue;
                    }
                }
                //buffer `follower` LWPort send `buffer` to `leader` LWPort
                char *buffer = malloc(length);
                do {
                    nRead = read(fd, buffer, length);
                } while (nRead == -1 && EINTR == errno);
                NSValue *data = [_requests objectForKey:@(fd)];
                Request request;
                [data getValue:&request];
                //notify leader
                request.callback(fd, request.info, buffer, length);
                //remember release malloc memory
                free(buffer);
                struct sockaddr_in sockaddr;
                socklen_t len;
                int ret = getpeername(fd, (struct sockaddr *)&sockaddr, &len);
                if (ret < 0) {
                    continue;
                }
                LWPortClientInfo *info = [_portClients valueForKey:[NSString stringWithFormat:@"%d", sockaddr.sin_port]];
                if (info.cacheSend && info.cacheSend.length > 0) {
                    //write cached on next event
                    [self kevent:fd filter:EVFILT_WRITE action:EV_ADD];
                }
            } else if (event & EVFILT_WRITE) {
                struct sockaddr_in sockaddr;
                socklen_t len;
                int ret = getpeername(fd, (struct sockaddr *)&sockaddr, &len);
                if (ret < 0) {
                    continue;
                }
                LWPortClientInfo *info = [_portClients valueForKey:[NSString stringWithFormat:@"%d", sockaddr.sin_port]];
                if (info.cacheSend && info.cacheSend.length > 0) {
                    ssize_t nWrite;
                    do {
                        nWrite = write(fd, [info.cacheSend bytes], info.cacheSend.length);
                    } while (nWrite == -1 && errno == EINTR);
                    
                    if (nWrite != 1) {
                        if (errno != EAGAIN) {
                            continue;
                        }
                    }
                    //clean the sending cache
                    info.cacheSend = nil;
                } else {
                    continue;
                }
            }
        }
    }
}

#pragma mark - Process two fds generated by pipe()
- (void)nativeWakeRunLoop
{
    ssize_t nWrite;
    do {
        nWrite = write(_mWritePipeFd, "w", 1);
    } while (nWrite == -1 && errno == EINTR);
    
    if (nWrite != 1) {
        if (errno != EAGAIN) {
            NSLog(@"Could not write wake signal, errno=%d", errno);
        }
    }
}

- (void)nativePollRunLoop
{
    char buffer[16];
    ssize_t nRead;
    do {
        nRead = read(_mReadPipeFd, buffer, sizeof(buffer));
    } while ((nRead == -1 && errno == EINTR) || nRead == sizeof(buffer));
}

#pragma mark -
- (void)addFd:(int)fd type:(LWNativeRunLoopFdType)type filter:(LWNativeRunLoopEventFilter)filter callback:(LWNativeRunLoopCallBack)callback data:(void *)info
{
    [self makeFdNonBlocking:fd];
    
    Request request;
    request.fd = fd;
    request.type = type;
    request.callback = callback;
    request.info = info;
    _requests[@(fd)]= [NSValue value:&request withObjCType:@encode(Request)];
    //temporary return
    if ([_requests objectForKey:@(fd)]) {
        return;
    }
    if (LWNativeRunLoopEventFilterRead == filter) {
        _leader = fd;
        [self kevent:fd filter:EVFILT_READ action:EV_ADD];
    } else if (LWNativeRunLoopEventFilterWrite == filter) {
        [self kevent:fd filter:EVFILT_WRITE action:EV_ADD];
    }
}

- (int)kevent:(int)fd filter:(int)filter action:(int)action
{
    struct kevent changes[1];
    EV_SET(changes, fd, EVFILT_WRITE, EV_ADD, 0, 0, NULL);
    int ret = kevent(_kq, changes, 1, NULL, 0, NULL);
    return ret;
}

- (BOOL)makeFdNonBlocking:(int)fd
{
    int flags;
    if ((flags = fcntl(fd, F_GETFL, NULL)) < 0) {
        return NO;
    }
    if (fcntl(fd, F_SETFL, flags | O_NONBLOCK) == -1) {
        return NO;
    }
    return YES;
}

#pragma mark - initialize the configuration for Event-Drive-Mode
- (void)prepareRunLoopInit
{
    int wakeFds[2];
    
    int result = pipe(wakeFds);
    NSAssert(result == 0, @"Failure in pipe().  errno=%d", errno);
    
    _mReadPipeFd = wakeFds[0];
    _mWritePipeFd = wakeFds[1];
    int rflags;
    if ((rflags = fcntl(_mReadPipeFd, F_GETFL, 0)) < 0) {
        NSLog(@"Failure in fcntl F_GETFL");
    };
    rflags |= O_NONBLOCK;
    result = fcntl(_mReadPipeFd, F_SETFL, rflags);
    NSAssert(result == 0, @"Failure in fcntl() for read wake fd.  errno=%d", errno);
    
    int wflags;
    if ((wflags = fcntl(_mWritePipeFd, F_GETFL, 0)) < 0) {
        NSLog(@"Failure in fcntl F_GETFL");
    };
    wflags |= O_NONBLOCK;
    result = fcntl(_mWritePipeFd, F_SETFL, wflags);
    NSAssert(result == 0, @"Failure in fcntl() for write wake fd.  errno=%d", errno);
    
    _kq = kqueue();
    NSAssert(_kq != -1, @"Failure in kqueue().  errno=%d", errno);
    
    struct kevent changes[1];
    EV_SET(changes, _mReadPipeFd, EVFILT_READ, EV_ADD, 0, 0, NULL);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-variable"
    int ret = kevent(_kq, changes, 1, NULL, 0, NULL);
    NSAssert(ret != -1, @"Failure in kevent().  errno=%d", errno);
#pragma clang diagnostic pop

    _fds = [[NSMutableArray alloc] init];
    _requests = [[NSMutableDictionary alloc] init];
    _portClients = [[NSMutableDictionary alloc] init];
}

#pragma mark - dispose the kqueue and pipe fds
- (void)nativeDestoryKernelFds
{
    close(_kq);
    close(_mReadPipeFd);
    close(_mWritePipeFd);
}

- (void)dealloc
{
    [self nativeDestoryKernelFds];
}

@end
