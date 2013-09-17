//
//  BLIPRequest.m
//  WebSocket
//
//  Created by Jens Alfke on 5/22/08.
//  Copyright 2008-2013 Jens Alfke.
//  Copyright (c) 2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "BLIPRequest.h"
#import "BLIP_Internal.h"

#import "Target.h"
#import "Logging.h"
#import "Test.h"
#import "ExceptionUtils.h"


@implementation BLIPRequest
{
    BLIPResponse *_response;
}


- (id) _initWithConnection: (id<BLIPMessageSender>)connection
                      body: (NSData*)body 
                properties: (NSDictionary*)properties
{
    self = [self _initWithConnection: connection
                              isMine: YES
                               flags: kBLIP_MSG
                              number: 0
                                body: body];
    if( self ) {
        _isMutable = YES;
        if( body )
            self.body = body;
        if( properties )
            [self.mutableProperties setAllProperties: properties];
    }
    return self;
}

+ (BLIPRequest*) requestWithBody: (NSData*)body
{
    return [[self alloc] _initWithConnection: nil body: body properties: nil];
}

+ (BLIPRequest*) requestWithBodyString: (NSString*)bodyString {
    return [self requestWithBody: [bodyString dataUsingEncoding: NSUTF8StringEncoding]];
}

+ (BLIPRequest*) requestWithBody: (NSData*)body
                      properties: (NSDictionary*)properties
{
    return [[self alloc] _initWithConnection: nil body: body properties: properties];
}

- (id)mutableCopyWithZone:(NSZone *)zone
{
    Assert(self.complete);
    BLIPRequest *copy = [[self class] requestWithBody: self.body 
                                           properties: self.properties.allProperties];
    copy.compressed = self.compressed;
    copy.urgent = self.urgent;
    copy.noReply = self.noReply;
    return copy;
}




- (BOOL) noReply                            {return (_flags & kBLIP_NoReply) != 0;}
- (void) setNoReply: (BOOL)noReply          {[self _setFlag: kBLIP_NoReply value: noReply];}
- (id<BLIPMessageSender>) connection        {return _connection;}

- (void) setConnection: (id<BLIPMessageSender>)conn
{
    Assert(_isMine && !_sent,@"Connection can only be set before sending");
     _connection = conn;
}


- (BLIPResponse*) send
{
    Assert(_connection,@"%@ has no connection to send over",self);
    Assert(!_sent,@"%@ was already sent",self);
    [self _encode];
    BLIPResponse *response = self.response;
    if( [_connection _sendRequest: self response: response] )
        self.sent = YES;
    else
        response = nil;
    return response;
}


- (BLIPResponse*) response
{
    if( ! _response && ! self.noReply )
        _response = [[BLIPResponse alloc] _initWithRequest: self];
    return _response;
}

- (void) deferResponse
{
    // This will allocate _response, causing -repliedTo to become YES, so BLIPWebSocket won't
    // send an automatic empty response after the current request handler returns.
    LogTo(BLIP,@"Deferring response to %@",self);
    [self response];
}

- (BOOL) repliedTo
{
    return _response != nil;
}

- (void) respondWithData: (NSData*)data contentType: (NSString*)contentType
{
    BLIPResponse *response = self.response;
    response.body = data;
    response.contentType = contentType;
    [response send];
}

- (void) respondWithString: (NSString*)string
{
    [self respondWithData: [string dataUsingEncoding: NSUTF8StringEncoding]
              contentType: @"text/plain; charset=UTF-8"];
}

- (void) respondWithError: (NSError*)error
{
    self.response.error = error; 
    [self.response send];
}

- (void) respondWithErrorCode: (int)errorCode message: (NSString*)errorMessage
{
    [self respondWithError: BLIPMakeError(errorCode, @"%@",errorMessage)];
}

- (void) respondWithException: (NSException*)exception
{
    [self respondWithError: BLIPMakeError(kBLIPError_HandlerFailed, @"%@", exception.reason)];
}


@end




/*
 Copyright (c) 2008-2013, Jens Alfke <jens@mooseyard.com>. All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, are permitted
 provided that the following conditions are met:
 
 * Redistributions of source code must retain the above copyright notice, this list of conditions
 and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright notice, this list of conditions
 and the following disclaimer in the documentation and/or other materials provided with the
 distribution.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR
 IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND 
 FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRI-
 BUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR 
 PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN 
 CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF 
 THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
