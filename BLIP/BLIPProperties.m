//
//  BLIPProperties.m
//  WebSocket
//
//  Created by Jens Alfke on 5/13/08.
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

#import "BLIPProperties.h"
#import "MYBuffer.h"
#import "MYData.h"
#import "Logging.h"
#import "Test.h"
#import "MYData.h"


/** Common strings are abbreviated as single-byte strings in the packed form.
    The ascii value of the single character minus one is the index into this table. */
static const char* kAbbreviations[] = {
    "Profile",
    "Error-Code",
    "Error-Domain",

    "Content-Type",
    "application/json",
    "application/octet-stream",
    "text/plain; charset=UTF-8",
    "text/xml",

    "Accept",
    "Cache-Control",
    "must-revalidate",
    "If-Match",
    "If-None-Match",
    "Location",
};
#define kNAbbreviations ((sizeof(kAbbreviations)/sizeof(const char*)))  // cannot exceed 31!



static NSString* readCString(MYSlice* slice) {
    const char* key = slice->bytes;
    size_t len = strlen(key);
    MYSliceMoveStart(slice, len+1);
    if (len == 0)
        return nil;
    uint8_t first = (uint8_t)key[0];
    if (first < ' ' && key[1]=='\0') {
        // Single-control-character property string is an abbreviation:
        if (first > kNAbbreviations)
            return nil;
        key = kAbbreviations[first-1];
    }
    return [NSString stringWithUTF8String: key];
}


NSDictionary* BLIPParseProperties(MYSlice *data, BOOL* complete) {
    MYSlice slice = *data;
    uint64_t length;
    if (!MYSliceReadVarUInt(&slice, &length) || slice.length < length) {
        *complete = NO;
        return nil;
    }
    *complete = YES;
    if (length == 0) {
        MYSliceMoveStart(data, 1);
        return @{};
    }
    MYSlice buf = MYMakeSlice(slice.bytes, (size_t)length);
    if (((const char*)slice.bytes)[buf.length - 1] != '\0')
        return nil;     // checking for nul at end makes it safe to use strlen in readCString
    NSMutableDictionary* result = [NSMutableDictionary new];
    while (buf.length > 0) {
        NSString* key = readCString(&buf);
        if (!key)
            return nil;
        NSString* value = readCString(&buf);
        if (!value)
            return nil;
        result[key] = value;
    }
    MYSliceMoveStartTo(data, buf.bytes);
    return result;
}


NSDictionary* BLIPReadPropertiesFromBuffer(MYBuffer* buffer, BOOL *complete) {
    MYSlice slice = buffer.flattened.my_asSlice;
    MYSlice readSlice = slice;
    NSDictionary* props = BLIPParseProperties(&readSlice, complete);
    if (props)
        [buffer readSliceOfMaxLength: slice.length - readSlice.length];
    return props;
}


static void appendStr( NSMutableData *data, NSString *str ) {
    const char *utf8 = [str UTF8String];
    size_t size = strlen(utf8)+1;
    for (uint8_t i=0; i<kNAbbreviations; i++)
        if (memcmp(utf8,kAbbreviations[i],size)==0) {
            const UInt8 abbrev[2] = {i+1,0};
            [data appendBytes: &abbrev length: 2];
            return;
        }
    [data appendBytes: utf8 length: size];
}

NSData* BLIPEncodeProperties(NSDictionary* properties) {
    static const int kPlaceholderLength = 1; // space to reserve for varint length
    NSMutableData *data = [NSMutableData dataWithCapacity: 16*properties.count];
    [data setLength: kPlaceholderLength];
    for (NSString *name in properties) {
        appendStr(data,name);
        appendStr(data,properties[name]);
    }
    NSUInteger length = data.length - kPlaceholderLength;
    UInt8 buf[10];
    UInt8* end = MYEncodeVarUInt(buf, length);
    [data replaceBytesInRange: NSMakeRange(0, kPlaceholderLength)
                    withBytes: buf
                       length: end-buf];
    return data;
}


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
