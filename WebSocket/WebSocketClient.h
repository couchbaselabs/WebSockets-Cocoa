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

/** Designated initializer. The scheme of the URL is ignored. */
- (id)initWithURLRequest:(NSURLRequest *)request;

- (instancetype) initWithURL: (NSURL*)url;

/** Configures the socket to use TLS/SSL. Settings dict is same as used with CFStream. */
- (void) useTLS: (NSDictionary*)tlsSettings;

/** Once the request has been customized, call this to open the connection. */
- (BOOL) connect: (NSError**)outError;

@end
