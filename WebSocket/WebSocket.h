//
//  WebSocket.h
//  WebSocket
//
//  Created by Jens Alfke on 9/10/13, based on Robbie Hanson's original code from
//  https://github.com/robbiehanson/CocoaHTTPServer
//

#import <Foundation/Foundation.h>
@class GCDAsyncSocket;


#define WebSocketDidDieNotification  @"WebSocketDidDie"


/** Abstract superclass WebSocket implementation. */
@interface WebSocket : NSObject

/** Designated initializer */
- (instancetype)init;

@property GCDAsyncSocket* asyncSocket;

@property (/* atomic */ weak) id delegate;

/** The WebSocket class is thread-safe, generally via its GCD queue.
    All public API methods are thread-safe,
    and the subclass API methods are thread-safe as they are all invoked on the same GCD queue. */
@property (nonatomic, readonly) dispatch_queue_t websocketQueue;

/** Begins an orderly shutdown of the WebSocket connection. */
- (void) close;

/** Abrupt socket disconnection. Normally you should call -close instead. */
- (void)disconnect;

/** Sends a text message over the WebSocket. This method is thread-safe. */
- (void)sendMessage:(NSString *)msg;

/** Sends a binary message over the WebSocket. This method is thread-safe. */
- (void)sendBinaryMessage:(NSData*)msg;


@end

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
///////////////////////////////////////////////////////////////////////////////////////////////////

/** Delegate API for WebSocket and its subclasses. */
@protocol WebSocketDelegate
@optional

- (void)webSocketDidOpen:(WebSocket *)ws;

- (void)webSocket:(WebSocket *)ws didReceiveMessage:(NSString *)msg;

- (void)webSocket:(WebSocket *)ws didReceiveBinaryMessage:(NSData *)msg;

- (void)webSocketDidClose:(WebSocket *)ws;

- (void)webSocketDidFail: (NSString*)reason;

@end