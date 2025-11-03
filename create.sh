#!/usr/bin/env bash
set -euo pipefail

PROJECT="${1:-}"
if [[ -z "${PROJECT}" ]]; then
  read -rp "اسم المشروع؟ " PROJECT
fi

# sanitize
PROJECT="$(echo "$PROJECT" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-')"
if [[ -z "${PROJECT}" ]]; then
  echo "❌ اسم مشروع غير صالح"
  exit 1
fi

WORKSPACE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_DIR="${WORKSPACE}/${PROJECT}"
TPL_DIR="${WORKSPACE}/_templates"

if [[ -d "${PROJ_DIR}" ]]; then
  echo "⚠️ المجلد ${PROJ_DIR} موجود مسبقًا."
  read -rp "تكملة قد تستبدل بعض الملفات. متابعة؟ [y/N] " ans
  [[ "${ans:-}" =~ ^[yY]$ ]] || exit 1
else
  mkdir -p "${PROJ_DIR}"
fi

# scaffold
mkdir -p "${PROJ_DIR}/api"
cp -f "${TPL_DIR}/api.Dockerfile" "${PROJ_DIR}/api/api.Dockerfile"
cp -f "${TPL_DIR}/nginx.conf" "${PROJ_DIR}/nginx.conf"
cp -f "${TPL_DIR}/docker-compose.tmpl.yml" "${PROJ_DIR}/docker-compose.yml"

# .env with dynamic defaults
ENV_FILE="${PROJ_DIR}/.env"
APP_PORT_DEFAULT=8081

# find free port starting from 8081
port="${APP_PORT_DEFAULT}"
# use ss if available, else fallback to netstat
if command -v ss >/dev/null 2>&1; then
  check_port() { ss -ltn | awk '{print $4}' | grep -q ":${1}$"; }
else
  check_port() { netstat -ltn | awk '{print $4}' | grep -q ":${1}$"; }
fi
while check_port "${port}"; do
  port=$((port+1))
done

cat > "${ENV_FILE}" <<EOF
PROJECT=${PROJECT}
APP_PORT=${port}
DB_ROOT_PASSWORD=${PROJECT}_root
DB_NAME=${PROJECT}_db
DB_USER=${PROJECT}_user
DB_PASSWORD=${PROJECT}_pass
DB_PORT=3306
EOF

echo "✅ تم إنشاء هيكل ${PROJECT}"
echo " - APP_PORT=${port}"
echo " - DB container name will be: ${PROJECT}_db"

# ensure dbmesh exists
docker network create dbmesh >/dev/null 2>&1 || true

# bring up
(
  cd "${PROJ_DIR}"
  docker compose up -d --build
)

# connect phpMyAdmin (if running) to shared network
if docker ps --format '{{.Names}}' | grep -q '^db-admin_phpmyadmin$'; then
  docker network connect dbmesh db-admin_phpmyadmin 2>/dev/null || true
fi

echo "✨ جاهز!"
echo " - API/Nginx:  http://localhost:${port}"
echo " - phpMyAdmin: http://localhost:8080  (Server: ${PROJECT}_db  | user: root | pass: ${PROJECT}_root)"
