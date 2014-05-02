//
//  WebSocketClient.m
//  WebSocket
//
//  Created by Jens Alfke on 9/10/13.
//  Copyright (c) 2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "WebSocketClient.h"
#import "WebSocket_Internal.h"
#import "WebSocketHTTPLogic.h"
#import "GCDAsyncSocket.h"
#import "DDData.h"

#import <Security/SecRandom.h>


@implementation WebSocketClient
{
    GCDAsyncSocket* _httpSocket;
    WebSocketHTTPLogic *_logic;
    NSArray* _protocols;
    NSString* _nonceKey;
}


@synthesize credential=_credential;


- (instancetype) initWithURLRequest:(NSURLRequest *)urlRequest {
    self = [super init];
    if (self) {
        _isClient = YES;
        _logic = [[WebSocketHTTPLogic alloc] initWithURLRequest: urlRequest];
        _logic.handleRedirects = YES;
        self.timeout = urlRequest.timeoutInterval;
    }
    return self;
}

- (instancetype) initWithURL:(NSURL*)url {
    return [self initWithURLRequest: [NSURLRequest requestWithURL: url]];
}

- (void)dealloc {
    HTTPLogTrace();
    [_httpSocket setDelegate:nil delegateQueue:NULL];
    [_httpSocket disconnect];
}


- (NSURL*) URL {
    return _logic.URL;
}


- (BOOL) connect: (NSError**)outError {
    __block BOOL result = NO;
	dispatch_sync(_websocketQueue, ^{
        result = [self _connect: outError];
    });
    return result;
}


// called on the _websocketQueue
- (BOOL) _connect: (NSError**)outError {
    HTTPLogTrace();
    NSParameterAssert(!_asyncSocket);
    NSParameterAssert(!_httpSocket);
    NSURL* url = _logic.URL;
    _httpSocket = [[GCDAsyncSocket alloc] initWithDelegate: self
                                             delegateQueue: _websocketQueue];
    [_httpSocket setDelegate:self delegateQueue:_websocketQueue];
    if (![_httpSocket connectToHost: url.host
                             onPort: (UInt16)(url.port ?url.port.intValue : 80)
                        withTimeout: self.timeout
                              error: outError]) {
        return NO;
    }

    if ([url.scheme caseInsensitiveCompare: @"https"] == 0)
        [_httpSocket startTLS: @{(id)kCFStreamSSLPeerName: url.host}];

    // Configure the nonce/key for the request:
    uint8_t nonceBytes[16];
    SecRandomCopyBytes(kSecRandomDefault, sizeof(nonceBytes), nonceBytes);
    NSData* nonceData = [NSData dataWithBytes: nonceBytes length: sizeof(nonceBytes)];
    _nonceKey = [nonceData base64Encoded];

    // Construct the HTTP request:
    _logic[@"Connection"] = @"Upgrade";
    _logic[@"Upgrade"] = @"websocket";
    _logic[@"Sec-WebSocket-Version"] = @"13";
    _logic[@"Sec-WebSocket-Key"] = _nonceKey;
    if (_protocols)
        _logic[@"Sec-WebSocket-Protocol"] = [_protocols componentsJoinedByString: @","];

    CFHTTPMessageRef httpMsg = [_logic newHTTPRequest];
    NSData* requestData = CFBridgingRelease(CFHTTPMessageCopySerializedMessage(httpMsg));
    CFRelease(httpMsg);

    // Send the request and await the response:
    //NSLog(@"Sending HTTP request:\n%@", [[NSString alloc] initWithData: requestData encoding:NSUTF8StringEncoding]);
    [_httpSocket writeData: requestData withTimeout: self.timeout
                        tag: TAG_HTTP_REQUEST_HEADERS];
    [_httpSocket readDataToData: [@"\r\n\r\n" dataUsingEncoding: NSASCIIStringEncoding]
                     withTimeout: self.timeout
                             tag: TAG_HTTP_RESPONSE_HEADERS];
    return YES;
}


// called on the _websocketQueue
- (void) gotHTTPResponse: (CFHTTPMessageRef)httpResponse data: (NSData*)responseData {
    HTTPLogTrace();
    //NSLog(@"Got HTTP response:\n%@", [[NSString alloc] initWithData: responseData encoding:NSUTF8StringEncoding]);
    if (!CFHTTPMessageAppendBytes(httpResponse, responseData.bytes, responseData.length) ||
            !CFHTTPMessageIsHeaderComplete(httpResponse)) {
        // Error reading response!
        [self didCloseWithCode: kWebSocketCloseProtocolError
                        reason: @"Unreadable HTTP response"];
        return;
    }

    [_logic receivedResponse: httpResponse];
    if (_logic.shouldRetry) {
        // Retry the connection, due to a redirect or auth challenge:
        [_httpSocket setDelegate:nil delegateQueue:NULL];
        [_httpSocket disconnect];
        _httpSocket = nil;
        [self _connect: NULL];
        return;
    }

    NSInteger httpStatus = _logic.httpStatus;
    if (httpStatus != 101) {
        WebSocketCloseCode closeCode = kWebSocketClosePolicyError;
        if (httpStatus >= 300 && httpStatus < 1000)
            closeCode = (WebSocketCloseCode)httpStatus;
        NSString* reason = CFBridgingRelease(CFHTTPMessageCopyResponseStatusLine(httpResponse));
        [self didCloseWithCode: closeCode reason: reason];
        return;
    } else if (!checkHeader(httpResponse, @"Connection", @"Upgrade", NO)) {
        [self didCloseWithCode: kWebSocketCloseProtocolError
                        reason: @"Invalid 'Connection' header"];
        return;
    } else if (!checkHeader(httpResponse, @"Upgrade", @"websocket", NO)) {
        [self didCloseWithCode: kWebSocketCloseProtocolError
                        reason: @"Invalid 'Upgrade' header"];
        return;
    }

    // Compute the value for the Sec-WebSocket-Accept header:
    NSString* str = [_nonceKey stringByAppendingString: @"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"];
    str = [[[str dataUsingEncoding: NSASCIIStringEncoding] sha1Digest] base64Encoded];

    if (!checkHeader(httpResponse, @"Sec-WebSocket-Accept", str, YES)) {
        [self didCloseWithCode: kWebSocketCloseProtocolError
                        reason: @"Invalid 'Sec-WebSocket-Accept' header"];
        return;
    }

    // TODO: Check Sec-WebSocket-Extensions for unknown extensions

    // Now I can hook up the socket as my asyncSocket and start the WebSocket protocol:
    _asyncSocket = _httpSocket;
    _httpSocket = nil;
    [self start];
}


// called on the _websocketQueue
- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag {
    if (sock == _httpSocket) {
        if (tag == TAG_HTTP_RESPONSE_HEADERS) {
            // HTTP response received:
            CFHTTPMessageRef httpResponse = CFHTTPMessageCreateEmpty(NULL, false);
            [self gotHTTPResponse: httpResponse data: data];
            CFRelease(httpResponse);
        }
    } else {
        [super socket: sock didReadData: data withTag: tag];
    }
}


// Tests whether a header value matches the expected string.
static BOOL checkHeader(CFHTTPMessageRef msg, NSString* header, NSString* expected, BOOL caseSens) {
    NSString* value = CFBridgingRelease(CFHTTPMessageCopyHeaderFieldValue(msg,
                                                                  (__bridge CFStringRef)header));
    if (caseSens)
        return [value isEqualToString: expected];
    else
        return value && [value caseInsensitiveCompare: expected] == 0;
}


@end
