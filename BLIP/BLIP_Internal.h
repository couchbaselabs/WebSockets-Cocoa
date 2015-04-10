//
//  BLIP_Internal.h
//  WebSocket
//
//  Created by Jens Alfke on 5/10/08.
//  Copyright 2008-2013 Jens Alfke.
//  Copyright (c) 2013 Couchbase, Inc. All rights reserved.

#import "BLIPWebSocket.h"
#import "BLIPRequest.h"
#import "BLIPResponse.h"
#import "BLIPProperties.h"
@class MYBuffer;


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


@interface BLIPWebSocket ()
- (BOOL) _sendRequest: (BLIPRequest*)q response: (BLIPResponse*)response;
- (BOOL) _sendResponse: (BLIPResponse*)response;
- (void) _messageReceivedProperties: (BLIPMessage*)message;
@end


@interface BLIPMessage ()
{
    @protected
    BLIPWebSocket* _connection;
    BLIPMessageFlags _flags;
    UInt32 _number;
    NSDictionary *_properties;
    NSData *_body;
    MYBuffer *_encodedBody;
    NSMutableData *_mutableBody;
    NSMutableArray* _bodyStreams;
    BOOL _isMine, _isMutable, _sent, _propertiesAvailable, _complete;
    NSInteger _bytesWritten, _bytesReceived;
    id _representedObject;
}
@property BOOL sent, propertiesAvailable, complete;
- (BLIPMessageFlags) _flags;
- (void) _setFlag: (BLIPMessageFlags)flag value: (BOOL)value;
- (void) _encode;
@end


@interface BLIPMessage ()
- (instancetype) _initWithConnection: (BLIPWebSocket*)connection
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
- (instancetype) _initWithConnection: (BLIPWebSocket*)connection
                                body: (NSData*)body
                          properties: (NSDictionary*)properties;
@end


@interface BLIPResponse ()
- (instancetype) _initWithRequest: (BLIPRequest*)request;
#if DEBUG
- (instancetype) _initIncomingWithProperties: (NSDictionary*)properties body: (NSData*)body;
#endif
@end
