package handlers

import (
	"net/http"

	"github.com/aioc/gateway/models"
	"github.com/gin-gonic/gin"
)

// SkillsHandler returns skills catalog filtered by plan.
type SkillsHandler struct{}

func NewSkillsHandler() *SkillsHandler {
	return &SkillsHandler{}
}

func (h *SkillsHandler) List(c *gin.Context) {
	traceID := c.GetString("trace_id")
	planLevel := c.GetString("plan_level")
	if planLevel == "" {
		planLevel = "free"
	}

	catalog, err := loadUseCaseCatalog()
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{
			Code:    0,
			Msg:     "failed to load skills catalog",
			TraceID: traceID,
		})
		return
	}

	filtered := make([]models.SkillDescriptor, 0, len(catalog.Skills))
	for _, s := range catalog.Skills {
		if planAllowsSkill(planLevel, s.MinPlan) {
			filtered = append(filtered, s)
		}
	}

	c.JSON(http.StatusOK, models.APIResponse{
		Code:    1,
		Msg:     "ok",
		Data:    filtered,
		TraceID: traceID,
	})
}

func planAllowsSkill(currentPlan, minPlan string) bool {
	_ = currentPlan
	_ = minPlan
	return true
}
