//
//  WebSocketListener.h
//  WebSocket
//
//  Created by Jens Alfke on 9/16/13.
//  Copyright (c) 2013 Couchbase. All rights reserved.

#import "WebSocket.h"


/** A listener/server for incoming WebSocket connections.
    This is actually a special-purpose HTTP listener that only handles a GET for the given path, with the right WebSocket upgrade headers. */
@interface WebSocketListener : NSObject

- (instancetype) initWithPath: (NSString*)path
                     delegate: (id<WebSocketDelegate>)delegate;

@property (readonly) NSString* path;

/** Starts the listener. */
- (BOOL) acceptOnInterface: (NSString*)interface
                      port: (UInt16)port
                     error: (NSError**)error;

/** Stops the listener from accepting any more connections. */
- (void) disconnect;

@end


/** A WebSocket created from an incoming request by a WebSocketListener.
    You don't instantiate this class directly.*/
@interface WebSocketIncoming : WebSocket

@property WebSocketListener* listener;

@end