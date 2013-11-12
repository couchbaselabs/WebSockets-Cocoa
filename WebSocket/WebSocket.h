//
//  WebSocket.h
//  WebSocket
//
//  Created by Jens Alfke on 9/10/13, based on Robbie Hanson's original code from
//  https://github.com/robbiehanson/CocoaHTTPServer

#import <Foundation/Foundation.h>
@class GCDAsyncSocket;
@protocol WebSocketDelegate;


/** States that a WebSocket can be in during its lifetime. */
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
    kWebSocketCloseGoingAway        = 1001, // Peer has to close, e.g. because host app is quitting
    kWebSocketCloseProtocolError    = 1002, // Protocol violation: invalid framing data
    kWebSocketCloseDataError        = 1003, // Message payload cannot be handled
    kWebSocketCloseNoCode           = 1005, // Never sent, only received
    kWebSocketCloseAbnormal         = 1006, // Never sent, only received
    kWebSocketCloseBadMessageFormat = 1007, // Unparseable message
    kWebSocketClosePolicyError      = 1008,
    kWebSocketCloseMessageTooBig    = 1009,
    kWebSocketCloseMissingExtension = 1010, // Peer doesn't provide a necessary extension
    kWebSocketCloseCantFulfill      = 1011, // Can't fulfill request due to "unexpected condition"
    kWebSocketCloseTLSFailure       = 1015, // Never sent, only received

    kWebSocketCloseFirstAvailable   = 4000, // First unregistered code for freeform use
};
typedef enum WebSocketCloseCode WebSocketCloseCode;


/** Abstract superclass WebSocket implementation.
    (If you want to connect to a server, look at WebSocketClient.)
    All methods are thread-safe unless otherwise noted. */
@interface WebSocket : NSObject

/** Designated initializer (for subclasses to call; remember, this class is abstract) */
- (instancetype) init;

/** Starts a server-side WebSocket on an already-open GCDAsyncSocket. */
- (instancetype) initWithConnectedSocket: (GCDAsyncSocket*)socket
                                delegate: (id<WebSocketDelegate>)delegate;

@property (weak) id<WebSocketDelegate> delegate;

/** Socket timeout interval. If no traffic is received for this long, the socket will close.
    Default is 60 seconds. Use a negative value to disable timeouts. */
@property NSTimeInterval timeout;

/** Configures the socket to use TLS/SSL. Settings dict is same as used with CFStream. */
- (void) useTLS: (NSDictionary*)tlsSettings;

/** Status of the connection (unopened, opening, ...)
    This is observable, but KVO notifications will be sent on the WebSocket's dispatch queue. */
@property (readonly) WebSocketState state;

/** Begins an orderly shutdown of the WebSocket connection, with code kWebSocketCloseNormal. */
- (void) close;

/** Begins an orderly shutdown of the WebSocket connection.
    @param code  The WebSocket status code to close with
    @param reason  Optional message associated with the code. This is not supposed to be shown
            to a human but may be useful in troubleshooting. */
- (void) closeWithCode:(WebSocketCloseCode)code reason:(NSString *)reason;

/** Abrupt socket disconnection. Normally you should call -close instead. */
- (void) disconnect;

/** Sends a text message over the WebSocket. */
- (void) sendMessage:(NSString *)msg;

/** Sends a binary message over the WebSocket. */
- (void) sendBinaryMessage:(NSData*)msg;


///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - UNDER THE HOOD
///////////////////////////////////////////////////////////////////////////////////////////////////

/** The GCD queue the WebSocket and its GCDAsyncSocket run on, and delegate methods are called on.
    This queue is created when the WebSocket is created. Don't use it for anything else. */
@property (nonatomic, readonly) dispatch_queue_t websocketQueue;


///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - OVERRIDEABLE METHODS
///////////////////////////////////////////////////////////////////////////////////////////////////

// These correspond to the delegate methods.
// Subclasses can override them, but those should call through to the superclass method.

- (void) didOpen;
- (void) didReceiveMessage:(NSString *)msg;
- (void) didReceiveBinaryMessage:(NSData *)msg;
- (void) isHungry;
- (void) didCloseWithCode: (WebSocketCloseCode)code reason: (NSString*)reason;


@end

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - DELEGATE API
///////////////////////////////////////////////////////////////////////////////////////////////////

/** Delegate API for WebSocket and its subclasses.
    Delegate messages are delivered on the WebSocket's dispatch queue (websocketQueue).
    Implementations will probably want to re-dispatch to their own queue. */
@protocol WebSocketDelegate <NSObject>
@optional

/** Only sent to a WebSocket opened from a WebSocketListener, before -webSocketDidOpen:.
    This method can determine whether the incoming connection should be accepted.
    @param request  The incoming HTTP request.
    @return  An HTTP status code: should be 101 to accept, or a value >= 300 to refuse.
        (As a convenience, any status code < 300 is mapped to 101. Also, if the client wants to return a boolean value, YES maps to 101 and NO maps to 403.)*/
- (int) webSocket: (WebSocket*)ws shouldAccept: (NSURLRequest*)request;

/** Called when a WebSocket has opened its connection and is ready to send and receive messages. */
- (void) webSocketDidOpen:(WebSocket *)ws;

/** Called when a WebSocket receives a textual message from its peer. */
- (void) webSocket:(WebSocket *)ws
         didReceiveMessage:(NSString *)msg;

/** Called when a WebSocket receives a binary message from its peer. */
- (void) webSocket:(WebSocket *)ws
         didReceiveBinaryMessage:(NSData *)msg;

/** Called when the WebSocket has finished sending all queued messages and is ready for more. */
- (void) webSocketIsHungry:(WebSocket *)ws;

/** Called after the WebSocket closes, either intentionally or due to an error. */
- (void) webSocket:(WebSocket *)ws
         didCloseWithCode: (WebSocketCloseCode)code
                   reason: (NSString*)reason;

@end
