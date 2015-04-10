//
//  BLIPWebSocketConnection.h
//  BLIPSync
//
//  Created by Jens Alfke on 4/10/15.
//  Copyright (c) 2015 Couchbase. All rights reserved.
//

#import "BLIPConnection.h"
#import "WebSocket.h"

@interface BLIPWebSocketConnection : BLIPConnection

- (instancetype) initWithURLRequest:(NSURLRequest *)request;
- (instancetype) initWithURL:(NSURL *)url;

- (instancetype) initWithWebSocket: (WebSocket*)webSocket;

- (void)closeWithCode:(WebSocketCloseCode)code reason:(NSString *)reason;

/** The underlying WebSocket. */
@property (readonly) WebSocket* webSocket;


@end
