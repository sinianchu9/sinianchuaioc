package handlers

import (
	"context"
	"net/http"
	"time"

	"github.com/aioc/gateway/models"
	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/shopspring/decimal"
)

// BillingHandler handles billing-related endpoints
type BillingHandler struct {
	db *pgxpool.Pool
}

// NewBillingHandler creates a new billing handler
func NewBillingHandler(db *pgxpool.Pool) *BillingHandler {
	return &BillingHandler{db: db}
}

// Summary handles GET /api/v1/billing/summary
func (h *BillingHandler) Summary(c *gin.Context) {
	traceID := c.GetString("trace_id")
	userID := c.GetString("user_id")
	tenantID := c.GetString("tenant_id")

	// Get period from query, default to current month
	period := c.DefaultQuery("period", time.Now().Format("2006-01"))

	// Parse period to get start/end dates
	startDate, err := time.Parse("2006-01", period)
	if err != nil {
		c.JSON(http.StatusBadRequest, models.APIResponse{
			Code:    0,
			Msg:     "invalid period format, expected YYYY-MM",
			TraceID: traceID,
		})
		return
	}
	endDate := startDate.AddDate(0, 1, 0)

	// Query billing summary
	var totalTokensIn, totalTokensOut, requestCount int64
	var totalCost decimal.Decimal

	err = h.db.QueryRow(context.Background(),
		`SELECT COALESCE(SUM(tokens_in), 0), COALESCE(SUM(tokens_out), 0),
		        COALESCE(SUM(cost), 0), COUNT(*)
		 FROM billing_logs
		 WHERE user_id = $1 AND tenant_id = $2
		   AND ts >= $3 AND ts < $4`,
		userID, tenantID, startDate, endDate,
	).Scan(&totalTokensIn, &totalTokensOut, &totalCost, &requestCount)

	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{
			Code:    0,
			Msg:     "failed to query billing summary",
			TraceID: traceID,
		})
		return
	}

	// Get tenant balance and plan
	var balance decimal.Decimal
	var planLevel string
	err = h.db.QueryRow(context.Background(),
		"SELECT balance, plan_level FROM tenants WHERE tenant_id = $1",
		tenantID,
	).Scan(&balance, &planLevel)

	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{
			Code:    0,
			Msg:     "failed to query tenant info",
			TraceID: traceID,
		})
		return
	}

	c.JSON(http.StatusOK, models.APIResponse{
		Code: 1,
		Msg:  "ok",
		Data: models.BillingSummary{
			TotalTokensIn:  totalTokensIn,
			TotalTokensOut: totalTokensOut,
			TotalCost:      totalCost.StringFixed(6),
			RequestCount:   requestCount,
			PlanLevel:      planLevel,
			Balance:        balance.StringFixed(6),
			Period:         period,
		},
		TraceID: traceID,
	})
}

// VerifyReceipt handles POST /api/v1/billing/verify_receipt (skeleton)
func (h *BillingHandler) VerifyReceipt(c *gin.Context) {
	traceID := c.GetString("trace_id")

	var req models.VerifyReceiptRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.APIResponse{
			Code:    0,
			Msg:     "invalid request: " + err.Error(),
			TraceID: traceID,
		})
		return
	}

	// TODO: Implement actual receipt verification with Apple/Google servers
	// For now, return a placeholder response
	c.JSON(http.StatusOK, models.APIResponse{
		Code: 1,
		Msg:  "receipt verification is not yet implemented (skeleton)",
		Data: map[string]any{
			"verified":  false,
			"platform":  req.Platform,
			"reason":    "receipt verification service not configured",
		},
		TraceID: traceID,
	})
}
