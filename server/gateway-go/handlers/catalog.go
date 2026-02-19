package handlers

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"

	"github.com/aioc/gateway/models"
)

type useCaseCatalog struct {
	Roles         []models.UseCaseRole         `json:"roles"`
	GenericSkills []models.UseCaseGenericSkill `json:"generic_skills"`
	Skills        []models.SkillDescriptor     `json:"skills"`
}

func loadUseCaseCatalog() (*useCaseCatalog, error) {
	candidates := make([]string, 0, 6)
	if envPath := os.Getenv("AIOC_USE_CASES_FILE"); envPath != "" {
		candidates = append(candidates, envPath)
	}
	candidates = append(
		candidates,
		"config/usecases.json",
		"configs/usecases.json",
		"/app/config/usecases.json",
		"/app/configs/usecases.json",
		"server/gateway-go/config/usecases.json",
	)

	var (
		b   []byte
		err error
	)
	for _, p := range candidates {
		b, err = os.ReadFile(p)
		if err == nil {
			break
		}
	}
	if err != nil {
		return nil, fmt.Errorf("usecases catalog not found in candidates: %v", candidates)
	}
	b = bytes.TrimPrefix(b, []byte{0xEF, 0xBB, 0xBF})

	var catalog useCaseCatalog
	if err := json.Unmarshal(b, &catalog); err != nil {
		return nil, err
	}
	return &catalog, nil
}
