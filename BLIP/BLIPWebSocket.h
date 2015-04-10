//
//  BLIPWebSocket.h
//  WebSocket
//
//  Created by Jens Alfke on 4/1/13.
//  Copyright (c) 2013 Couchbase, Inc. All rights reserved.

#import "WebSocket.h"
#import "BLIPMessage.h"
@class BLIPRequest, BLIPResponse, BLIPDispatcher;
@protocol BLIPWebSocketDelegate;


/** A BLIP connection layered on a WebSocket. */
@interface BLIPWebSocket : NSObject

- (instancetype) initWithURLRequest:(NSURLRequest *)request;
- (instancetype) initWithURL:(NSURL *)url;

- (instancetype) initWithWebSocket: (WebSocket*)webSocket;

/** Attaches a delegate, and specifies what GCD queue it should be called on. */
- (void) setDelegate: (id<BLIPWebSocketDelegate>)delegate
               queue: (dispatch_queue_t)delegateQueue;

/** URL this socket is connected to, _if_ it's a client socket; if it's an incoming one received
    by a BLIPWebSocketListener, this is nil. */
@property (readonly) NSURL* URL;

/** The underlying WebSocket. */
@property (readonly) WebSocket* webSocket;

@property (readonly) NSError* error;

- (BOOL) connect: (NSError**)outError;

- (void)close;
- (void)closeWithCode:(WebSocketCloseCode)code reason:(NSString *)reason;

@property (nonatomic) BLIPDispatcher* dispatcher;

/** If set to YES, an incoming message will be dispatched to the delegate and/or dispatcher before it's complete, as soon as its properties are available. The application should then set a dataDelegate on the message to receive its data a frame at a time. */
@property BOOL dispatchPartialMessages;

/** Creates a new, empty outgoing request.
    You should add properties and/or body data to the request, before sending it by
    calling its -send method. */
- (BLIPRequest*) request;

/** Creates a new outgoing request.
    The body or properties may be nil; you can add additional data or properties by calling
    methods on the request itself, before sending it by calling its -send method. */
- (BLIPRequest*) requestWithBody: (NSData*)body
                      properties: (NSDictionary*)properies;

/** Sends a request over this connection.
    (Actually, it queues it to be sent; this method always returns immediately.)
    Call this instead of calling -send on the request itself, if the request was created with
    +[BLIPRequest requestWithBody:] and hasn't yet been assigned to any connection.
    This method will assign it to this connection before sending it.
    The request's matching response object will be returned, or nil if the request couldn't be sent. */
- (BLIPResponse*) sendRequest: (BLIPRequest*)request;

/** Are any messages currently being sent or received? (Observable) */
@property (readonly) BOOL active;

@end



/** The delegate messages that BLIPWebSocketDelegate will send.
    All methods are optional. */
@protocol BLIPWebSocketDelegate <NSObject>
@optional

- (void)blipWebSocketDidOpen:(BLIPWebSocket*)webSocket;

- (void)blipWebSocket: (BLIPWebSocket*)webSocket didFailWithError:(NSError *)error;

- (void)blipWebSocket: (BLIPWebSocket*)webSocket
    didCloseWithError: (NSError*)error;

/** Called when a BLIPRequest is received from the peer, if there is no BLIPDispatcher
    rule to handle it.
    If the delegate wants to accept the request it should return YES; if it returns NO,
    a kBLIPError_NotFound error will be returned to the sender.
    The delegate should get the request's response object, fill in its data and properties
    or error property, and send it.
    If it doesn't explicitly send a response, a default empty one will be sent;
    to prevent this, call -deferResponse on the request if you want to send a response later. */
- (BOOL) blipWebSocket: (BLIPWebSocket*)webSocket receivedRequest: (BLIPRequest*)request;

/** Called when a BLIPResponse (to one of your requests) is received from the peer.
    This is called <i>after</i> the response object's onComplete target, if any, is invoked.*/
- (void) blipWebSocket: (BLIPWebSocket*)webSocket receivedResponse: (BLIPResponse*)response;

@end
