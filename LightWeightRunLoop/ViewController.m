//
//  ViewController.m
//  LightWeightRunLoop
//
//  Created by wuyunfeng on 15/10/30.
//  Copyright © 2015年 com.wuyunfeng.open. All rights reserved.
//

#import "ViewController.h"
#import "LightWeightRunLoop.h"
#import "UIViewAdditions.h"
#import "TestTarget1.h"
#import "TestTarget2.h"
#import "LWTimer.h"
#import "LWURLConnection.h"
#import "LWURLResponse.h"
@interface ViewController ()<LWURLConnectionDataDelegate>
{
    UIButton *_button1;
    UIButton *_button2;
    UIButton *_button3;
    UIButton *_button4;
    UIButton *_button5;
    
    NSThread *_thread;
    NSThread *_lwRunLoopThread;
    
    TestTarget1 *_target1;
    TestTarget2 *_target2;
    
    NSInteger _count;
    LWTimer *gTimer;
    NSInputStream *_inputStream;
    NSMutableData *_responseData;
}

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setContentView];
    [self testInputStream];

    _thread = [[NSThread alloc] initWithTarget:self selector:@selector(lightWeightRunloopThreadEntryPoint:) object:nil];
    _thread.name = @"Thead 1";
    [_thread start];

    _lwRunLoopThread = [[NSThread alloc] initWithTarget:self selector:@selector(lightWeightRunloopThreadEntryPoint2:) object:nil];
    _lwRunLoopThread.name = @"LWRunLoopThread";
    [_lwRunLoopThread start];
}

- (void)testInputStream
{
    NSString *content = @"name=john&address=beijing&mobile=140005&age=1200";

    NSData *data = [content dataUsingEncoding:NSUTF8StringEncoding];
    _inputStream = [[NSInputStream alloc] initWithData:data];
}

#pragma mark - layout all subviews
- (void)setContentView
{
    [self.view setBackgroundColor:[UIColor grayColor]];
    self.title = @"Realize RunLoop";
    
    _target1 = [[TestTarget1 alloc] init];
    _target2 = [[TestTarget2 alloc] init];
    
    _button1 = [UIButton new];
    _button1.width = self.view.width - 10;
    _button1.height = 40;
    _button1.top = 65;
    _button1.centerX = self.view.centerX;
    _button1.layer.borderColor = [UIColor yellowColor].CGColor;
    _button1.layer.cornerRadius = 4.0f;
    _button1.layer.masksToBounds = YES;
    _button1.backgroundColor = [UIColor whiteColor];
    [_button1 setTitle:@"MainThread -> LWRunLoop-Thread" forState:UIControlStateNormal];
    [_button1 setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [_button1 setTitleColor:[UIColor grayColor] forState:UIControlStateHighlighted];
    [_button1 addTarget:self action:@selector(executeMainThreadSelectorOnRunLoopThread:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_button1];
    
    _button2 = [UIButton new];
    _button2.width = self.view.width - 10;
    _button2.height = 40;
    _button2.top = _button1.bottom + 5;
    _button2.centerX = self.view.centerX;
    _button2.layer.cornerRadius = 4.0f;
    _button2.layer.borderColor = [UIColor yellowColor].CGColor;
    _button2.layer.masksToBounds = YES;
    _button2.backgroundColor = [UIColor whiteColor];
    [_button2 setTitle:@"AsyncThread -> LWRunLoop-Thread" forState:UIControlStateNormal];
    [_button2 setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [_button2 setTitleColor:[UIColor grayColor] forState:UIControlStateHighlighted];
    [_button2 addTarget:self action:@selector(executeThreadSelectorOnRunLoopThread:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_button2];
    
    _button3 = [UIButton new];
    _button3.width = self.view.width - 10;
    _button3.height = 40;
    _button3.top = _button2.bottom + 5;
    _button3.centerX = self.view.centerX;
    _button3.layer.cornerRadius = 4.0f;
    _button3.layer.borderColor = [UIColor yellowColor].CGColor;
    _button3.layer.masksToBounds = YES;
    _button3.backgroundColor = [UIColor whiteColor];
    [_button3 setTitle:@"MixedThread -> LWRunLoop-Thread" forState:UIControlStateNormal];
    [_button3 setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [_button3 setTitleColor:[UIColor grayColor] forState:UIControlStateHighlighted];
    [_button3 addTarget:self action:@selector(executeMixedSelectorOnRunLoopThread:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_button3];
    
    _button4 = [UIButton new];
    _button4.width = self.view.width - 10;
    _button4.height = 40;
    _button4.top = _button3.bottom + 5;
    _button4.centerX = self.view.centerX;
    _button4.layer.cornerRadius = 4.0f;
    _button4.layer.borderColor = [UIColor yellowColor].CGColor;
    _button4.layer.masksToBounds = YES;
    _button4.backgroundColor = [UIColor whiteColor];
    [_button4 setTitle:@"LWTimer -> LWRunLoop-Thread" forState:UIControlStateNormal];
    [_button4 setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [_button4 setTitleColor:[UIColor grayColor] forState:UIControlStateHighlighted];
    [_button4 addTarget:self action:@selector(executeTimerOnRunLoopThread:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_button4];
    
    _button5 = [UIButton new];
    _button5.width = self.view.width - 10;
    _button5.height = 40;
    _button5.top = _button4.bottom + 5;
    _button5.centerX = self.view.centerX;
    _button5.layer.cornerRadius = 4.0f;
    _button5.layer.borderColor = [UIColor yellowColor].CGColor;
    _button5.layer.masksToBounds = YES;
    _button5.backgroundColor = [UIColor whiteColor];
    [_button5 setTitle:@"LWURLConnection" forState:UIControlStateNormal];
    [_button5 setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [_button5 setTitleColor:[UIColor grayColor] forState:UIControlStateHighlighted];
    [_button5 addTarget:self action:@selector(executeURLConnection:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_button5];
}

#pragma mark - test perform selector on LWRunLoop Thread without delay
- (void)executeMainThreadSelectorOnRunLoopThread:(UIButton *)button
{
    [self postSelector:@selector(execute) onThread:_lwRunLoopThread withObject:nil afterDelay:1000];
    [_target1 postSelector:@selector(performTest) onThread:_lwRunLoopThread withObject:nil];
    [_target2 postSelector:@selector(performTest) onThread:_lwRunLoopThread withObject:nil afterDelay:2000];
}

#pragma mark - test perform selector on LWRunLoop Thread without delay
- (void)executeThreadSelectorOnRunLoopThread:(UIButton *)button
{
    [self postSelector:@selector(execute) onThread:_lwRunLoopThread withObject:nil afterDelay:1000];
    [_target1 postSelector:@selector(performTest) onThread:_lwRunLoopThread withObject:nil];
    [_target2 postSelector:@selector(performTest) onThread:_lwRunLoopThread withObject:nil afterDelay:2000];
}

#pragma mark - test perform selector on LWRunLoop Thread without delay
- (void)executeMixedSelectorOnRunLoopThread:(UIButton *)button
{
    [self postSelector:@selector(execute) onThread:_lwRunLoopThread withObject:nil afterDelay:1000];
    [_target1 postSelector:@selector(performTest) onThread:_lwRunLoopThread withObject:nil];
    [_target2 postSelector:@selector(performTest) onThread:_lwRunLoopThread withObject:nil afterDelay:2000];
    [NSThread detachNewThreadSelector:@selector(asyncExecuteMethodOnThread:) toTarget:self withObject:nil];
    [NSThread detachNewThreadSelector:@selector(asyncExecuteMethodOnThread:) toTarget:self withObject:nil];
}

#pragma mark - post method from new-thread to _thread
- (void)asyncExecuteMethodOnThread:(id)args
{
//    sleep(2);
    [_target1 postSelector:@selector(performTest) onThread:_lwRunLoopThread withObject:nil];
//    sleep(1);
    [_target2 postSelector:@selector(performTest) onThread:_lwRunLoopThread withObject:nil afterDelay:3000];
//    sleep(2);
    [self postSelector:@selector(execute) onThread:_lwRunLoopThread withObject:nil afterDelay:1000];
}

#pragma mark - Thread EntryPoint
- (void)lightWeightRunloopThreadEntryPoint:(id)data
{
    @autoreleasepool {
        [[LWRunLoop currentLWRunLoop] run];
    }
}


- (void)lightWeightRunloopThreadEntryPoint2:(id)data
{
    @autoreleasepool {
        LWRunLoop *looper = [LWRunLoop currentLWRunLoop];
        [looper run];
    }
}
#pragma mark - post method from main-thread to _thread
- (void)execute
{
    NSLog(@"* [ Object: %@ performSelector: ( %@ ) on Thread : %@ ] *", [self class], NSStringFromSelector(_cmd), [NSThread currentThread].name);
}

#pragma mark - perform LWTimer Test on LWRunLoop Thread
- (void)executeTimerOnRunLoopThread:(UIButton *)button
{
    [self postSelector:@selector(genernateLWTimer) onThread:_lwRunLoopThread withObject:nil];
}

- (void)genernateLWTimer
{
    _count = 0;
    LWTimer *timer = [LWTimer timerWithTimeInterval:1000 target:self selector:@selector(bindLWTimerWithSelector:) userInfo:nil repeats:YES];
    [timer fire];
//    gTimer = [LWTimer scheduledLWTimerWithTimeInterval:2000 target:self selector:@selector(bindLWTimerWithSelector:) userInfo:nil repeats:YES];
}

- (void)bindLWTimerWithSelector:(LWTimer *)timer
{
    _count++;
    NSLog(@"* [ LWTimer : %@ performSelector: ( %@ ) on Thread : %@ ] *", [self class], NSStringFromSelector(_cmd), [NSThread currentThread].name);
    if (_count >= 4) {
        [timer invalidate];
    }
}

#pragma mark - perform URLConnection Test on LWRunLoop Thread
- (void)executeURLConnection:(UIButton *)button
{
    [self postSelector:@selector(performURLConnectionOnRunLoopThread) onThread:_lwRunLoopThread withObject:nil];
}

- (void)performURLConnectionOnRunLoopThread
{
    NSLog(@"[%@ %@]", [self class], NSStringFromSelector(_cmd));
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"http://192.168.1.8:8888/post.php"]];
    request.HTTPMethod = @"POST";
    NSString *content = @"name=john&address=beijing&mobile=140005";
    request.HTTPBody = [content dataUsingEncoding:NSUTF8StringEncoding];
    LWURLConnection *conn = [[LWURLConnection alloc] initWithRequest:request delegate:self startImmediately:NO];
    [conn scheduleInRunLoop:_lwRunLoopThread.looper];
    [conn start];
}

#pragma mark - LWURLConnectionDataDelegate
- (void)lw_connection:(LWURLConnection * _Nonnull)connection didReceiveData:(NSData * _Nullable)data
{
    if (!_responseData) {
        _responseData = [[NSMutableData alloc] init];
    }
    NSLog(@"**Thread : %@ --[%@ %@]**",[NSThread currentThread].name, [self class], NSStringFromSelector(_cmd));
    [_responseData appendData:data];
}
- (void)lw_connection:(LWURLConnection * _Nonnull)connection didFailWithError:(NSError * _Nullable)error
{
    NSLog(@"**Thread : %@ --[%@ %@]**",[NSThread currentThread].name, [self class], NSStringFromSelector(_cmd));
}

- (void)lw_connectionDidFinishLoading:(LWURLConnection * _Nonnull)connection
{
    NSLog(@"**Thread : %@ --[%@ %@]**",[NSThread currentThread].name, [self class], NSStringFromSelector(_cmd));
//    NSString *response = [[NSString alloc] initWithData:_responseData encoding:NSUTF8StringEncoding];
    LWURLResponse *response = [[LWURLResponse alloc] initWithData:_responseData];
    NSLog(@"statusCode = %lu",(long)[response statusCode]);
    NSLog(@"statusMsg = %@", [response statusMsg]);
    NSLog(@"responseBody = %@", [response responseBody]);
    NSLog(@"responseHeader = %@", [response allHeaderFields]);
}



#pragma mark - MemoryWaring
- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
