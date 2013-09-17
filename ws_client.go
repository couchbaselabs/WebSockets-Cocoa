package main

import (
	"fmt"
	"log"

	"code.google.com/p/go.net/websocket"
)

// Connect to a WebSocket server and exchange messages.
func main() {
	url := "ws://localhost:2345/ws"
	origin := "http://localhost"
    ws, err := websocket.Dial(url, "", origin)
	if err != nil {
	    log.Fatal(err)
	}
	if _, err := ws.Write([]byte("hello, world!\n")); err != nil {
	    log.Fatal(err)
	}
	var msg = make([]byte, 512)
	var n int
	if n, err = ws.Read(msg); err != nil {
	    log.Fatal(err)
	}
	fmt.Printf("Received: %s.\n", msg[:n])
}
