package handlers

import (
	"context"
	"net/http"
	"time"

	"github.com/aioc/gateway/middleware"
	"github.com/aioc/gateway/models"
	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/crypto/bcrypt"
)

// AuthHandler handles authentication endpoints
type AuthHandler struct {
	db        *pgxpool.Pool
	jwtSecret string
	expireH   int
	refreshH  int
}

// NewAuthHandler creates a new auth handler
func NewAuthHandler(db *pgxpool.Pool, secret string, expireH, refreshH int) *AuthHandler {
	return &AuthHandler{
		db:        db,
		jwtSecret: secret,
		expireH:   expireH,
		refreshH:  refreshH,
	}
}

// Login handles POST /api/v1/auth/login
func (h *AuthHandler) Login(c *gin.Context) {
	traceID := c.GetString("trace_id")

	var req models.LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.APIResponse{
			Code:    0,
			Msg:     "invalid request: " + err.Error(),
			TraceID: traceID,
		})
		return
	}

	// Look up user
	var user models.User
	var passwordHash string
	err := h.db.QueryRow(context.Background(),
		`SELECT u.user_id, u.tenant_id, u.email, u.password_hash, u.display_name, u.roles, u.status
		 FROM users u WHERE u.email = $1`,
		req.Email,
	).Scan(&user.UserID, &user.TenantID, &user.Email, &passwordHash, &user.DisplayName, &user.Roles, &user.Status)

	if err != nil {
		c.JSON(http.StatusUnauthorized, models.APIResponse{
			Code:    0,
			Msg:     "invalid email or password",
			TraceID: traceID,
		})
		return
	}

	if user.Status != "active" {
		c.JSON(http.StatusForbidden, models.APIResponse{
			Code:    0,
			Msg:     "account has been suspended",
			TraceID: traceID,
		})
		return
	}

	// Verify password
	if err := bcrypt.CompareHashAndPassword([]byte(passwordHash), []byte(req.Password)); err != nil {
		c.JSON(http.StatusUnauthorized, models.APIResponse{
			Code:    0,
			Msg:     "invalid email or password",
			TraceID: traceID,
		})
		return
	}

	// Generate JWT tokens
	now := time.Now()
	accessToken, err := h.generateToken(user, now, time.Duration(h.expireH)*time.Hour, "access")
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{
			Code:    0,
			Msg:     "failed to generate token",
			TraceID: traceID,
		})
		return
	}

	refreshToken, err := h.generateToken(user, now, time.Duration(h.refreshH)*time.Hour, "refresh")
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{
			Code:    0,
			Msg:     "failed to generate refresh token",
			TraceID: traceID,
		})
		return
	}

	c.JSON(http.StatusOK, models.APIResponse{
		Code: 1,
		Msg:  "login successful",
		Data: models.LoginResponse{
			AccessToken:  accessToken,
			RefreshToken: refreshToken,
			ExpiresIn:    h.expireH * 3600,
			User: &models.User{
				UserID:      user.UserID,
				TenantID:    user.TenantID,
				Email:       user.Email,
				DisplayName: user.DisplayName,
				Roles:       user.Roles,
				Status:      user.Status,
			},
		},
		TraceID: traceID,
	})
}

// Refresh handles POST /api/v1/auth/refresh
func (h *AuthHandler) Refresh(c *gin.Context) {
	traceID := c.GetString("trace_id")

	var req models.RefreshRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.APIResponse{
			Code:    0,
			Msg:     "invalid request: " + err.Error(),
			TraceID: traceID,
		})
		return
	}

	// Parse the refresh token
	claims := &middleware.JWTClaims{}
	token, err := jwt.ParseWithClaims(req.RefreshToken, claims, func(token *jwt.Token) (interface{}, error) {
		return []byte(h.jwtSecret), nil
	})

	if err != nil || !token.Valid {
		c.JSON(http.StatusUnauthorized, models.APIResponse{
			Code:    0,
			Msg:     "invalid or expired refresh token",
			TraceID: traceID,
		})
		return
	}
	if claims.TokenType != "refresh" {
		c.JSON(http.StatusUnauthorized, models.APIResponse{
			Code:    0,
			Msg:     "invalid token type for refresh",
			TraceID: traceID,
		})
		return
	}

	// Look up the user again to get fresh data
	var user models.User
	err = h.db.QueryRow(context.Background(),
		`SELECT user_id, tenant_id, email, display_name, roles, status
		 FROM users WHERE user_id = $1`,
		claims.UserID,
	).Scan(&user.UserID, &user.TenantID, &user.Email, &user.DisplayName, &user.Roles, &user.Status)

	if err != nil || user.Status != "active" {
		c.JSON(http.StatusUnauthorized, models.APIResponse{
			Code:    0,
			Msg:     "user not found or inactive",
			TraceID: traceID,
		})
		return
	}

	now := time.Now()
	accessToken, err := h.generateToken(user, now, time.Duration(h.expireH)*time.Hour, "access")
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{
			Code:    0,
			Msg:     "failed to generate token",
			TraceID: traceID,
		})
		return
	}

	refreshToken, err := h.generateToken(user, now, time.Duration(h.refreshH)*time.Hour, "refresh")
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{
			Code:    0,
			Msg:     "failed to generate refresh token",
			TraceID: traceID,
		})
		return
	}

	c.JSON(http.StatusOK, models.APIResponse{
		Code: 1,
		Msg:  "token refreshed",
		Data: models.LoginResponse{
			AccessToken:  accessToken,
			RefreshToken: refreshToken,
			ExpiresIn:    h.expireH * 3600,
		},
		TraceID: traceID,
	})
}

func (h *AuthHandler) generateToken(user models.User, now time.Time, duration time.Duration, tokenType string) (string, error) {
	claims := middleware.JWTClaims{
		UserID:    user.UserID.String(),
		TenantID:  user.TenantID.String(),
		Email:     user.Email,
		Roles:     user.Roles,
		TokenType: tokenType,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(now.Add(duration)),
			IssuedAt:  jwt.NewNumericDate(now),
			Issuer:    "aioc",
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString([]byte(h.jwtSecret))
}
