//
//  BLIPMessage.h
//  WebSocket
//
//  Created by Jens Alfke on 5/10/08.
//  Copyright 2008-2013 Jens Alfke.
//  Copyright (c) 2013 Couchbase, Inc. All rights reserved.

#import <Foundation/Foundation.h>
@class BLIPMessage, BLIPRequest, BLIPResponse;
@protocol MYReader;


@protocol BLIPMessageSender <NSObject>
- (BOOL) _sendRequest: (BLIPRequest*)q response: (BLIPResponse*)response;
- (BOOL) _sendResponse: (BLIPResponse*)response;
@property (readonly) NSError* error;
- (void) _messageReceivedProperties: (BLIPMessage*)message;
@end


/** NSError domain and codes for BLIP */
extern NSString* const BLIPErrorDomain;
enum {
    kBLIPError_BadData = 1,
    kBLIPError_BadFrame,
    kBLIPError_Disconnected,
    kBLIPError_PeerNotAllowed,
    
    kBLIPError_Misc = 99,
    
    // errors returned in responses:
    kBLIPError_BadRequest = 400,
    kBLIPError_Forbidden = 403,
    kBLIPError_NotFound = 404,
    kBLIPError_BadRange = 416,
    
    kBLIPError_HandlerFailed = 501,
    kBLIPError_Unspecified = 599            // peer didn't send any detailed error info
};

NSError *BLIPMakeError( int errorCode, NSString *message, ... ) __attribute__ ((format (__NSString__, 2, 3)));


/** Abstract superclass for BLIP requests and responses. */
@interface BLIPMessage : NSObject

/** The BLIPWebSocket associated with this message. */
@property (readonly,strong) id<BLIPMessageSender> connection;

/** The onDataReceived callback allows for streaming incoming message data. If it's set, the block
    will be called every time more data arrives. The block can read data from the MYReader if it
    wants. Any data left unread will appear in the next call, and any data unread when the message
    is complete will be left in the .body property.
    (Note: If the message is compressed, onDataReceived won't be called while data arrives, just
    once at the end after decompression. This may be improved in the future.) */
@property (strong) void (^onDataReceived)(id<MYReader>);

/** Called after message data is sent over the socket. */
@property (strong) void (^onDataSent)(uint64_t totalBytesSent);

/** Called when the message has been completely sent over the socket. */
@property (strong) void (^onSent)();

/** This message's serial number in its connection.
    A BLIPRequest's number is initially zero, then assigned when it's sent.
    A BLIPResponse is automatically assigned the same number as the request it replies to. */
@property (readonly) UInt32 number;

/** Is this a message sent by me (as opposed to the peer)? */
@property (readonly) BOOL isMine;

/** Is this a request or a response? */
@property (readonly) BOOL isRequest;

/** Has this message been sent yet? (Only makes sense when isMine is true.) */
@property (readonly) BOOL sent;

/** Has enough of the message arrived to read its properies? */
@property (readonly) BOOL propertiesAvailable;

/** Has the entire message, including the body, arrived? */
@property (readonly) BOOL complete;

/** Should the message body be compressed with gzip?
    This property can only be set <i>before</i> sending the message. */
@property BOOL compressed;

/** Should the message be sent ahead of normal-priority messages?
    This property can only be set <i>before</i> sending the message. */
@property BOOL urgent;

/** Can this message be changed? (Only true for outgoing messages, before you send them.) */
@property (readonly) BOOL isMutable;

/** The message body, a blob of arbitrary data. */
@property (copy) NSData *body;

/** Appends data to the body. */
- (void) addToBody: (NSData*)data;

/** Appends the contents of a stream to the body. Don't close the stream afterwards, or read from
    it; the BLIPMessage will read from it later, while the message is being delivered, and close
    it when it's done. */
- (void) addStreamToBody: (NSInputStream*)stream;

/** The message body as an NSString.
    The UTF-8 character encoding is used to convert. */
@property (copy) NSString *bodyString;

/** The message body as a JSON-serializable object.
    The setter will raise an exception if the value can't be serialized;
    the getter just warns and returns nil. */
@property (copy) id bodyJSON;

/** An arbitrary object that you can associate with this message for your own purposes.
    The message retains it, but doesn't do anything else with it. */
@property (strong) id representedObject;

#pragma mark PROPERTIES:

/** The message's properties, a dictionary-like object.
    Message properties are much like the headers in HTTP, MIME and RFC822. */
@property (readonly) NSDictionary* properties;

/** Mutable version of the message's properties; only available if this mesage is mutable. */
@property (readonly) NSMutableDictionary* mutableProperties;

/** The value of the "Content-Type" property, which is by convention the MIME type of the body. */
@property (copy) NSString *contentType;

/** The value of the "Profile" property, which by convention identifies the purpose of the message. */
@property (copy) NSString *profile;

/** A shortcut to get the value of a property. */
- (NSString*)objectForKeyedSubscript:(NSString*)key;

/** A shortcut to set the value of a property. A nil value deletes that property. */
- (void) setObject: (NSString*)value forKeyedSubscript:(NSString*)key;

/** Similar to -description, but also shows the properties and their values. */
@property (readonly) NSString* descriptionWithProperties;


@end
