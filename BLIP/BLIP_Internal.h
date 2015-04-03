//
//  BLIP_Internal.h
//  WebSocket
//
//  Created by Jens Alfke on 5/10/08.
//  Copyright 2008-2013 Jens Alfke.
//  Copyright (c) 2013 Couchbase, Inc. All rights reserved.

#import "BLIPRequest.h"
#import "BLIPResponse.h"
#import "BLIPProperties.h"


/* Private declarations and APIs for BLIP implementation. Not for use by clients! */


/* Flag bits in a BLIP frame header */
typedef NS_OPTIONS(UInt8, BLIPMessageFlags) {
    kBLIP_MSG       = 0x00,       // initiating message
    kBLIP_RPY       = 0x01,       // response to a MSG
    kBLIP_ERR       = 0x02,       // error response to a MSG

    kBLIP_TypeMask  = 0x03,       // bits reserved for storing message type
    kBLIP_Compressed= 0x04,       // data is gzipped
    kBLIP_Urgent    = 0x08,       // please send sooner/faster
    kBLIP_NoReply   = 0x10,       // no RPY needed
    kBLIP_MoreComing= 0x20,       // More frames coming (Applies only to individual frame)
    kBLIP_Meta      = 0x40,       // Special message type, handled internally (hello, bye, ...)

    kBLIP_MaxFlag   = 0xFF
};

/* BLIP message types; encoded in each frame's header. */
typedef BLIPMessageFlags BLIPMessageType;


@interface BLIPMessage ()
{
    @protected
    id<BLIPMessageSender> _connection;
    BLIPMessageFlags _flags;
    UInt32 _number;
    BLIPProperties *_properties;
    NSData *_body;
    NSMutableData *_encodedBody;
    NSMutableData *_mutableBody;
    BOOL _isMine, _isMutable, _sent, _propertiesAvailable, _complete;
    NSInteger _bytesWritten;
    id _representedObject;
}
@property BOOL sent, propertiesAvailable, complete;
- (BLIPMessageFlags) _flags;
- (void) _setFlag: (BLIPMessageFlags)flag value: (BOOL)value;
- (void) _encode;
@end


@interface BLIPMessage ()
- (id) _initWithConnection: (id<BLIPMessageSender>)connection
                    isMine: (BOOL)isMine
                     flags: (BLIPMessageFlags)flags
                    number: (UInt32)msgNo
                      body: (NSData*)body;
- (NSData*) nextWebSocketFrameWithMaxSize: (UInt16)maxSize moreComing: (BOOL*)outMoreComing;
@property (readonly) NSInteger _bytesWritten;
- (void) _assignedNumber: (UInt32)number;
- (BOOL) _receivedFrameWithFlags: (BLIPMessageFlags)flags body: (NSData*)body;
- (void) _connectionClosed;
@end


@interface BLIPRequest ()
- (id) _initWithConnection: (id<BLIPMessageSender>)connection
                      body: (NSData*)body 
                properties: (NSDictionary*)properties;
@end


@interface BLIPResponse ()
- (id) _initWithRequest: (BLIPRequest*)request;
#if DEBUG
- (id) _initIncomingWithProperties: (BLIPProperties*)properties body: (NSData*)body;
#endif
@end
