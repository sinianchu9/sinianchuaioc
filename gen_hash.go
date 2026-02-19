package main

import (
	"os"

	"golang.org/x/crypto/bcrypt"
)

func main() {
	password := "123456"
	hash, _ := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	os.WriteFile("full_hash.txt", hash, 0644)
	println(string(hash))
}
