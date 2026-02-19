# AIOC Security Policy

## License Compliance

- **OpenClaw**: MIT License (Copyright 2025 Peter Steinberger)
  - ✅ Allows commercial use
  - ✅ Allows modification
  - ✅ Allows distribution
  - ✅ Allows sublicensing
  - ⚠️ Requires copyright notice retention
- **AIOC Strategy**: New code written from scratch. OpenClaw code in `/demo` is reference-only, never directly modified or included.

## Authentication & Authorization

- JWT (HS256) with configurable expiry (default 24h)
- Refresh tokens with 7-day expiry
- Role-based access (admin, user)
- Tenant isolation: all queries scoped by `tenant_id`

## Data Protection

- Passwords: bcrypt hashed (cost factor 10)
- API Keys: stored only in environment variables, never logged
- Sensitive fields: token, key, password, receipt are masked in JSON logs
- Audit logs: prompt/response snapshots truncated to 10KB max
- Database: all cost fields use `decimal(18,6)` for precision

## Anti-Piracy & DRM

- Client ID registration and version enforcement
- Server-side feature toggles (`/client/capabilities`)
- Server-side IAP receipt verification (Apple/Google)
- Instant ban capability: tenant, user, or client_id
- All capabilities gated by plan_level

## Rate Limiting & Circuit Breaker

- Per-user rate limiting: configurable requests/minute (default 60)
- Cost circuit breaker: $5.00/min threshold per user (configurable)
- Automatic blocking on anomalous cost patterns
- Client-side debounce required (enforced in Flutter client)

## Infrastructure Security

- PostgreSQL: credentials via env vars, not config files
- Redis: password-protected in production
- CORS: configurable allowed origins
- All inter-service communication via internal Docker network
- Enterprise: supports IP whitelist and LDAP/SAML (Phase 4)
