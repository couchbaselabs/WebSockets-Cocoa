⚠️ This repo is obsolete and not used.  The implementation of BLIP in Couchbase Lite for Cocoa is split between [Couchbase Lite iOS](https://github.com/couchbase/couchbase-lite-ios) for the transport and [BLIP](https://github.com/couchbase/couchbase-lite-core/tree/master/Networking/BLIP) for the protocol.

This is an Objective-C implementation of the [WebSocket][WEBSOCKET] protocol, for iOS and Mac OS. It includes a protocol extension called BLIP that adds RPC-style functionality.

It's built on top of Robbie Hanson's excellent [CocoaAsyncSocket][ASYNC] library. Its WebSocket class started out as a hack of a class from his [CocoaHTTPServer][HTTPSERVER], but has evolved from there.

(Note: this code is unrelated to the [cocoa-websocket][COCOAWEBSOCKET] library, except that they both use AsyncSocket.)

# Status

This is pretty early in development; pre-alpha for sure. But we plan to use it in Couchbase Lite in the near future. (Sept. 2013)

# BLIP

## Why BLIP?

BLIP adds several useful features that aren't supported directly by WebSocket:

* Request/response: Messages can have responses, and the responses don't have to be sent in the same order as the original messages. Responses are optional; a message can be sent in no-reply mode if it doesn't need one, otherwise a response (even an empty one) will always be sent after the message is handled.
* Metadata: Messages are structured, with a set of key/value headers and a binary body, much like HTTP or MIME messages. Peers can use the metadata to route incoming messages to different handlers, effectively creating multiple independent channels on the same connection.
* Multiplexing: Large messages are broken into fragments, and if multiple messages are ready to send their fragments will be interleaved on the connection, so they're sent in parallel. This prevents huge messages from blocking the connection.
* Priorities: Messages can be marked Urgent, which gives them higher priority in the multiplexing (but without completely starving normal-priority messages.) This is very useful for streaming media.

## BLIP Protocol

A BLIP message is either a request or a response; a request will have zero or one response associated with it. Messages can be arbitrarily long, but are broken up into smaller frames, generally between 4k and 16k bytes, during transmission to support multiplexing of messages.

BLIP frames are WebSocket binary messages that start with two [varint][VARINT]-encoded unsigned integers:

1. The first is a request number; this identifies which frames belong to the same message. Outgoing request messages are assigned sequential integers starting at 1. A response message uses the same number as its request, so the peer knows which request it answers.
2. The second is a set of flags:

        0x03    Message type (0-3)
        0x04    Compressed (if set, message data is gzipped)
        0x08    Urgent (prioritizes outgoing messages)
        0x10    No-reply (in requests only; recipient should not send a response)
        0x20    More coming (not the final frame of a message)
        0x40    Meta (messages for internal use; currently unused)

    where the message types (stored in the lower two bits) are:

        0       Request
        1       Response
        2       Error (a special type of response)
    
The frame data begins immediately after the flags.

Long messages will be broken into multiple frames. Every frame but the last will have the "More-coming" flag set. (Frame sizes aren't mandated by the protocol, but if a frame is too large it can hog the socket and starve other messages that are trying to be sent at the same time.) The message data is the concatenation of all the frame data.

The message data (_not_ each frame's data) begins with a block of properties. These start with a varint-encoded byte count (zero if there are no properties.) The properties follow, encoded as a series of NUL-terminated UTF-8 strings, alternating names and values. Certain commonly-used strings are encoded as single-byte strings whose one character has a value less than 0x20; there's a table of these in BLIPProperties.m.

The message data after the properties is the payload, i.e. the data the client is sending. If the Compressed flag is set, this payload is compressed with the Gzip algorithm.

[WEBSOCKET]: http://www.websocket.org
[ASYNC]: https://github.com/robbiehanson/CocoaAsyncSocket
[HTTPSERVER]: https://github.com/robbiehanson/CocoaHTTPServer
[BLIP]: https://bitbucket.org/snej/mynetwork/wiki/BLIP/Overview
[VARINT]: https://developers.google.com/protocol-buffers/docs/encoding#varints
[COCOAWEBSOCKET]: https://github.com/talkative/cocoa-websocket
