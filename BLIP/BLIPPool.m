//
//  BLIPPool.m
//  WebSocket
//
//  Created by Jens Alfke on 9/16/13.
//  Copyright (c) 2013 Couchbase. All rights reserved.
//

#import "BLIPPool.h"
#import "BLIPWebSocket.h"


@interface BLIPPool () <BLIPWebSocketDelegate>
@end


@implementation BLIPPool
{
    __weak id<BLIPWebSocketDelegate> _delegate;
    dispatch_queue_t _queue;
    NSMutableDictionary* _sockets;
}


@synthesize delegate=_delegate;


- (id)initWithDelegate: (id<BLIPWebSocketDelegate>)delegate
         dispatchQueue: (dispatch_queue_t)queue
{
    self = [super init];
    if (self) {
        _delegate = delegate;
        _queue = queue;
        _sockets = [[NSMutableDictionary alloc] init];
    }
    return self;
}


- (void) dealloc {
    [self closeWithCode: kWebSocketCloseGoingAway reason: nil];
}


// Returns an already-open BLIPWebSocket to use to communicate with a given URL.
- (BLIPWebSocket*) existingSocketToURL: (NSURL*)url error: (NSError**)outError {
    @synchronized(self) {
        return _sockets[url];
    }
}


// Returns an open BLIPWebSocket to use to communicate with a given URL.
- (BLIPWebSocket*) socketToURL: (NSURL*)url error: (NSError**)outError {
    @synchronized(self) {
        BLIPWebSocket* socket = _sockets[url];
        if (!socket) {
            if (!_sockets) {
                // I'm closed already
                if (outError)
                    *outError = nil;
                return nil;
            }
            socket = [[BLIPWebSocket alloc] initWithURL: url];
            [socket setDelegate: self queue: _queue];
            if (![socket connect: outError])
                return nil;
            _sockets[url] = socket;
        }
        return socket;
    }
}


- (void) forgetSocket: (BLIPWebSocket*)webSocket {
    @synchronized(self) {
        [_sockets removeObjectForKey: webSocket.URL];
    }
}


- (void) closeWithCode:(WebSocketCloseCode)code reason:(NSString *)reason {
    NSDictionary* sockets;
    @synchronized(self) {
        sockets = _sockets;
        _sockets = nil; // marks that I'm closed
    }
    for (NSURL* url in sockets) {
        BLIPWebSocket* socket = sockets[url];
        [socket closeWithCode: code reason: reason];
    }
}

- (void) close {
    [self closeWithCode: kWebSocketCloseNormal reason: nil];
}


#pragma mark - DELEGATE API:


// These forward to the delegate, and didClose/didFail also forget the socket:


- (void)blipWebSocketDidOpen:(BLIPWebSocket*)webSocket {
    if ([_delegate respondsToSelector: @selector(blipWebSocketDidOpen:)])
        [_delegate blipWebSocketDidOpen: webSocket];
}

- (void)blipWebSocket: (BLIPWebSocket*)webSocket didFailWithError:(NSError *)error {
    [self forgetSocket: webSocket];
    if ([_delegate respondsToSelector: @selector(blipWebSocket:didFailWithError:)])
        [_delegate blipWebSocket: webSocket didFailWithError: error];
}

- (void)blipWebSocket: (BLIPWebSocket*)webSocket
     didCloseWithCode: (WebSocketCloseCode)code
               reason: (NSString*)reason
{
    [self forgetSocket: webSocket];
    if ([_delegate respondsToSelector: @selector(blipWebSocket:didCloseWithCode:reason:)])
        [_delegate blipWebSocket: webSocket didCloseWithCode: code reason: reason];
}

- (BOOL) blipWebSocket: (BLIPWebSocket*)webSocket receivedRequest: (BLIPRequest*)request {
    return [_delegate respondsToSelector: @selector(blipWebSocket:receivedRequest:)]
        && [_delegate blipWebSocket: webSocket receivedRequest: request];
}

- (void) blipWebSocket: (BLIPWebSocket*)webSocket receivedResponse: (BLIPResponse*)response {
    if ([_delegate respondsToSelector: @selector(blipWebSocket:receivedResponse:)])
        [_delegate blipWebSocket: webSocket receivedResponse: response];
}


@end
