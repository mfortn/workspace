# 🧱 Workspace Final Setup

## ⚙️ تثبيت Docker و Docker Compose
```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# إضافة مستودع Docker الرسمي
echo   "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc]   https://download.docker.com/linux/ubuntu   $(. /etc/os-release && echo \"${UBUNTU_CODENAME:-$VERSION_CODENAME}\") stable" |   sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

sudo usermod -aG docker $USER
newgrp docker
```
```bash
git clone https://github.com/mfortn/workspace.git
```

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
./create.sh 
```
- Laravel API: http://localhost:<APP_PORT>
- Vue Dev:     http://localhost:<VUE_PORT>
- phpMyAdmin:  http://localhost:8080  (Server: <PROJECT>_db)
