//
//  BLIPDispatcher.m
//  WebSocket
//
//  Created by Jens Alfke on 5/15/08.
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

#import "BLIPDispatcher.h"
#import "Target.h"
#import "BLIPRequest.h"
#import "BLIPProperties.h"
#import "Test.h"


@implementation BLIPDispatcher
{
    NSMutableArray *_predicates, *_targets;
    BLIPDispatcher *_parent;
}


- (instancetype) init
{
    self = [super init];
    if (self != nil) {
        _targets = [[NSMutableArray alloc] init];
        _predicates = [[NSMutableArray alloc] init];
    }
    return self;
}



@synthesize parent=_parent;


- (id) onPredicate: (NSPredicate*)predicate do: (BLIPDispatchBlock)block {
    [_targets addObject: block];
    [_predicates addObject: predicate];
    return @(_targets.count - 1);
}


- (void) removeRule: (id)rule
{
    NSUInteger ruleID = [$cast(NSNumber, rule) unsignedIntegerValue];
    _targets[ruleID] = [NSNull null];
    _predicates[ruleID] = [NSNull null];
}


- (id) onProperty: (NSString*)key value: (NSString*)value do: (BLIPDispatchBlock)block {
    return [self onPredicate: [NSComparisonPredicate
                predicateWithLeftExpression: [NSExpression expressionForKeyPath: key]
                            rightExpression: [NSExpression expressionForConstantValue: value]
                                   modifier: NSDirectPredicateModifier
                                       type: NSEqualToPredicateOperatorType
                                    options: 0]
                   do: block];
}


- (BOOL) dispatchMessage: (BLIPMessage*)message
{
    NSDictionary *properties = message.properties.allProperties;
    NSUInteger n = _predicates.count;
    for( NSUInteger i=0; i<n; i++ ) {
        id p = _predicates[i];
        if([$castIf(NSPredicate,p) evaluateWithObject: properties]) {
            BLIPDispatchBlock target = _targets[i];
            target(message);
            return YES;
        }
    }
    return [_parent dispatchMessage: message];
}


- (BLIPDispatchBlock) asDispatchBlock
{
    return ^(BLIPMessage* msg) {
        [self dispatchMessage: msg];
    };
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
