//
//  WebSocketClient.h
//  WebSocket
//
//  Created by Jens Alfke on 9/10/13.
//
//

#import "WebSocket.h"

/** Client WebSocket -- opens a connection to a remote host. */
@interface WebSocketClient : WebSocket

- (instancetype) initWithURL: (NSURL*)url;

/** Sets a value for an HTTP header field in the initial request. Call this before -connect:. */
- (void) setValue:(NSString *)value forClientHeaderField:(NSString *)field;

/** Registers custom protocols that will be used. Call this before -connect:. */
- (void) setProtocols:(NSArray *)protocols;

/** Once the request has been customized, call this to open the connection. */
- (BOOL) connect: (NSError**)outError;

@end
