//
//  BLIPRequest+HTTP.m
//  WebSocket
//
//  Created by Jens Alfke on 4/15/13.
//
//

#import "BLIPRequest+HTTP.h"
#import "BLIP_Internal.h"
#import "Test.h"


@implementation BLIPRequest (HTTP)


static NSSet* kIgnoredHeaders;


+ (instancetype) requestWithHTTPRequest: (NSURLRequest*)req {
    if (!kIgnoredHeaders) {
        kIgnoredHeaders = [NSSet setWithObjects: @"host", nil];
    }
    CFHTTPMessageRef msg = CFHTTPMessageCreateRequest(NULL,
                                                      (__bridge CFStringRef)req.HTTPMethod,
                                                      (__bridge CFURLRef)req.URL,
                                                      kCFHTTPVersion1_1);
    NSDictionary* headers = req.allHTTPHeaderFields;
    for (NSString* header in headers) {
        if (![kIgnoredHeaders member: header.lowercaseString]) {
            CFHTTPMessageSetHeaderFieldValue(msg, (__bridge CFStringRef)header,
                                                  (__bridge CFStringRef)headers[header]);
        }
    }
    CFHTTPMessageSetBody(msg, (__bridge CFDataRef)req.HTTPBody);

    NSData* body = CFBridgingRelease(CFHTTPMessageCopySerializedMessage(msg));
    return [self requestWithBody: body
                      properties: @{@"Profile": @"HTTP"}];
}


- (NSURLRequest*) asHTTPRequest {
    NSMutableURLRequest* request = nil;
    CFHTTPMessageRef msg = CFHTTPMessageCreateEmpty(NULL, true);
    if (CFHTTPMessageAppendBytes(msg, self.body.bytes, self.body.length) &&
            CFHTTPMessageIsHeaderComplete(msg)) {
        NSURL* url = CFBridgingRelease(CFHTTPMessageCopyRequestURL(msg));
        request = [[NSMutableURLRequest alloc] initWithURL: url];
        request.HTTPMethod = CFBridgingRelease(CFHTTPMessageCopyRequestMethod(msg));
        request.allHTTPHeaderFields = CFBridgingRelease(CFHTTPMessageCopyAllHeaderFields(msg));
        request.HTTPBody = CFBridgingRelease(CFHTTPMessageCopyBody(msg));
    }
    CFRelease(msg);
    return request;
}


@end





@implementation BLIPResponse (HTTP)

- (void) setHTTPResponse: (NSHTTPURLResponse*)httpResponse
                withBody: (NSData*)httpBody
{
    NSInteger status = httpResponse.statusCode;
    NSString* statusDesc = [NSHTTPURLResponse localizedStringForStatusCode: status];
    CFHTTPMessageRef msg = CFHTTPMessageCreateResponse(NULL,
                                                       status,
                                                       (__bridge CFStringRef)statusDesc,
                                                       kCFHTTPVersion1_1);
    NSDictionary* headers = httpResponse.allHeaderFields;
    for (NSString* header in headers) {
        CFHTTPMessageSetHeaderFieldValue(msg, (__bridge CFStringRef)header,
                                         (__bridge CFStringRef)headers[header]);
    }
    CFHTTPMessageSetBody(msg, (__bridge CFDataRef)httpBody);
    self.profile = @"HTTP";
    self.body = CFBridgingRelease(CFHTTPMessageCopySerializedMessage(msg));
}


- (NSHTTPURLResponse*) asHTTPResponseWithBody: (NSData**)outHTTPBody forURL: (NSURL*)url {
    NSHTTPURLResponse* response = nil;
    CFHTTPMessageRef msg = CFHTTPMessageCreateEmpty(NULL, false);
    if (CFHTTPMessageAppendBytes(msg, self.body.bytes, self.body.length) &&
            CFHTTPMessageIsHeaderComplete(msg)) {
        response = [[NSHTTPURLResponse alloc]
                           initWithURL: url
                            statusCode: CFHTTPMessageGetResponseStatusCode(msg)
                           HTTPVersion: @"HTTP/1.1"
                          headerFields: CFBridgingRelease(CFHTTPMessageCopyAllHeaderFields(msg))];
        if (outHTTPBody)
            *outHTTPBody = CFBridgingRelease(CFHTTPMessageCopyBody(msg));
    }
    CFRelease(msg);
    return response;
}

@end


#if DEBUG

TestCase(HTTPRequest) {
    NSURL* url = [NSURL URLWithString:@"http://example.org/some/path?query=value"];
    NSMutableURLRequest* httpReq = [NSMutableURLRequest requestWithURL: url];
    httpReq.HTTPMethod = @"PUT";
    [httpReq setValue: @"application/json" forHTTPHeaderField: @"Content-Type"];
    httpReq.HTTPBody = [@"{\"foo\"=23}" dataUsingEncoding: NSUTF8StringEncoding];
    BLIPRequest* blipReq = [BLIPRequest requestWithHTTPRequest: httpReq];

    CAssert(blipReq != nil);
    CAssertEqual(blipReq.profile, @"HTTP");
    NSString* expectedBody = @"PUT /some/path?query=value HTTP/1.1\r\nContent-Type: application/json\r\n\r\n{\"foo\"=23}";
    CAssertEqual([[NSString alloc] initWithData: blipReq.body encoding: NSUTF8StringEncoding],
                 expectedBody);

    NSURLRequest* httpReq2 = [blipReq asHTTPRequest];
    CAssert(httpReq2 != nil);
    CAssertEqual(httpReq2.HTTPMethod, @"PUT");
    CAssertEqual(httpReq2.URL.path, @"/some/path");
    CAssertEqual(httpReq2.URL.query, @"query=value");
    CAssertEqual(httpReq2.allHTTPHeaderFields, @{@"Content-Type": @"application/json"});
    CAssertEqual([[NSString alloc] initWithData: httpReq.HTTPBody encoding: NSUTF8StringEncoding],
                 @"{\"foo\"=23}");
}


TestCase(httpResponse) {
    NSURL* url = [NSURL URLWithString:@"http://example.org/some/path?query=value"];
    NSString* bodyString = @"HTTP/1.1 201 Created\r\nLocation: /foo\r\n\r\nBody goes here";
    BLIPResponse* blipRes = [[BLIPResponse alloc] _initIncomingWithProperties: nil
                                     body: [bodyString dataUsingEncoding: NSUTF8StringEncoding]];

    NSData* body;
    NSHTTPURLResponse* httpRes = [blipRes asHTTPResponseWithBody: &body forURL: url];
    CAssert(httpRes != nil);
    CAssertEq(httpRes.statusCode, 201);
    CAssertEqual(httpRes.allHeaderFields, @{@"Location": @"/foo"});
    CAssertEqual([[NSString alloc] initWithData: body encoding: NSUTF8StringEncoding],
                 @"Body goes here");
}

TestCase(HTTP) {
    RequireTestCase(HTTPRequest);
    RequireTestCase(httpResponse);
}

#endif
