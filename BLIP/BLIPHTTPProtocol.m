//
//  BLIPHTTPProtocol.m
//  WebSocket
//
//  Created by Jens Alfke on 4/15/13.
//  Copyright (c) 2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "BLIPHTTPProtocol.h"
#import "BLIPWebSocket.h"
#import "BLIPPool.h"
#import "BLIPRequest+HTTP.h"

#import "CollectionUtils.h"
#import "Logging.h"


@interface BLIPHTTPProtocol () <BLIPMessageDataDelegate>
@end


@implementation BLIPHTTPProtocol
{
    NSURL* _webSocketURL;
    BLIPResponse* _response;
    BOOL _gotHeaders;
    NSMutableData* _responseBody;
}


static NSMutableDictionary* sMappings;
static NSMutableSet* sMappedHosts;

static BLIPPool* sSockets;


+ (void) registerWebSocketURL: (NSURL*)wsURL forURL: (NSURL*)baseURL {
    @synchronized(self) {
        if (!sMappings) {
            [NSURLProtocol registerClass: self];
            sMappings = [[NSMutableDictionary alloc] init];
        }
        if (!sMappedHosts)
            sMappedHosts = [[NSMutableSet alloc] init];
        sMappings[baseURL.absoluteString] = wsURL;
        [sMappedHosts addObject: baseURL.host];
    }
}


static inline bool urlPrefixMatch(NSString* prefix, NSString* urlString) {
    if (![urlString hasPrefix: prefix])
        return false;
    if (urlString.length == prefix.length || [prefix hasSuffix: @"/"])
        return true;
    // Make sure there's a path component boundary after the prefix:
    unichar nextChar = nextChar = [urlString characterAtIndex: prefix.length];
    return (nextChar == '/' || nextChar == '?' || nextChar == '#');
}


// Returns the HTTP URL to use to connect to the WebSocket server.
+ (NSURL*) webSocketURLForURL: (NSURL*)url {
    @synchronized(self) {
        if (![sMappedHosts containsObject: url.host]) // quick shortcut
            return nil;
        NSString* urlString = [url absoluteString];
        for (NSString* prefix in sMappings) {
            if (urlPrefixMatch(prefix, urlString))
                return sMappings[prefix];
        }
        return nil;
    }
}


#pragma mark - INITIALIZATION:


+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    return [self webSocketURLForURL: request.URL] != nil;
}


+ (NSURLRequest*) canonicalRequestForRequest: (NSURLRequest*)request {
    return request;
}


- (instancetype) initWithRequest:(NSURLRequest *)request
                  cachedResponse:(NSCachedURLResponse *)cachedResponse
                          client:(id <NSURLProtocolClient>)client
{
    self = [super initWithRequest: request cachedResponse: cachedResponse client:client];
    if (self) {
        _webSocketURL = [[self class] webSocketURLForURL: self.request.URL];
        if (!_webSocketURL) {
            return nil;
        }
    }
    return self;
}



- (void) startLoading {
    if (!sSockets)
        sSockets = [[BLIPPool alloc] initWithDelegate: nil
                                        dispatchQueue: dispatch_get_current_queue()];
    NSError* error;
    BLIPWebSocket* socket = [sSockets socketToURL: _webSocketURL error: &error];
    if (!socket) {
        [self.client URLProtocol: self didFailWithError: error];
        return;
    }
    _response = [socket sendRequest: [BLIPRequest requestWithHTTPRequest: self.request]];
    _response.dataDelegate = self;
}


- (void)stopLoading {
    // The Obj-C BLIP API has no way to stop a request, so just ignore its data:
    _response.dataDelegate = nil;
    _response = nil;
}


- (void) blipMessage: (BLIPMessage*)msg didReceiveData: (NSData*)data {
    id<NSURLProtocolClient> client = self.client;
    NSError* error = _response.error;
    if (error) {
        [client URLProtocol: self didFailWithError: error];
        return;
    }

    if (!_gotHeaders) {
        if (!_responseBody)
            _responseBody = [data mutableCopy];
        else
            [_responseBody appendData: data];

        NSData* body = nil;
        NSURLResponse* response = [_response asHTTPResponseWithBody: &body
                                                             forURL: self.request.URL];
        if (response) {
            _gotHeaders = YES;
            [client URLProtocol: self didReceiveResponse: response
                    cacheStoragePolicy: NSURLCacheStorageNotAllowed];
        }
        data = body;
    }

    if (data.length > 0)
        [client URLProtocol: self didLoadData: data];

    if (msg.complete)
        [client URLProtocolDidFinishLoading: self];
}


@end
