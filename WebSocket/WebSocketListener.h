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

/** Initializes a WebSocketListener.
    @param path  The URI path to accept requests on (other paths will get a 404 response.)
    @param delegate  The object that will become the delegate of WebSockets accepted by this listener. */
- (instancetype) initWithPath: (NSString*)path
                     delegate: (id<WebSocketDelegate>)delegate;

/** The URI path the listener is accepting requests on. */
@property (readonly) NSString* path;

/** Starts the listener.
    @param interface  The name of the network interface, or nil to listen on all interfaces
        (See the GCDAsyncSocket documentation for more details.)
    @param port  The TCP port to listen on.
    @param error  On return, will be filled in with an error if the method returned NO.
    @return  YES on success, NO on failure. */
- (BOOL) acceptOnInterface: (NSString*)interface
                      port: (UInt16)port
                     error: (NSError**)error;

/** Stops the listener from accepting any more connections. */
- (void) disconnect;

@end


/** A WebSocket created from an incoming request by a WebSocketListener.
    You don't instantiate this class directly. */
@interface WebSocketIncoming : WebSocket

@property WebSocketListener* listener;

@end