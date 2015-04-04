//
//  WebSocketListener.m
//  WebSocket
//
//  Created by Jens Alfke on 9/16/13.
//  Copyright (c) 2013 Couchbase. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "WebSocketListener.h"
#import "WebSocket_Internal.h"
#import "GCDAsyncSocket.h"
#import "DDData.h"
#import "CollectionUtils.h"
#import "Logging.h"
#import "MYURLUtils.h"


@interface WebSocketListener () <GCDAsyncSocketDelegate>
@end


@implementation WebSocketListener
{
    NSString* _path;
    NSString* _desc;
    GCDAsyncSocket* _listenerSocket;
    __weak id<WebSocketDelegate> _delegate;
    NSMutableSet* _connections;
}


@synthesize path=_path;


- (instancetype) initWithPath: (NSString*)path delegate: (id<WebSocketDelegate>)delegate {
    self = [super init];
    if (self) {
        _path = path;
        _delegate = delegate;
        _desc = path;
        dispatch_queue_t delegateQueue = dispatch_queue_create("WebSocketListener", 0);
        _listenerSocket = [[GCDAsyncSocket alloc] initWithDelegate: self
                                                     delegateQueue: delegateQueue];
        _connections = [[NSMutableSet alloc] init];
    }
    return self;
}


- (NSString*) description {
    return [NSString stringWithFormat: @"%@[%@]", self.class, _desc];
}



- (BOOL) acceptOnInterface: (NSString*)interface
                      port: (UInt16)port
                     error: (NSError**)outError
{
    if (![_listenerSocket acceptOnInterface: interface port: port error: outError])
        return NO;
    _desc = $sprintf(@"%@:%d%@", (interface ?: @""), port, _path);
    LogTo(WS, @"%@ now listening on port %d", self, port);
    return YES;
}


- (void) disconnect {
    [_listenerSocket disconnect];
}


- (void)socket:(GCDAsyncSocket *)sock didAcceptNewSocket:(GCDAsyncSocket *)newSocket {
    WebSocketIncoming* ws = [[WebSocketIncoming alloc] initWithConnectedSocket: newSocket
                                                                      delegate: _delegate];
    ws.listener = self;
    LogTo(WS, @"Opened incoming %@ with delegate %@", ws, ws.delegate);
    [_connections addObject: ws];
}

@end




@implementation WebSocketIncoming

@synthesize listener=_listener;

- (void)dealloc
{
    LogTo(WS, @"DEALLOC %@", self);
}

- (void) didOpen {
    // When the underlying socket opens, start reading the incoming HTTP request,
    // but don't call the inherited -isOpen till we're ready to talk WebSocket protocol.

    [_asyncSocket readDataToData: [@"\r\n\r\n" dataUsingEncoding: NSASCIIStringEncoding]
                     withTimeout: self.timeout
                             tag: TAG_HTTP_REQUEST_HEADERS];
}


static NSString* getHeader(CFHTTPMessageRef msg, NSString* header) {
    return CFBridgingRelease(CFHTTPMessageCopyHeaderFieldValue(msg, (__bridge CFStringRef)header));
}

static BOOL checkHeader(CFHTTPMessageRef msg, NSString* header, NSString* expected, BOOL caseSens) {
    NSString* value = getHeader(msg, header);
    if (caseSens)
        return [value isEqualToString: expected];
    else
        return value && [value caseInsensitiveCompare: expected] == 0;
}


- (void) gotHTTPRequest: (CFHTTPMessageRef)httpRequest data: (NSData*)requestData {
    HTTPLogTrace();
    //NSLog(@"Got HTTP request:\n%@", [[NSString alloc] initWithData: requestData encoding:NSUTF8StringEncoding]);
    if (!CFHTTPMessageAppendBytes(httpRequest, requestData.bytes, requestData.length) ||
            !CFHTTPMessageIsHeaderComplete(httpRequest)) {
        // Error reading request!
        LogTo(WS, @"Unreadable HTTP request:\n%@", requestData.my_UTF8ToString);
        [_asyncSocket disconnect];
        [self didCloseWithCode: kWebSocketCloseProtocolError
                        reason: @"Unreadable HTTP request"];
        return;
    }

    NSString* method = CFBridgingRelease(CFHTTPMessageCopyRequestMethod(httpRequest));
    NSURL* url = CFBridgingRelease(CFHTTPMessageCopyRequestURL(httpRequest));

    int status;
    NSString* statusText = @"";
    NSString* acceptStr;
    if (![url.path isEqualToString: _listener.path]) {
        status = 404;
        statusText = @"Not found";
    } else if (![method isEqualToString: @"GET"]) {
        status = 405;
        statusText = @"Unsupported method";
    } else if (!checkHeader(httpRequest, @"Connection", @"Upgrade", NO)
            || !checkHeader(httpRequest, @"Upgrade", @"websocket", NO)) {
        status = 400;
        statusText = @"Invalid upgrade request";
    } else if (!checkHeader(httpRequest, @"Sec-WebSocket-Version", @"13", YES)) {
        status = 426;
        statusText = @"Unsupported WebSocket protocol version";
    } else {
        NSString* nonceKey = getHeader(httpRequest, @"Sec-WebSocket-Key");
        if (nonceKey.length != 24) {
            status = 400;
            statusText = @"Invalid/missing Sec-WebSocket-Key header";
        } else {
            // Ask the delegate;
            status = [self statusForHTTPRequest: httpRequest];
            if (status >= 300) {
                statusText = @"Connection refused";
            } else {
                // Accept it!
                status = 101;
                acceptStr = [nonceKey stringByAppendingString: @"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"];
                acceptStr = [[[acceptStr dataUsingEncoding: NSASCIIStringEncoding] sha1Digest] base64Encoded];
            }
        }
    }

    // Write the HTTP response:
    NSMutableString* response = [NSMutableString stringWithFormat:
                                 @"HTTP/1.1 %d %@\r\n"
                                 "Server: CocoaWebSocket\r\n"
                                 "Sec-WebSocket-Version: 13\r\n",
                                 status, statusText];
    if (status == 101) {
        [response appendFormat: @"Connection: Upgrade\r\n"
                                 "Upgrade: websocket\r\n"
                                 "Sec-WebSocket-Accept: %@\r\n",
                                 acceptStr];
    }
    [response appendString: @"\r\n"];
    [_asyncSocket writeData: [response dataUsingEncoding: NSUTF8StringEncoding]
                withTimeout: self.timeout tag: TAG_HTTP_RESPONSE_HEADERS];

    if (status != 101) {
        [_asyncSocket disconnectAfterWriting];
        [self didCloseWithCode: kWebSocketCloseProtocolError
                        reason: $sprintf(@"Invalid HTTP request: %@", statusText)];
        return;
    }

    // Now I can finally tell the delegate I'm open (see explanation in my -didOpen method.)
    LogTo(WS, @"Accepted incoming connection");
    [super didOpen];
}


- (int) statusForHTTPRequest: (CFHTTPMessageRef)httpRequest {
    int status = 101;
    if ([_delegate respondsToSelector: @selector(webSocket:shouldAccept:)]) {
        NSURL* url = CFBridgingRelease(CFHTTPMessageCopyRequestURL(httpRequest));
        NSDictionary* headers = CFBridgingRelease(CFHTTPMessageCopyAllHeaderFields(httpRequest));
        NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL: url];
        for (NSString* header in headers)
            [request setValue: headers[header] forHTTPHeaderField: header];
        status = [_delegate webSocket: self shouldAccept: request];
        if (status == NO)
            status = 403;
        else if (status == YES)
            status = 101;
    }
    return status;
}


- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag {
    if (tag == TAG_HTTP_REQUEST_HEADERS) {
        // HTTP request received:
        CFHTTPMessageRef httpRequest = CFHTTPMessageCreateEmpty(NULL, true);
        [self gotHTTPRequest: httpRequest data: data];
        CFRelease(httpRequest);
    } else {
        [super socket: sock didReadData: data withTag: tag];
    }
}


- (NSURL*) URL {
    return $url($sprintf(@"ws://%@:%d/", _asyncSocket.connectedHost, _asyncSocket.connectedPort));
}


@end
