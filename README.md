# Multi-project Docker Workspace (Laravel API + Breeze + Vue + MySQL)

هذه الحزمة تُنشئ بيئة جاهزة لاستضافة عدة مشاريع على نفس السيرفر (mini PC, 16GB RAM, 512GB).

## المزايا
- Laravel API منفصل مع Breeze (API) وSanctum
- واجهة Vue منفصلة (static build) تُخدم عبر Nginx
- MySQL وRedis داخل Docker
- بورتات تتحدد تلقائياً من اسم المشروع (بدون تعارض غالباً)
- كل مشروع معزول على شبكة خاصة

## المتطلبات
- Ubuntu/Debian محدث
- Docker + Docker Compose v2 مثبتين (أوامر التثبيت بالأسفل)

## إنشاء مشروع جديد
```bash
cd Workspace
chmod +x create.sh
./create.sh proj2
```
سيتم إنشاء:
```
Workspace/
  /proj2/
    /api        # Laravel API
    /default    # Vue app
    docker-compose.yml
    .env        # يحدد المنافذ وبيئة قاعدة البيانات
```
الوصول:
- API: `http://localhost:<APP_PORT>`
- Frontend: `http://localhost:<VUE_PORT>`

## أوامر Docker مفيدة
```bash
cd proj2
docker compose --env-file .env up -d --build
docker compose --env-file .env logs -f
docker compose --env-file .env exec api-php php artisan migrate --force
docker compose --env-file .env run --rm vue-builder npm run build
```

## تثبيت Docker (Ubuntu 22.04/24.04)
```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker $USER
# 🔁 سجل خروج/دخول لتفعيل عضوية مجموعة docker
```

> ملاحظة: إن رغبت بتجميع كل المشاريع خلف Reverse Proxy واحد (نطاقات متعددة)، يمكن إضافة Traefik/Nginx مركزي لاحقاً.
