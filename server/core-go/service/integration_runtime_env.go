package service

import (
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"log"
	"os"
	"strings"
)

var runtimeIntegrationIDs = []string{"ocr.api", "asr.api", "tts.api", "search.brave"}
var runtimeSecretAllowList = map[string]struct{}{
	"OCR_API_BASE_URL": {},
	"OCR_API_TOKEN":    {},
	"OCR_MODEL":        {},
	"ASR_API_BASE_URL": {},
	"ASR_API_TOKEN":    {},
	"ASR_MODEL":        {},
	"TTS_API_BASE_URL": {},
	"TTS_API_TOKEN":    {},
	"TTS_VOICE":        {},
	"BRAVE_API_KEY":    {},
}

func (s *ChatService) loadIntegrationRuntimeEnv(ctx context.Context, tenantID string) map[string]string {
	if s.db == nil || strings.TrimSpace(tenantID) == "" {
		return map[string]string{}
	}

	rows, err := s.db.Query(ctx, `
SELECT s.secret_key_name, s.secret_ciphertext
  FROM integration_secrets s
  JOIN integrations i
    ON i.tenant_id = s.tenant_id
   AND i.id = s.integration_id
 WHERE s.tenant_id = $1
   AND i.is_enabled = true
   AND i.id = ANY($2)
`, tenantID, runtimeIntegrationIDs)
	if err != nil {
		// Keep request path resilient during rollout or before migration.
		log.Printf("loadIntegrationRuntimeEnv skipped: %v", err)
		return map[string]string{}
	}
	defer rows.Close()

	out := map[string]string{}
	for rows.Next() {
		var keyName, cipherText string
		if err := rows.Scan(&keyName, &cipherText); err != nil {
			continue
		}
		if _, ok := runtimeSecretAllowList[keyName]; !ok {
			continue
		}
		plain, err := decryptRuntimeSecret(cipherText)
		if err != nil {
			continue
		}
		out[keyName] = plain
	}
	return out
}

func decryptRuntimeSecret(ciphertext string) (string, error) {
	key, err := deriveRuntimeMasterKey()
	if err != nil {
		return "", err
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return "", err
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return "", err
	}
	raw, err := base64.StdEncoding.DecodeString(ciphertext)
	if err != nil {
		return "", err
	}
	nonceSize := aead.NonceSize()
	if len(raw) < nonceSize {
		return "", errors.New("invalid ciphertext payload")
	}
	nonce := raw[:nonceSize]
	enc := raw[nonceSize:]
	plain, err := aead.Open(nil, nonce, enc, nil)
	if err != nil {
		return "", err
	}
	return string(plain), nil
}

func deriveRuntimeMasterKey() ([]byte, error) {
	raw := strings.TrimSpace(os.Getenv("MASTER_KEY"))
	if raw == "" {
		// Fallback for local dev environments where gateway+core share same process env setup.
		raw = strings.TrimSpace(os.Getenv("AIOC_MASTER_KEY"))
	}
	if raw == "" {
		return nil, os.ErrNotExist
	}
	if decoded, err := base64.StdEncoding.DecodeString(raw); err == nil && len(decoded) == 32 {
		return decoded, nil
	}
	sum := sha256.Sum256([]byte(raw))
	return sum[:], nil
}
