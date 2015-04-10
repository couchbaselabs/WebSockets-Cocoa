//
//  BLIPConnection.h
//  WebSocket
//
//  Created by Jens Alfke on 4/1/13.
//  Copyright (c) 2013 Couchbase, Inc. All rights reserved.

#import "BLIPMessage.h"
@class BLIPRequest, BLIPResponse;
@protocol BLIPConnectionDelegate;


/** A network connection to a peer that can send and receive BLIP messages.
    This is an abstract class that doesn't use any specific transport. Subclasses must use and
    implement the methods declared in BLIPConnection+Transport.h. */
@interface BLIPConnection : NSObject

/** Attaches a delegate, and specifies what GCD queue it should be called on. */
- (void) setDelegate: (id<BLIPConnectionDelegate>)delegate
               queue: (dispatch_queue_t)delegateQueue;

/** URL this socket is connected to, _if_ it's a client socket; if it's an incoming one received
    by a BLIPConnectionListener, this is nil. */
@property (readonly) NSURL* URL;

@property (readonly) NSError* error;

- (BOOL) connect: (NSError**)outError;

- (void)close;

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



/** The delegate messages that BLIPConnection will send.
    All methods are optional. */
@protocol BLIPConnectionDelegate <NSObject>
@optional

- (void)blipConnectionDidOpen:(BLIPConnection*)connection;

- (void)blipConnection: (BLIPConnection*)connection didFailWithError:(NSError *)error;

- (void)blipConnection: (BLIPConnection*)connection
     didCloseWithError: (NSError*)error;

/** Called when a BLIPRequest is received from the peer, if there is no BLIPDispatcher
    rule to handle it.
    If the delegate wants to accept the request it should return YES; if it returns NO,
    a kBLIPError_NotFound error will be returned to the sender.
    The delegate should get the request's response object, fill in its data and properties
    or error property, and send it.
    If it doesn't explicitly send a response, a default empty one will be sent;
    to prevent this, call -deferResponse on the request if you want to send a response later. */
- (BOOL) blipConnection: (BLIPConnection*)connection receivedRequest: (BLIPRequest*)request;

/** Called when a BLIPResponse (to one of your requests) is received from the peer.
    This is called <i>after</i> the response object's onComplete target, if any, is invoked.*/
- (void) blipConnection: (BLIPConnection*)connection receivedResponse: (BLIPResponse*)response;

@end
