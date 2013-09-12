//
//  WebSocket_Internal.h
//  WebSocket
//
//  Created by Jens Alfke on 9/10/13.
//  Copyright (c) 2013 Couchbase. All rights reserved.
//

#import "WebSocket.h"
#import "GCDAsyncSocket.h"


#define TIMEOUT_NONE          -1
#define TIMEOUT_REQUEST_BODY  10

#define HTTPLogTrace() NSLog(@"TRACE: %s", __func__ )
#define HTTPLogTraceWith(MSG, PARAM...) NSLog(@"TRACE: %s " MSG, __func__, PARAM)


@interface WebSocket () <GCDAsyncSocketDelegate>
{
@protected
	__weak id<WebSocketDelegate> _delegate;
	dispatch_queue_t _websocketQueue;
	GCDAsyncSocket *_asyncSocket;

    WebSocketState _state;
//	BOOL _isStarted;
//	BOOL _isOpen;
    BOOL _isClient;
}

- (void)start;

- (void) sendFrame: (NSData*)msgData type: (unsigned)type tag: (long)tag;

- (void)didOpen;
- (void)didReceiveMessage:(NSString *)msg;
- (void)didReceiveBinaryMessage:(NSData *)msg;
- (void)didCloseWithCode: (WebSocketCloseCode)code reason: (NSString*)reason;

@end
