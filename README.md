# 🧱 Workspace Final v3 (Laravel API + Breeze + Vue)

## 1) Docker
(نفس خطوات تثبيت Docker من قبل)

## 2) شبكة قواعد البيانات المشتركة (مرة واحدة)
```bash
docker network create dbmesh || true
```

## 3) phpMyAdmin المركزي
```bash
cd ~/workspace/db-admin
docker compose up -d
# http://localhost:8080
```

## 4) إنشاء مشروع جديد (Laravel API + Breeze + Vue منفصل)
```bash
cd ~/workspace
chmod +x create.sh
./create.sh proj1
```
- Laravel API: http://localhost:<APP_PORT>
- Vue Dev:     http://localhost:<VUE_PORT>
- phpMyAdmin:  http://localhost:8080  (Server: <PROJECT>_db)
