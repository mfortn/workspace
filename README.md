# 🧱 Workspace Final Setup

## ⚙️ تثبيت Docker و Docker Compose
```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# إضافة مستودع Docker الرسمي
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo \"${UBUNTU_CODENAME:-$VERSION_CODENAME}\") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
````

---

## 🧭 تحميل مستودع العمل

```bash
git clone https://github.com/mfortn/workspace.git
```

---

## 🗄️ تشغيل phpMyAdmin المركزي

```bash
cd ~/db-admin
docker compose up -d
# الوصول عبر المتصفح:
# http://localhost:8080
```

---

## 🚀 إنشاء مشروع جديد

```bash
cd ~/workspace
./create.sh proj1
```
