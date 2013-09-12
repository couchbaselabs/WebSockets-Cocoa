package main

import (
	"bytes"
	"encoding/binary"
	"fmt"
	"log"
	"net/http"

	"code.google.com/p/go.net/websocket"
)

func DumpByteArray(frame []byte) {
	for line := 0; line <= 1; line++ {
		fmt.Print("\t")
		for i := 0; i < len(frame); i += 4 {
			end := i + 4
			if end > len(frame) {
				end = len(frame)
			}
			chunk := frame[i:end]
			if line == 0 {
				fmt.Printf("%x", chunk)
			} else {
				for _, c := range chunk {
					if c < ' ' || c >= 127 {
						c = ' '
					}
					fmt.Printf("%c ", c)
				}
			}
			fmt.Print(" ")
		}
		fmt.Printf("\n")
	}
}

// Dump structure of a BLIP frame
func DumpBLIPHandler(frame []byte) []byte {
	reader := bytes.NewReader(frame)
	var sequence uint32
	var flags uint16
	binary.Read(reader, binary.BigEndian, &sequence)
	binary.Read(reader, binary.BigEndian, &flags)
	log.Printf("Frame #%4d  flags = %016b", sequence, flags)
	DumpByteArray(frame[6:])
	return nil
}

// Echo the data received on the WebSocket.
func DumpHandler(frame []byte) []byte {
	DumpByteArray(frame)
	return nil
}

// Echo the data received on the WebSocket.
func EchoHandler(frame []byte) []byte {
	log.Printf("Read frame: %q", frame)
	return frame
}

// Echo the data received on the WebSocket.
func NewWebSocketHandler(fn func([]byte) []byte) http.Handler {
	var server websocket.Server
	server.Handler = func(ws *websocket.Conn) {
		log.Printf("--- Received connection")
		buffer := make([]byte, 8000)
		var err error
		for {
			var nBytes int
			nBytes, err = ws.Read(buffer)
			if err != nil {
				break
			}
			frame := buffer[:nBytes]
			if response := fn(frame); response != nil {
				ws.Write(response)
			}
		}
		log.Printf("--- End connection (%v)", err)
	}
	return server
}

// This example demonstrates a trivial echo server.
func main() {
	log.Printf("Listening on :12345 ...")

	http.Handle("/dump", NewWebSocketHandler(DumpHandler))
	http.Handle("/blip", NewWebSocketHandler(DumpBLIPHandler))
	http.Handle("/echo", NewWebSocketHandler(EchoHandler))

	if err := http.ListenAndServe(":12345", nil); err != nil {
		panic("ListenAndServe: " + err.Error())
	}
}
