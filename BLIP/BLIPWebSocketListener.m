//
//  BLIPWebSocketListener.m
//  BLIPSync
//
//  Created by Jens Alfke on 4/1/15.
//  Copyright (c) 2015 Couchbase. All rights reserved.
//

#import "BLIPWebSocketListener.h"
#import "WebSocketListener.h"
#import "BLIPWebSocket.h"


@implementation BLIPWebSocketListener
{
    id<BLIPWebSocketDelegate> _delegate;
    dispatch_queue_t _delegateQueue;
    NSMutableSet* _openSockets;
}

@synthesize dispatcher=_dispatcher;


- (instancetype)initWithDelegate: (id<BLIPWebSocketDelegate>)delegate
                           queue: (dispatch_queue_t)queue
{
    self = [super init];
    if (self) {
        _delegate = delegate;
        _delegateQueue = queue ?: dispatch_get_main_queue();
        _openSockets = [NSMutableSet new];
    }
    return self;
}


- (void) webSocketDidOpen:(WebSocket *)ws {
    BLIPWebSocket* b = [[BLIPWebSocket alloc] initWithWebSocket: ws];
    [_openSockets addObject: b];    //FIX: How to remove it since I'm not the delegate when it closes??
    [b setDelegate: _delegate queue: _delegateQueue];
    if (_dispatcher)
        b.dispatcher = _dispatcher;

    if (_delegate) {
        dispatch_async(_delegateQueue, ^{
            [_delegate blipWebSocketDidOpen: b];
        });
    }
}


@end
