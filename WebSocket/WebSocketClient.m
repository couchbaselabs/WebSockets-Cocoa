//
//  WebSocketClient.m
//  WebSocket
//
//  Created by Jens Alfke on 9/10/13.
//
//

#import "WebSocketClient.h"
#import "WebSocket_Internal.h"
#import "GCDAsyncSocket.h"
#import "DDData.h"

#import <Security/SecRandom.h>


enum {
    TAG_HTTP_REQUEST_HEADERS = 300,
    TAG_HTTP_RESPONSE_HEADERS,
};


@implementation WebSocketClient
{
    NSURLRequest* _urlRequest;
    NSArray* _protocols;
    NSString* _nonceKey;
}


- (id)initWithURLRequest:(NSURLRequest *)urlRequest {
    self = [super init];
    if (self) {
        _urlRequest = urlRequest;
        _isClient = YES;
        self.timeout = urlRequest.timeoutInterval;
        if ([urlRequest.URL.scheme caseInsensitiveCompare: @"https"] == 0)
           [self useTLS: @{}];  // default TLS settings
    }
    return self;
}

- (id)initWithURL:(NSURL*)url {
    return [self initWithURLRequest: [NSURLRequest requestWithURL: url]];
}


- (BOOL) connect: (NSError**)outError {
    NSParameterAssert(!_asyncSocket);

    NSURL* url = _urlRequest.URL;
    GCDAsyncSocket* socket = [[GCDAsyncSocket alloc] initWithDelegate: self
                                                        delegateQueue: _websocketQueue];
    if (![socket connectToHost: url.host
                        onPort: (url.port.intValue ?: 80)
                   withTimeout: self.timeout
                         error: outError]) {
        return NO;
    }
    self.asyncSocket = socket;
    [super start];
    return YES;
}


- (NSURL*) URL {
    return _urlRequest.URL;
}


#pragma mark - CONNECTION:


- (void) didOpen {
    HTTPLogTrace();

    // Now that the underlying socket has opened, send the HTTP request and wait for the
    // HTTP response. I do *not* call [super didOpen] until I receive the response, because the
    // WebSocket isn't ready for business till then.

    // Create the "Host" header:
    NSURL* url = _urlRequest.URL;
    NSString* host = url.host;
    if (url.port)
        host = [host stringByAppendingFormat: @":%@", url.port];

    // Configure the nonce/key for the request:
    uint8_t nonceBytes[16];
    SecRandomCopyBytes(kSecRandomDefault, sizeof(nonceBytes), nonceBytes);
    NSData* nonceData = [NSData dataWithBytes: nonceBytes length: sizeof(nonceBytes)];
    _nonceKey = [nonceData base64Encoded];

    // http://tools.ietf.org/html/rfc6455#section-4.1
    CFHTTPMessageRef httpMsg = CFHTTPMessageCreateRequest(NULL, CFSTR("GET"),
                                                          (__bridge CFURLRef)url,
                                                          kCFHTTPVersion1_1);
    NSMutableDictionary* headers = _urlRequest.allHTTPHeaderFields.mutableCopy;
    if (!headers)
        headers = [NSMutableDictionary dictionary];
    headers[@"Host"] = host;
    headers[@"Connection"] = @"Upgrade";
    headers[@"Upgrade"] = @"websocket";
    headers[@"Sec-WebSocket-Version"] = @"13";
    headers[@"Sec-WebSocket-Key"] = _nonceKey;
    if (_protocols)
        headers[@"Sec-WebSocket-Protocol"] = [_protocols componentsJoinedByString: @","];
    for (NSString* header in headers)
        CFHTTPMessageSetHeaderFieldValue(httpMsg, (__bridge CFStringRef)header,
                                                  (__bridge CFStringRef)headers[header]);

    NSData* requestData = CFBridgingRelease(CFHTTPMessageCopySerializedMessage(httpMsg));
    NSLog(@"Sending HTTP request:\n%@", [[NSString alloc] initWithData: requestData encoding:NSUTF8StringEncoding]);
    [_asyncSocket writeData: requestData withTimeout: self.timeout
                        tag: TAG_HTTP_REQUEST_HEADERS];
    [_asyncSocket readDataToData: [@"\r\n\r\n" dataUsingEncoding: NSASCIIStringEncoding]
                     withTimeout: self.timeout
                             tag: TAG_HTTP_RESPONSE_HEADERS];
}


static BOOL checkHeader(CFHTTPMessageRef msg, NSString* header, NSString* expected, BOOL caseSens) {
    NSString* value;
    value = CFBridgingRelease(CFHTTPMessageCopyHeaderFieldValue(msg, (__bridge CFStringRef)header));
    if (caseSens)
        return [value isEqualToString: expected];
    else
        return value && [value caseInsensitiveCompare: expected] == 0;
}


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

    CFIndex httpStatus = CFHTTPMessageGetResponseStatusCode(httpResponse);
    if (httpStatus != 101) {
        // TODO: Handle other responses, i.e. 401 or 30x
        NSString* reason = CFBridgingRelease(CFHTTPMessageCopyResponseStatusLine(httpResponse));
        [self didCloseWithCode: (httpStatus < 1000 ? httpStatus : kWebSocketClosePolicyError)
                        reason: reason];
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

    // Now I can finally tell the delegate I'm open (see explanation in my -didOpen method.)
    [super didOpen];
}


- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag {
    if (tag == TAG_HTTP_RESPONSE_HEADERS) {
        // HTTP response received:
        CFHTTPMessageRef httpResponse = CFHTTPMessageCreateEmpty(NULL, false);
        [self gotHTTPResponse: httpResponse data: data];
        CFRelease(httpResponse);
    } else {
        [super socket: sock didReadData: data withTag: tag];
    }
}


@end
