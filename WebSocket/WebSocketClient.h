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
- (instancetype) initWithURL: (NSURL*)url;

- (id)initWithURLRequest:(NSURLRequest *)request;

/** Sets a value for an HTTP header field in the initial request. Call this before -connect:. */
- (void) setValue:(NSString *)value forClientHeaderField:(NSString *)field;

/** Registers custom protocols that will be used. Call this before -connect:. */
- (void) setProtocols:(NSArray *)protocols;

/** Configures the socket to use TLS/SSL. Settings dict is same as used with CFStream. */
- (void) useTLS: (NSDictionary*)tlsSettings;

/** Once the request has been customized, call this to open the connection. */
- (BOOL) connectWithTimeout: (NSTimeInterval)timeout error: (NSError**)outError;

@end
