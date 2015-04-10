//
//  BLIPConnection+Transport.h
//  BLIPSync
//
//  Created by Jens Alfke on 4/10/15.
//  Copyright (c) 2015 Couchbase. All rights reserved.
//

#import "BLIPConnection.h"

/** Protected API of BLIPConnection, for use by concrete subclasses. */
@interface BLIPConnection ()

/** Designated initializer.
    @param transportQueue  The dispatch queue on which the transport should be called and on
                which it will call the BLIPConnection.
    @param isOpen  YES if the transport is already open and ready to send/receive messages. */
- (instancetype) initWithTransportQueue: (dispatch_queue_t)transportQueue
                                 isOpen: (BOOL)isOpen;

// This is settable.
@property (readwrite) NSError* error;

// Internal methods for subclasses to call:

/** Call this when the transport opens and is ready to send/receive messages. */
- (void) transportDidOpen;

/** Call this when the transport closes or fails to open.
    @param error  The error, or nil if this is a normal closure. */
- (void) transportDidCloseWithError: (NSError*)error;

/** Call this when the transport is done sending data and is ready to send more.
    If any messages are ready, it will call -sendFrame:. */
- (void) feedTransport;

/** Call this when the transport receives a frame from the peer. */
- (void) didReceiveFrame: (NSData*)frame;

// Abstract internal methods that subclasses must implement:

/** Subclass must implement this to return YES if the transport is in a state where it can send
    messages, NO if not. Most importantly, it should return NO if it's in the process of closing.*/
- (BOOL) transportCanSend;

/** Subclass must implement this to send the frame to the peer. */
- (void) sendFrame: (NSData*)frame;

// Abstract public methods that that subclasses must implement:
// - (BOOL) connect: (NSError**)outError;
// - (void) close;

@end
