# AIOC Billing System

## Overview

AIOC uses a metered billing system with per-request cost tracking at `decimal(18,6)` precision.

## Plan Levels

| Plan       | Monthly | Token Quota | Models             | Features            |
| ---------- | ------- | ----------- | ------------------ | ------------------- |
| Free       | $0      | 10,000      | Economy            | Chat, Stream        |
| Pro        | $20     | 1,000,000   | Economy, Precision | + Tools             |
| Team       | $50     | 5,000,000   | Economy, Precision | + RAG               |
| Enterprise | Custom  | Unlimited   | All + Privacy      | + SSO, Audit Export |

## Model Pricing (Per 1M Tokens)

| Model         | Input  | Output |
| ------------- | ------ | ------ |
| DeepSeek Chat | $0.14  | $0.28  |
| GPT-4         | $30.00 | $60.00 |
| GPT-4o-mini   | $0.15  | $0.60  |
| Ollama/Llama3 | $0.00  | $0.00  |

## Cost Calculation

```
cost = (tokens_in × input_price / 1M) + (tokens_out × output_price / 1M)
```

All calculations use `decimal` library (not floating point) to avoid rounding errors.

## Billing Flow

1. **Pre-check** (Gateway): Verify plan active, balance > 0
2. **Request** (Core): Execute LLM call
3. **Post-calculation** (Core): Compute tokens & cost
4. **Log** (Core): Write to `billing_logs` table
5. **Deduct** (Core): Subtract cost from tenant balance

## Circuit Breaker

- Threshold: $5.00/minute per user (configurable)
- Trigger: Immediate request blocking + alert log
- Purpose: Prevent runaway costs from bugs or abuse

## IAP Integration (Planned)

- Client submits receipt to `POST /billing/verify_receipt`
- Server verifies with Apple/Google servers
- On success: upgrade `plan_level` and `balance`
- No client-side trust: receipt validation is mandatory
