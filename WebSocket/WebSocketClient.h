//
//  WebSocketClient.h
//  WebSocket
//
//  Created by Jens Alfke on 9/10/13.
//  Copyright (c) 2013 Couchbase, Inc. All rights reserved.

#import "WebSocket.h"


/** Client WebSocket -- opens a connection to a remote host. */
@interface WebSocketClient : WebSocket

/** Designated initializer.
    The WebSocket's timeout will be set from the timeout of the URL request.
    If the scheme of the URL is "https", default TLS settings will be used. */
- (instancetype) initWithURLRequest:(NSURLRequest *)request;

/** Convenience initializer that calls -initWithURLRequest using a GET request to the given URL
    with no special HTTP headers and the default timeout. */
- (instancetype) initWithURL: (NSURL*)url;

/** Once the request has been customized, call this to open the connection. */
- (BOOL) connect: (NSError**)outError;

/** The URL this WebSocket connects to. */
@property (readonly) NSURL* URL;

/** Authentication credential. */
@property NSURLCredential* credential;

/** Determines whether connections should be made over a cellular network. The default value is YES. */
@property (nonatomic) BOOL allowsCellularAccess;

@end
