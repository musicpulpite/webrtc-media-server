package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"strconv"
	"time"
)

type OllamaRequest struct {
	Model  string `json:"model"`
	Prompt string `json:"prompt"`
}

type OllamaResponse struct {
	Response string `json:"response"`
	Done     bool   `json:"done"`
}

type OllamaWrapper struct {
	ollamaModel         string
	serverCmd           *exec.Cmd
	serverCmdCancelFunc *context.CancelFunc
}

func NewOllamaWrapper() *OllamaWrapper {
	ollamaModel := os.Getenv("OLLAMA_MODEL")
	if ollamaModel == "" {
		ollamaModel = "llama3.2"
	}

	return &OllamaWrapper{
		ollamaModel: ollamaModel,
	}
}

func (ow *OllamaWrapper) waitForServer(timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		resp, err := http.Get("http://localhost:11434/api/version")
		if err == nil {
			resp.Body.Close()
			return nil
		}
		time.Sleep(100 * time.Millisecond)
	}
	return fmt.Errorf("server failed to start within %s", timeout)
}

func (ow *OllamaWrapper) Initialize() error {
	ctx, cancel := context.WithCancel(context.Background())
	ollamaServerCmd := exec.CommandContext(ctx, "ollama", "serve")

	ollamaServerCmd.Stdout = os.Stdout
	ollamaServerCmd.Stderr = os.Stderr

	ow.serverCmd = ollamaServerCmd
	ow.serverCmdCancelFunc = &cancel

	if err := ollamaServerCmd.Start(); err != nil {
		panic(err)
	}

	serverGracePeriod := os.Getenv("SERVER_GRACE_PERIOD")
	if serverGracePeriod == "" {
		serverGracePeriod = "5"
	}
	serverGracePeriodInt, _ := strconv.Atoi(serverGracePeriod)
	if err := ow.waitForServer(time.Duration(serverGracePeriodInt) * time.Second); err != nil {
		return err
	}
	return nil
}

func (ow *OllamaWrapper) Close() error {
	(*ow.serverCmdCancelFunc)()

	if err := ow.serverCmd.Process.Signal(os.Interrupt); err != nil {
		return err
	}
	err := ow.serverCmd.Wait()
	if err != nil {
		if err.Error() != "signal: interrupt" && err.Error() != "signal: killed" {
			return err
		}
	}

	return nil
}

func (ow *OllamaWrapper) Query(prompt string) (string, error) {
	requestBody := OllamaRequest{
		Model:  ow.ollamaModel,
		Prompt: prompt,
	}

	jsonData, err := json.Marshal(requestBody)
	if err != nil {
		return "", fmt.Errorf("error marshaling request: %v", err)
	}

	resp, err := http.Post(
		"http://localhost:11434/api/generate",
		"application/json",
		bytes.NewBuffer(jsonData),
	)
	if err != nil {
		return "", fmt.Errorf("error making localhost http request: %v", err)
	}
	defer resp.Body.Close()

	var fullResponse string
	scanner := bufio.NewScanner(resp.Body)
	for scanner.Scan() {
		var response OllamaResponse
		if err := json.Unmarshal(scanner.Bytes(), &response); err != nil {
			return "", fmt.Errorf("error unmarshaling response: %v", err)
		}
		fullResponse += response.Response
	}

	if err := scanner.Err(); err != nil {
		return "", fmt.Errorf("error reading response: %v", err)
	}

	return fullResponse, nil
}

//func main() {
//	ollamaWrapper := NewOllamaWrapper()
//	ollamaWrapper.Initialize()
//	response, err := ollamaWrapper.Query("What is my name?")
//        if err != nil {
//        	fmt.Printf("Error querying Ollama: %v\n", err)
//        } else {
//        	fmt.Printf("Response: %s\n", response)
//        }
//	ollamaWrapper.Close()
//}
