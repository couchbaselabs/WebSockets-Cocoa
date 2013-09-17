//
//  BLIPProperties.m
//  WebSocket
//
//  Created by Jens Alfke on 5/13/08.
//  Copyright 2008-2013 Jens Alfke. All rights reserved.
//

#import "BLIPProperties.h"
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



// Concrete implementation that stores properties in a packed binary form.
@interface BLIPPackedProperties : BLIPProperties
{
    NSData *_data;
    int _count;
    const char **_strings;
    int _nStrings;
}

- (id) initWithData: (NSData*)data contents: (MYSlice)contents;

@end



// The base class just represents an immutable empty collection.
@implementation BLIPProperties


+ (BLIPProperties*) propertiesWithEncodedData: (NSData*)data usedLength: (ssize_t*)usedLength
{
    MYSlice slice = data.my_asSlice;
    UInt64 length;
    MYSlice props;
    if (!MYSliceReadVarUInt(&slice, &length) || !MYSliceReadSlice(&slice, (size_t)length, &props)) {
        *usedLength = 0;
        return nil;
    }

    *usedLength = slice.bytes - data.bytes;

    if (length == 0) {
        return [BLIPProperties properties];
    }

    // Copy the data (length + properties) and make a slice of just the properties part:
    size_t lengthSize = props.bytes - data.bytes;
    data = [data subdataWithRange: NSMakeRange(0, *usedLength)];
    slice = data.my_asSlice;
    MYSliceMoveStart(&slice, lengthSize);

    return [[BLIPPackedProperties alloc] initWithData: data contents: slice];
}


- (id) copyWithZone: (NSZone*)zone
{
    return self;
}

- (id) mutableCopyWithZone: (NSZone*)zone
{
    return [[BLIPMutableProperties allocWithZone: zone] initWithDictionary: self.allProperties];
}

- (BOOL) isEqual: (id)other
{
    return [other isKindOfClass: [BLIPProperties class]]
        && [self.allProperties isEqual: [other allProperties]];
}

- (NSString*) valueOfProperty: (NSString*)prop  {return nil;}
- (NSString*)objectForKeyedSubscript:(NSString*)key {return nil;}
- (NSDictionary*) allProperties                 {return @{};}
- (NSUInteger) count                            {return 0;}
- (NSUInteger) dataLength                       {return 1;}

- (NSData*) encodedData
{
    // varint-encoded zero:
    UInt8 len = 0;
    return [NSData dataWithBytes: &len length: 1];
}


// Singleton empty instance
+ (BLIPProperties*) properties
{
    static BLIPProperties *sEmptyInstance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sEmptyInstance = [[self alloc] init];
    });
    return sEmptyInstance;
}


@end



/** Internal immutable subclass that keeps its contents in the packed data representation. */
@implementation BLIPPackedProperties


- (id) initWithData: (NSData*)data contents: (MYSlice)contents {
    self = [super init];
    if (self != nil) {
        if (contents.length == 0 || ((const char*)contents.bytes)[contents.length-1] != '\0')
            goto fail;

        // Copy data, then skip the length field:
        _data = data;

        // The data consists of consecutive NUL-terminated strings, alternating key/value:
        int capacity = 0;
        const char *end = MYSliceGetEnd(contents);
        for( const char *str=contents.bytes; str < end; str += strlen(str)+1, _nStrings++ ) {
            if( _nStrings >= capacity ) {
                capacity = capacity ?(2*capacity) :4;
                _strings = realloc(_strings, capacity*sizeof(const char*));
            }
            UInt8 first = (UInt8)str[0];
            if( first>'\0' && first<' ' && str[1]=='\0' ) {
                // Single-control-character property string is an abbreviation:
                if( first > kNAbbreviations )
                    goto fail;
                _strings[_nStrings] = kAbbreviations[first-1];
            } else
                _strings[_nStrings] = str;
        }
        
        // It's illegal for the data to end with a non-NUL or for there to be an odd number of strings:
        if( (_nStrings & 1) )
            goto fail;
        
        return self;
            
    fail:
        Warn(@"BLIPProperties: invalid data");
        return nil;
    }
    return self;
}


- (void) dealloc
{
    if( _strings ) free(_strings);
}

- (id) copyWithZone: (NSZone*)zone
{
    return self;
}

- (id) mutableCopyWithZone: (NSZone*)zone
{
    return [[BLIPMutableProperties allocWithZone: zone] initWithDictionary: self.allProperties];
}


- (NSString*) valueOfProperty: (NSString*)prop
{
    const char *propStr = [prop UTF8String];
    Assert(propStr);
    // Search in reverse order so that later values will take precedence over earlier ones.
    for( int i=_nStrings-2; i>=0; i-=2 ) {
        if( strcmp(propStr, _strings[i]) == 0 )
            return @(_strings[i+1]);
    }
    return nil;
}

- (NSString*)objectForKeyedSubscript:(NSString*)key
{
    return [self valueOfProperty: key];
}


- (NSDictionary*) allProperties
{
    NSMutableDictionary *props = [NSMutableDictionary dictionaryWithCapacity: _nStrings/2];
    // Add values in forward order so that later ones will overwrite (take precedence over)
    // earlier ones, which matches the behavior of -valueOfProperty.
    for( int i=0; i<_nStrings; i+=2 ) {
        NSString *key = [[NSString alloc] initWithUTF8String: _strings[i]];
        NSString *value = [[NSString alloc] initWithUTF8String: _strings[i+1]];
        if( key && value )
            props[key] = value;
    }
    return props;
}


- (NSUInteger) count        {return _nStrings/2;}
- (NSData*) encodedData     {return _data;}
- (NSUInteger) dataLength   {return _data.length;}


@end



/** Mutable subclass that stores its properties in an NSMutableDictionary. */
@implementation BLIPMutableProperties
{
    NSMutableDictionary *_properties;
}


+ (BLIPProperties*) properties
{
    return [[self alloc] initWithDictionary: nil];
}

- (id) init
{
    self = [super init];
    if (self != nil) {
        _properties = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (id) initWithDictionary: (NSDictionary*)dict
{
    self = [super init];
    if (self != nil) {
        _properties = dict ?[dict mutableCopy] :[[NSMutableDictionary alloc] init];
    }
    return self;
}

- (id) initWithProperties: (BLIPProperties*)properties
{
    return [self initWithDictionary: [properties allProperties]];
}


- (id) copyWithZone: (NSZone*)zone
{
    ssize_t usedLength;
    BLIPProperties *copy = [BLIPProperties propertiesWithEncodedData: self.encodedData usedLength: &usedLength];
    Assert(copy);
    return copy;
}


- (NSString*) valueOfProperty: (NSString*)prop
{
    return _properties[prop];
}

- (NSString*)objectForKeyedSubscript:(NSString*)key
{
    return _properties[key];
}

- (NSDictionary*) allProperties
{
    return _properties;
}

- (NSUInteger) count        {return _properties.count;}


static void appendStr( NSMutableData *data, NSString *str ) {
    const char *utf8 = [str UTF8String];
    size_t size = strlen(utf8)+1;
    for( unsigned i=0; i<kNAbbreviations; i++ )
        if( memcmp(utf8,kAbbreviations[i],size)==0 ) {
            const UInt8 abbrev[2] = {i+1,0};
            [data appendBytes: &abbrev length: 2];
            return;
        }
    [data appendBytes: utf8 length: size];
}

- (NSData*) encodedData
{
    static const int kPlaceholderLength = 1; // space to reserve for varint length
    NSMutableData *data = [NSMutableData dataWithCapacity: 16*_properties.count];
    [data setLength: kPlaceholderLength];
    for( NSString *name in _properties ) {
        appendStr(data,name);
        appendStr(data,_properties[name]);
    }
    
    NSUInteger length = data.length - kPlaceholderLength;

    UInt8 buf[10];
    UInt8* end = MYEncodeVarUInt(buf, length);
    [data replaceBytesInRange: NSMakeRange(0, kPlaceholderLength) withBytes: buf length: end-buf];
    return data;
}

    
- (void) setValue: (NSString*)value ofProperty: (NSString*)prop
{
    Assert(prop.length>0);
    if( value )
        _properties[prop] = value;
    else
        [_properties removeObjectForKey: prop];
}

- (void) setObject: (NSString*)value forKeyedSubscript:(NSString*)key
{
    [self setValue: value ofProperty: key];
}


- (void) setAllProperties: (NSDictionary*)properties
{
    if( properties.count ) {
        for( id key in properties ) {
            Assert([key isKindOfClass: [NSString class]]);
            Assert([key length] > 0);
            Assert([properties[key] isKindOfClass: [NSString class]]);
        }
        [_properties setDictionary: properties];
    } else
        [_properties removeAllObjects];
}


@end




TestCase(BLIPProperties) {
    BLIPProperties *props;
    
    props = [BLIPProperties properties];
    CAssert(props);
    CAssertEq(props.count,0U);
    Log(@"Empty properties:\n%@", props.allProperties);
    NSData *data = props.encodedData;
    Log(@"As data: %@", data);
    CAssertEqual(data,[NSMutableData dataWithLength: 1]);
    
    BLIPMutableProperties *mprops = [props mutableCopy];
    Log(@"Mutable copy:\n%@", mprops.allProperties);
    data = mprops.encodedData;
    Log(@"As data: %@", data);
    CAssertEqual(data,[NSMutableData dataWithLength: 1]);
    
    ssize_t used;
    props = [BLIPProperties propertiesWithEncodedData: data usedLength: &used];
    CAssert(props != nil);
    CAssertEq(used,(ssize_t)data.length);
    CAssertEqual(props,mprops);
    
    [mprops setValue: @"Jens" ofProperty: @"First-Name"];
    [mprops setValue: @"Alfke" ofProperty: @"Last-Name"];
    [mprops setValue: @"" ofProperty: @"Empty-String"];
    [mprops setValue: @"Z" ofProperty: @"A"];
    Log(@"With properties:\n%@", mprops.allProperties);
    data = mprops.encodedData;
    Log(@"As data: %@", data);
    
    for( unsigned len=0; len<data.length; len++ ) {
        props = [BLIPProperties propertiesWithEncodedData: [data subdataWithRange: NSMakeRange(0,len)]
                                                                usedLength: &used];
        CAssertEq(props,(id)nil);
        CAssertEq(used,0);
    }
    props = [BLIPProperties propertiesWithEncodedData: data usedLength: &used];
    CAssertEq(used,(ssize_t)data.length);
    Log(@"Read back in:\n%@",props.allProperties);
    CAssertEqual(props,mprops);
    
    NSDictionary *all = mprops.allProperties;
    for( NSString *prop in all )
        CAssertEqual([props valueOfProperty: prop],all[prop]);
	
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
