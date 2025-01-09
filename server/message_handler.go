package main

import (
	"fmt"

	"github.com/pion/webrtc/v4"
)

type MessageHandler struct {
	dataChannel   *webrtc.DataChannel
	ollamaWrapper *OllamaWrapper
}

func NewMessageHandler(dataChannel *webrtc.DataChannel) *MessageHandler {
	ollamaWrapper := NewOllamaWrapper()
	ollamaWrapper.Initialize()
	return &MessageHandler{
		dataChannel:   dataChannel,
		ollamaWrapper: ollamaWrapper,
	}
}

func (mh *MessageHandler) ProcessMessage(msg webrtc.DataChannelMessage) {
	fmt.Printf("Message from DataChannel '%s': '%s'\n", mh.dataChannel.Label(), string(msg.Data))

	response, queryErr := mh.ollamaWrapper.Query(string(msg.Data))
	if queryErr != nil {
		panic(queryErr)
	}
	if sendErr := mh.dataChannel.SendText(response); sendErr != nil {
		panic(sendErr)
	}
}
