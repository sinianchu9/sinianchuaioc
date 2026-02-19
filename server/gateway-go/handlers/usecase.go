package handlers

import (
	"net/http"

	"github.com/aioc/gateway/models"
	"github.com/gin-gonic/gin"
)

type UseCaseHandler struct{}

func NewUseCaseHandler() *UseCaseHandler {
	return &UseCaseHandler{}
}

func (h *UseCaseHandler) List(c *gin.Context) {
	traceID := c.GetString("trace_id")
	planLevel := c.GetString("plan_level")
	if planLevel == "" {
		planLevel = "free"
	}

	catalog, err := loadUseCaseCatalog()
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{
			Code:    0,
			Msg:     "failed to load use-case catalog",
			TraceID: traceID,
		})
		return
	}

	allowedSkillIDs := map[string]struct{}{}
	for _, s := range catalog.Skills {
		if planAllowsSkill(planLevel, s.MinPlan) {
			allowedSkillIDs[s.ID] = struct{}{}
		}
	}

	filteredRoles := make([]models.UseCaseRole, 0, len(catalog.Roles))
	for _, role := range catalog.Roles {
		tasks := make([]models.UseCaseTask, 0, len(role.Tasks))
		for _, t := range role.Tasks {
			if !planAllowsSkill(planLevel, t.MinPlan) {
				continue
			}
			allReady := true
			for _, sid := range t.DefaultSkills {
				if _, ok := allowedSkillIDs[sid]; !ok {
					allReady = false
					break
				}
			}
			if allReady {
				tasks = append(tasks, t)
			}
		}
		if len(tasks) == 0 {
			continue
		}
		role.Tasks = tasks
		filteredRoles = append(filteredRoles, role)
	}

	generic := make([]models.UseCaseGenericSkill, 0, len(catalog.GenericSkills))
	for _, g := range catalog.GenericSkills {
		if _, ok := allowedSkillIDs[g.ID]; ok {
			generic = append(generic, g)
		}
	}

	data := map[string]any{
		"roles":          filteredRoles,
		"generic_skills": generic,
	}

	c.JSON(http.StatusOK, models.APIResponse{
		Code:    1,
		Msg:     "ok",
		Data:    data,
		TraceID: traceID,
	})
}
