#!/usr/bin/env bash
set -euo pipefail

PROJECT="${1:-}"
if [[ -z "${PROJECT}" ]]; then
  read -rp "اسم المشروع؟ " PROJECT
fi

PROJECT=$(echo "$PROJECT" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-')
WORKSPACE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_DIR="${WORKSPACE}/${PROJECT}"
API_DIR="${PROJ_DIR}/api"
VUE_DIR="${PROJ_DIR}/default"

if [[ -d "${PROJ_DIR}" ]]; then
  echo "⚠️ المجلد ${PROJ_DIR} موجود مسبقاً."
  exit 1
fi

mkdir -p "${API_DIR}/docker" "${VUE_DIR}" "${PROJ_DIR}/_data/mysql"
cp "${WORKSPACE}/_templates/docker-compose.tmpl.yml" "${PROJ_DIR}/docker-compose.yml"
cp "${WORKSPACE}/_templates/api.Dockerfile" "${API_DIR}/docker/api.Dockerfile"
cp "${WORKSPACE}/_templates/nginx.conf" "${API_DIR}/docker/nginx.conf"
cp "${WORKSPACE}/_templates/compose.env.example" "${PROJ_DIR}/.env"

HNUM=$(echo -n "${PROJECT}" | sha256sum | awk '{print $1}')
HEX="${HNUM:0:4}"
DEC=$(( 0x${HEX} ))
APP_PORT=$(( 8100 + (DEC % 400) ))
VUE_PORT=$(( 8500 + (DEC % 400) ))

sed -i "s/^PROJECT=.*/PROJECT=${PROJECT}/" "${PROJ_DIR}/.env"
sed -i "s/^APP_PORT=.*/APP_PORT=${APP_PORT}/" "${PROJ_DIR}/.env"
sed -i "s/^VUE_PORT=.*/VUE_PORT=${VUE_PORT}/" "${PROJ_DIR}/.env"
sed -i "s/^DB_NAME=.*/DB_NAME=${PROJECT}_db/" "${PROJ_DIR}/.env"
sed -i "s/^DB_USER=.*/DB_USER=${PROJECT}_user/" "${PROJ_DIR}/.env"
sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=${PROJECT}_pass/" "${PROJ_DIR}/.env"
sed -i "s/^DB_ROOT_PASSWORD=.*/DB_ROOT_PASSWORD=${PROJECT}_root/" "${PROJ_DIR}/.env"

docker run --rm -v "${API_DIR}":/app -w /app -u "$(id -u):$(id -g)" composer:2 bash -lc "
  composer create-project laravel/laravel /tmp/laravel && cp -a /tmp/laravel/. /app/
  composer require laravel/breeze && php artisan breeze:install api --no-interaction
"

LARAVEL_ENV="${API_DIR}/.env"
sed -i "s/^DB_HOST=.*/DB_HOST=db/" "${LARAVEL_ENV}"
sed -i "s/^DB_DATABASE=.*/DB_DATABASE=${PROJECT}_db/" "${LARAVEL_ENV}"
sed -i "s/^DB_USERNAME=.*/DB_USERNAME=${PROJECT}_user/" "${LARAVEL_ENV}"
sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=${PROJECT}_pass/" "${LARAVEL_ENV}"
echo "FRONTEND_URL=http://localhost:${VUE_PORT}" >> "${LARAVEL_ENV}"

docker run --rm -v "${VUE_DIR}":/app -w /app node:lts bash -lc '
  npm create vite@latest . -- --template vue
  npm install
  npm run build
'

cd "${PROJ_DIR}"
docker compose --env-file .env up -d --build

timeout 180 bash -lc '
  until [ "$(docker inspect -f {{.State.Health.Status}} '"${PROJECT}"'_db 2>/dev/null)" = "healthy" ]; do
    echo "⏳ في انتظار db..." ; sleep 3
  done
'

docker compose --env-file .env exec -T api-php php artisan migrate --force

if docker ps --format '{{.Names}}' | grep -q '^db-admin_phpmyadmin$'; then
  docker network connect "${PROJECT}_net" db-admin_phpmyadmin 2>/dev/null || true
fi

echo "✅ تم إنشاء المشروع ${PROJECT}!"
echo "API: http://localhost:${APP_PORT}"
echo "Vue: http://localhost:${VUE_PORT}"
