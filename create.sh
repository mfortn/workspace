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

# نسخ القوالب
cp -f "${TPL_DIR}/api.Dockerfile"          "${PROJ_DIR}/api/api.Dockerfile"
cp -f "${TPL_DIR}/nginx.conf"              "${PROJ_DIR}/nginx.conf"
cp -f "${TPL_DIR}/docker-compose.tmpl.yml" "${PROJ_DIR}/docker-compose.yml"

# Vue scaffold (بسيط جاهز)
cp -f "${TPL_DIR}/vue_pkg.json"            "${PROJ_DIR}/default/package.json"    2>/dev/null || true
cp -f "${TPL_DIR}/vue_index.html"          "${PROJ_DIR}/default/index.html"      2>/dev/null || true
cp -f "${TPL_DIR}/vite.config.js"          "${PROJ_DIR}/default/vite.config.js"  2>/dev/null || true
mkdir -p "${PROJ_DIR}/default/src"
cp -f "${TPL_DIR}/vue_main.js"             "${PROJ_DIR}/default/src/main.js"     2>/dev/null || true
cp -f "${TPL_DIR}/vue_App.vue"             "${PROJ_DIR}/default/src/App.vue"     2>/dev/null || true

# ==== اختيار منافذ بدون تكرار (Pure Bash) ====
have_cmd() { command -v "$1" >/dev/null 2>&1; }

list_used_ports_from_envs() {
  grep -hE '^(APP_PORT|VUE_PORT)=' "$WORKSPACE"/*/.env 2>/dev/null \
    | cut -d'=' -f2 \
    | grep -E '^[0-9]+$' \
    | sort -u || true
}

port_busy() {
  local p="$1"
  if have_cmd ss; then
    ss -ltn | awk '{print $4}' | grep -q ":${p}$"
  elif have_cmd netstat; then
    netstat -ltn | awk '{print $4}' | grep -q ":${p}$"
  else
    # fallback: حاول فتح socket عبر /dev/tcp
    (echo >/dev/tcp/127.0.0.1/"$p") >/dev/null 2>&1
  fi
}

pick_port() {
  local start="$1" p="$1"
  local used; used="$(list_used_ports_from_envs | tr '\n' ' ')"
  while :; do
    if echo " $used " | grep -q " $p "; then
      p=$((p+1)); continue
    fi
    if port_busy "$p"; then
      p=$((p+1)); continue
    fi
    echo "$p"; return 0
  done
}

APP_PORT="$(pick_port 8081)"
VUE_PORT="$(pick_port 5173)"

# .env
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

echo "✅ تم إنشاء هيكل ${PROJECT}"
echo " - APP_PORT=${APP_PORT}"
echo " - VUE_PORT=${VUE_PORT}"

# شبكة قواعد البيانات المشتركة
docker network create dbmesh >/dev/null 2>&1 || true

# شغّل الخدمات
(
  cd "${PROJ_DIR}"
  docker compose up -d --build
)

# وصل phpMyAdmin بالشبكة إن كان شغال
if docker ps --format '{{.Names}}' | grep -q '^db-admin_phpmyadmin$'; then
  docker network connect dbmesh db-admin_phpmyadmin 2>/dev/null || true
fi

# ==== تثبيت Laravel + Breeze تلقائيًا داخل api ====
(
  cd "${PROJ_DIR}"
  echo "🔍 فحص Laravel داخل ./api ..."
  if ! docker compose exec -T api-php bash -lc "test -f /var/www/html/public/index.php"; then
    echo "⬇️ تثبيت Laravel داخل ./api (بشكل آمن)"
    docker compose exec -T api-php bash -lc '
      set -e
      rm -rf /tmp/laravel-skel
      composer create-project laravel/laravel /tmp/laravel-skel
      cd /var/www/html
      [ -f api.Dockerfile ] && cp api.Dockerfile /tmp/api.Dockerfile.keep || true
      shopt -s dotglob
      rm -rf ./*
      cp -a /tmp/laravel-skel/. .
      rm -rf /tmp/laravel-skel
      [ -f /tmp/api.Dockerfile.keep ] && mv /tmp/api.Dockerfile.keep /var/www/html/api.Dockerfile || true
    '

    echo "🔧 تهيئة .env للـ DB والروابط"
    docker compose exec -T api-php bash -lc "
      cd /var/www/html && php -r 'copy(\".env.example\", \".env\");'
      php artisan key:generate
      php -r \"
        \$env = file_get_contents('.env');
        \$env = preg_replace('/^DB_HOST=.*/m', 'DB_HOST=db', \$env);
        \$env = preg_replace('/^DB_DATABASE=.*/m', 'DB_DATABASE=${DB_NAME}', \$env);
        \$env = preg_replace('/^DB_USERNAME=.*/m', 'DB_USERNAME=${DB_USER}', \$env);
        \$env = preg_replace('/^DB_PASSWORD=.*/m', 'DB_PASSWORD=${DB_PASSWORD}', \$env);
        \$env = preg_replace('/^APP_URL=.*/m', 'APP_URL=http://localhost:${APP_PORT}', \$env);
        file_put_contents('.env', \$env);
      \"
    "

    echo "🌬️ تثبيت Breeze (API)"
    docker compose exec -T api-php bash -lc "cd /var/www/html && composer require laravel/breeze --dev && php artisan breeze:install api"

    echo "🗄️ مهاجرات"
    docker compose exec -T api-php bash -lc "cd /var/www/html && php artisan migrate --force || true"
  else
    echo "ℹ️ Laravel موجود مسبقًا (تخطيت التثبيت)"
  fi
)

echo "✨ جاهز!"
echo " - API/Nginx:  http://localhost:${APP_PORT}"
echo " - Vue Dev:    http://localhost:${VUE_PORT}"
echo " - phpMyAdmin: http://localhost:8080  (Server: ${PROJECT}_db | root/${PROJECT}_root)"
