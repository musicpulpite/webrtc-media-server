package main

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/pion/webrtc/v4"
)

func main() {
	// Create PeerConnection configuration
	config := webrtc.Configuration{
		ICEServers: []webrtc.ICEServer{
			{
				URLs: []string{
					"stun:stun.l.google.com:19302",
					"stun:stun1.l.google.com:19302",
					"stun:stun2.l.google.com:19302",
					"stun:stun3.l.google.com:19302",
				},
			},
		},
	}

	// Create new PeerConnection
	peerConnection, err := webrtc.NewPeerConnection(config)
	if err != nil {
		panic(err)
	}
	defer func() {
		if cErr := peerConnection.Close(); cErr != nil {
			fmt.Printf("cannot close perrConnection: %v\n", cErr)
		}
	}()

	peerConnection.OnConnectionStateChange(func(s webrtc.PeerConnectionState) {
		fmt.Printf("Peer Connection State has changed: %s\n", s.String())
	})
	peerConnection.OnDataChannel(func(d *webrtc.DataChannel) {
		fmt.Printf("New DataChannel %s %d\n", d.Label(), d.ID())
	})
	peerConnection.OnICEConnectionStateChange(func(connectionState webrtc.ICEConnectionState) {
		fmt.Printf("ICE Connection State has changed: %s\n", connectionState.String())
		if connectionState == webrtc.ICEConnectionStateFailed {
			// Print the current connection stats when it fails
			stats := peerConnection.GetStats()
			fmt.Printf("Connection stats at failure: %+v\n", stats)
		}
	})
	peerConnection.OnConnectionStateChange(func(s webrtc.PeerConnectionState) {
		fmt.Printf("Peer Connection State has changed: %s\n", s.String())
	})
	peerConnection.OnSignalingStateChange(func(s webrtc.SignalingState) {
		fmt.Printf("Signaling State has changed: %s\n", s.String())
	})
	peerConnection.OnICEGatheringStateChange(func(s webrtc.ICEGatheringState) {
		fmt.Printf("ICE Gathering State has changed: %s\n", s.String())
	})
	peerConnection.OnICECandidate(func(i *webrtc.ICECandidate) {
		if i != nil {
			fmt.Printf("Received ICE candidate: %s\n", i.String())
		}
	})

	// important callbacks for handling data channel messages
	peerConnection.OnDataChannel(func(dataChannel *webrtc.DataChannel) {
		// Set up DataChannel handlers
		dataChannel.OnOpen(func() {
			fmt.Println("Data channel is open")
		})
		dataChannel.OnMessage(func(msg webrtc.DataChannelMessage) {
			NewMessageHandler(dataChannel).ProcessMessage(msg)
		})
	})

	// Create the gathering complete promise
	gatherComplete := webrtc.GatheringCompletePromise(peerConnection)

	// Using the pattern: client sends offer, server sends answer
	offer := webrtc.SessionDescription{}
	decode(os.Getenv("REMOTE_SESSION_DESCRIPTION"), &offer)

	err = peerConnection.SetRemoteDescription(offer)
	if err != nil {
		panic(err)
	}

	answer, err := peerConnection.CreateAnswer(nil)
	if err != nil {
		panic(err)
	}

	err = peerConnection.SetLocalDescription(answer)
	if err != nil {
		panic(err)
	}

	// Wait for ICE gathering to complete with timeout
	fmt.Println("Waiting for ICE gathering to complete...")
	select {
	case <-time.After(10 * time.Second):
		fmt.Println("ICE gathering timed out")
	case <-gatherComplete:
		fmt.Println("ICE gathering completed")
	}

	// Answer to be passed to client
	fmt.Println(encode(peerConnection.LocalDescription()))

	done := make(chan os.Signal, 1)
	// Wait for shutdown signal
	signal.Notify(done, syscall.SIGINT, syscall.SIGTERM)
	// Block until signal received
	<-done
}

// JSON encode + base64 a SessionDescription
func encode(obj *webrtc.SessionDescription) string {
	b, err := json.Marshal(obj)
	if err != nil {
		panic(err)
	}

	return base64.StdEncoding.EncodeToString(b)
}

// Decode a base64 and unmarshal JSON into a SessionDescription
func decode(in string, obj *webrtc.SessionDescription) {
	decoded, err := base64.StdEncoding.DecodeString(in)
	if err != nil {
		panic(err)
	}

	if err = json.Unmarshal(decoded, obj); err != nil {
		panic(err)
	}
}
