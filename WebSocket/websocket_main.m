//
//  main.m
//  WebSocket
//
//  Created by Jens Alfke on 9/10/13.
//  Copyright (c) 2013 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "WebSocketClient.h"


@interface Test : NSObject <WebSocketDelegate>

@end



@implementation Test
{
    WebSocketClient* _webSocket;
}

- (id) initWithURL: (NSURL*)url {
    self = [super init];
    if (self) {
        _webSocket = [[WebSocketClient alloc] initWithURL: url];
        _webSocket.delegate = self;
        NSError* error;
        if (![_webSocket connect: &error]) {
            NSLog(@"Failed to connect: %@", error);
            exit(1);
        }
        NSLog(@"Connecting...");
    }
    return self;
}

- (void) disconnect {
    [_webSocket disconnect];
}

- (void)webSocketDidOpen:(WebSocket *)ws {
    NSLog(@"webSocketDidOpen!");
    [_webSocket sendMessage: @"Hello, World!"];
}

- (void)webSocket:(WebSocket *)ws didReceiveMessage:(NSString *)msg {
    NSLog(@"Received message: %@", msg);
    [_webSocket close];
}

- (void)webSocket:(WebSocket *)ws didReceiveBinaryMessage:(NSData *)msg {
    NSLog(@"Received message: %@", msg);
    [_webSocket close];
}

- (void)webSocket:(WebSocket *)ws didCloseWithCode: (WebSocketCloseCode)code reason: (NSString*)reason {
    NSLog(@"webSocketDidClose: %d, %@", (int)code, reason);
}


@end



int main(int argc, const char * argv[])
{

    @autoreleasepool {
        
        Test *test = [[Test alloc] initWithURL: [NSURL URLWithString: @"ws://localhost:12345/echo"]];

        [[NSRunLoop currentRunLoop] run];

        [test disconnect];
    }
    return 0;
}

