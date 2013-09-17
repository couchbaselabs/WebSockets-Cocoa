This is an Objective-C implementation of the [WebSocket][WEBSOCKET] protocol, for iOS and Mac OS. It includes a protocol extension called BLIP that adds RPC-style functionality.

It's built on top of Robbie Hanson's excellent [CocoaAsyncSocket][ASYNC] library. Its WebSocket class started out as a hack of a class from his [CocoaHTTPServer][HTTPSERVER], but has evolved from there.

## BLIP Protocol

BLIP frames are WebSocket binary messages that start with three [varint][VARINT]-encoded numbers and an optional binary field:

* The first is a request number; this identifies which frames belong to the same request or response. Outgoing requests are assigned sequential integers starting at 1. A response uses the same number as its request, so the peer knows which request it's answering.
* The second is a set of flags:

    0x03    Message type (0-3)
    0x04    Compressed (if set, message data is gzipped)
    0x08    Urgent (prioritizes outgoing messages)
    0x10    No-reply (recipient should not send a response)
    0x20    More coming (not the final frame of a message)
    0x40    Meta (messages for internal use; currently unused)

The message types are:

    0       Request
    1       Response
    2       Error
    
The frame data begins immediately after the flags.

Long messages will be broken into multiple frames. Every frame but the last will have the "No-reply" flag set. (Frame sizes aren't mandated by the protocol, but if a frame is too large it can hog the socket and starve other messages that are trying to be sent at the same time.) The message data is the concatenation of all the frame data.

The message data begins with a block of properties. These start with a varint-encoded byte count (zero if there are no properties.) The properties follow, encoded as a series of NUL-terminated UTF-8 strings, alternating names and values. Certain commonly-used strings are encoded as single-byte strings whose one character has a value less than 0x20; there's a table of these in BLIPProperties.m.

The message data after the properties is the payload, i.e. the data the client is sending. If the Compressed flag is set, this payload is compressed with the Gzip algorithm.

[WEBSOCKET]: http://www.websocket.org
[ASYNC]: https://github.com/robbiehanson/CocoaAsyncSocket
[HTTPSERVER]: https://github.com/robbiehanson/CocoaHTTPServer
[VARINT]: https://developers.google.com/protocol-buffers/docs/encoding#varints
