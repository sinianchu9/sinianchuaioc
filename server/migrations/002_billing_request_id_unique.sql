-- Ensure billing request idempotency on existing deployments.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'uq_billing_logs_request_id'
    ) THEN
        ALTER TABLE billing_logs
            ADD CONSTRAINT uq_billing_logs_request_id UNIQUE (request_id);
    END IF;
END $$;
