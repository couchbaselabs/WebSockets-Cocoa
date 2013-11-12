//
//  main.m
//  WebSocket
//
//  Created by Jens Alfke on 9/10/13.
//  Copyright (c) 2013 Couchbase. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import <Foundation/Foundation.h>
#import "WebSocketClient.h"
#import "WebSocketListener.h"
#import "Logging.h"


@interface Test : NSObject <WebSocketDelegate>
@end



@implementation Test
{
    WebSocketClient* _webSocket;
    WebSocketListener* _listener;
}

- (instancetype) initWithURL: (NSURL*)url {
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

- (instancetype) initListenerWithPort: (UInt16)port path: (NSString*)path
{
    self = [super init];
    if (self) {
        NSError* error;
        _listener = [[WebSocketListener alloc] initWithPath: path delegate: self];
        if (![_listener acceptOnInterface: nil port: port error: &error]) {
            Warn(@"Couldn't open listener: %@", error);
            return nil;
        }

    }
    return self;
}

- (void) disconnect {
    [_webSocket disconnect];
    [_listener disconnect];
}

- (int) webSocket: (WebSocket*)ws shouldAccept: (NSURLRequest*)request {
    NSLog(@"webSocketShouldAccept: %@ %@", request.URL, request.allHTTPHeaderFields);
    return 101;
}

- (void)webSocketDidOpen:(WebSocket *)ws {
    NSLog(@"webSocketDidOpen: %@", ws);
    if (!_listener)
        [ws sendMessage: @"Hello, World!"];
}

- (void)webSocket:(WebSocket *)ws didReceiveMessage:(NSString *)msg {
    NSLog(@"Received message from %@: %@", ws, msg);
    [ws sendMessage: @"Thanks for your message!"];
    [ws close];
}

- (void)webSocket:(WebSocket *)ws didReceiveBinaryMessage:(NSData *)msg {
    NSLog(@"Received binary message from %@: %@", ws, msg);
    [ws sendBinaryMessage: msg];
    [ws close];
}

- (void)webSocket:(WebSocket *)ws didCloseWithCode: (WebSocketCloseCode)code
           reason: (NSString*)reason
{
    NSLog(@"webSocketDidClose %@: %d, %@", ws, (int)code, reason);
}


@end



int main(int argc, const char * argv[])
{

    @autoreleasepool {
        
        Test *test = [[Test alloc] initWithURL: [NSURL URLWithString: @"ws://localhost:12345/echo"]];
        Test *testListener = [[Test alloc] initListenerWithPort: 2345 path: @"/ws"];

        [[NSRunLoop currentRunLoop] run];

        [test disconnect];
        [testListener disconnect];
    }
    return 0;
}

