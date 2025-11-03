# Workspace v3.3 (Laravel API + Breeze + Vue)

## Once
```bash
docker network create dbmesh || true
cd db-admin && docker compose up -d   # http://localhost:8080
```

## New project
```bash
cd workspace
chmod +x create.sh
./create.sh projX
```
- API: http://localhost:<APP_PORT>
- Vue: http://localhost:<VUE_PORT>
- phpMyAdmin: http://localhost:8080 (Server: <PROJECT>_db)
