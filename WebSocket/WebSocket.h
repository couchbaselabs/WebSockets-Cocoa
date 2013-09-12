//
//  WebSocket.h
//  WebSocket
//
//  Created by Jens Alfke on 9/10/13, based on Robbie Hanson's original code from
//  https://github.com/robbiehanson/CocoaHTTPServer
//

#import <Foundation/Foundation.h>
@class GCDAsyncSocket;
@protocol WebSocketDelegate;


enum WebSocketState {
    kWebSocketUnopened,
    kWebSocketOpening,
    kWebSocketOpen,
    kWebSocketClosing,
    kWebSocketClosed
};
typedef enum WebSocketState WebSocketState;


/** Predefined status codes to use with -closeWithCode:reason:.
    They are defined at <http://tools.ietf.org/html/rfc6455#section-7.4.1> */
enum WebSocketCloseCode : UInt16 {
    kWebSocketCloseNormal           = 1000,
    kWebSocketCloseGoingAway        = 1001,
    kWebSocketCloseProtocolError    = 1002,
    kWebSocketCloseDataError        = 1003,
    kWebSocketCloseNoCode           = 1005, // Never sent, only received
    kWebSocketCloseAbnormal         = 1006, // Never sent, only received
    kWebSocketCloseBadMessageFormat = 1007,
    kWebSocketClosePolicyError      = 1008,
    kWebSocketCloseMessageTooBig    = 1009,
    kWebSocketCloseMissingExtension = 1010,
    kWebSocketCloseCantFulfill      = 1011,
    kWebSocketCloseTLSFailure       = 1015, // Never sent, only received

    kWebSocketCloseFirstAvailable   = 4000, // First unregistered code for freeform use
};
typedef enum WebSocketCloseCode WebSocketCloseCode;


/** Abstract superclass WebSocket implementation. */
@interface WebSocket : NSObject

/** Designated initializer */
- (instancetype) init;

@property GCDAsyncSocket* asyncSocket;

@property (weak) id<WebSocketDelegate> delegate;

/** The WebSocket class is thread-safe, generally via its GCD queue.
    All public API methods are thread-safe,
    and the subclass API methods are thread-safe as they are all invoked on the same GCD queue. */
@property (nonatomic, readonly) dispatch_queue_t websocketQueue;

@property (readonly) WebSocketState state;

/** Begins an orderly shutdown of the WebSocket connection. */
- (void) close;
- (void) closeWithCode:(WebSocketCloseCode)code reason:(NSString *)reason;

@property (readonly) NSError* error;

@property (readonly) BOOL closing;

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
@protocol WebSocketDelegate <NSObject>
@optional

- (void)webSocketDidOpen:(WebSocket *)ws;

- (void)webSocket:(WebSocket *)ws didReceiveMessage:(NSString *)msg;

- (void)webSocket:(WebSocket *)ws didReceiveBinaryMessage:(NSData *)msg;

- (void)webSocket:(WebSocket *)ws didCloseWithCode: (WebSocketCloseCode)code reason: (NSString*)reason;

@end