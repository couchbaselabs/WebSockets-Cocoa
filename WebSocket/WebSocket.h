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
    If you want to connect to a server, look at WebSocketClient. */
@interface WebSocket : NSObject

/** Designated initializer */
- (instancetype) init;

/** Starts a server-side WebSocket on an already-open GCDAsyncSocket. */
- (id)initWithConnectedSocket: (GCDAsyncSocket*)socket
                     delegate: (id<WebSocketDelegate>)delegate;

@property (weak) id<WebSocketDelegate> delegate;

/** Socket timeout interval. If no traffic is received for this long, the socket will close.
    Default is 60 seconds. Use a negative value to disable timeouts. */
@property NSTimeInterval timeout;

/** Configures the socket to use TLS/SSL. Settings dict is same as used with CFStream. */
- (void) useTLS: (NSDictionary*)tlsSettings;

/** Status of the connection (unopened, opening, ...) This is observable. */
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

/** Sends a text message over the WebSocket. This method is thread-safe. */
- (void) sendMessage:(NSString *)msg;

/** Sends a binary message over the WebSocket. This method is thread-safe. */
- (void) sendBinaryMessage:(NSData*)msg;


///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - UNDER THE HOOD
///////////////////////////////////////////////////////////////////////////////////////////////////

@property GCDAsyncSocket* asyncSocket;

/** The GCD queue the WebSocket and its GCDAsyncSocket run on. */
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

/** Delegate API for WebSocket and its subclasses. */
@protocol WebSocketDelegate <NSObject>
@optional

/** Only sent to a WebSocket opened from a WebSocketListener, before -webSocketDidOpen:.
    @param headers  The HTTP headers in the incoming request
    @return  An HTTP status code: should be 101 to accept, or a value >= 300 to refuse.
        (As a convenience, any status code < 300 is mapped to 101. Also, if the client want to return a boolean value, YES maps to 101 and NO maps to 403.)*/
- (int) webSocket: (WebSocket*)ws shouldAccept: (NSURLRequest*)request;

- (void) webSocketDidOpen:(WebSocket *)ws;

- (void) webSocket:(WebSocket *)ws
         didReceiveMessage:(NSString *)msg;

- (void) webSocket:(WebSocket *)ws
         didReceiveBinaryMessage:(NSData *)msg;

- (void) webSocketIsHungry:(WebSocket *)ws;

- (void) webSocket:(WebSocket *)ws
         didCloseWithCode: (WebSocketCloseCode)code
                   reason: (NSString*)reason;

@end
