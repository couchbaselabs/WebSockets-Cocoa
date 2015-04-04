//
//  BLIPWebSocketListener.h
//  BLIPSync
//
//  Created by Jens Alfke on 4/1/15.
//  Copyright (c) 2015 Couchbase. All rights reserved.
//

#import "WebSocketListener.h"
#import "BLIPWebSocket.h"

@interface BLIPWebSocketListener : WebSocketListener

- (instancetype) initWithPath: (NSString*)path
                     delegate: (id<BLIPWebSocketDelegate>)delegate
                        queue: (dispatch_queue_t)queue;

- (void)blipWebSocketDidOpen:(BLIPWebSocket*)webSocket;

@end
