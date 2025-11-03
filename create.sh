#!/usr/bin/env bash
set -euo pipefail

PROJECT="${1:-}"
if [[ -z "${PROJECT}" ]]; then
  read -rp "اسم المشروع؟ " PROJECT
fi
PROJECT="$(echo "$PROJECT" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-')"
[ -n "$PROJECT" ] || { echo "❌ اسم مشروع غير صالح"; exit 1; }

WORKSPACE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_DIR="${WORKSPACE}/${PROJECT}"
TPL_DIR="${WORKSPACE}/_templates"

mkdir -p "${PROJ_DIR}/api" "${PROJ_DIR}/default"

# Copy templates
cp -f "${TPL_DIR}/api.Dockerfile" "${PROJ_DIR}/api/api.Dockerfile"
cp -f "${TPL_DIR}/nginx.conf" "${PROJ_DIR}/nginx.conf"
cp -f "${TPL_DIR}/docker-compose.tmpl.yml" "${PROJ_DIR}/docker-compose.yml"

# Vue starter template
cp -f "${TPL_DIR}/vue_template_package.json" "${PROJ_DIR}/default/package.json"
cp -f "${TPL_DIR}/vue_template_index.html"   "${PROJ_DIR}/default/index.html"
mkdir -p "${PROJ_DIR}/default/src"
cp -f "${TPL_DIR}/vue_template_vite.config.js" "${PROJ_DIR}/default/vite.config.js"
cp -f "${TPL_DIR}/vue_template_src_main.js"    "${PROJ_DIR}/default/src/main.js"
cp -f "${TPL_DIR}/vue_template_src_App.vue"    "${PROJ_DIR}/default/src/App.vue"

# Pick free ports
pick_port() {
  local start="$1"
  python3 - <<PY || exit 1
import socket
port = int(${start})
while True:
    with socket.socket() as s:
        try:
            s.bind(("127.0.0.1", port))
        except OSError:
            port += 1
            continue
        break
print(port)
PY
}
APP_PORT="$(pick_port 8081)"
VUE_PORT="$(pick_port 5173)"

cat > "${PROJ_DIR}/.env" <<EOF
PROJECT=${PROJECT}
APP_PORT=${APP_PORT}
DB_ROOT_PASSWORD=${PROJECT}_root
DB_NAME=${PROJECT}_db
DB_USER=${PROJECT}_user
DB_PASSWORD=${PROJECT}_pass
DB_PORT=3306
VUE_PORT=${VUE_PORT}
EOF

echo "✅ هيكل ${PROJECT} جاهز (Laravel API + Vue)"

docker network create dbmesh >/dev/null 2>&1 || true

# Bring up infra (db + php + nginx + frontend dev server)
(
  cd "${PROJ_DIR}"
  docker compose up -d --build
)

# If phpMyAdmin is running, ensure it's on dbmesh
if docker ps --format '{{.Names}}' | grep -q '^db-admin_phpmyadmin$'; then
  docker network connect dbmesh db-admin_phpmyadmin 2>/dev/null || true
fi

# Scaffold Laravel + Breeze API inside ./api using the api-php container
(
  cd "${PROJ_DIR}"
  echo "⬇️ تثبيت Laravel في ./api ..."
  docker compose exec -T api-php bash -lc "cd /var/www/html && ls -A | wc -l" | grep -q '^0$' || { echo "⚠️ مجلد api غير فارغ، تخطيت التثبيت"; exit 0; }

  docker compose exec -T api-php bash -lc "cd /var/www/html && composer create-project laravel/laravel ."

  echo "🔑 ضبط .env للاتصال بقاعدة البيانات و الروابط"
  docker compose exec -T api-php bash -lc "cd /var/www/html && php -r "copy('.env.example','.env');" && php artisan key:generate"

  docker compose exec -T api-php bash -lc "cd /var/www/html &&     php -r "      $env = file_get_contents('.env');       $env = preg_replace('/^DB_HOST=.*/m', 'DB_HOST=db', $env);       $env = preg_replace('/^DB_DATABASE=.*/m', 'DB_DATABASE=${DB_NAME}', $env);       $env = preg_replace('/^DB_USERNAME=.*/m', 'DB_USERNAME=${DB_USER}', $env);       $env = preg_replace('/^DB_PASSWORD=.*/m', 'DB_PASSWORD=${DB_PASSWORD}', $env);       $env = preg_replace('/^APP_URL=.*/m', 'APP_URL=http://localhost:${APP_PORT}', $env);       file_put_contents('.env', $env);     ""

  echo "🌬️ تثبيت Breeze (API)"
  docker compose exec -T api-php bash -lc "cd /var/www/html && composer require laravel/breeze --dev && php artisan breeze:install api"

  echo "🗄️ تنفيذ المايجريشن"
  docker compose exec -T api-php bash -lc "cd /var/www/html && php artisan migrate --force"
)

echo "✨ تم!"
echo " - Laravel API: http://localhost:${APP_PORT}"
echo " - Vue Dev:     http://localhost:${VUE_PORT}"
echo " - phpMyAdmin:  http://localhost:8080  (Server: ${PROJECT}_db | root/${PROJECT}_root)"
