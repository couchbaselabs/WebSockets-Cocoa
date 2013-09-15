//
//  blip_main.m
//  WebSocket
//
//  Created by Jens Alfke on 9/10/13.
//  Copyright (c) 2013 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "BLIP.h"
#import "WebSocketClient.h"

#import "CollectionUtils.h"
#import "Logging.h"
#import "Test.h"


#define kSendInterval 1.0
#define kBodySize 50


@interface BLIPTest : NSObject <BLIPWebSocketDelegate>

@end



@implementation BLIPTest
{
    BLIPWebSocket* _webSocket;
    UInt64 _count;
    CFAbsoluteTime _startTime;
}

- (id) initWithURL: (NSURL*)url {
    self = [super init];
    if (self) {
        _webSocket = [[BLIPWebSocket alloc] initWithURL: url];
        [_webSocket setDelegate: self queue: NULL]; // use current queue
        if (![_webSocket open]) {
            Warn(@"Failed to connect: %@", _webSocket.error);
            exit(1);
        }
        Log(@"Connecting...");
    }
    return self;
}

- (void) disconnect {
    [_webSocket close];
}

- (void) send {
    if (_startTime == 0)
        _startTime = CFAbsoluteTimeGetCurrent();
    Log(@"SEND");

    NSMutableData* body = [NSMutableData dataWithLength: kBodySize];
    char* bytes = body.mutableBytes;
    for (NSUInteger i = 0; i < kBodySize; ++i)
        bytes[i] = 'A' + ((i + _count) % 26);

    BLIPRequest* req = [BLIPRequest requestWithBody: body];
    req.profile = @"BLIPTest/EchoData";
    [_webSocket sendRequest: req];
}

- (void)blipWebSocketDidOpen:(BLIPWebSocket*)webSocket {
    Log(@"webSocketDidOpen!");
    [self send];
}

- (BOOL) blipWebSocket: (BLIPWebSocket*)webSocket receivedRequest: (BLIPRequest*)request {
    Log(@"Received request: %@", request);
    return NO;
}

- (void) blipWebSocket: (BLIPWebSocket*)webSocket receivedResponse: (BLIPResponse*)response {
    NSString* body = [response.body my_UTF8ToString];
    ++_count;
    Log(@"Received response: %@ -- \"%@\"", response, body);
    if (_count % 1000 == 0) {
        NSTimeInterval elapsed = CFAbsoluteTimeGetCurrent() - _startTime;
        NSLog(@"Send %llu round-trips in %.3f sec -- %.0f/sec (%.0fMB/sec)",
              _count, elapsed, _count/elapsed, _count/elapsed*kBodySize*2/1e6);
    }

    if (kSendInterval > 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self performSelector: @selector(send) withObject: nil afterDelay: kSendInterval];
        });
    } else {
        [self send];
    }
}

- (void)blipWebSocket: (BLIPWebSocket*)webSocket didFailWithError:(NSError *)error {
    Warn(@"webSocketDidFail: %@", error);
}

- (void)blipWebSocket: (BLIPWebSocket*)webSocket
     didCloseWithCode:(WebSocketCloseCode)code
               reason:(NSString *)reason
{
    Log(@"Closed with code %d: \"%@\"", (int)code, reason);
}

@end



int main(int argc, const char * argv[])
{
    RunTestCases(argc, argv);

    @autoreleasepool {

        BLIPTest *test = [[BLIPTest alloc] initWithURL: [NSURL URLWithString: @"ws://localhost:12345/blip"]];

        [[NSRunLoop currentRunLoop] run];

        [test disconnect];
    }
    return 0;
}

