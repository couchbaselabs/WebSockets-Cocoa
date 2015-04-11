//
//  BLIPWebSocketListener.h
//  BLIPSync
//
//  Created by Jens Alfke on 4/1/15.
//  Copyright (c) 2015 Couchbase. All rights reserved.
//

#import "WebSocketListener.h"
#import "BLIPConnection.h"

@interface BLIPWebSocketListener : WebSocketListener

- (instancetype) initWithPath: (NSString*)path
                     delegate: (id<BLIPConnectionDelegate>)delegate
                        queue: (dispatch_queue_t)queue;

- (void) blipConnectionDidOpen:(BLIPConnection *)connection;

@end
