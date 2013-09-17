//
//  BLIPDispatcher.h
//  WebSocket
//
//  Created by Jens Alfke on 5/15/08.
//  Copyright 2008-2013 Jens Alfke.
//  Copyright (c) 2013 Couchbase, Inc. All rights reserved.

#import <Foundation/Foundation.h>
@class MYTarget, BLIPMessage;


/** A block that gets called if a dispatcher rule matches. */
typedef void (^BLIPDispatchBlock)(BLIPMessage*);


/** Routes BLIP messages to targets based on a series of rules.
 
    Every BLIPWebSocket has a BLIPDispatcher, which is initially empty, but you can add rules
    to it.
 
    Every BLIPListener also has a dispatcher, which is inherited as the parent by every
    connection that it accepts, so you can add rules to the listener's dispatcher to share them
    between all connections.
 
    It's not necessary to use a dispatcher. Any undispatched requests will be sent to the
    BLIPWebSocket's delegate's -connection:receivedRequest: method, which can do its own
    custom handling. But it's often easier to use the dispatcher to associate handlers with
    request based on property values. */
@interface BLIPDispatcher : NSObject 

/** The inherited parent dispatcher.
    If a message does not match any of this dispatcher's rules, it will next be passed to
    the parent, if there is one. */
@property (strong) BLIPDispatcher *parent;

/** Adds a new rule, to call a given target method if a given predicate matches the message. The return value is a token that you can later pass to -removeRule: to unregister this rule. */
- (id) onPredicate: (NSPredicate*)predicate do: (BLIPDispatchBlock)block;

/** Convenience method that adds a rule that compares a property against a string. */
- (id) onProperty: (NSString*)property value: (NSString*)value do: (BLIPDispatchBlock)block;

/** Removes all rules with the given target. */
- (void) removeRule: (id)rule;

/** Tests the message against all the rules, in the order they were added, and calls the
    target of the first matching rule.
    If no rule matches, the message is passed to the parent dispatcher's -dispatchMessage:,
    if there is a parent.
    If no rules at all match, NO is returned. */
- (BOOL) dispatchMessage: (BLIPMessage*)message;

/** Returns a target object that will call this dispatcher's -dispatchMessage: method.
    This can be used to make this dispatcher the target of another dispatcher's rule,
    stringing them together hierarchically. */
- (BLIPDispatchBlock) asDispatchBlock;

@end
