#!/usr/bin/env bash
set -euo pipefail

# -------- Helpers --------
die() { echo "❌ $*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "الأمر '$1' غير موجود. ثبتّه أولاً."
}

check_docker() {
  if ! docker info >/dev/null 2>&1; then
    die "Docker غير شغّال أو لا تملك صلاحيات الوصول. شغّل:
  sudo systemctl enable --now docker
  sudo usermod -aG docker \$USER && newgrp docker
  ثم جرّب: docker ps"
  fi
}

# -------- Parse args --------
PROJECT="${1:-}"
if [[ -z "${PROJECT}" ]]; then
  read -rp "اسم المشروع؟ " PROJECT
fi
PROJECT="$(echo "$PROJECT" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-')"
[[ -n "$PROJECT" ]] || die "اسم مشروع غير صالح."

# -------- Paths --------
WORKSPACE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_DIR="${WORKSPACE}/${PROJECT}"
API_DIR="${PROJ_DIR}/api"
VUE_DIR="${PROJ_DIR}/default"

# -------- Pre-checks --------
need_cmd docker
check_docker
need_cmd sha256sum
need_cmd sed
need_cmd awk

[[ -d "${PROJ_DIR}" ]] && die "⚠️  المجلد ${PROJ_DIR} موجود مسبقاً."

echo "📁 إنشاء المجلدات..."
mkdir -p "${API_DIR}/docker" "${VUE_DIR}" "${PROJ_DIR}/_data/mysql"

echo "🧩 تجهيز ملفات القوالب..."
cp "${WORKSPACE}/_templates/docker-compose.tmpl.yml" "${PROJ_DIR}/docker-compose.yml"
cp "${WORKSPACE}/_templates/api.Dockerfile"           "${API_DIR}/docker/api.Dockerfile"
cp "${WORKSPACE}/_templates/nginx.conf"               "${API_DIR}/docker/nginx.conf"
cp "${WORKSPACE}/_templates/compose.env.example"      "${PROJ_DIR}/.env"

# إصلاحين فوريين على ملفات المشروع المُنشأة:
# 1) احذف سطر 'version:' القديم من docker-compose.yml (Compose v2 يتجاهله)
sed -i '/^version:/d' "${PROJ_DIR}/docker-compose.yml"
# 2) ثبّت fastcgi_pass على اسم خدمة الـ PHP داخل الشبكة: api-php
sed -i 's#fastcgi_pass .*#fastcgi_pass api-php:9000;#' "${API_DIR}/docker/nginx.conf"

# -------- Ports from project hash (stable, low collision) --------
HNUM=$(echo -n "${PROJECT}" | sha256sum | awk '{print $1}')
HEX="${HNUM:0:4}"; DEC=$(( 0x${HEX} ))
APP_PORT=$(( 8100 + (DEC % 400) ))   # API
VUE_PORT=$(( 8500 + (DEC % 400) ))   # Vue

# -------- Fill .env for compose --------
sed -i "s/^PROJECT=.*/PROJECT=${PROJECT}/"           "${PROJ_DIR}/.env"
sed -i "s/^APP_PORT=.*/APP_PORT=${APP_PORT}/"        "${PROJ_DIR}/.env"
sed -i "s/^VUE_PORT=.*/VUE_PORT=${VUE_PORT}/"        "${PROJ_DIR}/.env"
sed -i "s/^DB_NAME=.*/DB_NAME=${PROJECT}_db/"        "${PROJ_DIR}/.env"
sed -i "s/^DB_USER=.*/DB_USER=${PROJECT}_user/"      "${PROJ_DIR}/.env"
sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=${PROJECT}_pass/" "${PROJ_DIR}/.env"
sed -i "s/^DB_ROOT_PASSWORD=.*/DB_ROOT_PASSWORD=${PROJECT}_root/" "${PROJ_DIR}/.env"

echo "🎛️ إنشاء تطبيق Laravel API داخل ${API_DIR}..."
# نظّف أي شيء باستثناء مجلد docker
find "${API_DIR}" -mindepth 1 -maxdepth 1 ! -name docker -exec rm -rf {} +

# أنشئ داخل /tmp ثم انسخ لتفادي شرط 'مجلد فارغ'
docker run --rm -v "${API_DIR}":/app -w /app -u "$(id -u):$(id -g)" composer:2 bash -lc "
  set -e
  rm -rf /tmp/laravel && composer create-project laravel/laravel /tmp/laravel
  cp -a /tmp/laravel/. /app/
  composer require laravel/breeze
  php artisan breeze:install api --no-interaction
"

# -------- Configure Laravel .env --------
LARAVEL_ENV="${API_DIR}/.env"
if [[ -f "${LARAVEL_ENV}" ]]; then
  sed -i "s/^DB_CONNECTION=.*/DB_CONNECTION=mysql/"     "${LARAVEL_ENV}"
  sed -i "s/^DB_HOST=.*/DB_HOST=db/"                    "${LARAVEL_ENV}"
  sed -i "s/^DB_PORT=.*/DB_PORT=3306/"                  "${LARAVEL_ENV}"
  sed -i "s/^DB_DATABASE=.*/DB_DATABASE=${PROJECT}_db/" "${LARAVEL_ENV}"
  sed -i "s/^DB_USERNAME=.*/DB_USERNAME=${PROJECT}_user/" "${LARAVEL_ENV}"
  sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=${PROJECT}_pass/" "${LARAVEL_ENV}"
  # FRONTEND_URL لسانكتُم/CORS
  if ! grep -q '^FRONTEND_URL=' "${LARAVEL_ENV}"; then
    echo "FRONTEND_URL=http://localhost:${VUE_PORT}" >> "${LARAVEL_ENV}"
  else
    sed -i "s|^FRONTEND_URL=.*|FRONTEND_URL=http://localhost:${VUE_PORT}|" "${LARAVEL_ENV}"
  fi
  # APP_URL (مفيد لبعض التوليدات)
  if ! grep -q '^APP_URL=' "${LARAVEL_ENV}"; then
    echo "APP_URL=http://localhost:${APP_PORT}" >> "${LARAVEL_ENV}"
  else
    sed -i "s|^APP_URL=.*|APP_URL=http://localhost:${APP_PORT}|" "${LARAVEL_ENV}"
  fi
fi

echo "🌱 إنشاء مشروع Vue في ${VUE_DIR}..."
docker run --rm -v "${VUE_DIR}":/app -w /app node:lts bash -lc '
  set -e
  if [ ! -f package.json ]; then
    npm create vite@latest . -- --template vue
  fi
  npm install
  npm run build
'

echo "🚀 تشغيل الحاويات لأول مرة..."
(
  cd "${PROJ_DIR}"
  docker compose --env-file .env up -d --build
)

# -------- Wait for DB health then migrate --------
echo "🗄️  انتظار قاعدة البيانات حتى الجاهزية ثم تشغيل الميجريشن..."
(
  cd "${PROJ_DIR}"

  # اسم الكونتينر مضبوط في القالب: ${PROJECT}_db
  DB_CNAME="${PROJECT}_db"

  # انتظر حتى تصبح db: healthy (حتى 180 ثانية)
  timeout 180 bash -lc '
    while true; do
      status=$(docker inspect -f "{{.State.Health.Status}}" '"$DB_CNAME"' 2>/dev/null || echo "starting")
      if [ "$status" = "healthy" ]; then
        exit 0
      fi
      echo "⏳ في انتظار db... (الحالة: $status)"
      sleep 3
    done
  '

  # توليد مفتاح التطبيق + إصلاح صلاحيات التخزين
  docker compose --env-file .env exec -T api-php bash -lc "
    php artisan key:generate --force || true
    chown -R www-data:www-data storage bootstrap/cache || true
  "

  # الميجريشن
  docker compose --env-file .env exec -T api-php php artisan migrate --force
)

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
