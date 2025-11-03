#!/usr/bin/env bash
set -euo pipefail

# Usage: ./create.sh proj2
PROJECT="${1:-}"
if [[ -z "${PROJECT}" ]]; then
  read -rp "اسم المشروع؟ " PROJECT
fi

# Normalize: lowercase, no spaces
PROJECT=$(echo "$PROJECT" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-')

WORKSPACE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_DIR="${WORKSPACE}/${PROJECT}"
API_DIR="${PROJ_DIR}/api"
VUE_DIR="${PROJ_DIR}/default"

if [[ -d "${PROJ_DIR}" ]]; then
  echo "⚠️  المجلد ${PROJ_DIR} موجود مسبقاً."
  exit 1
fi

echo "📁 إنشاء المجلدات..."
mkdir -p "${API_DIR}/docker" "${VUE_DIR}" "${PROJ_DIR}/_data/mysql"

echo "🧩 تجهيز ملفات القوالب..."
# Copy templates
cp "${WORKSPACE}/_templates/docker-compose.tmpl.yml" "${PROJ_DIR}/docker-compose.yml"
cp "${WORKSPACE}/_templates/api.Dockerfile" "${API_DIR}/docker/api.Dockerfile"
# prepare nginx.conf with project placeholder replaced at runtime via envsubst approach
# We'll keep ${PROJECT} literal and let docker-compose env-var substitution handle it.
cp "${WORKSPACE}/_templates/nginx.conf" "${API_DIR}/docker/nginx.conf"
cp "${WORKSPACE}/_templates/compose.env.example" "${PROJ_DIR}/.env"

# Pick ports deterministically from project name (avoid collisions)
# Hash then map to ranges: API 8100-8499, VUE 8500-8899
HNUM=$(echo -n "${PROJECT}" | sha256sum | awk '{print $1}')
HEX="${HNUM:0:4}"
DEC=$(( 0x${HEX} ))
APP_PORT=$(( 8100 + (DEC % 400) ))
VUE_PORT=$(( 8500 + (DEC % 400) ))

# Update .env values
sed -i "s/^PROJECT=.*/PROJECT=${PROJECT}/" "${PROJ_DIR}/.env"
sed -i "s/^APP_PORT=.*/APP_PORT=${APP_PORT}/" "${PROJ_DIR}/.env"
sed -i "s/^VUE_PORT=.*/VUE_PORT=${VUE_PORT}/" "${PROJ_DIR}/.env"
sed -i "s/^DB_NAME=.*/DB_NAME=${PROJECT}_db/" "${PROJ_DIR}/.env"
sed -i "s/^DB_USER=.*/DB_USER=${PROJECT}_user/" "${PROJ_DIR}/.env"
sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=${PROJECT}_pass/" "${PROJ_DIR}/.env"
sed -i "s/^DB_ROOT_PASSWORD=.*/DB_ROOT_PASSWORD=${PROJECT}_root/" "${PROJ_DIR}/.env"

echo "🎛️ إنشاء تطبيق Laravel API داخل ${API_DIR}..."
docker run --rm -v "${API_DIR}":/app -w /app \
  -u "$(id -u):$(id -g)" \
  composer:2 sh -lc "composer create-project laravel/laravel . && composer require laravel/breeze && php artisan breeze:install api --no-interaction"

# Configure Laravel .env to use MySQL running in compose
LARAVEL_ENV="${API_DIR}/.env"
if [[ -f "${LARAVEL_ENV}" ]]; then
  sed -i "s/^DB_CONNECTION=.*/DB_CONNECTION=mysql/" "${LARAVEL_ENV}"
  sed -i "s/^DB_HOST=.*/DB_HOST=db/" "${LARAVEL_ENV}"
  sed -i "s/^DB_PORT=.*/DB_PORT=3306/" "${LARAVEL_ENV}"
  sed -i "s/^DB_DATABASE=.*/DB_DATABASE=${PROJECT}_db/" "${LARAVEL_ENV}"
  sed -i "s/^DB_USERNAME=.*/DB_USERNAME=${PROJECT}_user/" "${LARAVEL_ENV}"
  sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=${PROJECT}_pass/" "${LARAVEL_ENV}"
  # CORS / Sanctum origin (Vue site)
  if ! grep -q "^FRONTEND_URL=" "${LARAVEL_ENV}"; then
    echo "FRONTEND_URL=http://localhost:${VUE_PORT}" >> "${LARAVEL_ENV}"
  else
    sed -i "s|^FRONTEND_URL=.*|FRONTEND_URL=http://localhost:${VUE_PORT}|" "${LARAVEL_ENV}"
  fi
fi

echo "🌱 إنشاء مشروع Vue في ${VUE_DIR}..."
docker run --rm -v "${VUE_DIR}":/app -w /app node:lts bash -lc "npm create vue@latest . -y && npm install && npm run build"

echo "🚀 تشغيل الحاويات لأول مرة..."
( cd "${PROJ_DIR}" && docker compose --env-file .env up -d --build )

echo "🗄️  تشغيل الميجريشن..."
( cd "${PROJ_DIR}" && docker compose --env-file .env exec -T api-php php artisan migrate --force )

echo
echo "✅ تم إنشاء المشروع ${PROJECT}!"
echo "API URL:    http://localhost:${APP_PORT}"
echo "Frontend:   http://localhost:${VUE_PORT}"
echo
echo "الأوامر المفيدة:"
echo "  cd ${PROJECT} && docker compose --env-file .env up -d --build"
echo "  cd ${PROJECT} && docker compose --env-file .env logs -f"
echo "  cd ${PROJECT} && docker compose --env-file .env exec api-php php artisan tinker"
echo "  cd ${PROJECT} && docker compose --env-file .env run --rm vue-builder npm run build"
