//
//  BLIPWebSocketListener.h
//  BLIPSync
//
//  Created by Jens Alfke on 4/1/15.
//  Copyright (c) 2015 Couchbase. All rights reserved.
//

#import "WebSocket.h"
#import "BLIPWebSocket.h"

@interface BLIPWebSocketListener : NSObject <WebSocketDelegate>

- (instancetype)initWithDelegate: (id<BLIPWebSocketDelegate>)delegate
                           queue: (dispatch_queue_t)queue;

@property BLIPDispatcher* dispatcher;

@end
