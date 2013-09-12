//
//  BLIPHTTPProtocol.m
//  MYNetwork
//
//  Created by Jens Alfke on 4/15/13.
//
//

#import "BLIPHTTPProtocol.h"
#import "BLIPWebSocket.h"
#import "BLIPRequest+HTTP.h"

#import "CollectionUtils.h"
#import "Logging.h"
#import "Target.h"


@implementation BLIPHTTPProtocol
{
    NSURL* _webSocketURL;
    BLIPResponse* _response;
}


static NSMutableDictionary* sMappings;
static NSMutableSet* sMappedHosts;

static NSMutableDictionary* sSockets;


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


// Returns an open BLIPWebSocket to use to communicate with a given wshttp: URL.
+ (BLIPWebSocket*) connectionToURL: (NSURL*)url {
    @synchronized(self) {
        if (!sSockets)
            sSockets = [[NSMutableDictionary alloc] init];
        BLIPWebSocket* socket = sSockets[url];
        if (!socket) {
            socket = [[BLIPWebSocket alloc] initWithURL: url];
            sSockets[url] = socket;
            [socket open];
        }
        return socket;
    }
}


#pragma mark - INITIALIZATION:


+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    return [self webSocketURLForURL: request.URL] != nil;
}


+ (NSURLRequest*) canonicalRequestForRequest: (NSURLRequest*)request {
    return request;
}


- (id)initWithRequest:(NSURLRequest *)request
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
        sSockets = [[NSMutableDictionary alloc] init];
    BLIPWebSocket* socket = [[self class] connectionToURL: _webSocketURL];

    _response = [socket sendRequest: [BLIPRequest requestWithHTTPRequest: self.request]];
    _response.onComplete = $target(self, onComplete:);
}


- (void)stopLoading {
    // The Obj-C BLIP API has no way to stop a request, so just ignore its data:
    _response.onComplete = nil;
    _response = nil;
}


- (void) onComplete: (id)sender {
    id<NSURLProtocolClient> client = self.client;
    NSError* error = _response.error;
    if (error) {
        [client URLProtocol: self didFailWithError: error];
        return;
    }

    NSData* body;
    NSURLResponse* response = [_response asHTTPResponseWithBody: &body forURL: self.request.URL];

    [client URLProtocol: self didReceiveResponse: response
         cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    if (body.length > 0)
        [client URLProtocol: self didLoadData: body];
    [client URLProtocolDidFinishLoading: self];
}


@end
