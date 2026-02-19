-- AIOC Seed Data
-- 自动播种：套餐、路由规则、测试账号

-- ==========================================
-- 1. Plans (默认套餐)
-- ==========================================
INSERT INTO plans (plan_id, name, price_monthly, token_quota, features) VALUES
('free', 'Free', 0.000000, 10000, '{"chat": true, "stream": true, "models": ["economy"], "max_sessions": 5, "tools": false, "rag": false}'),
('pro', 'Pro', 20.000000, 1000000, '{"chat": true, "stream": true, "models": ["economy", "precision"], "max_sessions": 100, "tools": true, "rag": false}'),
('team', 'Team', 50.000000, 5000000, '{"chat": true, "stream": true, "models": ["economy", "precision"], "max_sessions": -1, "tools": true, "rag": true}'),
('enterprise', 'Enterprise', 0.000000, 0, '{"chat": true, "stream": true, "models": ["economy", "precision", "privacy"], "max_sessions": -1, "tools": true, "rag": true, "sso": true, "audit_export": true}')
ON CONFLICT (plan_id) DO NOTHING;

-- ==========================================
-- 2. Default Tenants (默认租户)
-- ==========================================
INSERT INTO tenants (tenant_id, name, type, plan_level, balance, status) VALUES
('00000000-0000-0000-0000-000000000001', 'AIOC Admin Org', 'enterprise', 'enterprise', 9999.000000, 'active'),
('00000000-0000-0000-0000-000000000002', 'Test User Org', 'individual', 'pro', 100.000000, 'active')
ON CONFLICT (tenant_id) DO NOTHING;

-- ==========================================
-- 3. Default Users (默认测试用户)
-- password_hash = bcrypt('123456')
-- ==========================================
INSERT INTO users (user_id, tenant_id, email, password_hash, display_name, roles) VALUES
('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000001', 'admin@aioc.internal', '$2a$10$9FutyqKduuXf6LSnSsCeV.EeaNsO2k35IAYFLGrCLh8u54QHWUCfu', 'Admin', ARRAY['admin', 'user']),
('00000000-0000-0000-0000-000000000012', '00000000-0000-0000-0000-000000000002', 'user@aioc.internal', '$2a$10$9FutyqKduuXf6LSnSsCeV.EeaNsO2k35IAYFLGrCLh8u54QHWUCfu', 'Test User', ARRAY['user'])
ON CONFLICT (user_id) DO NOTHING;

-- ==========================================
-- 4. Default Client Registry (默认客户端)
-- ==========================================
INSERT INTO client_registry (client_id, name, platform, min_version, feature_flags, status) VALUES
('00000000-0000-0000-0000-000000000101', 'AIOC Desktop macOS', 'macos', '1.0.0', '{"chat": true, "stream": true, "tools": true}', 'active'),
('00000000-0000-0000-0000-000000000102', 'AIOC Desktop Windows', 'windows', '1.0.0', '{"chat": true, "stream": true, "tools": true}', 'active'),
('00000000-0000-0000-0000-000000000103', 'AIOC Mobile iOS', 'ios', '1.0.0', '{"chat": true, "stream": true, "tools": false}', 'active'),
('00000000-0000-0000-0000-000000000104', 'AIOC Mobile Android', 'android', '1.0.0', '{"chat": true, "stream": true, "tools": false}', 'active'),
('00000000-0000-0000-0000-000000000105', 'AIOC CLI', 'cli', '1.0.0', '{"chat": true, "stream": true, "tools": true}', 'active')
ON CONFLICT (client_id) DO NOTHING;

-- ==========================================
-- 5. Routing Rules (默认路由规则)
-- ==========================================
INSERT INTO routing_rules (rule_id, name, condition_expr, target_model, mode, max_tokens, priority, enabled) VALUES
('00000000-0000-0000-0000-000000000201', 'Economy Default', 'mode == economy', 'deepseek-chat', 'economy', 4096, 10, true),
('00000000-0000-0000-0000-000000000202', 'Precision Default', 'mode == precision', 'deepseek-chat', 'precision', 8192, 10, true),
('00000000-0000-0000-0000-000000000203', 'Privacy Default', 'mode == privacy', 'ollama/llama3', 'privacy', 4096, 10, true),
('00000000-0000-0000-0000-000000000204', 'Economy Fallback', 'mode == economy AND fallback', 'deepseek-chat', 'economy', 4096, 5, true),
('00000000-0000-0000-0000-000000000205', 'Precision Fallback', 'mode == precision AND fallback', 'deepseek-chat', 'precision', 4096, 5, true)
ON CONFLICT (rule_id) DO NOTHING;
