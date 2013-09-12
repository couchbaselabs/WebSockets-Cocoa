//
//  BLIPWebSocket.m
//  MYNetwork
//
//  Created by Jens Alfke on 4/1/13.
//
//

#import "BLIPWebSocket.h"
#import "BLIPRequest.h"
#import "BLIPDispatcher.h"
#import "BLIP_Internal.h"
#import "WebSocketClient.h"

#import "ExceptionUtils.h"
#import "Logging.h"
#import "Test.h"


#define kDefaultFrameSize 4096


@interface BLIPWebSocket () <WebSocketDelegate>
@property (readwrite) NSError* error;
@end


@implementation BLIPWebSocket
{
    WebSocket* _webSocket;
    bool _webSocketIsOpen;
    NSError* _error;
    __weak id<BLIPWebSocketDelegate> _delegate;
    
    NSMutableArray *_outBox;
    UInt32 _numRequestsSent;

    UInt32 _numRequestsReceived;
    NSMutableDictionary *_pendingRequests, *_pendingResponses;

    BLIPDispatcher* _dispatcher;
}


@synthesize delegate=_delegate;


// Designated initializer
- (id)initWithWebSocket: (WebSocket*)webSocket {
    Assert(webSocket);
    self = [super init];
    if (self) {
        if (!webSocket)
            return nil;
        _webSocket = webSocket;
        _webSocket.delegate = self;
        _pendingRequests = [[NSMutableDictionary alloc] init];
        _pendingResponses = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (id)initWithURLRequest:(NSURLRequest *)request {
    return [self initWithWebSocket: [[WebSocketClient alloc] initWithURLRequest: request]];
}

- (id)initWithURL:(NSURL *)url {
    return [self initWithWebSocket: [[WebSocketClient alloc] initWithURL: url]];
}


@synthesize error=_error, webSocket=_webSocket;


#pragma mark - OPEN/CLOSE:


- (BOOL) open {
    NSError* error;
    if (![(WebSocketClient*)_webSocket connectWithTimeout: -1 error: &error]) {
        self.error = error;
        return NO;
    }
    return YES;
}


- (void)close {
    [_webSocket close];
}

- (void)closeWithCode:(NSInteger)code reason:(NSString *)reason {
    [_webSocket closeWithCode: code reason: reason];
}

- (void) _closeWithError: (NSError*)error {
    self.error = error;
    [_webSocket closeWithCode: kWebSocketClosePolicyError reason: error.localizedDescription];
}


- (void)webSocketDidOpen:(WebSocket *)webSocket {
    LogTo(BLIP, @"%@ is open!", self);
    _webSocketIsOpen = true;
    if ([_delegate respondsToSelector: @selector(blipWebSocketDidOpen:)])
        [_delegate blipWebSocketDidOpen: self];
    if (_outBox.count > 0)
        [self webSocketReadyForData: _webSocket];
}


- (void)webSocket:(WebSocket *)webSocket didFailWithError:(NSError *)error {
    LogTo(BLIP, @"%@ closed with error %@", self, error);
    if (error && !_error)
        self.error = error;
    if ([_delegate respondsToSelector: @selector(blipWebSocket:didFailWithError:)])
        [_delegate blipWebSocket: self didFailWithError: error];
}


- (void)webSocket:(WebSocket *)webSocket
 didCloseWithCode:(WebSocketCloseCode)code
           reason:(NSString *)reason
{
    LogTo(BLIP, @"%@ closed with code %d", self, (int)code);
    if ([_delegate respondsToSelector: @selector(blipWebSocket:didCloseWithCode:reason:)])
        [_delegate blipWebSocket: self didCloseWithCode: code reason: reason];
}


#pragma mark - SENDING:


- (BLIPRequest*) request
{
    return [[BLIPRequest alloc] _initWithConnection: self body: nil properties: nil];
}

- (BLIPRequest*) requestWithBody: (NSData*)body
                      properties: (NSDictionary*)properties
{
    return [[BLIPRequest alloc] _initWithConnection: self body: body properties: properties];
}

- (BLIPResponse*) sendRequest: (BLIPRequest*)request
{
    if (!request.isMine || request.sent) {
        // This was an incoming request that I'm being asked to forward or echo;
        // or it's an outgoing request being sent to multiple connections.
        // Since a particular BLIPRequest can only be sent once, make a copy of it to send:
        request = [request mutableCopy];
    }
    id<BLIPMessageSender> itsConnection = request.connection;
    if( itsConnection==nil )
        request.connection = self;
    else
        Assert(itsConnection==self,@"%@ is already assigned to a different BLIPConnection",request);
    return [request send];
}


- (void) _queueMessage: (BLIPMessage*)msg isNew: (BOOL)isNew
{
    NSInteger n = _outBox.count, index;
    if( msg.urgent && n > 1 ) {
        // High-priority gets queued after the last existing high-priority message,
        // leaving one regular-priority message in between if possible.
        for( index=n-1; index>0; index-- ) {
            BLIPMessage *otherMsg = _outBox[index];
            if( [otherMsg urgent] ) {
                index = MIN(index+2, n);
                break;
            } else if( isNew && otherMsg._bytesWritten==0 ) {
                // But have to keep message starts in order
                index = index+1;
                break;
            }
        }
        if( index==0 )
            index = 1;
    } else {
        // Regular priority goes at the end of the queue:
        index = n;
    }
    if( ! _outBox )
        _outBox = [[NSMutableArray alloc] init];
    [_outBox insertObject: msg atIndex: index];
    
    if( isNew ) {
        LogTo(BLIP,@"%@ queuing outgoing %@ at index %li",self,msg,(long)index);
        if( n==0 && _webSocketIsOpen )
            [self webSocketReadyForData: _webSocket];  // queue the first message now
    }
}


- (BOOL) _sendMessage: (BLIPMessage*)message
{
    Assert(!message.sent,@"message has already been sent");
    [self _queueMessage: message isNew: YES];
    return YES;
}


- (BOOL) _sendRequest: (BLIPRequest*)q response: (BLIPResponse*)response
{
    if( _webSocketIsOpen && _webSocket.state >= kWebSocketClosing ) {
        Warn(@"%@: Attempt to send a request after the connection has started closing: %@",self,q);
        return NO;
    }
    [q _assignedNumber: ++_numRequestsSent];
    if( response ) {
        [response _assignedNumber: _numRequestsSent];
        [self _addPendingResponse: response];
    }
    return [self _sendMessage: q];
}


- (BOOL) _sendResponse: (BLIPResponse*)response {
    return [self _sendMessage: response];
}


- (void) webSocketReadyForData:(WebSocket *)webSocket {
    if( _outBox.count > 0 ) {
        // Pop first message in queue:
        BLIPMessage *msg = _outBox[0];
        [_outBox removeObjectAtIndex: 0];
        
        // As an optimization, allow message to send a big frame unless there's a higher-priority
        // message right behind it:
        size_t frameSize = kDefaultFrameSize;
        if( msg.urgent || _outBox.count==0 || ! [_outBox[0] urgent] )
            frameSize *= 4;

        BOOL moreComing;
        NSData* frame = [msg nextWebSocketFrameWithMaxSize: frameSize moreComing: &moreComing];
        LogTo(BLIPVerbose,@"%@: Sending frame of %@",self, msg);
        [_webSocket sendBinaryMessage: frame];
        if (moreComing) {
            // add it back so it can send its next frame later:
            [self _queueMessage: msg isNew: NO];
        }
    } else {
        LogTo(BLIPVerbose,@"%@: no more work for writer",self);
    }
}


#pragma mark - RECEIVING FRAMES:


- (BOOL) isBusy
{
    return _pendingRequests.count > 0 || _pendingResponses.count > 0;
}


- (void) _addPendingResponse: (BLIPResponse*)response
{
    _pendingResponses[$object(response.number)] = response;
}


- (void)webSocket:(WebSocket *)webSocket didReceiveBinaryMessage:(NSData*)message {
    size_t frameSize = [message length];
    if (frameSize < kBLIPWebSocketFrameHeaderSize) {
        return;
    }
    
    const BLIPWebSocketFrameHeader* header = [message bytes];
    NSData* body = [message subdataWithRange: NSMakeRange(kBLIPWebSocketFrameHeaderSize,
                                                  frameSize - kBLIPWebSocketFrameHeaderSize)];

    [self receivedFrameWithNumber: NSSwapBigIntToHost(header->number)
                            flags: NSSwapBigShortToHost(header->flags)
                             body: body];
}


- (void) receivedFrameWithNumber: (UInt32)requestNumber
                           flags: (BLIPMessageFlags)flags
                            body: (NSData*)body
{
    static const char* kTypeStrs[16] = {"MSG","RPY","ERR","3??","4??","5??","6??","7??"};
    BLIPMessageType type = flags & kBLIP_TypeMask;
    LogTo(BLIPVerbose,@"%@ rcvd frame of %s #%u, length %lu",self,kTypeStrs[type],(unsigned int)requestNumber,(unsigned long)body.length);

    id key = $object(requestNumber);
    BOOL complete = ! (flags & kBLIP_MoreComing);
    switch(type) {
        case kBLIP_MSG: {
            // Incoming request:
            BLIPRequest *request = _pendingRequests[key];
            if( request ) {
                // Continuation frame of a request:
                if( complete ) {
                    [_pendingRequests removeObjectForKey: key];
                }
            } else if( requestNumber == _numRequestsReceived+1 ) {
                // Next new request:
                request = [[BLIPRequest alloc] _initWithConnection: self
                                                            isMine: NO
                                                             flags: flags | kBLIP_MoreComing
                                                            number: requestNumber
                                                              body: nil];
                if( ! complete )
                    _pendingRequests[key] = request;
                _numRequestsReceived++;
            } else
                return [self _closeWithError: BLIPMakeError(kBLIPError_BadFrame, 
                                               @"Received bad request frame #%u (next is #%u)",
                                               (unsigned int)requestNumber,
                                               (unsigned)_numRequestsReceived+1)];
            
            if( ! [request _receivedFrameWithFlags: flags body: body] )
                return [self _closeWithError: BLIPMakeError(kBLIPError_BadFrame, 
                                               @"Couldn't parse message frame")];
            
            if( complete )
                [self _dispatchRequest: request];
            break;
        }
            
        case kBLIP_RPY:
        case kBLIP_ERR: {
            BLIPResponse *response = _pendingResponses[key];
            if( response ) {
                if( complete ) {
                    [_pendingResponses removeObjectForKey: key];
                }
                
                if( ! [response _receivedFrameWithFlags: flags body: body] ) {
                    return [self _closeWithError: BLIPMakeError(kBLIPError_BadFrame, 
                                                          @"Couldn't parse response frame")];
                } else if( complete ) 
                    [self _dispatchResponse: response];
                
            } else {
                if( requestNumber <= _numRequestsSent )
                    LogTo(BLIP,@"??? %@ got unexpected response frame to my msg #%u",
                          self,(unsigned int)requestNumber); //benign
                else
                    return [self _closeWithError: BLIPMakeError(kBLIPError_BadFrame, 
                                                          @"Bogus message number %u in response",
                                                          (unsigned int)requestNumber)];
            }
            break;
        }
            
        default:
            // To leave room for future expansion, undefined message types are just ignored.
            Log(@"??? %@ received header with unknown message type %i", self,type);
            break;
    }
}


#pragma mark - DISPATCHING:


- (BLIPDispatcher*) dispatcher
{
    if( ! _dispatcher ) {
        _dispatcher = [[BLIPDispatcher alloc] init];
    }
    return _dispatcher;
}


- (BOOL) _dispatchMetaRequest: (BLIPRequest*)request
{
#if 0
    NSString* profile = request.profile;
    if( [profile isEqualToString: kBLIPProfile_Bye] ) {
        [self _handleCloseRequest: request];
        return YES;
    }
#endif
    return NO;
}


- (void) _dispatchRequest: (BLIPRequest*)request
{
    LogTo(BLIP,@"Received all of %@",request.descriptionWithProperties);
    @try{
        BOOL handled;
        if( request._flags & kBLIP_Meta )
            handled =[self _dispatchMetaRequest: request];
        else {
            handled = [self.dispatcher dispatchMessage: request];
            if (!handled && [_delegate respondsToSelector: @selector(blipWebSocket:receivedRequest:)])
                handled = [_delegate blipWebSocket: self receivedRequest: request];
        }
        
        if (!handled) {
            LogTo(BLIP,@"No handler found for incoming %@",request);
            [request respondWithErrorCode: kBLIPError_NotFound message: @"No handler was found"];
        } else if( ! request.noReply && ! request.repliedTo ) {
            LogTo(BLIP,@"Returning default empty response to %@",request);
            [request respondWithData: nil contentType: nil];
        }
    }@catch( NSException *x ) {
        MYReportException(x,@"Dispatching BLIP request");
        [request respondWithException: x];
    }
}

- (void) _dispatchResponse: (BLIPResponse*)response
{
    LogTo(BLIP,@"Received all of %@",response);
    if ([_delegate respondsToSelector: @selector(blipWebSocket:receivedResponse:)])
        [_delegate blipWebSocket: self receivedResponse: response];
}


@end
