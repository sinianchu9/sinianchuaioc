package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
)

func main() {
	loginBody := map[string]string{
		"email":    "admin@aioc.internal",
		"password": "123456",
	}
	jb, _ := json.Marshal(loginBody)
	resp, err := http.Post("http://localhost:8080/api/v1/auth/login", "application/json", bytes.NewReader(jb))
	if err != nil {
		fmt.Printf("Login failed: %v\n", err)
		os.Exit(1)
	}
	defer resp.Body.Close()

	var loginResult struct {
		Data struct {
			AccessToken string `json:"access_token"`
		} `json:"data"`
	}
	json.NewDecoder(resp.Body).Decode(&loginResult)
	token := loginResult.Data.AccessToken
	fmt.Printf("Token obtained\n")

	// 2. Chat Stream
	chatBody := map[string]any{
		"mode": "economy",
		"messages": []map[string]string{
			{"role": "user", "content": "reply 123"},
		},
	}
	jb, _ = json.Marshal(chatBody)
	req, _ := http.NewRequest("POST", "http://localhost:8080/api/v1/chat/stream", bytes.NewReader(jb))
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Client-Id", "00000000-0000-0000-0000-000000000102")
	req.Header.Set("X-Client-Version", "1.0.0")

	fmt.Printf("Connecting to stream...\n")
	resp, err = http.DefaultClient.Do(req)
	if err != nil {
		fmt.Printf("Stream request failed: %v\n", err)
		os.Exit(1)
	}
	defer resp.Body.Close()

	fmt.Printf("Status: %d\n", resp.StatusCode)
	if resp.StatusCode != 200 {
		buf := new(bytes.Buffer)
		buf.ReadFrom(resp.Body)
		fmt.Printf("Error Body: %s\n", buf.String())
		return
	}

	reader := bufio.NewReader(resp.Body)
	for {
		line, err := reader.ReadString('\n')
		if err != nil {
			fmt.Printf("Stream end: %v\n", err)
			break
		}
		if line != "\n" {
			fmt.Print(line)
		}
	}
}
