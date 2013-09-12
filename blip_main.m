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


@interface BLIPTest : NSObject <BLIPWebSocketDelegate>

@end



@implementation BLIPTest
{
    BLIPWebSocket* _webSocket;
}

- (id) initWithURL: (NSURL*)url {
    self = [super init];
    if (self) {
        _webSocket = [[BLIPWebSocket alloc] initWithURL: url];
        _webSocket.delegate = self;
        [(WebSocketClient*)_webSocket.webSocket setValue: @"http://localhost" //TEMP
                                    forClientHeaderField: @"Origin"];
        if (![_webSocket open]) {
            NSLog(@"Failed to connect: %@", _webSocket.error);
            exit(1);
        }
        NSLog(@"Connecting...");
    }
    return self;
}

- (void) disconnect {
    [_webSocket close];
}

- (void)blipWebSocketDidOpen:(BLIPWebSocket*)webSocket {
    NSLog(@"webSocketDidOpen!");
    BLIPRequest* req = [BLIPRequest requestWithBodyString: @"Hello, World!"];
    req.profile = @"BLIPTest/EchoData";
    [_webSocket sendRequest: req];
}

- (BOOL) blipWebSocket: (BLIPWebSocket*)webSocket receivedRequest: (BLIPRequest*)request {
    NSLog(@"Received request: %@", request);
    return NO;
}

- (void) blipWebSocket: (BLIPWebSocket*)webSocket receivedResponse: (BLIPResponse*)response {
    NSString* body = [response.body my_UTF8ToString];
    NSLog(@"Received response: %@ -- \"%@\"", response, body);
}

- (void)blipWebSocket: (BLIPWebSocket*)webSocket didFailWithError:(NSError *)error {
    NSLog(@"webSocketDidFail: %@", error);
}

- (void)blipWebSocket: (BLIPWebSocket*)webSocket
     didCloseWithCode:(WebSocketCloseCode)code
               reason:(NSString *)reason
{
    NSLog(@"Closed with code %d: \"%@\"", (int)code, reason);
}

@end



int main(int argc, const char * argv[])
{

    @autoreleasepool {

        BLIPTest *test = [[BLIPTest alloc] initWithURL: [NSURL URLWithString: @"ws://localhost:12345/blip"]];

        [[NSRunLoop currentRunLoop] run];

        [test disconnect];
    }
    return 0;
}

