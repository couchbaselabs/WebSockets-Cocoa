//
//  BLIPResponse.m
//  WebSocket
//
//  Created by Jens Alfke on 9/15/13.
//  Copyright (c) 2013 Couchbase. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "BLIPResponse.h"
#import "BLIP_Internal.h"

#import "Logging.h"
#import "Test.h"
#import "ExceptionUtils.h"


@implementation BLIPResponse
{
    void (^_onComplete)();
}

- (id) _initWithRequest: (BLIPRequest*)request
{
    Assert(request);
    self = [super _initWithConnection: request.connection
                               isMine: !request.isMine
                                flags: kBLIP_RPY | kBLIP_MoreComing
                               number: request.number
                                 body: nil];
    if (self != nil) {
        if( _isMine ) {
            _isMutable = YES;
            if( request.urgent )
                _flags |= kBLIP_Urgent;
        } else {
            _flags |= kBLIP_MoreComing;
        }
    }
    return self;
}


#if DEBUG
// For testing only
- (id) _initIncomingWithProperties: (BLIPProperties*)properties body: (NSData*)body {
    self = [self _initWithConnection: nil
                              isMine: NO
                               flags: kBLIP_MSG
                              number: 0
                                body: nil];
    if (self != nil ) {
        _body = [body copy];
        _isMutable = NO;
        _properties = properties;
    }
    return self;
}
#endif


- (NSError*) error
{
    if( (_flags & kBLIP_TypeMask) != kBLIP_ERR )
        return nil;
    
    NSMutableDictionary *userInfo = [[self.properties allProperties] mutableCopy];
    NSString *domain = userInfo[@"Error-Domain"];
    int code = [userInfo[@"Error-Code"] intValue];
    if( domain==nil || code==0 ) {
        domain = BLIPErrorDomain;
        if( code==0 )
            code = kBLIPError_Unspecified;
    }
    [userInfo removeObjectForKey: @"Error-Domain"];
    [userInfo removeObjectForKey: @"Error-Code"];
    return [NSError errorWithDomain: domain code: code userInfo: userInfo];
}

- (void) _setError: (NSError*)error
{
    _flags &= ~kBLIP_TypeMask;
    if( error ) {
        // Setting this stuff is a PITA because this object might be technically immutable,
        // in which case the standard setters would barf if I called them.
        _flags |= kBLIP_ERR;
        _body = nil;
        _mutableBody = nil;
        
        BLIPMutableProperties *errorProps = [self.properties mutableCopy];
        if( ! errorProps )
            errorProps = [[BLIPMutableProperties alloc] init];
        NSDictionary *userInfo = error.userInfo;
        for( NSString *key in userInfo ) {
            id value = $castIf(NSString,userInfo[key]);
            if( value )
                [errorProps setValue: value ofProperty: key];
        }
        [errorProps setValue: error.domain ofProperty: @"Error-Domain"];
        [errorProps setValue: $sprintf(@"%li",(long)error.code) ofProperty: @"Error-Code"];
         _properties = errorProps;
        
    } else {
        _flags |= kBLIP_RPY;
        [self.mutableProperties setAllProperties: nil];
    }
}

- (void) setError: (NSError*)error
{
    Assert(_isMine && _isMutable);
    [self _setError: error];
}


- (BOOL) send
{
    Assert(_connection,@"%@ has no connection to send over",self);
    Assert(!_sent,@"%@ was already sent",self);
    [self _encode];
    BOOL sent = self.sent = [_connection _sendResponse: self];
    Assert(sent);
    return sent;
}


@synthesize onComplete=_onComplete;


- (void) setComplete: (BOOL)complete
{
    [super setComplete: complete];
    if( complete && _onComplete ) {
        @try{
            _onComplete();
        }catchAndReport(@"BLIPRequest onComplete block");
    }
}


- (void) _connectionClosed
{
    [super _connectionClosed];
    if( !_isMine && !_complete ) {
        NSError *error = _connection.error;
        if (!error)
            error = BLIPMakeError(kBLIPError_Disconnected,
                                  @"Connection closed before response was received");
        // Change incoming response to an error:
        _isMutable = YES;
        _properties = [_properties mutableCopy];
        [self _setError: error];
        _isMutable = NO;
        
        self.complete = YES;    // Calls onComplete target
    }
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
