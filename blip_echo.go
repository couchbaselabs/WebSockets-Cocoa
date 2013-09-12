package main

import (
	"fmt"
	"log"
	"net/http"

	"github.com/snej/go-blip"
)

func dispatchEcho(request *blip.Message) {
	body, err := request.Body()
	if err != nil {
		log.Printf("ERROR reading body of %s: %s", request, err)
		return
	}
	log.Printf("Got request, properties = %v", request.Properties)
	DumpByteArray(body)
	if response := request.Response(); response != nil {
		response.SetBody(body)
		response.Properties["Content-Type"] = request.Properties["Content-Type"]
	}
}

func main() {
	context := blip.NewContext()
	context.LogFrames = true
	context.HandlerForProfile["BLIPTest/EchoData"] = dispatchEcho
	http.Handle("/blip", context.HTTPHandler())
	log.Printf("Listening on :12345/blip ...")
	if err := http.ListenAndServe(":12345", nil); err != nil {
		panic("ListenAndServe: " + err.Error())
	}
}

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
