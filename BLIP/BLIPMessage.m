//
//  BLIPMessage.m
//  WebSocket
//
//  Created by Jens Alfke on 5/10/08.
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

#import "BLIPMessage.h"
#import "BLIP_Internal.h"

#import "Logging.h"
#import "Test.h"
#import "ExceptionUtils.h"
#import "MYData.h"
#import "MYBuffer.h"

// From Google Toolbox For Mac <http://code.google.com/p/google-toolbox-for-mac/>
#import "GTMNSData+zlib.h"


NSString* const BLIPErrorDomain = @"BLIP";

NSError *BLIPMakeError( int errorCode, NSString *message, ... ) {
    va_list args;
    va_start(args,message);
    message = [[NSString alloc] initWithFormat: message arguments: args];
    va_end(args);
    LogTo(BLIP,@"BLIPError #%i: %@",errorCode,message);
    NSDictionary *userInfo = @{NSLocalizedDescriptionKey: message};
    return [NSError errorWithDomain: BLIPErrorDomain code: errorCode userInfo: userInfo];
}


@implementation BLIPMessage


@synthesize onDataReceived=_onDataReceived, onDataSent=_onDataSent, onSent=_onSent;


- (instancetype) _initWithConnection: (id<BLIPMessageSender>)connection
                              isMine: (BOOL)isMine
                               flags: (BLIPMessageFlags)flags
                              number: (UInt32)msgNo
                                body: (NSData*)body
{
    self = [super init];
    if (self != nil) {
        _connection = connection;
        _isMine = isMine;
        _isMutable = isMine;
        _flags = flags;
        _number = msgNo;
        if (isMine) {
            _body = body.copy;
            _properties = [[NSMutableDictionary alloc] init];
            _propertiesAvailable = YES;
            _complete = YES;
        } else {
            _encodedBody = [[MYBuffer alloc] initWithData: body];
        }
        LogTo(BLIPLifecycle,@"INIT %@",self);
    }
    return self;
}

#if DEBUG
- (void) dealloc {
    LogTo(BLIPLifecycle,@"DEALLOC %@",self);
}
#endif


- (NSString*) description {
    NSUInteger length = (_body.length ?: _mutableBody.length) ?: _encodedBody.minLength;
    NSMutableString *desc = [NSMutableString stringWithFormat: @"%@[#%u, %lu bytes",
                             self.class,(unsigned int)_number, (unsigned long)length];
    if (_flags & kBLIP_Compressed) {
        if (_encodedBody && _encodedBody.minLength != length)
            [desc appendFormat: @" (%lu gzipped)", (unsigned long)_encodedBody.minLength];
        else
            [desc appendString: @", gzipped"];
    }
    if (_flags & kBLIP_Urgent)
        [desc appendString: @", urgent"];
    if (_flags & kBLIP_NoReply)
        [desc appendString: @", noreply"];
    if (_flags & kBLIP_Meta)
        [desc appendString: @", META"];
    if (_flags & kBLIP_MoreComing)
        [desc appendString: @", incomplete"];
    [desc appendString: @"]"];
    return desc;
}

- (NSString*) descriptionWithProperties {
    NSMutableString *desc = (NSMutableString*)self.description;
    [desc appendFormat: @" %@", self.properties];
    return desc;
}


#pragma mark -
#pragma mark PROPERTIES & METADATA:


@synthesize connection=_connection, number=_number, isMine=_isMine, isMutable=_isMutable,
            _bytesWritten, sent=_sent, propertiesAvailable=_propertiesAvailable, complete=_complete,
            representedObject=_representedObject;


- (void) _setFlag: (BLIPMessageFlags)flag value: (BOOL)value {
    Assert(_isMine && _isMutable);
    if (value)
        _flags |= flag;
    else
        _flags &= ~flag;
}

- (BLIPMessageFlags) _flags                 {return _flags;}

- (BOOL) isRequest                          {return (_flags & kBLIP_TypeMask) == kBLIP_MSG;}
- (BOOL) compressed                         {return (_flags & kBLIP_Compressed) != 0;}
- (BOOL) urgent                             {return (_flags & kBLIP_Urgent) != 0;}
- (void) setCompressed: (BOOL)compressed    {[self _setFlag: kBLIP_Compressed value: compressed];}
- (void) setUrgent: (BOOL)high              {[self _setFlag: kBLIP_Urgent value: high];}


- (NSData*) body {
    if (! _body && _isMine)
        return [_mutableBody copy];
    else
        return _body;
}

- (void) setBody: (NSData*)body {
    Assert(_isMine && _isMutable);
    if (_mutableBody)
        [_mutableBody setData: body];
    else
        _mutableBody = [body mutableCopy];
}

- (void) _addToBody: (NSData*)data {
    if (data.length) {
        if (_mutableBody)
            [_mutableBody appendData: data];
        else
            _mutableBody = [data mutableCopy];
        _body = nil;
    }
}

- (void) addToBody: (NSData*)data {
    Assert(_isMine && _isMutable);
    [self _addToBody: data];
}

- (void) addStreamToBody:(NSInputStream *)stream {
    if (!_bodyStreams)
        _bodyStreams = [NSMutableArray new];
    [_bodyStreams addObject: stream];
}


- (NSString*) bodyString {
    NSData *body = self.body;
    if (body)
        return [[NSString alloc] initWithData: body encoding: NSUTF8StringEncoding];
    else
        return nil;
}

- (void) setBodyString: (NSString*)string {
    self.body = [string dataUsingEncoding: NSUTF8StringEncoding];
    self.contentType = @"text/plain; charset=UTF-8";
}


- (id) bodyJSON {
    NSData* body = self.body;
    if (body.length == 0)
        return nil;
    NSError* error;
    id jsonObj = [NSJSONSerialization JSONObjectWithData: body
                                                 options: NSJSONReadingAllowFragments
                                                   error: &error];
    if (!jsonObj)
        Warn(@"Couldn't parse %@ body as JSON: %@", self, error.localizedFailureReason);
    return jsonObj;
}


- (void) setBodyJSON: (id)jsonObj {
    NSError* error;
    NSData* body = [NSJSONSerialization dataWithJSONObject: jsonObj options: 0 error: &error];
    Assert(body, @"Couldn't encode as JSON: %@", error.localizedFailureReason);
    self.body = body;
    self.contentType = @"application/json";
    self.compressed = (body.length > 100);
}


- (NSDictionary*) properties {
    return _properties;
}

- (NSMutableDictionary*) mutableProperties {
    Assert(_isMine && _isMutable);
    return (NSMutableDictionary*)_properties;
}

- (NSString*) objectForKeyedSubscript: (NSString*)key {
    return _properties[key];
}

- (void) setObject: (NSString*)value forKeyedSubscript:(NSString*)key {
    [self.mutableProperties setValue: value forKey: key];
}


- (NSString*) contentType               {return self[@"Content-Type"];}
- (void) setContentType: (NSString*)t   {self[@"Content-Type"] = t;}
- (NSString*) profile                   {return self[@"Profile"];}
- (void) setProfile: (NSString*)p       {self[@"Profile"] = p;}


#pragma mark -
#pragma mark I/O:


- (void) _encode {
    Assert(_isMine && _isMutable);
    _isMutable = NO;

    NSDictionary *oldProps = _properties;
    _properties = [oldProps copy];
    
    _encodedBody = [[MYBuffer alloc] initWithData: BLIPEncodeProperties(_properties)];
    Assert(_encodedBody.maxLength > 0);

    NSData *body = _body ?: _mutableBody;
    NSUInteger length = body.length;
    if (length > 0) {
        if (self.compressed)
            body = [NSData gtm_dataByGzippingData: body compressionLevel: 5];
        [_encodedBody writeData: body];
    }
    for (NSInputStream* stream in _bodyStreams)
        [_encodedBody writeContentsOfStream: stream];
    _bodyStreams = nil;
}


- (void) _assignedNumber: (UInt32)number {
    Assert(_number==0,@"%@ has already been sent",self);
    _number = number;
    _isMutable = NO;
}


// Generates the next outgoing frame.
- (NSData*) nextWebSocketFrameWithMaxSize: (UInt16)maxSize moreComing: (BOOL*)outMoreComing {
    Assert(_number!=0);
    Assert(_isMine);
    Assert(_encodedBody);
    *outMoreComing = NO;
    if (_bytesWritten==0)
        LogTo(BLIP,@"Now sending %@",self);
    size_t headerSize = MYLengthOfVarUInt(_number) + MYLengthOfVarUInt(_flags);

    // Allocate frame and read bytes from body into it:
    NSUInteger frameSize = MIN(headerSize + _encodedBody.maxLength, maxSize);
    NSMutableData* frame = [NSMutableData dataWithLength: frameSize];
    ssize_t bytesRead = [_encodedBody readBytes: (uint8_t*)frame.mutableBytes + headerSize
                                      maxLength: frameSize - headerSize];
    if (bytesRead < 0)
        return nil;
    frame.length = headerSize + bytesRead;
    _bytesWritten += bytesRead;

    // Write the header:
    if (_encodedBody.atEnd) {
        _flags &= ~kBLIP_MoreComing;
    } else {
        _flags |= kBLIP_MoreComing;
        *outMoreComing = YES;
    }
    void* pos = MYEncodeVarUInt(frame.mutableBytes, _number);
    MYEncodeVarUInt(pos, _flags);

    LogTo(BLIPVerbose,@"%@ pushing frame, bytes %lu-%lu%@", self,
          (unsigned long)_bytesWritten-bytesRead, (unsigned long)_bytesWritten,
          (*outMoreComing ? @"" : @" (finished)"));
    if (_onDataSent)
        _onDataSent(_bytesWritten);
    if (!*outMoreComing)
        self.complete = YES;
    return frame;
}


// Parses the next incoming frame.
- (BOOL) _receivedFrameWithFlags: (BLIPMessageFlags)flags body: (NSData*)frameBody {
    Assert(!_isMine);
    Assert(_flags & kBLIP_MoreComing);

    if (!self.isRequest)
        _flags = flags | kBLIP_MoreComing;

    _bytesReceived += frameBody.length;
    if (!_encodedBody)
        _encodedBody = [[MYBuffer alloc] init];
    [_encodedBody writeData: frameBody];
    LogTo(BLIPVerbose,@"%@ rcvd bytes %lu-%lu, flags=%x",
          self, (unsigned long)_bytesReceived-frameBody.length, (unsigned long)_bytesReceived, flags);
    
    if (! _properties) {
        // Try to extract the properties:
        BOOL complete;
        _properties = BLIPReadPropertiesFromBuffer(_encodedBody, &complete);
        if (_properties) {
            self.propertiesAvailable = YES;
            [_connection _messageReceivedProperties: self];
        } else if (complete) {
            return NO;
        }
    }

    void (^onDataReceived)(id<MYReader>) = (_properties && !self.compressed) ? _onDataReceived : nil;
    if (onDataReceived) {
        LogTo(BLIPVerbose, @"%@ -> calling onDataReceived(%lu bytes)", self, frameBody.length);
        onDataReceived(_encodedBody);
    }

    if (! (flags & kBLIP_MoreComing)) {
        // After last frame, decode the data:
        _flags &= ~kBLIP_MoreComing;
        if (! _properties)
            return NO;
        _body = _encodedBody.flattened;
        _encodedBody = nil;
        NSUInteger encodedLength = _body.length;
        if (self.compressed && encodedLength>0) {
            _body = [[NSData gtm_dataByInflatingData: _body] copy];
            if (! _body) {
                Warn(@"Failed to decompress %@", self);
                return NO;
            }
            LogTo(BLIPVerbose,@"Uncompressed %@ from %lu bytes (%.1fx)", self, (unsigned long)encodedLength,
                  _body.length/(double)encodedLength);
            if (_onDataReceived) {
                MYBuffer* buffer = [[MYBuffer alloc] initWithData: _body];
                _onDataReceived(buffer);
                _body = buffer.flattened;
            }
        }
        _onDataReceived = nil;
        self.propertiesAvailable = self.complete = YES;
    }

    return YES;
}


- (void) _connectionClosed {
    if (_isMine) {
        _bytesWritten = 0;
        _flags |= kBLIP_MoreComing;
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
