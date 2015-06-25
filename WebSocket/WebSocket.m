//
//  WebSocket.m
//  WebSocket
//
//  Created by Jens Alfke on 9/10/13, based on Robbie Hanson's original code from
//  https://github.com/robbiehanson/CocoaHTTPServer
//
//  Copyright (c) 2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "WebSocket.h"
#import "WebSocket_Internal.h"
#import "GCDAsyncSocket.h"
#import <Security/SecRandom.h>
@class HTTPMessage;

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

// Does ARC support GCD objects?
// It does if the minimum deployment target is iOS 6+ or Mac OS X 8+

#if TARGET_OS_IPHONE

  // Compiling for iOS

  #if __IPHONE_OS_VERSION_MIN_REQUIRED >= 60000 // iOS 6.0 or later
    #define NEEDS_DISPATCH_RETAIN_RELEASE 0
  #else                                         // iOS 5.X or earlier
    #define NEEDS_DISPATCH_RETAIN_RELEASE 1
  #endif

#else

  // Compiling for Mac OS X

  #if MAC_OS_X_VERSION_MIN_REQUIRED >= 1080     // Mac OS X 10.8 or later
    #define NEEDS_DISPATCH_RETAIN_RELEASE 0
  #else
    #define NEEDS_DISPATCH_RETAIN_RELEASE 1     // Mac OS X 10.7 or earlier
  #endif

#endif

#define TIMEOUT_NONE          -1
#define TIMEOUT_REQUEST_BODY  10

#define HUNGRY_SIZE 5

/* unused
static inline BOOL WS_OP_IS_FINAL_FRAGMENT(UInt8 frame) {
	return (frame & 0x80) ? YES : NO;
}*/

static inline BOOL WS_PAYLOAD_IS_MASKED(UInt8 frame) {
	return (frame & 0x80) ? YES : NO;
}

static inline NSUInteger WS_PAYLOAD_LENGTH(UInt8 frame) {
	return frame & 0x7F;
}

static inline void maskBytes(NSMutableData* data, NSUInteger offset, NSUInteger length,
                             const UInt8* mask)
{
    // OPT: Is there a vector operation to do this more quickly?
    UInt8* bytes = (UInt8*)data.mutableBytes + offset;
    for (NSUInteger i = 0; i < length; ++i) {
        bytes[i] ^= mask[i % 4];
    }
}


NSString* const WebSocketErrorDomain = @"WebSocket";


@interface WebSocket ()
@property (readwrite) WebSocketState state;
@end


///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
///////////////////////////////////////////////////////////////////////////////////////////////////

@implementation WebSocket
{
	BOOL _isRFC6455;
    NSTimeInterval _timeout;
	BOOL _nextFrameMasked;
	NSData *_maskingKey;
	NSUInteger _nextOpCode;
    NSUInteger _writeQueueSize;
    BOOL _readyToReadMessage;       // YES when message read and ready to start reading the next
    BOOL _readPaused;               // While YES, stop reading messages from the socket
}


///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Setup and Teardown
///////////////////////////////////////////////////////////////////////////////////////////////////

@synthesize timeout=_timeout, websocketQueue=_websocketQueue, state=_state;

static NSData* kTerminator;

+ (void) initialize {
    if (!kTerminator)
        kTerminator = [[NSData alloc] initWithBytes:"\xFF" length:1];
}

// For compatibility with the WebSocket class in the CocoaHTTPServer library
+ (BOOL)isWebSocketRequest:(HTTPMessage *)request {
    return NO;
}

- (instancetype) init {
	HTTPLogTrace();

	if ((self = [super init])) {
        _timeout = TIMEOUT_DEFAULT;
        _state = kWebSocketUnopened;
		_websocketQueue = dispatch_queue_create("WebSocket", NULL);
		_isRFC6455 = YES;
	}
	return self;
}

- (instancetype) initWithConnectedSocket: (GCDAsyncSocket*)socket
                                delegate: (id<WebSocketDelegate>)delegate
{
    self = [self init];
    if (self) {
		_delegate = delegate;
        self.asyncSocket = socket;
        [self didOpen];
    }
    return self;
}

- (void)dealloc {
	HTTPLogTrace();
	
	#if NEEDS_DISPATCH_RETAIN_RELEASE
	dispatch_release(_websocketQueue);
	#endif
	
	[_asyncSocket setDelegate:nil delegateQueue:NULL];
	[_asyncSocket disconnect];
}

- (GCDAsyncSocket*) asyncSocket {
    return _asyncSocket;
}

- (void) setAsyncSocket: (GCDAsyncSocket*)socket {
    NSAssert(!_asyncSocket, @"Already have a socket");
    _asyncSocket = socket;
    [_asyncSocket setDelegate:self delegateQueue:_websocketQueue];
    if (_tlsSettings)
        [_asyncSocket startTLS: _tlsSettings];
}

- (id)delegate {
	__block id result = nil;
	
	dispatch_sync(_websocketQueue, ^{
		result = _delegate;
	});
	
	return result;
}

- (void)setDelegate:(id<WebSocketDelegate>)newDelegate {
	dispatch_async(_websocketQueue, ^{
		_delegate = newDelegate;
	});
}

- (void) useTLS: (NSDictionary*)tlsSettings {
	dispatch_async(_websocketQueue, ^{
        _tlsSettings = tlsSettings;
    });
}


///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Start and Stop
///////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Starting point for the WebSocket after it has been fully initialized (including subclasses).
**/
- (void)start {
	// This method is not exactly designed to be overriden.
	// Subclasses are encouraged to override the didOpen method instead.
	
	dispatch_async(_websocketQueue, ^{ @autoreleasepool {
		if (_state > kWebSocketUnopened)
            return;
		self.state = kWebSocketOpening;
		
        [self didOpen];
	}});
}

/**
 * Abrupt disconnection.
**/
- (void)disconnect {
	// This method is not exactly designed to be overriden.
	// Subclasses are encouraged to override the didClose method instead.
	
	dispatch_async(_websocketQueue, ^{ @autoreleasepool {
		[_asyncSocket disconnect];
	}});
}

- (void) close {
    // Codes are defined in http://tools.ietf.org/html/rfc6455#section-7.4
    [self closeWithCode: kWebSocketCloseNormal reason: nil];
}

- (void) closeWithCode:(WebSocketCloseCode)code reason:(NSString *)reason {
	HTTPLogTrace();

    // http://tools.ietf.org/html/rfc6455#section-5.5.1
    NSMutableData* msg = nil;
    if (code > 0 || reason != nil) {
        UInt16 rawCode = NSSwapHostShortToBig(code);
        if (reason)
            msg = [[reason dataUsingEncoding: NSUTF8StringEncoding] mutableCopy];
        else
            msg = [NSMutableData dataWithCapacity: sizeof(rawCode)];
        [msg replaceBytesInRange: NSMakeRange(0, 0) withBytes: &rawCode length: sizeof(rawCode)];
    }

	dispatch_async(_websocketQueue, ^{ @autoreleasepool {
        if (_state == kWebSocketOpen) {
            [self sendFrame: msg type: WS_OP_CONNECTION_CLOSE tag: 0];
            self.state = kWebSocketClosing;
        }
    }});
}

- (void)didOpen {
	HTTPLogTrace();
	
	// Override me to perform any custom actions once the WebSocket has been opened.
	// This method is invoked on the websocketQueue.
	// 
	// Don't forget to invoke [super didOpen] in your method.

    self.state = kWebSocketOpen;
	
	// Start reading for messages
    _readyToReadMessage = YES;
    [self startReadingNextMessage];
	// Notify delegate
    id<WebSocketDelegate> delegate = _delegate;
	if ([delegate respondsToSelector:@selector(webSocketDidOpen:)]) {
		[delegate webSocketDidOpen:self];
	}
}

- (void)didCloseWithCode: (WebSocketCloseCode)code reason: (NSString*)reason {
    NSError* error;
    if (code != kWebSocketCloseNormal) {
        error = [NSError errorWithDomain: WebSocketErrorDomain
                                    code: code
                                userInfo: @{NSLocalizedFailureReasonErrorKey: reason}];
    }
    [self didCloseWithError: error];
}

- (void)didCloseWithError: (NSError*)error {
	HTTPLogTrace();

	// Override me to perform any cleanup when the socket is closed
	// This method is invoked on the websocketQueue.
	//
	// Don't forget to invoke [super didCloseWithError:] at the end of your method.

	// Notify delegate
    id<WebSocketDelegate> delegate = _delegate;
	if ([delegate respondsToSelector:@selector(webSocket:didCloseWithError:)]) {
        [delegate webSocket:self didCloseWithError: error];
	}
}

#pragma mark - SENDING MESSAGES:

- (void)sendMessage:(NSString *)msg {
    [self sendFrame: [msg dataUsingEncoding: NSUTF8StringEncoding]
               type: WS_OP_TEXT_FRAME
                tag: TAG_MESSAGE];
}

- (void)sendBinaryMessage:(NSData*)msg {
    [self sendFrame: msg type: WS_OP_BINARY_FRAME tag: TAG_MESSAGE];
}

- (void) sendFrame: (NSData*)msgData type: (unsigned)type tag: (long)tag {
	HTTPLogTrace();

    if (_state >= kWebSocketClosing)
        return;
	
	NSMutableData *data = nil;
	
	if (_isRFC6455) {
        // Framing format: http://tools.ietf.org/html/rfc6455#section-5.2
        UInt8 header[14] = {(0x80 | (UInt8)type) /*, 0x00...*/};
        NSUInteger headerLen;

		NSUInteger length = msgData.length;
		if (length <= 125) {
            header[1] = (UInt8)length;
            headerLen = 2;
		} else if (length <= 0xFFFF) {
            header[1] = 0x7E;
            UInt16 bigLen = NSSwapHostShortToBig((UInt16)length);
            memcpy(&header[2], &bigLen, sizeof(bigLen));
			headerLen = 4;
		} else {
            header[1] = 0x7F;
            UInt64 bigLen = NSSwapHostLongLongToBig(length);
            memcpy(&header[2], &bigLen, sizeof(bigLen));
			headerLen = 10;
		}

        UInt8 mask[4];
        if (_isClient) {
            header[1] |= 0x80;  // Sets the 'mask' flag
            SecRandomCopyBytes(kSecRandomDefault, sizeof(mask), mask);
            memcpy(&header[headerLen], mask, sizeof(mask));
            headerLen += sizeof(mask);
        }

        data = [NSMutableData dataWithCapacity: headerLen + length];
        [data appendBytes: header length: headerLen];
        [data appendData: msgData];

        if (_isClient) {
            maskBytes(data, headerLen, length, mask);
        }
	} else {
		data = [NSMutableData dataWithCapacity:([msgData length] + 2)];
		[data appendBytes:"\x00" length:1];
		[data appendData:msgData];
		[data appendBytes:"\xFF" length:1];
	}
	
	dispatch_async(_websocketQueue, ^{ @autoreleasepool {
        if (_state == kWebSocketOpen) {
            if (tag == TAG_MESSAGE) {
                _writeQueueSize += 1; // data.length would be better
            }
            [_asyncSocket writeData:data withTimeout:_timeout tag: tag];
            if (tag == TAG_MESSAGE && _writeQueueSize <= HUNGRY_SIZE)
                [self isHungry];
        }
    }});
}

- (void) finishedSendingFrame {
    _writeQueueSize -= 1; // data.length would be better but we don't know it anymore
    if (_writeQueueSize <= HUNGRY_SIZE)
        [self isHungry];
}

- (void) isHungry {
	HTTPLogTrace();
	// Notify delegate
    id<WebSocketDelegate> delegate = _delegate;
	if ([delegate respondsToSelector:@selector(webSocketIsHungry:)])
		[delegate webSocketIsHungry:self];
}

#pragma mark - RECEIVING MESSAGES:

- (BOOL) didReceiveFrame: (NSData*)frame type: (NSUInteger)type {
	HTTPLogTrace();
    switch (type) {
        case WS_OP_TEXT_FRAME: {
            NSString *msg = [[NSString alloc] initWithData: frame encoding: NSUTF8StringEncoding];
            [self didReceiveMessage: msg];
            return YES;
        }
        case WS_OP_BINARY_FRAME:
            [self didReceiveBinaryMessage:frame];
            return YES;
        case WS_OP_PING:
            [self sendFrame: frame type: WS_OP_PONG tag: 0];
            return YES;
        case WS_OP_PONG:
            return YES;
        case WS_OP_CONNECTION_CLOSE:
            if (_state >= kWebSocketClosing) {
                // This is presumably an echo of the close frame I sent; time to stop:
                [self disconnect];
            } else {
                // Peer requested a close, so echo it and then stop:
                [self sendFrame: frame type: WS_OP_CONNECTION_CLOSE tag: TAG_STOP];
                self.state = kWebSocketClosing;
            }
            return NO;
        default:
			[self didCloseWithCode: kWebSocketCloseProtocolError
                            reason: @"Unsupported frame type"];
            return NO;
    }
}

- (void)didReceiveMessage:(NSString *)msg {
	HTTPLogTrace();

	// Override me to process incoming messages.
	// This method is invoked on the websocketQueue.
	//
	// For completeness, you should invoke [super didReceiveMessage:msg] in your method.

	// Notify delegate
    id<WebSocketDelegate> delegate = _delegate;
	if ([delegate respondsToSelector:@selector(webSocket:didReceiveMessage:)]) {
		if (![delegate webSocket:self didReceiveMessage:msg])
            [self _setReadPaused: YES];
	}
}

- (void)didReceiveBinaryMessage:(NSData *)msg {
	HTTPLogTrace();

	// Override me to process incoming messages.
	// This method is invoked on the websocketQueue.
	//
	// For completeness, you should invoke [super didReceiveBinaryMessage:msg] in your method.

	// Notify delegate
    id<WebSocketDelegate> delegate = _delegate;
	if ([delegate respondsToSelector:@selector(webSocket:didReceiveBinaryMessage:)]) {
		if (![delegate webSocket:self didReceiveBinaryMessage:msg])
            [self _setReadPaused: YES];
	}
}

- (void) startReadingNextMessage {
    if (_readyToReadMessage && !_readPaused && _state == kWebSocketOpen) {
        _readyToReadMessage = NO;
        [_asyncSocket readDataToLength:1 withTimeout:_timeout
                                   tag:(_isRFC6455 ? TAG_PAYLOAD_PREFIX : TAG_PREFIX)];
    }
}

- (BOOL) readPaused {
    __block BOOL result;
    dispatch_sync(_websocketQueue, ^{
        result = _readPaused;
    });
    return result;
}

- (void) setReadPaused: (BOOL)paused {
    dispatch_async(_websocketQueue, ^{
        [self _setReadPaused: paused];
    });
}

- (void) _setReadPaused: (BOOL)paused {
    _readPaused = paused;
    if (!paused)
        [self startReadingNextMessage];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark AsyncSocket Delegate
///////////////////////////////////////////////////////////////////////////////////////////////////


- (void)socket:(GCDAsyncSocket *)sock
        didReceiveTrust:(SecTrustRef)trust
        completionHandler:(void (^)(BOOL shouldTrustPeer))completionHandler
{
    // This only gets called if the SSL settings disable regular cert validation.
    SecTrustEvaluateAsync(trust, dispatch_get_main_queue(),
                          ^(SecTrustRef trustRef, SecTrustResultType result)
    {
        BOOL ok;
        id<WebSocketDelegate> delegate = _delegate;
        if ([delegate respondsToSelector: @selector(webSocket:shouldSecureWithTrust:)]) {
            ok = [delegate webSocket: self shouldSecureWithTrust: trust];
        } else {
            ok = (result == kSecTrustResultProceed || result == kSecTrustResultUnspecified);
        }
        completionHandler(ok);
    });
}

// 0                   1                   2                   3
// 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
// +-+-+-+-+-------+-+-------------+-------------------------------+
// |F|R|R|R| opcode|M| Payload len |    Extended payload length    |
// |I|S|S|S|  (4)  |A|     (7)     |             (16/64)           |
// |N|V|V|V|       |S|             |   (if payload len==126/127)   |
// | |1|2|3|       |K|             |                               |
// +-+-+-+-+-------+-+-------------+ - - - - - - - - - - - - - - - +
// |     Extended payload length continued, if payload len == 127  |
// + - - - - - - - - - - - - - - - +-------------------------------+
// |                               |Masking-key, if MASK set to 1  |
// +-------------------------------+-------------------------------+
// | Masking-key (continued)       |          Payload Data         |
// +-------------------------------- - - - - - - - - - - - - - - - +
// :                     Payload Data continued ...                :
// + - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - +
// |                     Payload Data continued ...                |
// +---------------------------------------------------------------+

- (BOOL)isValidWebSocketFrame:(UInt8)frame {
	NSUInteger rsv =  frame & 0x70;
	NSUInteger opcode = frame & 0x0F;
	return ! ((rsv || (3 <= opcode && opcode <= 7) || (0xB <= opcode && opcode <= 0xF)));
}

- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag {
	HTTPLogTrace();
	
	if (tag == TAG_PREFIX) {
		UInt8 *pFrame = (UInt8 *)[data bytes];
		UInt8 frame = *pFrame;
		
		if (frame <= 0x7F) {
			[_asyncSocket readDataToData: kTerminator withTimeout:_timeout tag:TAG_MSG_PLUS_SUFFIX];
		} else {
			// Unsupported frame type
			[self didCloseWithCode: kWebSocketCloseProtocolError
                            reason: @"Unsupported frame type"];
		}
	} else if (tag == TAG_PAYLOAD_PREFIX) {
		UInt8 *pFrame = (UInt8 *)[data bytes];
		UInt8 frame = *pFrame;

		if ([self isValidWebSocketFrame: frame]) {
			_nextOpCode = (frame & 0x0F);
			[_asyncSocket readDataToLength:1 withTimeout:_timeout tag:TAG_PAYLOAD_LENGTH];
		} else {
			// Unsupported frame type
			[self didCloseWithCode: kWebSocketCloseProtocolError
                            reason: @"Invalid incoming frame"];
		}
	} else if (tag == TAG_PAYLOAD_LENGTH) {
		UInt8 frame = *(UInt8 *)[data bytes];
		BOOL masked = WS_PAYLOAD_IS_MASKED(frame);
		NSUInteger length = WS_PAYLOAD_LENGTH(frame);
		_nextFrameMasked = masked;
		_maskingKey = nil;
        if (length <= 125) {
			if (_nextFrameMasked)
			{
				[_asyncSocket readDataToLength:4 withTimeout:_timeout tag:TAG_MSG_MASKING_KEY];
			}
            if (length > 0) {
                [_asyncSocket readDataToLength:length withTimeout:_timeout tag:TAG_MSG_WITH_LENGTH];
            } else {
                // Special case: zero-length payload doesn't need any read call at all
                [self socket: sock didReadData: [NSData data] withTag: TAG_MSG_WITH_LENGTH];
            }
		} else if (length == 126) {
			[_asyncSocket readDataToLength:2 withTimeout:_timeout tag:TAG_PAYLOAD_LENGTH16];
		} else {
			[_asyncSocket readDataToLength:8 withTimeout:_timeout tag:TAG_PAYLOAD_LENGTH64];
		}
	} else if (tag == TAG_PAYLOAD_LENGTH16) {
		UInt8 *pFrame = (UInt8 *)[data bytes];
		NSUInteger length = ((NSUInteger)pFrame[0] << 8) | (NSUInteger)pFrame[1];
		if (_nextFrameMasked) {
			[_asyncSocket readDataToLength:4 withTimeout:_timeout tag:TAG_MSG_MASKING_KEY];
		}
		[_asyncSocket readDataToLength:length withTimeout:_timeout tag:TAG_MSG_WITH_LENGTH];
	} else if (tag == TAG_PAYLOAD_LENGTH64) {
		// TODO: 64bit data size in memory?
        [self didCloseWithCode: kWebSocketClosePolicyError
                        reason: @"Oops, 64-bit frame size not yet supported"];
	} else if (tag == TAG_MSG_WITH_LENGTH) {
		NSUInteger msgLength = [data length];
		if (_nextFrameMasked && _maskingKey) {
			NSMutableData *masked = data.mutableCopy;
            maskBytes(masked, 0, msgLength, _maskingKey.bytes);
			data = masked;
		}
        _readyToReadMessage = YES;
        if ([self didReceiveFrame: data type: _nextOpCode]) {
            // Read next frame
            [self startReadingNextMessage];
        }
	} else if (tag == TAG_MSG_MASKING_KEY) {
		_maskingKey = data.copy;
	} else {
		NSUInteger msgLength = [data length] - 1; // Excluding ending 0xFF frame
		NSString *msg = [[NSString alloc] initWithBytes:[data bytes] length:msgLength encoding:NSUTF8StringEncoding];
        _readyToReadMessage = YES;
		[self didReceiveMessage:msg];
        // Read next message
        [self startReadingNextMessage];
	}
}

- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag {
	HTTPLogTrace();
    if (tag == TAG_STOP) {
        [self disconnect];
    } else if (tag == TAG_MESSAGE) {
        [self finishedSendingFrame];
    }
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)error {
	HTTPLogTraceWith("error= %@", error.localizedDescription);
    if ([error.domain isEqualToString: @"kCFStreamErrorDomainSSL"]) {
        // This is CGDAsyncSocket returning a SecureTransport error code. Map to NSURLError:
        NSInteger urlCode;
        switch (error.code) {
            case errSSLXCertChainInvalid:
            case errSSLUnknownRootCert:
                urlCode = NSURLErrorServerCertificateUntrusted;
                break;
            case errSSLNoRootCert:
                urlCode = NSURLErrorServerCertificateHasUnknownRoot;
                break;
            case errSSLCertExpired:
                urlCode = NSURLErrorServerCertificateHasBadDate;
                break;
            case errSSLCertNotYetValid:
                urlCode = NSURLErrorServerCertificateNotYetValid;
                break;
            default:
                urlCode = NSURLErrorSecureConnectionFailed;
                break;
        }
        error = [NSError errorWithDomain: NSURLErrorDomain
                                    code: urlCode
                                userInfo: @{NSUnderlyingErrorKey: error}];
    }
    [self didCloseWithError: error];
}

@end
