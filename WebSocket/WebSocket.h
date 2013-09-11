#import <Foundation/Foundation.h>

@class HTTPMessage;
@class GCDAsyncSocket;


#define WebSocketDidDieNotification  @"WebSocketDidDie"


/** Abstract superclass WebSocket implementation. */
@interface WebSocket : NSObject

/** Designated initializer */
- (id)init;

@property GCDAsyncSocket* asyncSocket;

/**
 * Delegate option.
 * 
 * In most cases it will be easier to subclass WebSocket,
 * but some circumstances may lead one to prefer standard delegate callbacks instead.
**/
@property (/* atomic */ weak) id delegate;

/**
 * The WebSocket class is thread-safe, generally via its GCD queue.
 * All public API methods are thread-safe,
 * and the subclass API methods are thread-safe as they are all invoked on the same GCD queue.
**/
@property (nonatomic, readonly) dispatch_queue_t websocketQueue;

/** Begins an orderly shutdown of the WebSocket connection. */
- (void) close;

/** Abrupt socket disconnection. Normally you should call -close instead. */
- (void)disconnect;

/**
 * Public API
 * 
 * Sends a message over the WebSocket.
 * This method is thread-safe.
**/
- (void)sendMessage:(NSString *)msg;

- (void)sendBinaryMessage:(NSData*)msg;


@end

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
///////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * There are two ways to create your own custom WebSocket:
 * 
 * - Subclass it and override the methods you're interested in.
 * - Use traditional delegate paradigm along with your own custom class.
 * 
 * They both exist to allow for maximum flexibility.
 * In most cases it will be easier to subclass WebSocket.
 * However some circumstances may lead one to prefer standard delegate callbacks instead.
 * One such example, you're already subclassing another class, so subclassing WebSocket isn't an option.
**/

@protocol WebSocketDelegate
@optional

- (void)webSocketDidOpen:(WebSocket *)ws;

- (void)webSocket:(WebSocket *)ws didReceiveMessage:(NSString *)msg;

- (void)webSocket:(WebSocket *)ws didReceiveBinaryMessage:(NSData *)msg;

- (void)webSocketDidClose:(WebSocket *)ws;

- (void)webSocketDidFail: (NSString*)reason;

@end