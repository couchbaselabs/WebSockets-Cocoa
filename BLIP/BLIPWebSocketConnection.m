//
//  BLIPWebSocketConnection.m
//  BLIPSync
//
//  Created by Jens Alfke on 4/10/15.
//  Copyright (c) 2015 Couchbase. All rights reserved.
//

#import "BLIPWebSocketConnection.h"
#import "BLIPConnection+Transport.h"
#import "WebSocketClient.h"
#import "Test.h"


@interface BLIPWebSocketConnection () <WebSocketDelegate>
@end


@implementation BLIPWebSocketConnection

@synthesize webSocket=_webSocket;

// Public API; Designated initializer
- (instancetype) initWithWebSocket: (WebSocket*)webSocket {
    Assert(webSocket);
    self = [super initWithTransportQueue: webSocket.websocketQueue
                                  isOpen: webSocket.state == kWebSocketOpen];
    if (self) {
        _webSocket = webSocket;
        _webSocket.delegate = self;
    }
    return self;
}

// Public API
- (instancetype) initWithURLRequest:(NSURLRequest *)request {
    return [self initWithWebSocket: [[WebSocketClient alloc] initWithURLRequest: request]];
}

// Public API
- (instancetype) initWithURL:(NSURL *)url {
    return [self initWithWebSocket: [[WebSocketClient alloc] initWithURL: url]];
}


- (NSURL*) URL {
    return ((WebSocketClient*)_webSocket).URL;
}

// Public API
- (BOOL) connect: (NSError**)outError {
    NSError* error;
    if (![(WebSocketClient*)_webSocket connect: &error]) {
        self.error = error;
        if (outError)
            *outError = error;
        return NO;
    }
    return YES;
}

// Public API
- (void) close {
    NSError* error = self.error;
    if (error == nil) {
        [_webSocket close];
    } else if ([error.domain isEqualToString: WebSocketErrorDomain]) {
            [_webSocket closeWithCode: error.code reason: error.localizedFailureReason];
    } else {
        [_webSocket closeWithCode: kWebSocketClosePolicyError reason: error.localizedDescription];
    }
}

// Public API
- (void) closeWithCode: (WebSocketCloseCode)code reason:(NSString *)reason {
    [_webSocket closeWithCode: code reason: reason];
}

// WebSocket delegate method
- (void) webSocketDidOpen: (WebSocket *)webSocket {
    [self transportDidOpen];
}

// WebSocket delegate method
- (void) webSocket: (WebSocket *)webSocket didFailWithError: (NSError *)error {
    [self transportDidCloseWithError: error];
}

// WebSocket delegate method
- (void) webSocket: (WebSocket *)webSocket didCloseWithError: (NSError*)error
{
    [self transportDidCloseWithError: error];
}

// WebSocket delegate method
- (void) webSocketIsHungry: (WebSocket *)ws {
    [self feedTransport];
}

- (BOOL) transportCanSend {
    return _webSocket.state == kWebSocketOpen;
}

- (void) sendFrame:(NSData *)frame {
    [_webSocket sendBinaryMessage: frame];
}

// WebSocket delegate method
- (BOOL)webSocket:(WebSocket *)webSocket didReceiveBinaryMessage:(NSData*)message {
    [self didReceiveFrame: message];
    return YES;
}

@end
