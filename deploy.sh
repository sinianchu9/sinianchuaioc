#!/usr/bin/env bash
# =============================================================
# AIOC 全自动部署脚本（内部测试模式，无防火墙限制）
# 目标系统：Ubuntu 22.04 LTS x86_64
# 用法：curl -fsSL https://raw.githubusercontent.com/sinianchu9/sinianchuaioc/master/deploy.sh | bash
#       或：chmod +x deploy.sh && ./deploy.sh
# =============================================================
set -euo pipefail

REPO_URL="https://github.com/sinianchu9/sinianchuaioc.git"
INSTALL_DIR="/opt/aioc"
COMPOSE_FILE="infra/docker-compose/enterprise.private.yml"
DB_CONTAINER="aioc-ent-postgres"

# ─── 颜色输出 ──────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fatal()   { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }
banner()  { echo -e "\n${BOLD}${CYAN}==============================${NC}"; echo -e "${BOLD}${CYAN} $*${NC}"; echo -e "${BOLD}${CYAN}==============================${NC}"; }

# ─── 1. 检查 root / sudo ─────────────────────────────────
banner "Step 1: 环境预检"
[[ $EUID -ne 0 ]] && fatal "请以 root 或 sudo 运行此脚本：sudo bash deploy.sh"
info "OS: $(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"')"

# ─── 2. 安装 Docker ───────────────────────────────────────
banner "Step 2: 安装 Docker"
if command -v docker &>/dev/null; then
  success "Docker 已存在: $(docker --version)"
else
  info "安装 Docker Engine..."
  apt-get update -qq
  apt-get install -y -qq ca-certificates curl gnupg lsb-release

  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list

  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io \
                         docker-buildx-plugin docker-compose-plugin

  systemctl enable docker
  systemctl start docker
  success "Docker 安装完成: $(docker --version)"
fi

# 确保 docker compose 可用
docker compose version &>/dev/null || fatal "docker compose 插件未安装"

# ─── 3. 拉取代码 ─────────────────────────────────────────
banner "Step 3: 拉取代码"
if [[ -d "$INSTALL_DIR/.git" ]]; then
  info "目录已存在，执行 git pull..."
  git -C "$INSTALL_DIR" pull --rebase
else
  info "克隆仓库到 $INSTALL_DIR ..."
  git clone "$REPO_URL" "$INSTALL_DIR"
fi
success "代码已就绪: $INSTALL_DIR"
cd "$INSTALL_DIR"

# ─── 4. 生成 .env（已存在则跳过） ────────────────────────
banner "Step 4: 配置环境变量"
ENV_FILE="$INSTALL_DIR/.env"
if [[ -f "$ENV_FILE" ]]; then
  warn ".env 已存在，跳过生成（保留已有配置）"
else
  info "生成默认 .env（内部测试配置）..."
  JWT_SECRET=$(openssl rand -hex 48)
  DB_PASSWORD=$(openssl rand -hex 16)
  MASTER_KEY=$(openssl rand -hex 32)

  cat > "$ENV_FILE" << ENVEOF
# 自动生成于 $(date '+%Y-%m-%d %H:%M:%S')
# 内部测试配置，生产环境请替换所有密钥

DB_USER=aioc
DB_PASSWORD=${DB_PASSWORD}
DB_NAME=aioc

JWT_SECRET=${JWT_SECRET}

MASTER_KEY=${MASTER_KEY}

# ── 填写你的 LLM API Key ──
DEEPSEEK_API_KEY=${DEEPSEEK_API_KEY:-}
OPENAI_API_KEY=${OPENAI_API_KEY:-}

GATEWAY_PORT=8080
CORE_PORT=8081
ENGINE_PROVIDER=openclaw
ENVEOF
  success ".env 已生成"
fi

# 读取 DB_USER / DB_NAME（供后续迁移使用）
source "$ENV_FILE" 2>/dev/null || true
DB_USER="${DB_USER:-aioc}"
DB_NAME="${DB_NAME:-aioc}"

# ─── 5. 拉起 PostgreSQL，执行全部迁移 ────────────────────
banner "Step 5: 数据库迁移"
info "启动 PostgreSQL 容器..."
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d postgres

info "等待 PostgreSQL 就绪..."
for i in $(seq 1 20); do
  docker exec "$DB_CONTAINER" pg_isready -U "$DB_USER" -d "$DB_NAME" &>/dev/null && break
  echo -n "."
  sleep 2
done
echo ""
docker exec "$DB_CONTAINER" pg_isready -U "$DB_USER" -d "$DB_NAME" \
  || fatal "PostgreSQL 未能在 40 秒内就绪"
success "PostgreSQL 已就绪"

info "按顺序执行所有 SQL 迁移..."
MIGRATION_DIR="$INSTALL_DIR/server/migrations"
for f in $(ls "$MIGRATION_DIR"/*.sql | sort); do
  fname=$(basename "$f")
  # 跳过 seed.sql（由 Docker entrypoint 已经运行过 001 + seed）
  [[ "$fname" == "001_init.sql" ]] && { info "  跳过 $fname（由 entrypoint 首次初始化完成）"; continue; }
  [[ "$fname" == "seed.sql" ]]     && { info "  跳过 $fname（同上）"; continue; }
  info "  → $fname"
  cat "$f" | docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" \
    && success "    $fname 执行成功" \
    || warn "    $fname 执行时有警告（可能已存在，通常无害）"
done

# ─── 6. 启动全部服务 ──────────────────────────────────────
banner "Step 6: 启动全栈服务"
info "构建并启动所有容器（首次需要几分钟）..."
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d --build
success "所有容器已启动"

# ─── 7. 健康检查 ──────────────────────────────────────────
banner "Step 7: 健康检查"
info "等待 Gateway 就绪（最多 30s）..."
for i in $(seq 1 15); do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/api/v1/health 2>/dev/null || echo "000")
  [[ "$STATUS" == "200" ]] && break
  echo -n "."
  sleep 2
done
echo ""

HEALTH=$(curl -s http://localhost:8080/api/v1/health 2>/dev/null || echo '{}')
if echo "$HEALTH" | grep -q '"code":1'; then
  success "Gateway 健康检查通过"
else
  warn "Gateway 可能还未完全就绪，请稍后运行：curl http://localhost:8080/api/v1/health"
fi

# ─── 8. 打印摘要 ──────────────────────────────────────────
banner "部署完成 🎉"
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
echo -e ""
echo -e "  ${BOLD}API 地址：${NC}  http://${SERVER_IP}:8080"
echo -e "  ${BOLD}健康检查：${NC}  http://${SERVER_IP}:8080/api/v1/health"
echo -e "  ${BOLD}容器状态：${NC}  docker compose -f $INSTALL_DIR/$COMPOSE_FILE ps"
echo -e "  ${BOLD}实时日志：${NC}  docker compose -f $INSTALL_DIR/$COMPOSE_FILE logs -f"
echo -e ""
echo -e "  ${YELLOW}LLM API Key 提醒：${NC}"
echo -e "  编辑 ${BOLD}${INSTALL_DIR}/.env${NC} 填写 DEEPSEEK_API_KEY / OPENAI_API_KEY"
echo -e "  然后执行：docker restart aioc-ent-gateway aioc-ent-core"
echo -e ""
