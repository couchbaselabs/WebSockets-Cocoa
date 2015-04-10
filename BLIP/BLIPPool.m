//
//  BLIPPool.m
//  WebSocket
//
//  Created by Jens Alfke on 9/16/13.
//  Copyright (c) 2013 Couchbase. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "BLIPPool.h"
#import "BLIPWebSocketConnection.h"


@interface BLIPPool () <BLIPConnectionDelegate>
@end


@implementation BLIPPool
{
    __weak id<BLIPConnectionDelegate> _delegate;
    dispatch_queue_t _queue;
    NSMutableDictionary* _sockets;
}


@synthesize delegate=_delegate;


- (instancetype) initWithDelegate: (id<BLIPConnectionDelegate>)delegate
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


// Returns an already-open BLIPWebSocketConnection to use to communicate with a given URL.
- (BLIPWebSocketConnection*) existingSocketToURL: (NSURL*)url error: (NSError**)outError {
    @synchronized(self) {
        return _sockets[url];
    }
}


// Returns an open BLIPWebSocketConnection to use to communicate with a given URL.
- (BLIPWebSocketConnection*) socketToURL: (NSURL*)url error: (NSError**)outError {
    @synchronized(self) {
        BLIPWebSocketConnection* socket = _sockets[url];
        if (!socket) {
            if (!_sockets) {
                // I'm closed already
                if (outError)
                    *outError = nil;
                return nil;
            }
            socket = [[BLIPWebSocketConnection alloc] initWithURL: url];
            [socket setDelegate: self queue: _queue];
            if (![socket connect: outError])
                return nil;
            _sockets[url] = socket;
        }
        return socket;
    }
}


- (void) forgetSocket: (BLIPConnection*)webSocket {
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
        BLIPWebSocketConnection* socket = sockets[url];
        [socket closeWithCode: code reason: reason];
    }
}

- (void) close {
    [self closeWithCode: kWebSocketCloseNormal reason: nil];
}


#pragma mark - DELEGATE API:


// These forward to the delegate, and didClose/didFail also forget the socket:


- (void)blipConnectionDidOpen:(BLIPConnection*)webSocket {
    id<BLIPConnectionDelegate> delegate = _delegate;
    if ([delegate respondsToSelector: @selector(blipConnectionDidOpen:)])
        [delegate blipConnectionDidOpen: webSocket];
}

- (void)blipConnection: (BLIPConnection*)webSocket didFailWithError:(NSError *)error {
    [self forgetSocket: webSocket];
    id<BLIPConnectionDelegate> delegate = _delegate;
    if ([delegate respondsToSelector: @selector(blipConnection:didFailWithError:)])
        [delegate blipConnection: webSocket didFailWithError: error];
}

- (void)blipConnection: (BLIPConnection*)webSocket
    didCloseWithError: (NSError*)error
{
    [self forgetSocket: webSocket];
    id<BLIPConnectionDelegate> delegate = _delegate;
    if ([delegate respondsToSelector: @selector(blipConnection:didCloseWithError:)])
        [delegate blipConnection: webSocket didCloseWithError: error];
}

- (BOOL) blipConnection: (BLIPConnection*)webSocket receivedRequest: (BLIPRequest*)request {
    id<BLIPConnectionDelegate> delegate = _delegate;
    return [delegate respondsToSelector: @selector(blipConnection:receivedRequest:)]
        && [delegate blipConnection: webSocket receivedRequest: request];
}

- (void) blipConnection: (BLIPConnection*)webSocket receivedResponse: (BLIPResponse*)response {
    id<BLIPConnectionDelegate> delegate = _delegate;
    if ([delegate respondsToSelector: @selector(blipConnection:receivedResponse:)])
        [delegate blipConnection: webSocket receivedResponse: response];
}


@end
