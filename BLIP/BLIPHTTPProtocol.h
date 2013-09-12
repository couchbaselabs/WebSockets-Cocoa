//
//  BLIPHTTPProtocol.h
//  MYNetwork
//
//  Created by Jens Alfke on 4/15/13.
//
//

#import <Foundation/Foundation.h>

/** Implementation of the "wshttp" URL protocol, for sending HTTP-style requests over WebSockets
    using BLIP. */
@interface BLIPHTTPProtocol : NSURLProtocol

+ (void) registerWebSocketURL: (NSURL*)wsURL forURL: (NSURL*)baseURL;

@end
