package main

import (
    "log"
    "net/http"

    "code.google.com/p/go.net/websocket"
)

// Echo the data received on the WebSocket.
func EchoServer(ws *websocket.Conn) {
    log.Printf("Got a connection!");
    buffer := make([]byte, 8000)
    var err error
    for {
        var nBytes int
        nBytes, err = ws.Read(buffer)
        if err != nil {
            break
        }
        frame := buffer[:nBytes]
        log.Printf("Read frame: %s", frame);
        ws.Write(frame);
    }
    log.Printf("Connection closed with error: %v", err)
}

// This example demonstrates a trivial echo server.
func main() {
    log.Printf("Listening on :12345 ...");
    
    server := websocket.Server{ Handler: EchoServer }
    http.Handle("/echo", server)
    if err := http.ListenAndServe(":12345", nil); err != nil {
        panic("ListenAndServe: " + err.Error())
    }
}