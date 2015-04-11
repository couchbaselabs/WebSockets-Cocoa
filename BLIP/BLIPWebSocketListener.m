//
//  BLIPWebSocketListener.m
//  BLIPSync
//
//  Created by Jens Alfke on 4/1/15.
//  Copyright (c) 2015 Couchbase. All rights reserved.
//

#import "BLIPWebSocketListener.h"
#import "BLIPWebSocketConnection.h"
#import "WebSocketListener.h"
#import "Logging.h"


@interface BLIPWebSocketListener () <WebSocketDelegate>
@end


@implementation BLIPWebSocketListener
{
    id<BLIPConnectionDelegate> _blipDelegate;
    dispatch_queue_t _delegateQueue;
    NSMutableSet* _openSockets;
}

- (instancetype) initWithPath: (NSString*)path
                     delegate: (id<BLIPConnectionDelegate>)delegate
{
    return [self initWithPath: path delegate: delegate queue: nil];
}


- (instancetype) initWithPath: (NSString*)path
                     delegate: (id<BLIPConnectionDelegate>)delegate
                        queue: (dispatch_queue_t)queue;
{
    self = [super initWithPath: path delegate: self];
    if (self) {
        _blipDelegate = delegate;
        _delegateQueue = queue ?: dispatch_get_main_queue();
        _openSockets = [NSMutableSet new];
    }
    return self;
}


- (void) webSocketDidOpen:(WebSocket *)ws {
    BLIPWebSocketConnection* b = [[BLIPWebSocketConnection alloc] initWithWebSocket: ws];
    [_openSockets addObject: b];    //FIX: How to remove it since I'm not the delegate when it closes??
    LogTo(BLIP, @"Listener got connection: %@", b);
    dispatch_async(_delegateQueue, ^{
        [self blipConnectionDidOpen: b];
    });
}


- (void)blipConnectionDidOpen:(BLIPConnection*)b {
    [b setDelegate: _blipDelegate queue: _delegateQueue];
}


@end
